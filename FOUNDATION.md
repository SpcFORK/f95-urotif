> **0.4 is available:** see [TYPED_LINKS.md](TYPED_LINKS.md) for typed libraries, and [ROUNDTRIP.md](ROUNDTRIP.md) for 0.3's budgets, Fortran emission and recoverable source. The detailed 0.2 contract/measurements below remain historical; target, limit and numeric-only plugin restrictions are superseded by those guides.


# Urotif Foundation
## A small primitive runtime, with linking and portable targets

**Milestone 0.2 · 4 September 2026 · Proposed profile, implemented and tested**

The direction is deliberately simple: **construct values, resolve a reference, apply it, transfer control**. Keep Fortran in charge of the source language. Make useful higher-level conveniences disappear before execution. Optimize the representation and common paths—not the meaning of the program.

The Foundation profile extends the original import/reference/apply design. Its spellings and ABI are explicit implementation proposals, not features retrospectively attributed to the supplied Oak prototype.

---

## 1. The intended truth-loop behavior

`examples/foundation/truth.utf`:

```text
=) urotif
[[[std]i@[int]S@]g@`]a@%{0}30=$20^
%$30^
```

Read the second line in pieces:

| Source | Effect |
|---|---|
| `[std]i@` | Import the already-granted `std` module |
| `[int]S@` | Construct the text name `int` |
| `[[std]i@[int]S@]g@` | Resolve that module's external `int` reference |
| `` ` `` | Read input as text |
| `[reference input]a@` | Conceptually: apply that reference to that input |
| `%{0}30=` | Keep one copy of the result; compare the other against numeric zero; jump to line 3, column 0 if equal |
| `$20^` | Otherwise print the retained input and return to line 2, column 0 |

The third line, `%$30^`, prints a copy of zero and loops without consuming the retained zero.

**The descriptive `reference input` row above is stack notation, not literal source. Spaces are data in Urotif.** The compact full program is the executable version.

```sh
printf '7\n2\n0\nBAD\n' | bin/urotif probe examples/foundation/truth.utf --foundation --fuel 200
```

Observed across the four execution paths:

- Output: `72` followed by zeros.
- Final data stack: one numeric zero in the Fortran probe.
- Stop: `P008`, the requested fuel bound.
- It never reads `BAD` after entering the zero loop.
- It does not suffer the revised fixture's second-pass underflow.

The zero loop is intentionally nonterminating at the language level. The bounded runner stops it; that is not presented as normal program termination.

The original and revised fixtures remain unchanged. Their old failures are still tested under the reference profile. This new file implements the clarified truth-loop behavior rather than silently editing that historical evidence.

---

## 2. Three ways to call a function

### Import → reference → explicit argument packet

