# Urotif 0.4 — typed libraries, the same small language

**Fortran Main → Fortran-decoded IR → Rust chain → C / Rust / Fortran / WASM.**

This milestone removes the numeric-only foreign-call bottleneck. ABI 2 adds **number, bytes, and flat numeric vector** parameters/results. It uses the existing first-class references, direct `@` application, packet `a@` application, and subroutines. No new Urotif opcode is required for these libraries.

- `make typed-examples` generates the local `TYPED_LINKS.html` inspector with actual generated files and library implementations.
- [examples/typed/](examples/typed/): ten source/assembled examples; [cases.json](examples/typed/cases.json) records imports and exact expected output bytes.
- [lib/typed.ufm](lib/typed.ufm): convenience words implemented as ordinary source macros.
- `artifacts/typed/`: generated files, catalogs, and execution/recovery records, created locally and ignored by Git.
- [ROUNDTRIP.md](ROUNDTRIP.md): the 0.3 baseline, resource-policy ranges, source libraries, streaming I/O, and source capsules.

## What changed—and what did not

| Area | 0.4 behavior |
|---|---|
| Frontend / main | Still Fortran; Rust receives decoded IR, not Urotif source to parse |
| Value and marshalling core | Compiles as strict F95 |
| Standard C interoperability | Isolated F2003 adapter, both native and in emitted Fortran |
| Existing native plugins | ABI 1 is retained unchanged for numeric calls |
| New typed plugins | Separate `urotif_plugin_v2` descriptor and typed call signature |
| Generated C / Rust / Fortran | Generic marshalling plus signature-generated canonical bindings |
| WASM | Core-WASM, not WASI/WIT; typed import catalog plus explicit JS provider grants |
| Source recovery | Optional normalized-source metadata, not decompilation or edit synchronization |
| Resource policy | The existing eleven checked budgets remain; foreign calls do not disable them |

**An internal reference kind is not a new source opcode.** Kind 7 selects generic typed marshalling. Adding a function means implementing its library body and declaring its signature; the compiler mechanically generates a binding. There is no hand-maintained `buffers.hex` or `unicode.upper` case in the generic interpreter/marshaller.

## Build and run the main example

Commands below were checked on Linux with GCC/gfortran 14.2, Rust 1.98.1, Node 20.20.2, and Python 3.13.14. Other platforms/toolchains need their own ABI and link-flag verification.

```sh
# Install once if your toolchain does not already have it:
rustup target add wasm32-unknown-unknown
make all core95 plugins

bin/urotif assemble examples/typed/showcase.ufm -o examples/typed/showcase.utf
bin/urotif run examples/typed/showcase.utf --foundation \
  --link build/buffers.so --link build/unicode.so
```

Output:

```text
00ff43
[21, 41]
62
STRASSE CAFÉ
```

The C plugin converts `00 ff 43` to hex, transforms `[10, 20]` by `2*x + 1`, and sums the result. The Rust plugin uppercases valid UTF-8. The `.ufm` example invokes them with `.use hex`, `.use affine`, `.use vector_sum`, and `.use uppercase`; these are tiny source macros, not built-ins.

Use `.text`, `.number`, `.ref`, and `.bytes` for literals and names. They correctly escape UTF-8 bytes and operator characters. In raw `.utf`, an unescaped `_` is a drop instruction and an unescaped `-` is subtraction; non-pushable bytes are not automatically string characters. This remains the byte-language grammar, not a new quoted-string grammar.

## Emit all four targets without loading native code

`--extern-v2` declares only metadata. Unlike `--link`, it does **not** load a shared library or run native constructors. Quote the arrow in a shell.

For the following commands, define a Bash array once:

```sh
typed=(
  --extern-v2 'buffers.hex/bytes->bytes'
  --extern-v2 'buffers.affine/vector,number,number->vector'
  --extern-v2 'buffers.sum/vector->number'
  --extern-v2 'unicode.upper/bytes->bytes'
)
mkdir -p build/typed-demo
```

### Urotif → C

```sh
bin/urotif c examples/typed/showcase.utf --foundation --embed-source \
  "${typed[@]}" -o build/typed-demo/program.c
gcc -std=c99 -O2 build/typed-demo/program.c build/buffers.o build/libunicode.a \
  -ldl -lpthread -lm -lrt -lutil -o build/typed-demo/c-program
build/typed-demo/c-program --json
```

