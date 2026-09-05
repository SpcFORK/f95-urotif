> **0.4 extension:** [TYPED_LINKS.md](TYPED_LINKS.md) adds typed number/byte/vector libraries across all targets. This page retains the 0.3 baseline, resource ranges, and verification history. Its numeric-only plugin restriction is superseded by ABI 2; source-recovery limits and safety requirements still apply.

# Urotif 0.3 — Fortran transpilation and recoverable builds

**Fortran remains the frontend and native main.** This milestone adds a standalone Fortran target, configurable resource budgets, source libraries, 14 examples, byte literals, and on-demand native I/O.

```text
.ufm source + libraries ── Fortran assembler ──► .utf byte program
                                                   │
                                   Fortran decoder / optimizer
                                                   │
                                            source-stable IR2
                                                   │
                                         linked Rust backend
                                       ┌───────┬───────┬────────┐
                                       C       Rust    Fortran  WASM
                                                       │
                                                    gfortran
                                                       │
                                                 native program

With --embed-source: any emitted artifact ── recover ──► normalized .utf
```

The targets are **table-driven transpiled programs**: decoded instructions plus an execution kernel, not a reparse of embedded Urotif and not a translation into hand-written-looking loops. Generated Fortran shares the native F95 value/GC/primitive implementation. It needs no Urotif executable or Rust library at runtime. A program using plugins still needs its declared foreign implementations.

## Run the new Fortran target

From this directory, with GCC/gfortran, Rust/Cargo and Node installed:

```sh
rustup target add wasm32-unknown-unknown
make all core95
mkdir -p build/demo

bin/urotif assemble examples/next/cube-library.ufm -o build/demo/cube.utf
bin/urotif fortran build/demo/cube.utf --foundation --embed-source \
  -o build/demo/cube.f90
(cd build/demo && gfortran -std=f2003 -O2 -fcheck=all cube.f90 -o cube)
build/demo/cube --json
```

Result: **`27\n`**, status 0. Compile generated Fortran in its own directory so its `.mod` files cannot replace the compiler's modules.

Strict F95, without command-line or foreign-binding adapters:

```sh
bin/urotif fortran build/demo/cube.utf --foundation --f95 -o build/demo/cube95.f90
(cd build/demo && gfortran -std=f95 -pedantic-errors -O2 cube95.f90 -o cube95)
build/demo/cube95
```

`--f95` supports the built-in std/math catalog, reads program input from stdin, and uses the default fuel. The ordinary emitted Fortran program uses an F2003 CLI and, when needed, ISO_C_BINDING for C/Rust plugins. Its value/execution core is F95.

## The same Urotif, four targets

```sh
bin/urotif c       build/demo/cube.utf --foundation -o build/demo/cube.c
bin/urotif rust    build/demo/cube.utf --foundation -o build/demo/cube.rs
bin/urotif fortran build/demo/cube.utf --foundation -o build/demo/cube.f90
bin/urotif wasm    build/demo/cube.utf --foundation -o build/demo/cube.wasm

gcc -std=c99 -O2 build/demo/cube.c -lm -o build/demo/cube-c
rustc --edition=2021 -O build/demo/cube.rs -o build/demo/cube-rust
(cd build/demo && gfortran -std=f2003 -O2 cube.f90 -o cube-fortran)

build/demo/cube-c --json
build/demo/cube-rust --json
build/demo/cube-fortran --json
node tools/foundation-wasm.mjs build/demo/cube.wasm --json
```

Run `python3 tools/show_transpilation.py` to generate `artifacts/roundtrip/`, execution/recovery reports, and the offline `TRANSPILE.html` inspector. These are local outputs, intentionally excluded from the source repository.

## What “round trip” means here

There are two checks:

1. **Behavioral equivalence:** native Urotif and compiled C/Rust/Fortran/WASM agree on output bytes, status, fuel steps, stack depth and error coordinates in the differential tests.
2. **Source recovery:** `--embed-source` stores a versioned, CRC32-checked record of the normalized byte program in generated text comments or a WASM custom section.

