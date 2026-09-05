//! Foundation IR2 -> portable C/Rust; Rust -> WASM. No source-language parser.
use crate::{capsule, host, limits::Limits, TextSpan};
use std::{
    fmt::Write,
    fs,
    panic::{catch_unwind, AssertUnwindSafe},
    process::Command,
};
#[repr(C)]
#[derive(Clone, Copy, Debug)]
pub struct Inst {
    pub op: i32,
    pub arg: i32,
    pub next: i32,
    pub cost: i32,
    pub line: i32,
    pub column: i32,
    pub number: f64,
}
fn validate(code: &[Inst], entry: i32, literals: &[Vec<u8>]) -> Result<(), String> {
    if code.is_empty() || code.len() > 8388609 || entry < 0 || entry as usize >= code.len() {
        return Err("invalid Foundation IR2 size/entry".into());
    }
    if code.last().unwrap().op != 0 {
        return Err("IR2 must end in a halt sentinel".into());
    }
    for (pc, i) in code.iter().enumerate() {
        if !(0..=27).contains(&i.op)
            || i.next < 0
            || i.next as usize >= code.len()
            || i.cost < 0
            || i.line < 1
            || i.column < 1
            || !i.number.is_finite()
        {
            return Err(format!("invalid IR2 instruction {pc}"));
        }
        if matches!(i.op, 24 | 25) && (i.arg < 0 || i.arg as usize >= literals.len()) {
            return Err("bad literal index".into());
        }
        if i.op == 23 && (i.arg < 0 || i.arg as usize >= host::registry().symbols.len()) {
            return Err("bad external handle".into());
        }
        if i.op != 0 && i.op != 3 && i.cost == 0 {
            return Err("executable entry has zero fuel cost".into());
        }
        if i.op == 4 && !(0..=256).contains(&i.arg) {
            return Err("invalid escape byte".into());
        }
        if (23..=26).contains(&i.op) && i.cost < if i.op == 23 || i.op == 25 { 4 } else { 2 } {
            return Err("invalid fast-path cost".into());
        }
        if matches!(i.op, 1 | 27) && !(0..=255).contains(&i.arg) {
            return Err("invalid byte constant".into());
        }
        if matches!(i.op, 5 | 6) && !(0..=1).contains(&i.arg) {
            return Err("invalid frame kind".into());
        }
    }
    Ok(())
}
pub(crate) fn lines(code: &[Inst]) -> Vec<(usize, usize)> {
    let mut out = Vec::new();
    let mut start = 0;
    for (pc, i) in code.iter().enumerate() {
        if i.op == 3 {
            out.push((start, pc - start));
            start = pc + 1
        }
    }
    out.push((start, code.len() - 1 - start));
    out
}
fn rust_source(code: &[Inst], entry: i32, literals: &[Vec<u8>], limits: &Limits) -> String {
    let r = host::registry();
    let mut s=String::from("// Generated Foundation program; Fortran front end, Rust chain.\n#[derive(Clone,Copy)] struct I{op:u8,arg:usize,next:usize,cost:u32,line:usize,col:usize,value:f64}\nstruct Sym{module:usize,name:&'static str,arity:usize,kind:u8,parameters:&'static[u32],result:u32}\n");
    writeln!(
        s,
        "const ENTRY:usize={entry};\nconst USES_INPUT:bool={};\nconst CODE:&[I]=&[",
        code.iter().any(|i| i.op == 18)
    )
    .unwrap();
    for i in code {
        writeln!(
            s,
            "I{{op:{},arg:{},next:{},cost:{},line:{},col:{},value:{:.17e}}},",
            i.op, i.arg, i.next, i.cost, i.line, i.column, i.number
        )
        .unwrap();
    }
    s.push_str("];\nconst LINES:&[(usize,usize)]=&[");
    for (a, b) in lines(code) {
        write!(s, "({a},{b}),").unwrap()
    }
    s.push_str("];\nconst LITERALS:&[&[u8]]=&[");
    for b in literals {
        write!(s, "&{:?},", b).unwrap()
    }
    s.push_str("];\nconst MODULES:&[&str]=&[");
    for m in &r.modules {
        write!(s, "{m:?},").unwrap()
    }
    s.push_str("];\nconst SYMBOLS:&[Sym]=&[\n");
    for x in &r.symbols {
        writeln!(
            s,
            "Sym{{module:{},name:{:?},arity:{},kind:{},parameters:&{:?},result:{}}},",
            x.module,
            x.name,
            x.arity,
            x.kind,
            x.signature
                .as_ref()
                .map(|s| s.parameters.as_slice())
                .unwrap_or(&[]),
            x.signature.as_ref().map_or(0, |s| s.result)
        )
        .unwrap()
    }
    s.push_str("];\n");
    for (id, x) in r
        .symbols
        .iter()
        .enumerate()
        .filter(|(_, x)| x.module >= 2 && x.kind == 0)
    {
        let m = &r.modules[x.module];
        writeln!(s,"#[cfg(not(target_arch=\"wasm32\"))] extern \"C\" {{#[link_name=\"urotif_ext_{m}_{}\"] fn ext_{id}(a:*const f64,n:usize,out:*mut f64)->i32;}}",x.name).unwrap();
        writeln!(s,"#[cfg(target_arch=\"wasm32\")] #[link(wasm_import_module={m:?})] extern \"C\" {{#[link_name={:?}] fn ext_{id}(a:*const f64,n:usize,out:*mut f64)->i32;}}",x.name).unwrap();
    }
    s.push_str("fn foreign_call(id:usize,a:&[f64])->Result<f64,i32>{let x=match id{\n");
    for (id, x) in r.symbols.iter().enumerate().filter(|(_, x)| x.kind == 0) {
        if x.module == 1 {
            let expr = match x.name.as_str() {
                "sqrt" => "a[0].sqrt()",
                "square" => "a[0]*a[0]",
                "abs" => "a[0].abs()",
                "add" => "a[0]+a[1]",
                _ => unreachable!(),
            };
            writeln!(
                s,
                "{id}=>{{if a.len()!={}{{return Err(12)}}{expr}}},",
                x.arity
            )
            .unwrap()
        } else {
            writeln!(s,"{id}=>{{let mut out=f64::NAN;if unsafe{{ext_{id}(a.as_ptr(),a.len(),&mut out)}}!=0{{return Err(12)}}out}},").unwrap()
        }
    }
    s.push_str("_=>return Err(12)};if !x.is_finite(){return Err(12)}Ok(x)}\n");
    s.push_str(&crate::typed_emit::rust());
    s.push_str(&limits.rust_prelude());
    s.push_str(include_str!("../../runtime/foundation.rs"));
    s.push_str(include_str!("../../runtime/typed.rs"));
    s
}
fn c_source(code: &[Inst], entry: i32, literals: &[Vec<u8>], limits: &Limits) -> String {
    let r = host::registry();
    let mut s=String::from("typedef struct{int op,arg,next,cost,line,col;double value;} I;\ntypedef struct{int start,len;} Line;\ntypedef struct{const unsigned char*data;int len;} Literal;\ntypedef struct{int module;const char*name;int arity,kind;} Symbol;\n");
    writeln!(s,"#define ENTRY {entry}\n#define USES_INPUT {}\n#define CODE_COUNT {}\nstatic const I code[]={{",u8::from(code.iter().any(|i|i.op==18)),code.len()).unwrap();
    for i in code {
        writeln!(
            s,
            "{{{},{},{},{},{},{},{:.17e}}},",
            i.op, i.arg, i.next, i.cost, i.line, i.column, i.number
        )
        .unwrap()
    }
    s.push_str("};\n");
    let ls = lines(code);
    writeln!(
        s,
        "#define LINE_COUNT {}\nstatic const Line lines[]={{",
        ls.len()
    )
    .unwrap();
    for (a, b) in ls {
        write!(s, "{{{a},{b}}},").unwrap()
    }
    s.push_str("};\n");
    for (id, b) in literals.iter().enumerate() {
        write!(s, "static const unsigned char literal_{id}[]={{").unwrap();
        if b.is_empty() {
            s.push('0')
        } else {
            for c in b {
                write!(s, "{c},").unwrap()
            }
        }
        s.push_str("};\n");
    }
    writeln!(
        s,
        "#define LITERAL_COUNT {}\nstatic const Literal literals[]={{",
        literals.len()
    )
    .unwrap();
    if literals.is_empty() {
        s.push_str("{(const unsigned char*)\"\",0}")
    }
    for (id, b) in literals.iter().enumerate() {
        write!(s, "{{literal_{id},{}}},", b.len()).unwrap()
    }
    s.push_str("};\n");
    writeln!(
        s,
        "#define MODULE_COUNT {}\nstatic const char*const modules[]={{",
        r.modules.len()
    )
    .unwrap();
    for m in &r.modules {
        write!(s, "{m:?},").unwrap()
    }
    s.push_str("};\n");
    writeln!(
        s,
        "#define SYMBOL_COUNT {}\nstatic const Symbol symbols[]={{",
        r.symbols.len()
    )
    .unwrap();
    for x in &r.symbols {
        writeln!(s, "{{{},{:?},{},{}}},", x.module, x.name, x.arity, x.kind).unwrap()
    }
    s.push_str("};\n");
    for x in r.symbols.iter().filter(|x| x.module >= 2 && x.kind == 0) {
        writeln!(
            s,
            "extern int32_t urotif_ext_{}_{}(const double*,size_t,double*);",
            r.modules[x.module], x.name
        )
        .unwrap();
    }
    s.push_str("static int foreign_call(int id,const double*a,size_t n,double*out){switch(id){\n");
    for (id, x) in r.symbols.iter().enumerate().filter(|(_, x)| x.kind == 0) {
        write!(s, "case {id}:if(n!={})return 1;", x.arity).unwrap();
        if x.module == 1 {
            let expr = match x.name.as_str() {
                "sqrt" => "sqrt(a[0])",
                "square" => "a[0]*a[0]",
                "abs" => "fabs(a[0])",
                "add" => "a[0]+a[1]",
                _ => unreachable!(),
            };
            writeln!(s, "*out={expr};return isfinite(*out)?0:1;").unwrap()
        } else {
            writeln!(
                s,
                "return urotif_ext_{}_{}(a,n,out);",
                r.modules[x.module], x.name
            )
            .unwrap()
        }
    }
    s.push_str("default:return 1;}}\n");
    s.push_str(&crate::typed_emit::c());
    include_str!("../../runtime/foundation.c")
        .replace("/* GENERATED_LIMITS */", &limits.c_prelude())
        .replace("/* GENERATED_TABLES */", &s)
        .replace("/* TYPED_RUNTIME */", include_str!("../../runtime/typed.c"))
}
fn manifest(limits: &Limits) -> String {
    let r = host::registry();
    let mut s =
        String::from("{\n  \"format\": \"Urotif Foundation link catalog 2\",\n  \"symbols\": [\n");
    for (i, x) in r.symbols.iter().enumerate() {
        if i > 0 {
            s.push_str(",\n")
        }
        write!(s,"    {{\"slot\":{i},\"module\":{:?},\"name\":{:?},\"arity\":{},\"kind\":{},\"wasm_import\":{},\"signature\":{}}}",r.modules[x.module],x.name,x.arity,x.kind,x.module>=2,x.signature.as_ref().map(|v|v.json()).unwrap_or_else(||"null".into())).unwrap()
    }
    s.push_str("\n  ],\n  \"limits\": ");
    s.push_str(&limits.json());
    s.push_str("\n}\n");
    s
}
#[no_mangle]
pub unsafe extern "C" fn urotif_foundation_emit_v3(
    abi: i32,
    code: *const Inst,
    count: usize,
    entry: i32,
    bytes: *const u8,
    byte_count: usize,
    spans: *const TextSpan,
    text_count: usize,
    path: *const u8,
    path_len: usize,
    format: i32,
    limits: *const i32,
    source: *const u8,
    source_len: usize,
    flags: i32,
    error: *mut u8,
    error_cap: usize,
) -> i32 {
    let result = catch_unwind(AssertUnwindSafe(|| -> Result<(), String> {
        if abi != 3 {
            return Err("expected Foundation emission ABI 3".into());
        }
        let limits = Limits::checked(unsafe { crate::checked_slice(limits, 11, 11)? })?;
        if flags & !3 != 0 {
            return Err("unknown emission flags".into());
        }
        if flags & 2 != 0 && format != 3 {
            return Err("strict F95 is a Fortran-only option".into());
        }
        let source = unsafe { crate::checked_slice(source, source_len, 8388608)? };
        let code = unsafe { crate::checked_slice(code, count, 8388609)? };
        let blob = unsafe { crate::checked_slice(bytes, byte_count, 2097152)? };
        let spans = unsafe { crate::checked_slice(spans, text_count, 1024)? };
        let p = unsafe { crate::checked_slice(path, path_len, 4096)? };
        let path = std::str::from_utf8(p).map_err(|_| "output path must be UTF-8")?;
        if path.is_empty() {
            return Err("empty output path".into());
        }
        let mut literals = Vec::new();
        for x in spans {
            if x.offset < 0 || x.length < 0 || x.length > 2048 {
                return Err("bad literal span".into());
            }
            literals.push(
                blob.get(x.offset as usize..x.offset as usize + x.length as usize)
                    .ok_or("literal out of bounds")?
                    .to_vec(),
            )
        }
        validate(code, entry, &literals)?;
        if code.len() > limits.0[9] as usize + 1 {
            return Err("IR exceeds source policy".into());
        }
        if flags & 1 != 0 && source.len() + 1 != code.len() {
            return Err("source capsule/IR length mismatch".into());
        }
        let embedded = |mut text: String, prefix: &str| {
            if flags & 1 != 0 {
                text.push_str(&capsule::text(source, prefix));
            }
            text
        };
        match format {
            0 => fs::write(
                path,
                embedded(c_source(code, entry, &literals, &limits), "//"),
            )
            .map_err(|e| e.to_string())?,
            1 => fs::write(
                path,
                embedded(rust_source(code, entry, &literals, &limits), "//"),
            )
            .map_err(|e| e.to_string())?,
            2 => {
                let source_path = format!("{path}.rs");
                fs::write(
                    &source_path,
                    embedded(rust_source(code, entry, &literals, &limits), "//"),
                )
                .map_err(|e| e.to_string())?;
                let temp = format!("{path}.tmp-{}", std::process::id());
                let output=Command::new("rustc").args(["--edition=2021","--crate-name","urotif_program","--crate-type=cdylib","--target=wasm32-unknown-unknown","-O","-C","panic=abort","-C","strip=symbols","-A","dead_code","-A","unused_imports"]).arg(&source_path).arg("-o").arg(&temp).output().map_err(|e|format!("cannot invoke rustc: {e}; install rustc and the wasm32-unknown-unknown target"))?;
                if !output.status.success() {
                    let _ = fs::remove_file(temp);
                    return Err(format!(
                        "rustc WASM build failed: {}",
                        String::from_utf8_lossy(&output.stderr)
                    ));
                }
                {
                    use std::io::Write as IoWrite;
                    let mut f = fs::OpenOptions::new()
                        .append(true)
                        .open(&temp)
                        .map_err(|e| e.to_string())?;
                    f.write_all(&crate::typed_emit::catalog_section(&manifest(&limits)))
                        .map_err(|e| e.to_string())?;
                }
                if flags & 1 != 0 {
                    use std::io::Write as IoWrite;
                    let mut f = fs::OpenOptions::new()
                        .append(true)
                        .open(&temp)
                        .map_err(|e| e.to_string())?;
                    f.write_all(&capsule::wasm(source))
                        .map_err(|e| e.to_string())?;
                }
                fs::rename(temp, path).map_err(|e| e.to_string())?;
            }
            3 => {
                let text =
                    crate::fortran_target::source(code, entry, &literals, &limits, flags & 2 != 0)?;
                fs::write(path, embedded(text, "!")).map_err(|e| e.to_string())?;
            }
            _ => return Err("target format must be C(0), Rust(1), WASM(2), or Fortran(3)".into()),
        }
        fs::write(format!("{path}.links.json"), manifest(&limits)).map_err(|e| e.to_string())?;
        Ok(())
    }));
    let (status, msg) = match result {
        Ok(Ok(())) => (0, String::new()),
        Ok(Err(e)) => (1, e),
        Err(_) => (2, "Foundation emitter panic contained".into()),
    };
    if error_cap > 0 && !error.is_null() {
        let n = msg.len().min(error_cap - 1);
        unsafe {
            std::ptr::copy_nonoverlapping(msg.as_ptr(), error, n);
            *error.add(n) = 0;
        }
    }
    status
}
/// Compatibility entry for IR ABI 2 clients: default policy, no capsule.
#[no_mangle]
pub unsafe extern "C" fn urotif_foundation_emit(
    abi: i32,
    code: *const Inst,
    count: usize,
    entry: i32,
    bytes: *const u8,
    byte_count: usize,
    spans: *const TextSpan,
    text_count: usize,
    path: *const u8,
    path_len: usize,
    format: i32,
    error: *mut u8,
    error_cap: usize,
) -> i32 {
    let defaults = Limits::default();
    unsafe {
        urotif_foundation_emit_v3(
            if abi == 2 { 3 } else { -1 },
            code,
            count,
            entry,
            bytes,
            byte_count,
            spans,
            text_count,
            path,
            path_len,
            format,
            defaults.0.as_ptr(),
            std::ptr::null(),
            0,
            0,
            error,
            error_cap,
        )
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn wire_layout() {
        assert_eq!(std::mem::size_of::<Inst>(), 32)
    }
    #[test]
    fn bad_ir_rejected() {
        assert!(validate(&[], 0, &[]).is_err())
    }
}