### Urotif → Rust

```sh
bin/urotif rust examples/typed/showcase.utf --foundation --embed-source \
  "${typed[@]}" -o build/typed-demo/program.rs
rustc --edition=2021 --crate-name typed_program -O -A dead_code -A unused_imports \
  build/typed-demo/program.rs -C link-arg=build/buffers.o \
  -C link-arg=build/libunicode.a -o build/typed-demo/rust-program
build/typed-demo/rust-program --json
```

### Urotif → Fortran

```sh
bin/urotif fortran examples/typed/showcase.utf --foundation --embed-source \
  "${typed[@]}" -o build/typed-demo/program.f90
(cd build/typed-demo && gfortran -std=f2003 -pedantic-errors -O2 -fcheck=all \
  program.f90 ../buffers.o ../libunicode.a -ldl -lpthread -lm -lrt -lutil \
  -o fortran-program)
build/typed-demo/fortran-program --json
```

Compile generated Fortran in an isolated directory: its standalone modules deliberately share names with the native core. It needs the selected plugin implementations, **not** the Rust compiler-chain library or a Urotif parser. `--f95` still produces strict-F95 standalone output for built-in-only programs; it rejects foreign bindings because standardized C interoperability is F2003.

### Urotif → WASM

```sh
bin/urotif wasm examples/typed/showcase.utf --foundation --embed-source \
  "${typed[@]}" -o build/typed-demo/program.wasm
node tools/foundation-wasm.mjs build/typed-demo/program.wasm \
  --host plugins/typed-host.mjs --json
```

WASM does not load `buffers.so` or `unicode.so`. The explicit JS host supplies corresponding operations. Its ABI-2 providers carry signatures, not just raw functions. The host validates them against `urotif.links.v2`, an embedded custom section. A sidecar `<file>.links.json` is also written for inspection. The catalog is declarative metadata, **not authentication or a capability grant**.

Old numeric WASM modules without this custom section still work with ABI-1 hosts. `plugins/all-host.mjs` grants both sample families; use it for `mixed-abi`.

Generated target programs execute decoded tables through a kernel. They are actual standalone translations, not promises of idiomatic hand-written target loops.

## Recover, re-emit, execute

```sh
bin/urotif recover build/typed-demo/program.wasm -o build/typed-demo/recovered.utf
cmp examples/typed/showcase.utf build/typed-demo/recovered.utf
bin/urotif wasm build/typed-demo/recovered.utf --foundation \
  "${typed[@]}" -o build/typed-demo/recovered.wasm
node tools/foundation-wasm.mjs build/typed-demo/recovered.wasm \
  --host plugins/typed-host.mjs --json
```

C, Rust, and Fortran capsules recover through the same `recover` command. The showcase script byte-compares all four recoveries and also re-emits/runs each sample's recovered WASM source.

Recovery restores normalized primitive `.utf`, not macro/include structure. Reapply declarations, resource policy and runtime host grants. A recovered source file cannot load or authorize a native plugin. Editing arbitrary generated code is not translated back into Urotif. The capsule's CRC is corruption detection, not a signature. Reference IDs are registry-local: preserving IDs in reflective output requires the same declaration order/link catalog.

## ABI 2 in brief

Headers: [urotif_typed_values.h](include/urotif_typed_values.h), [urotif_plugin_v2.h](include/urotif_plugin_v2.h). Rust layouts: [typed_abi.rs](runtime/typed_abi.rs).

```c
int32_t function(const UrotifTypedArg *args, size_t argc,
                 UrotifTypedResult *result);
```

| Signature kind | Tag | Urotif input | C payload | JS provider value |
|---|---:|---|---|---|
| `number` | 1 | Numeric/integer-tagged value | finite `double` | finite `number` |
| `bytes` | 2 | Byte/text value | pointer + byte length | copied `Uint8Array` |
| `vector` | 3 | Flat array of numeric values | aligned `double*` + element count | copied `Float64Array` |

