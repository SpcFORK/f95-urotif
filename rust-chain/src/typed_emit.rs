//! Signature-driven binding generation: independent of plugin function names.
use crate::host;
use std::fmt::Write;
pub fn c() -> String {
    let r = host::registry();
    let mut s = String::from(include_str!("../../include/urotif_typed_values.h"));
    s.push_str("\nstatic const uint32_t typed_parameters[SYMBOL_COUNT][8]={\n");
    for x in &r.symbols {
        let mut a = [0; 8];
        if let Some(sig) = &x.signature {
            a[..sig.parameters.len()].copy_from_slice(&sig.parameters)
        }
        writeln!(
            s,
            "{{{}}},",
            a.iter()
                .map(|k| k.to_string())
                .collect::<Vec<_>>()
                .join(",")
        )
        .unwrap();
    }
    s.push_str("};\nstatic const int typed_result_kind[SYMBOL_COUNT]={");
    for x in &r.symbols {
        write!(s, "{},", x.signature.as_ref().map_or(0, |v| v.result)).unwrap();
    }
    s.push_str("};\n");
    for x in r.symbols.iter().filter(|x| x.signature.is_some()) {
        writeln!(
            s,
            "extern int32_t urotif_ext_{}_{}(const UrotifTypedArg*,size_t,UrotifTypedResult*);",
            r.modules[x.module], x.name
        )
        .unwrap();
    }
    s.push_str("static int foreign_typed(int id,const UrotifTypedArg*a,size_t n,UrotifTypedResult*out){switch(id){\n");
    for (id, x) in r
        .symbols
        .iter()
        .enumerate()
        .filter(|(_, x)| x.signature.is_some())
    {
        writeln!(
            s,
            "case {id}:return urotif_ext_{}_{}(a,n,out);",
            r.modules[x.module], x.name
        )
        .unwrap();
    }
    s.push_str("default:return 1;}}\n");
    s
}
pub fn rust() -> String {
    let r = host::registry();
    let mut s = String::from(include_str!("../../runtime/typed_abi.rs"));
    for (id, x) in r
        .symbols
        .iter()
        .enumerate()
        .filter(|(_, x)| x.signature.is_some())
    {
        let m = &r.modules[x.module];
        writeln!(s,"#[cfg(not(target_arch=\"wasm32\"))] extern \"C\"{{#[link_name=\"urotif_ext_{m}_{}\"] fn typed_{id}(a:*const TypedArg,n:usize,out:*mut TypedResult)->i32;}}",x.name).unwrap();
        writeln!(s,"#[cfg(target_arch=\"wasm32\")] #[link(wasm_import_module={m:?})] extern \"C\"{{#[link_name={:?}] fn typed_{id}(a:*const TypedArg,n:usize,out:*mut TypedResult)->i32;}}",x.name).unwrap();
    }
    s.push_str("unsafe fn foreign_typed(id:usize,a:*const TypedArg,n:usize,out:*mut TypedResult)->i32{match id{\n");
    for (id, _) in r
        .symbols
        .iter()
        .enumerate()
        .filter(|(_, x)| x.signature.is_some())
    {
        writeln!(s, "{id}=>unsafe{{typed_{id}(a,n,out)}},").unwrap();
    }
    s.push_str("_=>1}}\n");
    s
}
pub fn catalog_section(json: &str) -> Vec<u8> {
    fn leb(mut n: usize, b: &mut Vec<u8>) {
        loop {
            let x = (n & 127) as u8;
            n >>= 7;
            b.push(x | if n > 0 { 128 } else { 0 });
            if n == 0 {
                return;
            }
        }
    }
    let name = b"urotif.links.v2";
    let mut body = Vec::new();
    leb(name.len(), &mut body);
    body.extend_from_slice(name);
    body.extend_from_slice(json.as_bytes());
    let mut out = vec![0];
    leb(body.len(), &mut out);
    out.extend(body);
    out
}
