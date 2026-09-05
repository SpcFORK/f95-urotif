// ABI-2 Rust plugin. Canonical functions also link into generated native code.
#[path = "../runtime/typed_abi.rs"]
mod abi;
use abi::{TypedArg, TypedFn, TypedResult};
use std::{
    ffi::c_char,
    panic::{catch_unwind, AssertUnwindSafe},
};
unsafe fn bytes<'a>(
    a: *const TypedArg,
    n: usize,
    r: *mut TypedResult,
) -> Result<(&'a [u8], &'a mut TypedResult), i32> {
    if n != 1 || a.is_null() || r.is_null() {
        return Err(1);
    }
    let a = unsafe { &*a };
    if a.tag != 2 || (a.length > 0 && a.bytes.is_null()) {
        return Err(1);
    }
    let b = if a.length == 0 {
        &[]
    } else {
        unsafe { std::slice::from_raw_parts(a.bytes, a.length) }
    };
    Ok((b, unsafe { &mut *r }))
}
#[no_mangle]
pub unsafe extern "C" fn urotif_ext_unicode_upper(
    a: *const TypedArg,
    n: usize,
    r: *mut TypedResult,
) -> i32 {
    catch_unwind(AssertUnwindSafe(|| unsafe {
        let (b, r) = match bytes(a, n, r) {
            Ok(x) => x,
            Err(e) => return e,
        };
        let s = match std::str::from_utf8(b) {
            Ok(s) => s,
            Err(_) => return 1,
        };
        let result = s.to_uppercase();
        if result.len() > r.capacity {
            return 2;
        }
        if !result.is_empty() {
            std::ptr::copy_nonoverlapping(result.as_ptr(), r.bytes, result.len())
        }
        r.length = result.len();
        0
    }))
    .unwrap_or(1)
}
#[no_mangle]
pub unsafe extern "C" fn urotif_ext_unicode_codepoints(
    a: *const TypedArg,
    n: usize,
    r: *mut TypedResult,
) -> i32 {
    catch_unwind(AssertUnwindSafe(|| unsafe {
        let (b, r) = match bytes(a, n, r) {
            Ok(x) => x,
            Err(e) => return e,
        };
        let s = match std::str::from_utf8(b) {
            Ok(s) => s,
            Err(_) => return 1,
        };
        r.number = s.chars().count() as f64;
        0
    }))
    .unwrap_or(1)
}
#[no_mangle]
pub unsafe extern "C" fn urotif_ext_unicode_sort(
    a: *const TypedArg,
    n: usize,
    r: *mut TypedResult,
) -> i32 {
    catch_unwind(AssertUnwindSafe(|| unsafe {
        if n != 1 || a.is_null() || r.is_null() {
            return 1;
        }
        let a = &*a;
        let r = &mut *r;
        if a.tag != 3 || a.count > r.vector_capacity {
            return 2;
        }
        if a.count > 0 {
            if a.vector.is_null() || r.vector.is_null() {
                return 1;
            }
            let values = std::slice::from_raw_parts(a.vector, a.count);
            if values.iter().any(|x| !x.is_finite()) {
                return 1;
            }
            let out = std::slice::from_raw_parts_mut(r.vector, a.count);
            out.copy_from_slice(values);
            out.sort_by(f64::total_cmp);
        }
        r.count = a.count;
        0
    }))
    .unwrap_or(1)
}
#[cfg(not(urotif_static_link))]
mod descriptor {
    use super::*;
    #[repr(C)]
    struct Symbol {
        name: *const c_char,
        arity: u32,
        parameters: [u32; 8],
        result: u32,
        call: Option<TypedFn>,
    }
    #[repr(C)]
    pub struct Plugin {
        abi: u32,
        struct_size: u32,
        module: *const c_char,
        count: usize,
        symbols: *const Symbol,
    }
    // These descriptors and every pointer target are immutable static data.
    unsafe impl Sync for Symbol {}
    unsafe impl Sync for Plugin {}
    static SYMBOLS: [Symbol; 3] = [
        Symbol {
            name: b"upper\0".as_ptr() as *const c_char,
            arity: 1,
            parameters: [2, 0, 0, 0, 0, 0, 0, 0],
            result: 2,
            call: Some(urotif_ext_unicode_upper),
        },
        Symbol {
            name: b"codepoints\0".as_ptr() as *const c_char,
            arity: 1,
            parameters: [2, 0, 0, 0, 0, 0, 0, 0],
            result: 1,
            call: Some(urotif_ext_unicode_codepoints),
        },
        Symbol {
            name: b"sort\0".as_ptr() as *const c_char,
            arity: 1,
            parameters: [3, 0, 0, 0, 0, 0, 0, 0],
            result: 3,
            call: Some(urotif_ext_unicode_sort),
        },
    ];
    static PLUGIN: Plugin = Plugin {
        abi: 2,
        struct_size: std::mem::size_of::<Plugin>() as u32,
        module: b"unicode\0".as_ptr() as *const c_char,
        count: 3,
        symbols: SYMBOLS.as_ptr(),
    };
    #[no_mangle]
    pub extern "C" fn urotif_plugin_v2() -> *const Plugin {
        &PLUGIN
    }
}
