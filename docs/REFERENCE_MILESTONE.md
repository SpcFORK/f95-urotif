> **Historical v0.1 document.** Current features, commands, and results are in [../README.md](../README.md) and [../FOUNDATION.md](../FOUNDATION.md). Statements below describe the earlier reference-first milestone.

# Urotif — Fortran main, reference-first milestone

A working **Fortran-owned** Urotif implementation, developed by reducing and testing the supplied Oak interpreter and samples. This is an incremental compatibility milestone, **not a completed Oak port or a frozen language redesign**.

The revised truth fixture and its measured failure are documented in **[REVISED_TRUTH.md](../REVISED_TRUTH.md)**.

## Architecture

```text
Fortran main program
  ├─ default: Fortran 95 character dispatcher + stack/array runtime
  │             └─ original archive fixtures and ablation probes
  └─ --core: experimental Fortran lexer/parser → resolved instruction IR
                  ├─ Fortran native VM
                  └─ Fortran 2003 C-ABI adapter
                        → linked Rust static library
                        → WAT / WebAssembly binary
```

Rust has **no host main, prototype parser, or native Urotif interpreter** here. It is a linked code-generation backend. The native link is performed by `gfortran`. The WASM backend currently accepts only the explicitly selected experimental numeric/text IR, **not the reference interpreter's full arrays, character semantics, or dynamic commands**.

This does not compile the Fortran engine itself into WebAssembly. Native Fortran remains in charge; the Rust library emits target modules. No native object file is presented as WASM.

## Build

Tested on Linux x86-64 using GNU Fortran 14.2.0, Rust 1.98.1, Node 20.20.2, and Python 3.13.14. The optional independent oracle was official Oak v0.3.

Dependencies: `gfortran`, Cargo/Rust, Make, Python 3; Node for WASM tests. The first Cargo build downloads the dependencies pinned by `rust-chain/Cargo.lock`.

```sh
make                  # Fortran main + native Rust static library
make core95           # Standalone strict-F95 entry point; no Rust dependency
make test             # Rust unit tests + Python regression/integration suite
```