- Zero to eight ordered parameters, exactly one declared result. `/->bytes` is a valid zero-argument signature.
- Numbers are binary64, not int64. Integer-tagged inputs can cross as numbers; a numeric result is a float-tagged value. There is no implicit parsing of byte strings.
- Bytes can contain NUL or invalid UTF-8. The Unicode library alone opts into UTF-8 validation. `std.len` counts bytes; `unicode.codepoints` counts Unicode scalar values, **not grapheme clusters**.
- Vectors are flat and numeric. Mixed/nested arrays, references, module handles, arbitrary objects, callbacks and opaque foreign handles are not supported by ABI 2.
- Inputs are read-only, borrowed only for the call. No VM node handles cross FFI. The F95 adapter copies into interoperable buffers; generated C/Rust may borrow byte storage and pack vectors. This is not a universal zero-copy API.
- Result buffers are caller-owned, allocated/initialized by the host. `number` starts at NaN; `length` and `count` start at zero. Zero-length byte/vector results are valid.
- A callback returns zero on success and sets the declared number, byte length, or vector count. Nonzero status becomes **P012**. The callback must fill every element it claims to have written.
- Pointers and capacities must remain unchanged, and lengths/counts must fit. Returned numeric values must be finite.
- ABI-1 and ABI-2 descriptors have separate entry names. If a library exports V2, it is selected; an invalid V2 descriptor is rejected, **not silently downgraded to V1**.

### Layout is platform-dependent

Native 64-bit tests verify 48-byte arguments and 56-byte results. Core-WASM32 uses 32-byte arguments and results; compile-time checks and exported size helpers verify that target. The JS host uses little-endian access and refreshes memory views after callbacks.

| Field offsets | WASM32 argument | WASM32 result |
|---|---|---|
| Leading scalar fields | tag 0, reserved 4, number 8 | number 0 |
| Byte view | bytes 16, length 20 | bytes 8, capacity 12, length 16 |
| Vector view | vector 24, count 28 | vector 20, vector_capacity 24, count 28 |

Do not reinterpret these structs using the native 64-bit offsets in a WASM host. Matching struct layout does not by itself prove a foreign function's calling convention or pointer validity.

## Add a function without editing the runtime

For a C plugin:

1. Implement `urotif_ext_MODULE_SYMBOL` using `UrotifTypedArg`/`UrotifTypedResult`.
2. Add a `UrotifPluginSymbolV2` entry: name, arity, parameter tags, result tag, callback. Unused signature slots must be zero.
3. Export an immutable `UrotifPluginV2` descriptor with ABI 2 and `sizeof(UrotifPluginV2)`.
4. Build a shared library for `--link`, or omit the descriptor and link canonical functions into emitted native programs.
5. Declare/grant the same signature for emitted WASM, and provide a synchronous JS implementation.

For example, the existing affine entry is:

```c
{"affine", 3, {UROTIF_T_VECTOR, UROTIF_T_NUMBER, UROTIF_T_NUMBER},
 UROTIF_T_VECTOR, urotif_ext_buffers_affine}
```

Its WASM provider has this shape:

```js
export default {
  'buffers.affine': {
    abi: 2,
    parameters: ['vector', 'number', 'number'],
    result: 'vector',
    call: ([values, scale, offset], capacity) => {
      if (values.length > capacity.vectorCapacity) throw Error('capacity');
      return values.map(x => x * scale + offset);
    },
  },
};
```

The host also verifies finite results and result length. Byte results must be `Uint8Array` (Node `Buffer` is accepted); vector results can be `Float64Array` or a dense numeric array. Providers are synchronous; promises/async services are not an ABI-2 feature. `capacity` reports `bytesCapacity` and `vectorCapacity`. Sparse/non-numeric vectors are rejected. Missing or mismatched provider grants fail before running the program.

C sample static builds use `-DUROTIF_STATIC_LINK`; the Rust Unicode sample uses `--cfg urotif_static_link`. These omit the shared descriptor entry so multiple objects can link without colliding on `urotif_plugin_v2`. Native function declarations/objects must match the selected ABI: a C linker does not validate metadata against an object file's implementation. Keep canonical C symbol names unique across the link set; the underscore-joined module/function convention is not a general collision-free name-mangling scheme.

## Limits and trust

The old eleven-field policy is retained. Typed calls additionally observe:

