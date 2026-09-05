//! Link once, seal once, then use stable integer handles. No loader is exposed
//! to Urotif source. Native plugins must be trusted; an ABI check is not a sandbox.
use libloading::Library;
use std::ffi::c_char;
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::sync::{Mutex, OnceLock};

pub type NumberFn = unsafe extern "C" fn(*const f64, usize, *mut f64) -> i32;
#[repr(C)]
pub struct PluginSymbol {
    name: *const c_char,
    arity: u32,
    call: Option<NumberFn>,
}
#[repr(C)]
pub struct Plugin {
    abi: u32,
    module: *const c_char,
    count: usize,
    symbols: *const PluginSymbol,
}
#[derive(Clone, Debug)]
pub struct Symbol {
    pub module: usize,
    pub name: String,
    pub arity: usize,
    pub kind: i32,
    pub call: Option<NumberFn>,
    pub signature: Option<crate::typed::Signature>,
    pub typed_call: Option<crate::typed::TypedFn>,
}
pub struct Registry {
    pub modules: Vec<String>,
    pub symbols: Vec<Symbol>,
    _libraries: Vec<Library>,
}
static BUILDER: OnceLock<Mutex<Option<Registry>>> = OnceLock::new();
static SEALED: OnceLock<Registry> = OnceLock::new();

