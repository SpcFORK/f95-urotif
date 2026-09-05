// Shared native/WASM ABI declarations. No ownership crosses these raw views.
#[repr(C)]
#[derive(Clone, Copy, Debug)]
pub struct TypedArg {
    pub tag: u32,
    pub reserved: u32,
    pub number: f64,
    pub bytes: *const u8,
    pub length: usize,
    pub vector: *const f64,
    pub count: usize,
}
impl Default for TypedArg {
    fn default() -> Self {
        Self {
            tag: 0,
            reserved: 0,
            number: 0.0,
            bytes: std::ptr::null(),
            length: 0,
            vector: std::ptr::null(),
            count: 0,
        }
    }
}
#[repr(C)]
#[derive(Debug)]
pub struct TypedResult {
    pub number: f64,
    pub bytes: *mut u8,
    pub capacity: usize,
    pub length: usize,
    pub vector: *mut f64,
    pub vector_capacity: usize,
    pub count: usize,
}
pub type TypedFn = unsafe extern "C" fn(*const TypedArg, usize, *mut TypedResult) -> i32;
