> **0.4:** ABI 2 adds bounded number/bytes/flat-vector signatures across native execution and emitted C, Rust, Fortran and WASM. See [TYPED_LINKS.md](../TYPED_LINKS.md) and `include/urotif_plugin_v2.h`. ABI 1 below remains supported. Strict `--f95` output rejects foreign bindings; standardized C interop uses a separate F2003 adapter. Recovery does not authorize or load a library.


# Foundation linking and host ABI

## Two separate boundaries

1. **Compiler IR2 boundary:** Fortran-owned source decoding → native Rust code generator. Header: `include/urotif_foundation.h`.
2. **Foreign-service ABIs:** ABI 1 numeric services (`include/urotif_plugin.h`) and ABI 2 typed values (`include/urotif_plugin_v2.h`). These are independent of the compiler IR/emission ABI version.

Do not confuse either with the older experimental `include/urotif_backend.h` / WASM IR1 interface.

## ABI-1 native plugin descriptor

A shared library exports `urotif_plugin_v1()`, returning an immutable `UrotifPlugin`:

- ABI version 1.
- Module name: ASCII identifier, 1–63 bytes.
- 1–128 symbols.
- Each symbol: ASCII identifier, 1–63 bytes; arity 0–8; numeric function pointer.
- Descriptors, strings, tables, and function code must remain valid until process termination.

Numeric function signature:

```c
int32_t function(const double *args, size_t argc, double *result);
```

Arguments and result are binary64. Success is zero status and a finite result. The service must write exactly one result, preserve the caller's floating-point environment, and neither retain borrowed pointers nor unwind through the ABI. The host initializes a result sentinel so a missing write is not accepted as an accidental zero.

The native registry has 32 module slots and 256 symbol slots, including `std` and `math`. CLI grants are processed before source execution/compilation. The first lookup, catalog request, or emitter access seals the registry. Numeric reference IDs are stable **within that registry**, not guaranteed to match a different declaration order or link set.

## C example

`plugins/demo.c` exports these native implementations:

```c
int32_t urotif_ext_demo_cube(const double *a, size_t n, double *out) {
    if (n != 1 || !a || !out) return 1;
    *out = a[0] * a[0] * a[0];
    return isfinite(*out) ? 0 : 1;
}
```

The file also defines the descriptor for dynamic loading, plus `sum3` and `affine`. `affine(2,3,5)` returns 11 and is used to verify argument order.

```sh
make plugins
bin/urotif links --link build/demo.so
bin/urotif run examples/foundation/plugin.utf --foundation --link build/demo.so
# 27
```

For an emitted native C program, declare only the needed signature and link the implementation object:

```sh
bin/urotif c examples/foundation/plugin.utf --foundation \
  --extern demo.cube/1 -o build/plugin.c
gcc -std=c99 -O3 build/plugin.c build/demo.o -lm -o build/plugin-c
build/plugin-c --json
```

`build/demo.o` is compiled with `-DUROTIF_STATIC_LINK`. This omits the common `urotif_plugin_v1` descriptor export, preventing duplicate loader-entry symbols when multiple plugin objects are linked into one executable. Native service symbols use the convention `urotif_ext_MODULE_SYMBOL`.

## Rust example

`plugins/rust_demo.rs` has no third-party dependency and exports `rustdemo.twice` through the same C-compatible descriptor.

```sh
rustc --edition=2021 -O --crate-type=cdylib plugins/rust_demo.rs -o build/rust_demo.so
bin/urotif links --link build/rust_demo.so
```

In Foundation:

```text
{21}[rustdemo.twice]r@@$
```

prints `42` when that library is granted.

For emitted Rust using the C demo implementation:

```sh
bin/urotif rust examples/foundation/plugin.utf --foundation \
  --extern demo.cube/1 -o build/plugin.rs
rustc --edition=2021 -O -C strip=symbols -A dead_code -A unused_imports \
  -C link-arg=build/demo.o build/plugin.rs -o build/plugin-rust
build/plugin-rust --json
```

The Rust demo also supports `--cfg static_link` when building a static library, to omit its loader descriptor. Rust static libraries may need platform system-library flags; inspect the compiler's `--print=native-static-libs` output. The recorded cross-target tests use the C demo object, and separately verify that the native Fortran host can load and call the Rust shared library.

## WASM imports without native loading

```sh
bin/urotif wasm examples/foundation/plugin.utf --foundation \
  --extern demo.cube/1 -o build/plugin.wasm
node tools/foundation-wasm.mjs build/plugin.wasm \
  --host plugins/demo-host.mjs --json
```

