//! Build as cdylib for the Fortran host. Use --cfg static_link when building
//! a staticlib for an emitted native program, to omit the loader entry symbol.
use std::ffi::c_char;
#[repr(C)]
struct Symbol {
    name: *const c_char,
    arity: u32,
    call: unsafe extern "C" fn(*const f64, usize, *mut f64) -> i32,
}
#[repr(C)]
struct Plugin {
    abi: u32,
    module: *const c_char,
    count: usize,
    symbols: *const Symbol,
}
// These descriptors only point to immutable static bytes, a static table, and
// code. No shared mutable state is exposed through either pointer.
unsafe impl Sync for Symbol {}
unsafe impl Sync for Plugin {}
#[no_mangle]
pub unsafe extern "C" fn urotif_ext_rustdemo_twice(a: *const f64, n: usize, out: *mut f64) -> i32 {
    if n != 1 || a.is_null() || out.is_null() {
        return 1;
    }
    let x = unsafe { *a } * 2.0;
    if !x.is_finite() {
        return 1;
    }
    unsafe { *out = x };
    0
}
#[cfg(not(static_link))]
static SYMBOLS: [Symbol; 1] = [Symbol {
    name: b"twice\0".as_ptr() as *const c_char,
    arity: 1,
    call: urotif_ext_rustdemo_twice,
}];
#[cfg(not(static_link))]
static PLUGIN: Plugin = Plugin {
    abi: 1,
    module: b"rustdemo\0".as_ptr() as *const c_char,
    count: 1,
    symbols: SYMBOLS.as_ptr(),
};
#[cfg(not(static_link))]
#[no_mangle]
pub extern "C" fn urotif_plugin_v1() -> *const std::ffi::c_void {
    &PLUGIN as *const Plugin as *const std::ffi::c_void
}