```text
=) urotif
[[[std]i@[int]S@]g@`]a@$
```

Input `17` prints `17`. `g@` resolves an external; `a@` applies an array whose first item is the reference and whose remaining items are arguments, in source order.

### Qualified reference → direct application

```text
=) urotif
{9}[math.square]r@@$
```

Output: `81`.

- `{9}` constructs a numeric value.
- `[math.square]r@` resolves the reference.
- The following `@`, with a reference on top, consumes the declared arguments and pushes its result.

For a two-argument example:

```text
{3}{4}[math.add]r@@$
```

Output: `7`. Arguments are passed left-to-right, not in pop order.

### The original-style standard-call convenience

```text
=) urotif
[[int]S@`]C@$
```

`C@` means “resolve the standard function named by the first array item, then apply it to the remaining items.” It works in Foundation without `--repair`.

`G@` is the standard-module reference shorthand: `[int]G@` resolves `std.int`. `r@` accepts a qualified name and defaults a bare name to `std`.

### Built-in catalog

| Module | Service | Arity | Contract |
|---|---|---:|---|
| `std` | `int` | 1 | Convert a finite decimal/number; truncate toward zero; enforce the exact portable integer range |
| `std` | `float` | 1 | Convert a finite decimal/number to binary64 |
| `std` | `string` | 1 | Format a value as text |
| `std` | `len` | 1 | Byte length of text or element count of an array |
| `math` | `sqrt` | 1 | Numeric square root; invalid/non-finite results fail |
| `math` | `square` | 1 | Numeric square |
| `math` | `abs` | 1 | Numeric absolute value |
| `math` | `add` | 2 | Numeric sum |

Inspect the actual registry with `bin/urotif links`.

The `std` value operations execute in the Fortran/target runtime. Foreign numeric functions do **not** receive raw VM values. A foreign call requires numeric arguments; a text character `9` is not silently accepted as numeric 9. Use `{9}` or an explicit converter.

---

## 3. Subroutines remain coordinate-based

New proposed control commands:

| Operation | Contract |
|---|---|
| `k@` | Consume an array of two coordinates, line then column; push the continuation on a separate return stack; transfer control |
| `R@` | Return to that continuation; require the saved construction depth |
| `h@` | Halt the program |

Example:

```text
=) urotif
{9}[30]k@$h@
%*R@
```

`[30]` contains text `3` and `0`; Foundation permits their coordinate conversion. The subroutine on line 3 squares its input and returns. The result is `81`.

For larger coordinates, use explicit numbers: `[{12}{0}]k@`. Calls do not declare local variables or a source-routine arity. They use the existing data stack. The return stack is separate, bounded to 1,024 entries, and cannot be forged by pushing numbers. Underflow, overflow, or mismatched construction depth is diagnosed.

Line coordinates are **one-based**, columns are **zero-based**. Columns count normalized source bytes, not Unicode characters. Diagnostic columns are one-based. A column beyond the line's end advances to the next line, as in the character runner. EOF and `h@` halt the entire program; they are not implicit subroutine returns.

---

## 4. Faster programming: labels that disappear

Hand-counted addresses are a bad editing interface even when coordinates are a good machine primitive. The new F95 assembler provides:

```text
.label NAME
.goto NAME
.eq NAME
.call NAME
.return
.halt
```

Example `examples/foundation/square.ufm`:

```text
# Symbolic conveniences assemble to the same primitive character language.
{9}
.call square
$
.halt
.label square
%*
.return
```

```sh
bin/urotif assemble examples/foundation/square.ufm -o build/square.utf
bin/urotif run build/square.utf --foundation
```

The assembler resolves addresses in Fortran and writes ordinary primitive Urotif. `.goto` becomes numeric coordinates followed by `^`; `.eq` becomes coordinates followed by `=`; `.call` becomes a coordinate packet and `k@`. Labels add **no runtime lookup or opcode**. `.eq` still consumes both comparison values—duplication remains explicit.

`examples/foundation/truth.ufm` is a label-based version of the same input/zero logic. Its emitted line numbers differ from the hand-written three-line version, but its behavior is the same.

Directives must begin at column zero and occupy a whole line. Labels are case-sensitive ASCII identifiers, at most 63 bytes. Duplicate, invalid, and unresolved labels fail before an output file is created. Raw lines and trailing spaces are preserved. A header is emitted automatically; an optional input header is skipped. The primitive `.utf` parser does not interpret these directives: assemble `.ufm` first.

---

## 5. Linking C, Rust, and WASM hosts

The current foreign ABI is deliberately small:

```c
int32_t function(const double *args, size_t argc, double *result);
```

Zero to eight finite numeric arguments; exactly one finite numeric result; zero status for success. No exceptions, panics, retained argument pointers, implicit allocation ownership, or guessed foreign layouts cross that boundary.

### Trusted native libraries

```sh
make plugins
bin/urotif links --link build/demo.so --link build/rust_demo.so
bin/urotif run examples/foundation/plugin.utf --foundation --link build/demo.so
```

The C demo exports cube, sum-of-three, and affine functions. The Rust demo exports `rustdemo.twice`. Tests execute both from the **Fortran** runtime and check argument order through the generated targets.

Loading is explicit. The source-language `i@` cannot open a library file: it only imports a module that was already granted. The registry seals at its first lookup/emission/catalog request. Handles then stay stable and libraries remain resident. Built-in modules cannot be overridden.

### Signature-only imports

Do not load a native library just to compile a WASM program if all you need is its signature:

```sh
bin/urotif wasm examples/foundation/plugin.utf --foundation \
  --extern demo.cube/1 -o build/plugin.wasm
node tools/foundation-wasm.mjs build/plugin.wasm \
  --host plugins/demo-host.mjs --json
```

`--extern` registers a name and arity **without executing native code**. For native interpretation, an unimplemented declared function fails at application. For emitted native code, the native linker must supply its symbol. For WASM, the host must explicitly supply its import; missing imports fail rather than becoming fake successful stubs.

A loaded module grants its whole descriptor. A list of `--extern` declarations can grant a smaller set of signatures. This milestone uses a process-wide sealed native registry, not per-component privilege isolation.

See [docs/LINKING.md](docs/LINKING.md), `include/urotif_plugin.h`, and `include/urotif_foundation.h` for complete builds and ownership rules.

**Native libraries are trusted process code, not sandboxed code.** ABI checks cannot make hostile pointers, constructors, crashes, aborts, or hanging functions safe. The host's panic containment does not catch foreign exceptions or prevent a plugin from aborting the process.

---

## 6. Transpilation without reversing the architecture

```text
Fortran source reader + decoder + optimizer
                ↓
       source-byte-stable IR2
                ↓
       Fortran C-ABI adapter
                ↓
        linked Rust backend
        ↙               ↘
   C99 source         Rust source
       ↓               ↙     ↘
 native compiler    native   WASM
```

Fortran owns source interpretation and all source-to-IR decisions. Rust validates the borrowed IR and emits target source. Rust's compiler then builds the WASM module. There is no Rust Urotif lexer or a Rust frontend generating Fortran.

Generated C/Rust programs embed the decoded tables and a bounded runtime. They are standalone target implementations, not idiomatic reconstruction of the original source. WASM uses that same Rust target runtime, not the Fortran executable or a native object renamed `.wasm`.

```sh
bin/urotif c examples/foundation/external.utf --foundation -o build/external.c
gcc -std=c99 -O3 build/external.c -lm -o build/external-c

bin/urotif rust examples/foundation/external.utf --foundation -o build/external.rs
rustc --edition=2021 -O -C strip=symbols -A dead_code -A unused_imports \
  build/external.rs -o build/external-rust

bin/urotif wasm examples/foundation/external.utf --foundation -o build/external.wasm
node tools/foundation-wasm.mjs build/external.wasm --json
```

Every target gets a `.links.json` catalog. WASM emission also leaves `.wasm.rs` so the actual target source is inspectable. Nonessential Rust/WASM debug sections are stripped; the sample WASM modules are about 100–102 KiB rather than roughly 1.6 MiB. Explicit Urotif location exports remain available.

`check --foundation` and `ir --foundation` inspect decoding/IR, not a proof of every runtime stack state. Arbitrary coordinate control flow and dynamic names still require runtime checks.

---

## 7. Optimization rules that respect arbitrary jumps

Implemented:

1. **Predecode every byte.** Resolve operation dispatch and source locations once for compiled targets.
2. **Keep every interior entry.** A jump into an escape, a literal, or an optimized span still executes the original instruction at that byte.
3. **Fast paths for constant arrays/text, decimal construction, and literal external references.** Names become stable handles when resolvable.
4. **Cache immutable characters, module handles, references, and bounded literal values.** Avoid recreating the same objects in loops.
5. **Stable-ID mark/sweep collection.** Scan active data/construction values and all caches, reclaim dead nodes, compact text/edge storage, never relocate a live value ID.
6. **Preserve logical fuel.** A fused operation charges its original instruction count. If fuel is too short, or transient stack/frame capacity would differ, execute its original opening instruction and continue through the retained interior path instead.
7. **Bound deep comparison work.** Do not let an expanded shared structure create unbounded comparison work inside one instruction.

This is not arbitrary instruction fusion, a JIT, or direct-threaded machine code. The unfused Fortran character runner remains a useful independent execution oracle. `--no-opt` on compilation disables the constant/reference fast paths; it does not disable bounds checks, predecoding, caches, or collection.

### What was measured

Three loop-heavy local workloads: countdown, repeated external math calls, and repeated constant text construction. Both C variants have identical compiler flags and report identical output and logical instruction counts. Regenerate local measurements with `make benchmark`; it writes `benchmarks/RESULTS.md` and `artifacts/foundation-benchmarks.json`. Generated measurements are excluded from the source repository.

Complete CLI latency includes startup and VM initialization. Warm WASM execution is shown separately, not mixed into a misleading comparison. These are microbenchmarks on one shared Linux machine—not a proof of the fastest possible design, a comparison against arbitrary hand-written C/Rust, or a prediction for your application.

Research and deferred ideas are in [docs/RESEARCH.md](docs/RESEARCH.md).

---

## 8. Exact guarantees and current limits

| Area | Implemented contract |
|---|---|
| Data stack | 2,048 values, with construction-frame pop floors |
| Construction nesting | 64 frames |
| Return stack | 1,024 continuations, saved construction depth |
| Arenas | 32,768 value slots; 32,768 array edges; 524,288 text bytes |
| Buffered output | 262,144 bytes |
| Input record | At most 2,048 bytes; exhausted input is a diagnostic |
| Compiled/WASM input buffer | At most 1 MiB per run |
| Compiled source | At most 65,535 normalized source bytes; native source reader allows up to 262,144 |
| Link registry | 32 modules including built-ins; 256 total symbols |
| Native descriptor | 1–128 symbols; ASCII identifiers 1–63 bytes; arity 0–8 |
| Literal cache | At most 1,024 distinct pools / 8,192 literal bytes |
| Comparison work | At most 262,144 recursive value comparisons per equality instruction |
| Numbers | Finite IEEE binary64; integer-tagged results restricted to ±(2^53−1) |
| Source locations | Byte-oriented; diagnostics use one-based line/column |

- `=` consumes the two compared operands and two coordinates. Numeric integer/float equality is allowed; numeric zero is not text `0`.
- Foundation deliberately fixes the standard-call receiver, indexing order, and coordinate conversion. Index keys follow the explicit repair behavior, including truncation; taken jump/call coordinates must be integral.
- Foundation comments resume at column zero of the next line. The reference profile retains its measured comment-column behavior.
- Spaces, digits, letters, and selected punctuation push character text; newlines do not. Unknown plain bytes are ignored as in the reference dispatcher. Escape punctuation when it must be data; this is not a conventional whitespace-insensitive syntax.
- The source macros are ASCII-oriented. This is not a Unicode-token or Unicode-index language. Human-facing JSON probes are intended for text/ASCII diagnostics; use raw output and WASM byte buffers for binary data rather than assuming arbitrary bytes are UTF-8 JSON strings.
- Output is buffered until the run ends. The Fortran runner reads input records on demand. The generated CLI runners buffer stdin through EOF when their bytecode contains a read; programs with no read instructions do not wait for stdin. Those are batch runners, not a finished interactive console.
- Fuel bounds Urotif instructions, not wall time, I/O waits, native constructors, or external service duration. Put untrusted workloads behind a real host timeout/isolation boundary.
- Implementation memory budgets can be reached at different points when caching/fusion changes allocation. The verified parity cases are within those budgets; no claim of allocation-identical execution is made.

Not implemented: an Oak object/eval/source-module loader, a `.uru`/`.urb` binary format loader, arbitrary pointer FFI, general string/array foreign results, a full int64 data model, WASI components/WIT, a JIT, concurrent/reentrant instances in the native host, or production security certification.

---

## 9. Verification, not just examples

Recorded full run:

- **101** original-profile/experimental-core Python tests pass.
- **23** Foundation differential/integration suites pass.
- **11** Rust unit tests pass.
- **202** emitted-C runs under AddressSanitizer and UndefinedBehaviorSanitizer report no diagnostics in the smoke test.

The Foundation suites include 100 arithmetic expressions, 100 malformed entry paths, 46 partial-fuel boundaries, the intended truth flow, typed equality, imports, argument ordering, C/Rust plugins, missing grants, bad ABI rejection, subroutine recursion/returns, jumps into optimized literals/escape interiors, multi-line literals, live nested values surviving GC, stack/frame limits, repeated runs, label assembly, and invalid WASM calls clearing prior output.

The reference files and runnable ablations are retained. Original file bytes are checked by `reference/SHA256.json`; archived logs and ZIPs are not part of this source-only repository.

**Bottom line:** the foundation is now runnable, linkable, measurable, and small enough to reason about. The next sensible expansion is a versioned borrowed-byte/batch-call ABI and broader differential testing—not silently adding unsafe pointer features or claiming it is already battle-proven.
