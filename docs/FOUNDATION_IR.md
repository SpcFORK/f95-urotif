> **0.3 addendum:** the 32-byte IR2 instruction layout is unchanged. Opcode **27** is a decoded `\xHH` byte push (cost 1, next entry after the four-byte escape). Only 23–26 are constant-span fast paths. Every interior source byte still retains its own entry. The new `urotif_foundation_emit_v3` adapter carries 11 policy integers, optional source bytes and flags; the released ABI-2 emitter remains available with defaults. Format 3 emits standalone Fortran. IR allocation follows source size; the old 65,535-byte ceiling below is historical. See `include/urotif_foundation.h` and `ROUNDTRIP.md`.

# Foundation IR2 and optimization contract

## Ownership

`fortran/urotif_foundation_ir.f90` reads and decodes the primitive character language. `fortran/urotif_assembler.f90` optionally resolves symbolic conveniences before this step. Both are F95. `urotif_foundation_bridge.f90` converts the result to explicit C-compatible fields. The native Rust library validates the IR and generates C/Rust source; rustc builds the WASM target.

The target kernels in `runtime/foundation.c` and `runtime/foundation.rs` **do not parse Urotif source**. They execute already-decoded entries and implement value operations. Runtime decimal/name parsing is parsing data, not replacing the Fortran frontend.

## Wire record

IR ABI number: **2**, separate from experimental IR1.

```c
struct instruction {
    int32_t op, arg, next, cost, line, column;
    double number;
};
```

The tested native wire layout is 32 bytes. `next` is an absolute zero-based IR index. `line`/`column` are one-based diagnostic coordinates. All buffers are borrowed for the duration of the emit call. Text spans use zero-based offsets and lengths. See `include/urotif_foundation.h`.

Limits: at most 65,536 entries including the terminal sentinel, 1,024 literal pools of at most 2,048 bytes each, and 8,192 bytes of distinct cached literal content selected by the optimizer. IR validation checks operation ranges, targets, argument indices, spans, fuel costs, finite constants, and the final halt sentinel. It cannot make invalid foreign memory pointers safe; the embedding caller owns that contract.

## Entries

| ID | Operation | Argument |
|---:|---|---|
| 0 | EOF halt sentinel | — |
| 1 | Push literal character | Byte |
| 2 | Ignored source byte | — |
| 3 | Line boundary | Zero fuel; `next` advances |
| 4 | Escape | Byte; 256 marks an invalid trailing escape |
| 5 | Open construction | 0 array, 1 numeric |
| 6 | Close construction | 0 array, 1 numeric |
| 7 | Duplicate | — |
| 8 | Drop | — |
| 9–12 | Add, subtract, multiply, divide | — |
| 13 | Negate | — |
| 14 | Print | — |
| 15 | Spread array | — |
| 16 | Index | — |
| 17 | `@` dispatch/application | — |
| 18 | Read text record | — |
| 19 | Coordinate jump | — |
| 20 | Consuming equality/coordinate branch | — |
| 21 | Comment skip | `next` resumes next line at column zero |
| 22 | Recognized unsupported object operation | Runtime P006 |
| 23 | Cached external-reference fast path | Stable symbol slot |
| 24 | Cached constant character-array fast path | Literal pool |
| 25 | Cached constant text fast path | Literal pool |
| 26 | Decimal-number construction fast path | `number` |

This is a compact representation of the source semantics, not 27 new surface-language keywords.

## Why every byte keeps an entry

Urotif can jump to an arbitrary character/byte offset, including the middle of what looks like a literal or escape. Deleting an interior instruction would change the language.

The decoder therefore emits an entry for **every normalized source byte**, including bytes normally skipped by a comment, header, or escape. The normal entry skips an optional initial `=)` header. An escape has a two-byte `next`, but the second byte still has its own independently executable entry. A line feed costs zero logical instructions.

A recognized constant replaces only its **starting entry's execution path**. Its interior entries remain intact. Enter at the start and the fast path skips to the original continuation; enter at any interior byte and the original byte operation runs.

Example tested across targets:

```text
=) urotif
[31^
[ab]P@h@
```

The first `[` opens a construction; the jump enters line 3 at column 1, skipping the second `[` but retaining `a`, `b`, `]`, and the print. It outputs `ab` plus newline even though `[ab]` has an optimized entry at column zero.

## Fuel and transient stack depth

A fast path charges the sum of the original executable character instructions. It does not count skipped newlines twice or count an escape's second byte as a separate normal-path instruction.

When remaining fuel is smaller than that cost, the engine executes the original opening `[` or `{` at cost one, then follows the unfused interior entries. This preserves partial progress, underflows, and error coordinates at intermediate fuel values.

The same fallback is required when replacing a construction would bypass the original transient stack/nesting limit. For example, a constant array cannot be pushed directly to avoid a stack overflow that its individual character pushes would have encountered. The current pure-literal patterns have a derivable transient peak from their original cost; the runtime checks it before using the fast path.

No callbacks, input operations, or general sequences with side effects are fused. Unresolvable literal names remain runtime resolution operations; the optimizer does not invent a grant.

## Allocation and collection

Values have tags: null, float, bytes, array, exact-range integer, module, and reference. Arrays/bytes are immutable. Data stacks contain value IDs, not foreign pointers.

Collection happens only between instructions:

1. Mark active data/construction values, character caches, module/reference caches, and target literal caches.
2. Follow immutable array edges.
3. Reuse unreachable value slots.
4. Compact live text and edge payloads, updating their owning node offsets.
5. Keep every live value ID unchanged.

Temporary IDs within an instruction cannot be collected mid-operation. Foreign calls receive copied numeric arguments, not GC-managed value pointers. Caches are bounded so cached dead-path constants cannot grow without limit. Allocation profiles differ across implementations/optimization modes; the budget is a safety limit, not a promise of allocation-identical failure points.

## What is deliberately not here

- No Rust source-language frontend.
- No arbitrary instruction deletion, relocation of public byte targets, or unchecked computed goto.
- No JIT, dynamic machine-code generation, direct-threading requirement, or pointer punning.
- No source-static claim that arbitrary goto programs are well-typed or always terminate.
- No native-plugin sandbox or preemption of foreign code by the instruction counter.

The next optimizations should be selected by profiles: compact native-Rust indices, additional proven fast paths, top-of-stack caching, or block lowering with retained interior entry paths. Each needs an ablation and the same differential/fuel tests, not a blanket assumption that more fusion is faster.
