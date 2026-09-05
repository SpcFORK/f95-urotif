# Research decisions for Foundation 0.2

The research guides hypotheses. The local tests and ablation measurements determine what this implementation can actually claim.

## Interpreter overhead: reduce work, keep entry semantics

Ertl/Gregg/Casey's interpreter work studies indirect-branch behavior, superinstructions, and stack caching. Their primary publication list identifies the relevant 2003, 2004, and 2007 papers. It is a reason to investigate dispatch reduction—not a transferable speedup guarantee. [1](https://www.scss.tcd.ie/David.Gregg/pubs.html)

The more recent **Ertl and Paysan, ECOOP 2024** paper examines VM instruction-pointer update dependencies. Its abstract reports that those dependencies can become a critical path on newer out-of-order processors, particularly with lightweight instructions and loop-heavy workloads. The effect depends on the benchmark and hardware. [5](https://drops.dagstuhl.de/entities/document/10.4230/LIPIcs.ECOOP.2024.14)

**Applied here:** Fortran predecoding; constant/reference fast paths; fewer temporary arrays/text conversions; cached immutable values. Every source-byte entry remains available, and short fuel/capacity uses the original instruction path. This combines lower normal-path dispatch/allocation work with Urotif's arbitrary coordinate jumps.

**Not claimed or implemented:** a universal fastest interpreter, automatic replication of the papers' results, native direct threading, a JIT, or general side-effecting superinstructions. More fusion can also increase code size and complicate entry/fuel semantics; this milestone starts with tightly constrained patterns and measures them.

Regenerate local measurements with `make benchmark`; output goes to the ignored `benchmarks/RESULTS.md`. The benchmark compares C opt/no-opt at identical compiler flags. Cross-language ratios are explicitly not isolated dispatch experiments. Warm WASM and full CLI latency are reported separately.

## C ABI and unwinding

Rust's official FFI guidance distinguishes unwind-permitting ABIs from ordinary `extern "C"`, warns that foreign exceptions entering a non-unwind Rust boundary can cause undefined behavior, and explains that `catch_unwind` does not catch aborting panics. [1](https://doc.rust-lang.org/nomicon/ffi.html)

**Applied here:** explicit `repr(C)`/`BIND(C)` wire types, borrowed buffers, version checks, checked arities, a status/result convention, and panic containment at the host Rust boundary. The plugin contract forbids exceptions/panics crossing its ordinary C ABI. The WASM target uses `panic=abort`; normal language failures return status rather than panic.

This is not a promise that calling arbitrary native code is safe. A native library can corrupt memory or terminate the process before any language-level status is available.

## Native library lifetime and loading

The libloading repository identifies prevention of dangling loaded symbols as a key safety property. [5](https://github.com/nagisa/rust_libloading)

The official `Library::new` documentation was also reviewed directly: <https://docs.rs/libloading/latest/libloading/struct.Library.html>. It states that loading executes initialization routines, describes platform-dependent filename lookup, and recommends explicit paths. This project pins libloading 0.8.9, not an unpinned latest release.

**Applied here:** require an explicit existing library path and canonicalize it; validate a versioned descriptor; retain loaded libraries; seal the registry before execution/emission; cache stable IDs rather than resolving library symbols in the call loop.

**Additional safety choice:** `--extern MODULE.SYMBOL/ARITY` supplies signatures without loading code. It is the preferred path when compiling WASM for a separately supplied host. There is no source-level dynamic loader.

## Explicit capabilities

WASI's security description starts from no ambient authority: operations are available only through capabilities granted by the host. Its component model expresses capability surfaces through explicit imports. [1](https://wasi.dev/security)

**Applied as a principle:** native/compiled registries contain only built-ins and explicit grants; WASM requires matching imports; the sample host rejects missing services rather than stubbing success. Importing a source-level module cannot discover a filesystem library.

**Important distinction:** Urotif Foundation does not implement WASI components or WIT. It uses core WASM and a small numeric import ABI. Native plugins are not isolated. A host-supplied import may itself grant powerful effects, and a fuel counter cannot preempt a hanging host function.

## Fortran remains the main/front end

The GNU Fortran C-interoperability documentation describes the standardized Fortran 2003 interoperability facilities: <https://gcc.gnu.org/onlinedocs/gfortran/Interoperability-with-C.html>.

**Applied here:** compile the language runtime, decoder, and assembler under strict F95. Isolate standard CLI/C interoperability in small F2003 files. Link Rust as a native static library behind the Fortran main. Generated C/Rust/WASM targets contain a target runtime, but no Rust Urotif source parser.

## Design priorities and next experiments

1. **Design speed:** one byte-language model, a small set of typed values, a versioned foreign boundary, independent source-level execution versus target IR execution.
2. **Programming speed:** named labels assemble away; imported references and standard-call conveniences remove repeated low-level boilerplate without changing `=`'s consumption or hiding conversions.
3. **Execution speed:** predecode, remove proven repeated construction/name work, cache immutable handles, reclaim arenas, and ship stripped WASM rather than large debug sections.
4. **Next measured work:** compact native-Rust indices, bulk/borrowed-byte foreign calls, larger adversarial/differential corpora, and only then block lowering or additional superinstructions with proven interior-entry behavior.

A small implementation is easier to inspect, but smallness is not proof of correctness or security. The current test/sanitizer results support this milestone's behavior; they do not establish production hardening.


## 0.3 implementation follow-through

Fortran 95 permits dynamic pointer components; allocatable derived-type components were standardized later. That distinction motivated keeping the value arenas as owned pointer arrays rather than quietly requiring a newer core language. The historical Fortran 2003 overview discusses this distinction and its aliasing/optimization tradeoff. [3](https://cug.org/5-publications/proceedings_attendee_lists/2005CD/S05_Proceedings/pages/Authors/Long-0517-1100/Long-0517-1100_paper.pdf)

Local compiler tests, not that paper, established the following Urotif results: strict `-std=f95 -pedantic-errors` standalone output compiles; source buffers with an 8 MiB configured capacity work after heap-backing large CHARACTER workspaces; a near-full arena GC stress test that exceeded 30 seconds passes after reserving for the active stack/pending literal instead of the full stack capacity. These are local implementation observations, not general language-performance comparisons. The source repository retains the regression tests; archived machine-specific logs are omitted. See [VERIFICATION.md](VERIFICATION.md).


## 0.4 follow-through: typed values, not foreign object graphs

Primary sources revisited on 5 September 2026:

- [Rust Reference, type layout](https://doc.rust-lang.org/reference/type-layout.html#the-c-representation) specifies the purpose/field layout of `repr(C)` and notes that pointer/usize sizes and primitive alignment depend on the target. **Applied:** explicit repr(C) records; native64 tests plus WASM32 layout assertions. The JS adapter does not reuse native pointer offsets.
- [Rustonomicon, FFI](https://doc.rust-lang.org/nomicon/ffi.html) describes raw-pointer obligations, caller-provided output storage, correct declarations, and non-unwind C boundaries. **Applied:** borrowed input views, initialized caller-owned bounded output buffers, finite-result and ownership-descriptor validation; no untrusted-native sandbox claim.
- [MDN, WebAssembly.Memory.grow](https://developer.mozilla.org/en-US/docs/WebAssembly/Reference/JavaScript_interface/Memory/grow) documents detached old non-shared buffers after growth. **Applied and locally tested:** copy input values before calling JS and reacquire memory before output writes, including a callback that grows memory.
- [GNU Fortran C interoperability](https://gcc.gnu.org/onlinedocs/gfortran/Interoperability-with-C.html) keeps the language-version distinction explicit. **Applied:** F95 flat-buffer marshalling, F2003 C views/bindings, and strict-F95 no-plugin output.

A separate versioned descriptor avoids reinterpreting ABI-1 storage. Signatures, not a growing opcode list, drive new bindings. Scalar/byte/vector buffers do not introduce recursive objects, ownership transfer, asynchronous callbacks or integer64 semantics. Library metadata is not an authorization credential. Native pointers remain a trusted boundary even after null/alignment/length checks.

0.4 records execution-equivalence and sanitizer tests, not a new performance benchmark. Batching useful library work can reduce crossing frequency; reusable per-VM scratch buffers remain a future measured optimization. The old dispatch benchmark ratios must not be attributed to this new marshaller.