```sh
bin/urotif fortran examples/next/cube-library.utf --foundation --embed-source \
  -o build/demo/recoverable.f90
bin/urotif recover build/demo/recoverable.f90 -o build/demo/recovered.utf
cmp examples/next/cube-library.utf build/demo/recovered.utf
bin/urotif wasm build/demo/recovered.utf --foundation -o build/demo/recovered.wasm
node tools/foundation-wasm.mjs build/demo/recovered.wasm --json
```

**This is not a general Fortran → Urotif decompiler or a self-hosting compiler.** Recovery retrieves metadata, not edits made to the generated Fortran body. It preserves normalized `.utf` bytes, not the original CRLF layout or an `.ufm` include tree. CRC32 detects accidental capsule corruption; it does not authenticate code. Recovery does not automatically restore resource policy, import grants, or libraries; reapply the required flags using the `.links.json` catalog. Recovery rejects absent/corrupt capsules before replacing an output file.

## Extend ordinary programs in one place

`lib/prelude.ufm` defines words in Urotif itself:

```text
.define square %*
.define cube %%**
.define concat x@+
.define hypot %*x@%*+[math.sqrt]r@@
```

A new word does not require a new C, Rust, Fortran or WASM backend case:

```text
.define fourth %*%*
.number 3
.use fourth
.println
.halt
```

This prints `81`. Definitions are nonrecursive, single-line primitive expansions; `.include` reads local files relative to the including file. Labels remain global within one assembly. Put subroutine libraries after the main program's `.halt`.

New assembly conveniences:

- `.text TEXT` — literal remainder of the line, including trailing spaces; UTF-8 is encoded into byte escapes.
- `.bytes 00 FF C3 A9` — exact byte text, including NUL and invalid UTF-8.
- `.number -3`, `.ref math.square`, `.import math`.
- `.dup`, `.drop`, `.swap`, `.over`, `.rot`, `.depth`, `.pack [N]`.
- `.read`, `.print`, `.println`; existing labels/gotos/calls/returns remain.

New Foundation primitives: `x@` swap, `o@` over, `t@` rotate `(a b c → b c a)`, `d@` active-frame depth, and `b@` pack a numeric count of existing values in source order. Construction frames remain isolated. `\xHH` is a single byte escape; malformed hex escapes report P003. These are proposed Foundation spellings, not changes to the preserved reference profile.

## Practical limits changed

Use `--limit NAME=N` on a native Foundation run or when emitting a target. **An emitted program carries the policy selected at emission**; its CLI does not resize it later. Policies are recorded in `.links.json`. Safety checks stay enabled.

| Resource | Default | Configurable maximum |
|---|---:|---:|
| `source` — normalized bytes | 1,048,576 | 8,388,608 |
| `stack` — live handles | 2,048 | 1,048,576 |
| `nodes` | 32,768 | 1,048,576 |
| `edges` — array elements | 32,768 | 4,194,304 |
| `text` — arena bytes | 524,288 | 67,108,864 |
| `output` — retained bytes | 262,144 | 33,554,432 |
| `frames` — construction/traversal depth | 64 | 1,024 |
| `returns` | 1,024 | 1,048,576 |
| `input-line` — bytes per record | 2,048 | 16,777,216 |
| `input` — input budget/buffer capacity | 1,048,576 | 67,108,864 |
| `work` — comparison/diagnostic traversal | 262,144 | 16,777,216 |

```sh
bin/urotif run examples/next/record-length.utf --foundation --limit input-line=8192
bin/urotif fortran PROGRAM.utf --foundation \
  --limit stack=8192 --limit nodes=100000 --limit edges=100000 \
  --limit output=400000 -o PROGRAM.f90
```

