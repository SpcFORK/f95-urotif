//! ABI 2: explicit typed views, borrowed inputs, caller-owned result buffers.
//! Pointer validity still belongs to trusted C/native callers and libraries.
use crate::host::{self, Symbol};
use libloading::Library;
use std::{
    ffi::c_char,
    mem::{align_of, size_of},
};
include!("../../runtime/typed_abi.rs");
pub const KIND: i32 = 7;
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Signature {
    pub parameters: Vec<u32>,
    pub result: u32,
}
impl Signature {
    pub fn checked(parameters: &[u32], result: u32) -> Result<Self, String> {
        if parameters.len() > 8
            || parameters.iter().any(|x| !(1..=3).contains(x))
            || !(1..=3).contains(&result)
        {
            return Err("invalid typed signature".into());
        }
        Ok(Self {
            parameters: parameters.to_vec(),
            result,
        })
    }
    pub fn parse(s: &str) -> Result<Self, String> {
        let (args, out) = s
            .split_once("->")
            .ok_or("use MODULE.SYMBOL/number,bytes,vector->TYPE")?;
        fn kind(s: &str) -> Result<u32, String> {
            match s {
                "number" => Ok(1),
                "bytes" => Ok(2),
                "vector" => Ok(3),
                _ => Err("types must be number, bytes, or vector".into()),
            }
        }
        let args = if args.is_empty() {
            Vec::new()
        } else {
            args.split(',').map(kind).collect::<Result<Vec<_>, _>>()?
        };
        Self::checked(&args, kind(out)?)
    }
    pub fn display(&self) -> String {
        fn name(k: u32) -> &'static str {
            match k {
                1 => "number",
                2 => "bytes",
                3 => "vector",
                _ => "invalid",
            }
        }
        format!(
            "{}->{}",
            self.parameters
                .iter()
                .map(|k| name(*k))
                .collect::<Vec<_>>()
                .join(","),
            name(self.result)
        )
    }
    pub fn json(&self) -> String {
        format!(
            "{{\"abi\":2,\"parameters\":{:?},\"result\":{}}}",
            self.parameters, self.result
        )
    }
}
#[repr(C)]
pub struct PluginSymbolV2 {
    pub name: *const c_char,
    pub arity: u32,
    pub parameters: [u32; 8],
    pub result: u32,
    pub call: Option<TypedFn>,
}
#[repr(C)]
pub struct PluginV2 {
    pub abi: u32,
    pub struct_size: u32,
    pub module: *const c_char,
    pub count: usize,
    pub symbols: *const PluginSymbolV2,
}

pub unsafe fn load(
    lib: &Library,
    module_id: usize,
) -> Result<Option<(String, Vec<Symbol>)>, String> {
    let entry = match unsafe {
        lib.get::<unsafe extern "C" fn() -> *const PluginV2>(b"urotif_plugin_v2\0")
    } {
        Ok(f) => f,
        Err(_) => return Ok(None),
    };
    let p = unsafe { entry() };
    if p.is_null() {
        return Err("null ABI-2 descriptor".into());
    }
    buffer_guard(p, 1, 1)?;
    let p = unsafe { &*p };
    if p.abi != 2
        || p.struct_size as usize != size_of::<PluginV2>()
        || p.count == 0
        || p.count > 128
        || p.symbols.is_null()
    {
        return Err("invalid plugin ABI-2 descriptor/table".into());
    }
    let module = unsafe { host::c_name(p.module) }?;
    let mut symbols = Vec::new();
    for s in unsafe { view(p.symbols, p.count, 128)? } {
        let name = unsafe { host::c_name(s.name) }?;
        if s.arity > 8 || s.call.is_none() {
            return Err("invalid typed symbol signature".into());
        }
        if s.parameters[s.arity as usize..].iter().any(|x| *x != 0) {
            return Err("unused signature slots must be zero".into());
        }
        let signature = Signature::checked(&s.parameters[..s.arity as usize], s.result)?;
        if symbols.iter().any(|x: &Symbol| x.name == name) {
            return Err("duplicate typed symbol".into());
        }
        symbols.push(Symbol {
            module: module_id,
            name,
            arity: s.arity as usize,
            kind: KIND,
            call: None,
            signature: Some(signature),
            typed_call: s.call,
        });
    }
    Ok(Some((module, symbols)))
}