unsafe extern "C" fn sqrt(a: *const f64, n: usize, o: *mut f64) -> i32 {
    if n != 1 {
        return 1;
    }
    unsafe { *o = (*a).sqrt() };
    0
}
unsafe extern "C" fn square(a: *const f64, n: usize, o: *mut f64) -> i32 {
    if n != 1 {
        return 1;
    }
    unsafe { *o = *a * *a };
    0
}
unsafe extern "C" fn abs(a: *const f64, n: usize, o: *mut f64) -> i32 {
    if n != 1 {
        return 1;
    }
    unsafe { *o = (*a).abs() };
    0
}
unsafe extern "C" fn add(a: *const f64, n: usize, o: *mut f64) -> i32 {
    if n != 2 {
        return 1;
    }
    unsafe { *o = *a + *a.add(1) };
    0
}
fn initial() -> Registry {
    let mut r = Registry {
        modules: vec!["std".into(), "math".into()],
        symbols: Vec::new(),
        _libraries: Vec::new(),
    };
    for (name, kind) in [("int", 1), ("float", 2), ("string", 3), ("len", 4)] {
        r.symbols.push(Symbol {
            module: 0,
            name: name.into(),
            arity: 1,
            kind,
            call: None,
            signature: None,
            typed_call: None,
        });
    }
    for (name, arity, f) in [
        ("sqrt", 1, sqrt as NumberFn),
        ("square", 1, square as NumberFn),
        ("abs", 1, abs as NumberFn),
        ("add", 2, add as NumberFn),
    ] {
        r.symbols.push(Symbol {
            module: 1,
            name: name.into(),
            arity,
            kind: 0,
            call: Some(f),
            signature: None,
            typed_call: None,
        });
    }
    r
}
pub(crate) fn builder() -> &'static Mutex<Option<Registry>> {
    BUILDER.get_or_init(|| Mutex::new(Some(initial())))
}
pub fn registry() -> &'static Registry {
    SEALED.get_or_init(|| builder().lock().unwrap().take().unwrap_or_else(initial))
}
pub fn resolve(module: usize, name: &str) -> Result<usize, String> {
    registry()
        .symbols
        .iter()
        .position(|s| s.module == module && s.name == name)
        .ok_or_else(|| format!("unresolved symbol {name}"))
}
pub fn qualified(name: &str) -> Result<usize, String> {
    let (module, symbol) = name.split_once('.').unwrap_or(("std", name));
    let m = registry()
        .modules
        .iter()
        .position(|m| m == module)
        .ok_or_else(|| format!("module not granted: {module}"))?;
    resolve(m, symbol)
}
pub(crate) fn ident(s: &str) -> bool {
    !s.is_empty()
        && s.len() <= 63
        && s.bytes()
            .enumerate()
            .all(|(i, c)| c.is_ascii_alphabetic() || c == b'_' || (i > 0 && c.is_ascii_digit()))
}
pub(crate) unsafe fn c_name(p: *const c_char) -> Result<String, String> {
    if p.is_null() {
        return Err("null plugin name".into());
    }
    // Valid bounded strings are a requirement on a TRUSTED plugin, not something
    // arbitrary foreign pointers can be made safe by checking for null alone.
    let mut bytes = Vec::new();
    for i in 0..64 {
        let c = unsafe { *p.add(i) } as u8;
        if c == 0 {
            let s = String::from_utf8(bytes).map_err(|_| "plugin name is not UTF-8")?;
            if !ident(&s) {
                return Err("plugin identifiers must be ASCII, 1..63 bytes".into());
            }
            return Ok(s);
        }
        bytes.push(c)
    }
    Err("plugin name exceeds 63 bytes".into())
}
pub fn load(path: &str) -> Result<(), String> {
    let mut guard = builder().lock().map_err(|_| "link registry poisoned")?;
    let r = guard
        .as_mut()
        .ok_or("link registry is sealed; load plugins before execution/emission")?;
    if !std::path::Path::new(path).is_file() {
        return Err("--link requires an explicit existing file path".into());
    }
    if r.modules.len() >= 32 {
        return Err("module limit (32)".into());
    }
    let lib = unsafe { Library::new(std::fs::canonicalize(path).map_err(|e| e.to_string())?) }
        .map_err(|e| e.to_string())?;
    if let Some((module, symbols)) = unsafe { crate::typed::load(&lib, r.modules.len())? } {
        if r.modules.contains(&module) {
            return Err(format!("duplicate module: {module}"));
        }
        if r.symbols.len() + symbols.len() > 256 {
            return Err("symbol limit (256)".into());
        }
        r.modules.push(module);
        r.symbols.extend(symbols);
        r._libraries.push(lib);
        return Ok(());
    }
    let entry =
        unsafe { lib.get::<unsafe extern "C" fn() -> *const Plugin>(b"urotif_plugin_v1\0") }
            .map_err(|e| e.to_string())?;
    let p = unsafe { entry() };
    if p.is_null() {
        return Err("null plugin descriptor".into());
    }
    let p = unsafe { &*p };
    if p.abi != 1 || p.count == 0 || p.count > 128 || p.symbols.is_null() {
        return Err("invalid plugin ABI/table".into());
    }
    let module = unsafe { c_name(p.module) }?;
    if r.modules.contains(&module) {
        return Err(format!("duplicate module: {module}"));
    }
    if r.symbols.len() + p.count > 256 {
        return Err("symbol limit (256)".into());
    }
    let mut symbols = Vec::new();
    for s in unsafe { std::slice::from_raw_parts(p.symbols, p.count) } {
        let name = unsafe { c_name(s.name) }?;
        if s.arity > 8 || s.call.is_none() {
            return Err("invalid symbol signature".into());
        }
        if symbols.iter().any(|x: &Symbol| x.name == name) {
            return Err(format!("duplicate symbol: {name}"));
        }
        symbols.push(Symbol {
            module: r.modules.len(),
            name,
            arity: s.arity as usize,
            kind: 0,
            call: s.call,
            signature: None,
            typed_call: None,
        });
    }
    r.modules.push(module);
    r.symbols.extend(symbols);
    r._libraries.push(lib);
    Ok(())
}
pub(crate) unsafe fn input<'a>(p: *const u8, n: usize) -> Result<&'a str, String> {
    if n > 4096 || (n > 0 && p.is_null()) {
        return Err("invalid string buffer".into());
    }
    let b = if n == 0 {
        &[]
    } else {
        unsafe { std::slice::from_raw_parts(p, n) }
    };
    std::str::from_utf8(b).map_err(|_| "expected UTF-8 metadata".into())
}
pub(crate) unsafe fn finish(result: Result<(), String>, err: *mut u8, cap: usize) -> i32 {
    let (status, text) = match result {
        Ok(()) => (0, String::new()),
        Err(e) => (1, e),
    };
    if cap > 0 && !err.is_null() {
        let n = text.len().min(cap - 1);
        unsafe {
            std::ptr::copy_nonoverlapping(text.as_ptr(), err, n);
            *err.add(n) = 0;
        }
    }
    status
}
pub(crate) fn caught(f: impl FnOnce() -> Result<(), String>) -> Result<(), String> {
    catch_unwind(AssertUnwindSafe(f)).unwrap_or_else(|_| Err("backend panic contained".into()))
}
#[no_mangle]
pub unsafe extern "C" fn urotif_host_load(p: *const u8, n: usize, err: *mut u8, cap: usize) -> i32 {
    unsafe { finish(caught(|| load(input(p, n)?)), err, cap) }
}
#[no_mangle]
pub unsafe extern "C" fn urotif_host_lookup(
    mode: i32,
    module: i32,
    p: *const u8,
    n: usize,
    id: *mut i32,
    arity: *mut i32,
    kind: *mut i32,
    err: *mut u8,
    cap: usize,
) -> i32 {
    unsafe {
        finish(
            caught(|| {
                if id.is_null() || arity.is_null() || kind.is_null() {
                    return Err("null result pointer".into());
                }
                *id = -1;
                *arity = 0;
                *kind = 0;
                if !(0..=2).contains(&mode) {
                    return Err("invalid lookup mode".into());
                }
                let name = input(p, n)?;
                if mode == 0 {
                    *id = registry()
                        .modules
                        .iter()
                        .position(|m| m == name)
                        .ok_or_else(|| format!("module not granted: {name}"))?
                        as i32;
                } else {
                    let slot = if mode == 2 {
                        qualified(name)?
                    } else {
                        resolve(usize::try_from(module).map_err(|_| "bad module")?, name)?
                    };
                    let s = &registry().symbols[slot];
                    *id = slot as i32;
                    *arity = s.arity as i32;
                    *kind = s.kind;
                }
                Ok(())
            }),
            err,
            cap,
        )
    }
}
#[no_mangle]
pub unsafe extern "C" fn urotif_host_call(
    id: i32,
    args: *const f64,
    n: usize,
    out: *mut f64,
    err: *mut u8,
    cap: usize,
) -> i32 {
    unsafe {
        finish(
            caught(|| {
                let s = registry()
                    .symbols
                    .get(usize::try_from(id).map_err(|_| "bad reference")?)
                    .ok_or("bad reference")?;
                if n != s.arity || n > 8 || out.is_null() || (n > 0 && args.is_null()) {
                    return Err("external arity/buffer mismatch".into());
                }
                let f = s
                    .call
                    .ok_or("external declared but no native implementation was linked")?;
                *out = f64::NAN;
                if f(args, n, out) != 0 {
                    return Err("external service returned failure".into());
                }
                if !(*out).is_finite() {
                    return Err("external service returned non-finite result".into());
                }
                Ok(())
            }),
            err,
            cap,
        )
    }
}
#[no_mangle]
pub unsafe extern "C" fn urotif_host_catalog(out: *mut u8, cap: usize) -> i32 {
    let result = caught(|| {
        let r = registry();
        let mut s = String::from("Linked modules / symbols (registry sealed):\n");
        for (i, x) in r.symbols.iter().enumerate() {
            s.push_str(&format!(
                "{i:3}  {}.{} / {} argument(s){}\n",
                r.modules[x.module],
                x.name,
                x.arity,
                x.signature
                    .as_ref()
                    .map(|v| format!(" [ABI 2: {}]", v.display()))
                    .unwrap_or_default()
            ));
        }
        if out.is_null() || cap <= s.len() {
            return Err("catalog buffer too small".into());
        }
        unsafe {
            std::ptr::copy_nonoverlapping(s.as_ptr(), out, s.len());
            *out.add(s.len()) = 0;
        }
        Ok(())
    });
    if result.is_ok() {
        0
    } else {
        1
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn builtin_registry_is_typed() {
        assert_eq!(qualified("std.int").unwrap(), 0);
        assert_eq!(registry().symbols[qualified("math.add").unwrap()].arity, 2);
    }
    #[test]
    fn unknown_modules_are_denied() {
        assert!(qualified("filesystem.read").is_err());
    }
    #[test]
    fn identifiers_are_not_paths() {
        assert!(!ident("../evil"));
        assert!(ident("math_2"));
    }
}

pub fn declare(spec: &str) -> Result<(), String> {
    let (qualified, arity) = spec.split_once('/').ok_or("use MODULE.SYMBOL/ARITY")?;
    let (module, name) = qualified.split_once('.').ok_or("use MODULE.SYMBOL/ARITY")?;
    let arity = arity.parse::<usize>().map_err(|_| "arity must be 0..8")?;
    if !ident(module) || !ident(name) || arity > 8 {
        return Err("invalid external declaration".into());
    }
    if module == "std" || module == "math" {
        return Err("built-in modules cannot be extended or overridden".into());
    }
    let mut lock = builder().lock().map_err(|_| "link registry poisoned")?;
    let r = lock.as_mut().ok_or("link registry is sealed")?;
    if r.symbols.len() >= 256 {
        return Err("symbol limit".into());
    }
    let m = match r.modules.iter().position(|m| m == module) {
        Some(i) => i,
        None => {
            if r.modules.len() == 32 {
                return Err("module limit".into());
            }
            r.modules.push(module.into());
            r.modules.len() - 1
        }
    };
    if r.symbols.iter().any(|s| s.module == m && s.name == name) {
        return Err("duplicate symbol declaration".into());
    }
    r.symbols.push(Symbol {
        module: m,
        name: name.into(),
        arity,
        kind: 0,
        call: None,
        signature: None,
        typed_call: None,
    });
    Ok(())
}
#[no_mangle]
pub unsafe extern "C" fn urotif_host_declare(
    p: *const u8,
    n: usize,
    err: *mut u8,
    cap: usize,
) -> i32 {
    unsafe { finish(caught(|| declare(input(p, n)?)), err, cap) }
}