The old 65,535-byte emitter ceiling is gone: IR storage follows the source size. Source line and label tables are source-sized rather than fixed at 65,536 lines/1,024 labels. F95 arenas use owned pointer arrays. Large scalar work buffers use heap-backed, one-element allocatable CHARACTER arrays, avoiding dependence on an 8 MiB process stack.

Verified boundary examples include **70,000+ source bytes; 1,500+ labels; 5,000 live stack values; a 5,000-byte record; 300,000 output bytes; 1,500 nested calls; 100 construction levels; a 33,000-deep live array; and more than 1 MiB of consumed input**. Large values may require raising several related budgets. Maximum settings are admission guards, not a guarantee that every host has enough memory.

### I/O and byte diagnostics

Native Urotif, generated C, Rust and ordinary Fortran read records on demand. They no longer require EOF before executing an input-using program. Add `--stream` to flush output while running:

```sh
bin/urotif run examples/next/prompt-square.utf --foundation --stream
# A generated executable uses: ./program --stream
```

The prompt appears before the user enters a number. Streaming is incompatible with generated `--json` or `--repeat`. Repeated runs intentionally buffer and replay stdin. WASM retains its explicit bounded input/output buffer API; it is not a resumable streaming VM. Native formatted reads normalize records; WASM admission counts the supplied raw buffer.

JSON now has **`output_hex`** for exact output bytes. `output` is a UTF-8 display string with replacement characters for invalid sequences. Language indexing/length remains byte-based. Native stack diagnostics are bounded and expose `stack_truncated`; they are not an unlimited serialization interface.

## Fourteen new examples

See [examples/next/cases.json](examples/next/cases.json) for exact input/output bytes.

| Program | Demonstrates / output |
|---|---|
| `hello-utf8` | `Café ☕ — Hello from Urotif!` |
| `cube-library` | Source macro; `27` |
| `factorial` | Goto loop and stack shuffles; `720` |
| `fibonacci` | Twelve terms, `0` through `89` |
| `live-array` | Pack computed values, index, length |
| `prompt-square` | Interactive prompt; input `9` → `81` |
| `record-length` | Configurable input record capacity |
| `binary-bytes` | Exact `00ffc3a90a` output |
| `nested-calls` | Included subroutine library; `729` |
| `zero-branch` | Consuming equality and named branches |
| `text-library` | A conventional-order concat macro |
| `hypotenuse` | Source-defined helper; `5` |
| `fahrenheit` | Input `212` → `100` |
| `stack-tour` | Rotate and dynamic packing |

## Verification

The 0.3 validation was staged, not a single post-fix monolithic test run. An initial duplicated-discovery run exposed a near-full-arena timeout; the fixed collector reserves for the active stack/pending literal rather than full configured stack capacity. Relevant regressions are retained in the test suite.

Current recorded coverage and source-bundle checks are summarized in [docs/VERIFICATION.md](docs/VERIFICATION.md). Local logs and generated reports are not committed.

```sh
make test-reference
make test-foundation
make test-roundtrip
make sanitize
```

## Still deliberately bounded / not implemented

- Integer-tagged numbers still use binary64 and are checked within ±(2^53−1); this is **not int64**.
- ABI 1 retains numeric calls; 0.4 adds ABI 2 number/bytes/flat-vector signatures with at most eight arguments. See [TYPED_LINKS.md](TYPED_LINKS.md).
- The registry remains 32 modules / 256 symbols; identifiers are ASCII and at most 63 bytes. Includes have a 32-level recursion guard. Literal caches are bounded optimizations; longer literals fall back to ordinary execution.
- Native libraries must be trusted. ABI validation cannot sandbox constructors, pointers, crashes, hangs, or foreign unwinding. Fuel cannot preempt blocked I/O or native callbacks.
- Output remains retained and budgeted even in stream mode. WASM is the core-WASM buffer/import model, not WASI or the component model.
- Source macros simplify source-level extension. New fundamental value kinds or execution semantics still require implementation and cross-target tests.

The unchanged original references and ablations remain available for comparison; old release archives are not included in the source repository.