The language core is compiled with `-std=f95 -pedantic-errors`. Only `main.f90` and `urotif_bridge.f90` use Fortran 2003 facilities: command-line handling, a standard error unit, and `ISO_C_BINDING`/`BIND(C)`. Standardized C interoperability begins with Fortran 2003; compiler-specific linking is possible with older Fortran, but is not the portable interface used here. [1](https://gcc.gnu.org/onlinedocs/gfortran/Interoperability-with-C.html)

The Makefile's native Rust system-library flags are Linux defaults. Other platforms may need `RUST_NATIVE_LIBS` adjusted using the Rust compiler's `--print=native-static-libs` output; they have not been validated.

## Run the actual reference files

```sh
bin/urotif run reference/smp/hello.utf
# Hello, World!

printf '2\n3\n' | bin/urotif run reference/smp/anb.utf
# 32 (text concatenation, NOT numeric addition)

bin/urotif probe reference/smp/fib.utf --repair
# final stack: [["0","1"],"0"]; no program output

printf '2\n3\n' | bin/urotif probe examples/truth-revised.utf --repair
# output "0", then a diagnosed second-pass empty-stack print
```

`run` emits the program's buffered output. `probe` emits JSON containing output, final stack, open construction depth, executed-character count, and any diagnostic. Both accept `--fuel N` (default 1,000,000). A failed probe exits nonzero even though its JSON is valid.

The F95-only driver reads its command and filename from standard input, followed by any program input:

```sh
printf 'run\nreference/smp/hello.utf\n' | bin/urotif95
printf 'probe\nreference/smp/anb.utf\n2\n3\n' | bin/urotif95
```

## What the archives actually do

The unmodified `run.oak` wrapper fails on `__` with official Oak v0.3. Calling `main.file(...)` directly bypasses that wrapper and gives this independent baseline:

| Unchanged sample | Oak interpreter through direct API | Fortran reference path |
|---|---|---|
| `hello.utf` | `Hello, World!` and newline | Same output |
| `anb.utf`, inputs `2`, `3` | `32`, no newline | Same output |
| `bin.uru` | No output; pushes the nine characters | Same stack |
| `fib.utf` | Indexing error at `;` | Corresponding diagnostic; explicit repair completes |
| `truth.utf` | `C@` receiver error | Corresponding diagnostic; repairs expose a later underflow |
| `hello.urb` | Prints `<`; pushes remaining recognized characters | Same **raw dispatch**, not a binary/urobore loader |

Do not infer a Fibonacci sequence generator from the filename: `[01]%0;` contains no printing or loop. Do not infer `.urb` or `.uru` format support from the raw dispatcher accepting those filenames. The archive has no implemented extension-based loader.

## Opt-in repairs

`--repair` is an auditable test profile, not a silent redefinition:

1. `;`: use the second item as container and convert the top item to an integer index, corresponding to `h.(int(k))` rather than `k.(h)`.
2. `C@`: honor the intended standard-library receiver; the implemented test subset is `std.int` with one argument.
3. `gotoVec`: explicitly convert its two coordinates to integers.

It does **not** change zero-based effective columns, typed equality, the `=` pop order, or the source's comment-column carry behavior. See `docs/ABLATION_REPORT.md` and the revised-program report for consequences.

## Scope and intentional safety differences

The reference path implements the sample-critical subset: ASCII character pushes, input as text, nested construction stacks, float construction, duplication/drop, arithmetic, output, array spreading, indexing, `p/P/s/S@`, an opt-in `C@ int`, and coordinate jumps/conditionals.

It is not a full emulator:

- Empty stacks, exhausted input, invalid bounds/delimiters, division by zero, and non-finite results are diagnosed rather than inheriting null/unsafe behavior.
- Unknown plain characters are ignored, matching the source dispatch. Unescaped non-ASCII bytes have no push macro; use a future encoding policy rather than assuming Unicode literal support. Binary-string/JSON edge cases are not a compatibility claim.
- Float and integer tags are distinguished where the samples need them, but numeric payloads use binary64; full Oak 64-bit-integer precision/overflow behavior is not yet reproduced.
- Objects, arbitrary standard-library calls, evaluation, imports, modules, macros, and table operations are not ported. Unsupported `@` calls are diagnosed.
- Values are immutable arena entries in this milestone. There is no garbage collector or mutation/aliasing compatibility claim.
- Output is buffered for deterministic probes; this is not an interactive REPL.

Bounds: normalized source 262,144 bytes; 65,536 lines; 2,048 stack entries; 64 construction frames; 32,768 value nodes and array edges; 524,288 text-arena bytes; 262,144 output bytes; 2,048 bytes per input line. Fuel is configurable. These limits are checked, not silently truncated.

## Experimental subroutines and WASM — separate profile

The earlier named subroutine/goto scaffold remains available behind **`--core`**. It has a different numeric/text syntax and must not be used as evidence of prototype compatibility.

```sh
bin/urotif run examples/core/factorial.utf --core
# 720

bin/urotif wasm examples/core/factorial.utf --core -o factorial.wasm
node tools/wasm-run.mjs factorial.wasm
# 720

bin/urotif wat examples/core/factorial.utf --core -o factorial.wat
bin/urotif ir examples/core/factorial.utf --core
```

`make examples` rebuilds the two experimental modules under `artifacts/wasm/`. The Rust backend lowers the resolved program to structured WASM dispatch and encodes it with the `wat` crate. It does not require Rust's `wasm32` standard library because the backend itself is a native library.

`include/urotif_backend.h` documents the borrowed-buffer C ABI. Rust catches unwinding panics at that boundary and returns diagnostics. `staticlib` is the Rust library form intended for linkage into a non-Rust application. [2](https://doc.rust-lang.org/reference/linkage.html)

WASM modules import `urotif.write_text(i32,i32)`, `write_number(f64)`, and `read_number()->f64`; export memory, `urotif_run(fuel)->status`, source location, and step count. The Node host demonstrates the same import-object mechanism used by browsers. [3](https://developer.mozilla.org/en-US/docs/WebAssembly/Reference/JavaScript_interface/instantiate_static)

**Prototype WASM compilation is deliberately rejected without `--core`**, rather than silently turning `anb.utf`'s `32` into `5`.

## Tests and evidence

Current recorded run: **101 Python tests plus 6 Rust unit tests pass**. The Python suite includes 52 small ablation fixtures, original and revised sample checks, 100 bounded random probes within a fuzz smoke test, strict-F95 execution, and separate native/WASM differential tests including recursion and error paths. Passing diagnostic tests do not mean that broken samples terminate successfully.

Archived logs and generated reports are omitted from the source repository. The retained tests and fixtures include:

- `reference/SHA256.json` — preserved source/sample checksums.
- `tests/ablation-cases.json`, `ablations/` — runnable reductions and expected outcomes.

Reproduce the optional independent oracle without editing any reference file:

```sh
python3 tools/probe_oak.py --oak /path/to/oak
```

## Next compatibility work

1. Settle the revised truth program's comparison and restart intent before changing source semantics.
2. Carry the verified character, array, and typed-input semantics into the IR and WASM backend.
3. Extend `@` commands from reduced examples, keeping source behavior and deliberate repairs separate.
4. Only then finalize user-defined subroutine syntax and its BNF.

Reference material remains attributed to the supplied archives; no upstream ownership or license is reassigned. Third-party dependencies retain their own licenses.