`--extern` is metadata, not library loading. `--link` loads native code even when the eventual output is WASM; use it only for trusted libraries.

A WASM foreign import is named `MODULE.SYMBOL` and has the low-level signature:

```text
(args_pointer: i32, argument_count: i32, result_pointer: i32) -> status: i32
```

Pointers are offsets in the instance's linear memory. Arguments and the result are little-endian f64 values, aligned to eight bytes. The generated caller checks arity/types. The supplied host checks pointer ranges, count, alignment, finite input/output, and synchronous results. It copies arguments before invoking a granted JS function and refreshes memory views before writing the result.

`plugins/demo-host.mjs` exports explicit functions, for example:

```js
export default {
  'demo.cube': ([x]) => x * x * x,
};
```

The actual demo file supplies all three C-demo functions and `rustdemo.twice`. The host must grant every import retained in the compiled catalog. A whole loaded plugin grants its entire symbol table; signature-only declarations can make that set smaller. Missing imports are rejected—never replaced with a zero-returning stub.

New ABI-2 WASM providers must declare exact parameter/result kinds; see `plugins/typed-host.mjs`. New modules embed a `urotif.links.v2` catalog. The host still accepts old numeric-only modules without that section.

## WASM public run interface

Foundation modules export:

| Export | Meaning |
|---|---|
| `memory` | Linear memory |
| `urotif_input_ptr()` | Writable input-buffer offset |
| `urotif_input_capacity()` | Compiled input capacity (default 1 MiB) |
| `urotif_uses_input()` | Conservative bytecode-read flag |
| `urotif_run(input_length, fuel)` | Reset and execute; return status |
| `urotif_output_ptr()` / `urotif_output_len()` | Output bytes from the most recent call |
| `urotif_steps()` | Logical source-instruction count |
| `urotif_error_line()` / `urotif_error_column()` | One-based diagnostic location |
| `urotif_collections()` | GC count for that run |
| `urotif_stack_depth()` | Final data-stack depth |

Call `urotif_input_ptr()` before filling input, then refresh your view of `memory.buffer`: allocation can grow memory. Fill at most the exported capacity. Call `urotif_run`; afterwards obtain fresh output pointers/views. Output and diagnostics are reset even for an invalid input-length/fuel request. A fuel value of zero stops before the first executable instruction; the CLI requires positive fuel. Values above 2^31−1 are rejected by this ABI implementation.

Do not reenter a running instance from an import. Do not retain pointers across runs or assume a typed-array view survives memory growth. Use `tools/foundation-wasm.mjs`, not the older `tools/wasm-run.mjs`, which implements the **different IR1 ABI**.

## Error categories

| Code | Category |
|---|---|
| P001 | Data-stack underflow |
| P002 | Resource/work limit |
| P003 | Construction/escape error |
| P004 | Data type / numeric-construction error |
| P005 | Indexing error |
| P006 | Unsupported operation / invalid `@` command |
| P007 | Coordinate error |
| P008 | Fuel exhausted |
| P009 | Input error or exhausted input |
| P010 | Arithmetic, non-finite result, or exact-integer overflow |
| P011 | Import/name/reference resolution |
| P012 | Foreign/std application, arity, conversion, or service result |
| P013 | Call/return contract |

Foreign nonzero statuses map to P012. These are bounded-runtime categories, not a foreign exception transport.

## Trust and isolation

- Native plugins can execute constructors during loading and can access the host process's privileges. No ABI test proves hostile memory is valid.
- `catch_unwind` contains appropriate **host Rust unwinding panics**, not aborts, segfaults, arbitrary plugin panics across `extern "C"`, or foreign exceptions.
- Loader/VM reentrancy is not supported. Callbacks must return synchronously and respect the borrowed-buffer contract.
- Fuel cannot interrupt a slow/hung import or constructor. Use OS/process/worker timeouts when hosting untrusted workloads.
- Generated WASM has no ambient filesystem/network API in this runtime, but an import can grant powerful effects. Trust and validate the host implementation.
- This project uses explicit core-WASM imports, **not the WASI Component Model or WIT**.

ABI 1 remains numeric-only by design. ABI 2 now supplies the separate borrowed-byte/flat-vector channel with explicit ownership, capacities and signatures; it does not expose VM node handles. See [the 0.4 contract and examples](../TYPED_LINKS.md).