// Bounds/null/alignment checks are useful ABI diagnostics. They cannot prove
// that an arbitrary native pointer denotes readable/writable memory.
fn buffer_guard<T>(p: *const T, n: usize, max: usize) -> Result<(), String> {
    if n > max
        || n.checked_mul(size_of::<T>())
            .is_none_or(|x| x > isize::MAX as usize)
    {
        return Err("typed buffer exceeds ABI guard".into());
    }
    if n > 0 && (p.is_null() || (p as usize) % align_of::<T>() != 0) {
        return Err("null/misaligned typed buffer".into());
    }
    if (p as usize).checked_add(n * size_of::<T>()).is_none() {
        return Err("typed pointer span wraps address space".into());
    }
    Ok(())
}
unsafe fn view<'a, T>(p: *const T, n: usize, max: usize) -> Result<&'a [T], String> {
    buffer_guard(p, n, max)?;
    if n == 0 {
        return Ok(&[]);
    }
    Ok(unsafe { std::slice::from_raw_parts(p, n) })
}
pub unsafe fn checked_call(
    f: TypedFn,
    sig: &Signature,
    args: &[TypedArg],
    out: &mut TypedResult,
) -> Result<(), String> {
    if args.len() != sig.parameters.len() {
        return Err("typed arity mismatch".into());
    }
    for (a, expected) in args.iter().zip(&sig.parameters) {
        if a.tag != *expected || a.reserved != 0 {
            return Err("typed argument tag mismatch".into());
        }
        match a.tag {
            1 => {
                if !a.number.is_finite() {
                    return Err("non-finite typed argument".into());
                }
            }
            2 => {
                let _ = unsafe { view(a.bytes, a.length, 67_108_864)? };
            }
            3 => {
                if unsafe { view(a.vector, a.count, 4_194_304)? }
                    .iter()
                    .any(|x| !x.is_finite())
                {
                    return Err("non-finite vector argument".into());
                }
            }
            _ => return Err("invalid typed argument".into()),
        }
    }
    buffer_guard(out.bytes, out.capacity, 67_108_864)?;
    buffer_guard(out.vector, out.vector_capacity, 4_194_304)?;
    let owned = (out.bytes, out.capacity, out.vector, out.vector_capacity);
    out.number = f64::NAN;
    out.length = 0;
    out.count = 0;
    let status = unsafe { f(args.as_ptr(), args.len(), out) };
    if (out.bytes, out.capacity, out.vector, out.vector_capacity) != owned {
        return Err("plugin changed caller-owned buffers/capacities".into());
    }
    if status != 0 {
        return Err(format!("typed service returned status {status}"));
    }
    if out.length > out.capacity || out.count > out.vector_capacity {
        return Err("typed result exceeds caller capacity".into());
    }
    match sig.result {
        1 => {
            if !out.number.is_finite() {
                return Err("typed service returned non-finite number".into());
            }
        }
        2 => {}
        3 => {
            if unsafe { view(out.vector, out.count, out.vector_capacity)? }
                .iter()
                .any(|x| !x.is_finite())
            {
                return Err("typed service returned non-finite vector".into());
            }
        }
        _ => return Err("invalid typed result signature".into()),
    }
    Ok(())
}
pub fn declare(spec: &str) -> Result<(), String> {
    let (qualified, types) = spec
        .split_once('/')
        .ok_or("use MODULE.SYMBOL/TYPES->TYPE")?;
    let (module, name) = qualified
        .split_once('.')
        .ok_or("use MODULE.SYMBOL/TYPES->TYPE")?;
    if !host::ident(module) || !host::ident(name) || module == "std" || module == "math" {
        return Err("invalid typed declaration/module".into());
    }
    let signature = Signature::parse(types)?;
    let mut lock = host::builder()
        .lock()
        .map_err(|_| "link registry poisoned")?;
    let r = lock.as_mut().ok_or("link registry is sealed")?;
    if r.symbols.len() == 256 {
        return Err("symbol limit".into());
    }
    let module = match r.modules.iter().position(|m| m == module) {
        Some(m) => m,
        None => {
            if r.modules.len() == 32 {
                return Err("module limit".into());
            }
            r.modules.push(module.into());
            r.modules.len() - 1
        }
    };
    if r.symbols
        .iter()
        .any(|s| s.module == module && s.name == name)
    {
        return Err("duplicate symbol declaration".into());
    }
    r.symbols.push(Symbol {
        module,
        name: name.into(),
        arity: signature.parameters.len(),
        kind: KIND,
        call: None,
        signature: Some(signature),
        typed_call: None,
    });
    Ok(())
}
#[no_mangle]
pub unsafe extern "C" fn urotif_host_declare_v2(
    p: *const u8,
    n: usize,
    error: *mut u8,
    cap: usize,
) -> i32 {
    unsafe { host::finish(host::caught(|| declare(host::input(p, n)?)), error, cap) }
}
#[no_mangle]
pub unsafe extern "C" fn urotif_host_signature(
    id: i32,
    kinds: *mut i32,
    result: *mut i32,
    error: *mut u8,
    cap: usize,
) -> i32 {
    unsafe {
        host::finish(
            host::caught(|| {
                if kinds.is_null() || result.is_null() {
                    return Err("null signature output".into());
                }
                *result = 0;
                for i in 0..8 {
                    *kinds.add(i) = 0;
                }
                let sig = host::registry()
                    .symbols
                    .get(usize::try_from(id).map_err(|_| "bad reference")?)
                    .and_then(|s| s.signature.as_ref())
                    .ok_or("not a typed reference")?;
                for (i, k) in sig.parameters.iter().enumerate() {
                    *kinds.add(i) = *k as i32;
                }
                *result = sig.result as i32;
                Ok(())
            }),
            error,
            cap,
        )
    }
}
#[no_mangle]
pub unsafe extern "C" fn urotif_host_call_v2(
    id: i32,
    args: *const TypedArg,
    n: usize,
    out: *mut TypedResult,
    error: *mut u8,
    cap: usize,
) -> i32 {
    unsafe {
        host::finish(
            host::caught(|| {
                if out.is_null() || (out as usize) % align_of::<TypedResult>() != 0 {
                    return Err("null/misaligned typed result".into());
                }
                let s = host::registry()
                    .symbols
                    .get(usize::try_from(id).map_err(|_| "bad reference")?)
                    .ok_or("bad reference")?;
                let sig = s.signature.as_ref().ok_or("not a typed reference")?;
                let f = s
                    .typed_call
                    .ok_or("typed external declared but no native implementation was linked")?;
                checked_call(f, sig, view(args, n, 8)?, &mut *out)
            }),
            error,
            cap,
        )
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn signature_parser() {
        assert_eq!(
            Signature::parse("bytes,number->vector").unwrap().parameters,
            vec![2, 1]
        );
        assert!(Signature::parse("->bytes").is_ok());
        for s in ["bytes", "foo->bytes", "number,->number", "bytes->object"] {
            assert!(Signature::parse(s).is_err());
        }
    }
    #[test]
    #[cfg(target_pointer_width = "64")]
    fn native_layout() {
        assert_eq!(size_of::<TypedArg>(), 48);
        assert_eq!(size_of::<TypedResult>(), 56);
        assert_eq!(std::mem::offset_of!(TypedArg, vector), 32);
        assert_eq!(std::mem::offset_of!(TypedResult, count), 48);
    }
    unsafe extern "C" fn bad_capacity(_: *const TypedArg, _: usize, out: *mut TypedResult) -> i32 {
        unsafe { (*out).capacity += 1 };
        0
    }
    unsafe extern "C" fn bad_length(_: *const TypedArg, _: usize, out: *mut TypedResult) -> i32 {
        unsafe { (*out).length = (*out).capacity + 1 };
        0
    }
    unsafe extern "C" fn no_result(_: *const TypedArg, _: usize, _: *mut TypedResult) -> i32 {
        0
    }
    #[test]
    fn result_contract() {
        let mut b = [0u8; 8];
        let mut v = [0.0; 8];
        for (f, result) in [
            (bad_capacity as TypedFn, 2),
            (bad_length as TypedFn, 2),
            (no_result as TypedFn, 1),
        ] {
            let mut out = TypedResult {
                number: 0.0,
                bytes: b.as_mut_ptr(),
                capacity: 8,
                length: 0,
                vector: v.as_mut_ptr(),
                vector_capacity: 8,
                count: 0,
            };
            let sig = Signature::checked(&[], result).unwrap();
            assert!(unsafe { checked_call(f, &sig, &[], &mut out) }.is_err());
        }
    }
    #[test]
    fn arity_and_buffer_guards() {
        assert!(Signature::checked(&[1; 8], 3).is_ok());
        assert!(Signature::checked(&[1; 9], 3).is_err());
        assert!(buffer_guard::<f64>(std::ptr::null(), 0, 8).is_ok());
        assert!(buffer_guard::<f64>(std::ptr::null(), 1, 8).is_err());
        assert!(buffer_guard::<f64>(1usize as *const f64, 1, 8).is_err());
        assert!(buffer_guard::<u8>((usize::MAX - 2) as *const u8, 4, 8).is_err());
    }
    #[test]
    fn argument_contract_is_checked_before_call() {
        let mut b = [0u8; 8];
        let mut v = [0.0; 8];
        let nan = [f64::NAN];
        let mut out = TypedResult {
            number: 0.0,
            bytes: b.as_mut_ptr(),
            capacity: 8,
            length: 0,
            vector: v.as_mut_ptr(),
            vector_capacity: 8,
            count: 0,
        };
        let bad = [
            TypedArg {
                tag: 1,
                number: f64::INFINITY,
                ..TypedArg::default()
            },
            TypedArg {
                tag: 1,
                reserved: 1,
                ..TypedArg::default()
            },
            TypedArg {
                tag: 2,
                length: 1,
                ..TypedArg::default()
            },
            TypedArg {
                tag: 3,
                vector: nan.as_ptr(),
                count: 1,
                ..TypedArg::default()
            },
        ];
        for arg in bad {
            let sig = Signature::checked(&[arg.tag], 1).unwrap();
            // This function would change capacity if reached; guard rejection must precede it.
            assert!(unsafe { checked_call(bad_capacity, &sig, &[arg], &mut out) }.is_err());
            assert_eq!(out.capacity, 8);
        }
    }
}