| Channel | Bound |
|---|---|
| Aggregate byte arguments | Sum of lengths ≤ text budget, including aliases passed multiple times |
| Aggregate vector arguments | Sum of element counts ≤ edge budget, including aliases |
| Byte result capacity | `min(output budget, remaining text arena)` |
| Vector result capacity | `max(0, min(output budget / 8, remaining edges, available nodes - 1))` |
| Type/name registry | 32 modules / 256 symbols total, including built-ins; 1–128 symbols per loaded plugin |

The output budget doubles as the per-result workspace cap here; it is not permission to append more than the remaining printed-output space. Aggregate input/core allocation/output failures are **P002**. Plugin rejection, over-capacity result descriptors and callback result-contract failures are **P012**. A zero status from the plugin does not override subsequent VM allocation/stack/output checks.

**Native code is trusted, not sandboxed.** Checks can detect bad descriptors and lengths; they cannot prove allocation validity, undo out-of-bounds writes, prevent malicious input mutation, stop constructors, enforce callback execution time, or catch native crashes. Do not free/retain host buffers, replace pointers, unwind across C ABI boundaries, change the floating-point environment, or reenter the running VM. Rust `catch_unwind` is not protection against aborts, foreign exceptions, or arbitrary pointer misuse.

WASM isolates its linear memory, but granted JS code executes with host privileges. The host validates ranges/alignment and copies inputs; it is not a sandbox for the provider itself. Fuel counts Urotif instructions, not foreign callback work. Use process/worker isolation and external timeouts for untrusted workloads.

The new marshalling allocates/copies bounded buffers. This milestone does not claim a new benchmark speedup; old 0.2 benchmark figures remain historical. Reusable per-VM scratch buffers and batched domain operations are reasonable next measured optimizations, not completed performance claims.

## Verification and reproducible examples

See [docs/VERIFICATION.md](docs/VERIFICATION.md) for recorded 0.4 coverage and clean-source checks. Generated artifacts, galleries and local logs are intentionally excluded from this GitHub source tree. The tests and generators remain available:

```sh
python3 tests/test_typed.py Typed.test_value_flow_all_targets Typed.test_failure_matrix_all_targets
python3 tests/test_typed.py Typed.test_output_channel_boundaries Typed.test_aggregate_input_limits_count_aliases
python3 tests/test_typed.py Typed.test_metadata_only_grants_and_recovery \
  Typed.test_declared_signature_validation Typed.test_bad_v2_descriptor_does_not_fall_back_to_v1
python3 tests/test_typed.py Typed.test_gc_preserves_typed_results Typed.test_calls_subroutines_and_repeat
python3 tests/test_typed.py Typed.test_legacy_missing_result_is_not_zero
node --test tests/test_wasm_links.mjs
python3 tools/sanitize_typed.py
python3 tools/show_typed_transpilation.py --only showcase binary-hex byte-join
```

`make test-typed` runs the extension suites; `make typed-examples` rebuilds all ten examples and checks their native/target executions, four source recoveries, and recovered-WASM re-emission. Longer legacy suites have separate Make targets. Sanitizers instrument the generated C runtime and C plugins; the linked Rust sample archive is not instrumented by that harness. These checks are not production hardening or universal ABI-portability certification.

## Research behind the choices

- [Rust Reference: type layout](https://doc.rust-lang.org/reference/type-layout.html#the-c-representation): `repr(C)` field layout, alignment and target-dependent pointer/`usize` sizes motivate explicit native/WASM layout checks.
- [Rustonomicon: FFI](https://doc.rust-lang.org/nomicon/ffi.html): raw pointer/calling-convention obligations and unwinding restrictions motivate the small borrowed-view boundary and the trusted-code warning.
- [MDN: WebAssembly.Memory.grow](https://developer.mozilla.org/en-US/docs/WebAssembly/Reference/JavaScript_interface/Memory/grow): non-shared old buffers detach after growth; the host copies input and reacquires memory before writing results. This behavior is exercised in host tests.
- [GNU Fortran: C interoperability](https://gcc.gnu.org/onlinedocs/gfortran/Interoperability-with-C.html): standardized C interop is isolated in F2003 adapters, rather than relabeling the F95 core.

These sources inform the design. Execution, ABI-layout and sanitizer results are local measurements summarized in docs/VERIFICATION.md, not claims made by those sources.
