// Explicitly granted WASM host implementations; no native plugin is loaded.
export default {
  'demo.cube': ([x]) => x * x * x,
  'demo.sum3': ([a, b, c]) => a + b + c,
  'demo.affine': ([a, b, c]) => a * b + c,
  'rustdemo.twice': ([x]) => x * 2,
};
