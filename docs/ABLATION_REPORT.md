# Archive ablation log

## Preserved inputs

| Archive | SHA-256 |
|---|---|
| `smp.zip.txt` | `0db7aa943cc3fdd7a2b7690e7ffc5d94ba74cc1d7a5fe202de0198504189489f` |
| `urotif.zip.txt` | `e746da7164154170f91f9666500ca91c904333afaec6fe75f8b8436f43f52c79` |

The `.txt` suffixes conceal actual ZIP files. They contain six sample files and five Oak source files. Both were inspected and extracted without changing their contents. The available `USAGE.md` was also retained; where it disagrees with measured behavior, it is not used as an execution oracle.

## Method

Use the official Oak v0.3 executable, first with the supplied CLI wrapper, then with a tiny driver that imports the original interpreter and calls `main.file(...)`. Save stdout and final `Env.Memory`. Apply one semantic patch at a time to temporary copies only. Compare the Fortran port with these observations, not with inferred behavior from filenames or comments.

Oak documents typed values rather than general implicit conversion, consistent with the observed difference between raw character digits, numeric conversion, and string concatenation. [1](https://github.com/thesephist/oak)

## A0 — remove the runner as a confounder

All six files fail through unmodified `run.oak` on official Oak v0.3:

```text
Runtime error [6:2]: __ is undefined
```

This could differ in an unprovided Oak fork. The measured baseline names its interpreter version explicitly. Bypassing the runner does not require an interpreter patch.

## A1 — measure direct interpreter behavior

- `hello.utf`: `Hello, World!\n`; empty final data stack.
- `anb.utf`, inputs `2\n3\n`: `32`; empty stack. `input('').data` is text, and the source implements `pop() + pop()`.
- `bin.uru`: no output; stack is the nine individual characters `fcda123ad`.
- `fib.utf`: fails because `;` evaluates `k.(h)`, indexing the top string `"0"` with an array.
- `truth.utf`: fails because `callFx(sc,lx)` ignores `sc` and calls `Ctx.(lx.0)`; `Ctx.int` is not a function.
- `hello.urb`: `<` followed by a stack of characters. The first `=)` line is skipped regardless of its declared name; there is no urobore decoder in this execution path.

## A2 — index only

Patch:

```diff
- Env.add(k.(h))
+ Env.add(h.(int(k)))
```

The unchanged Fibonacci-named sample now terminates with memory:

```json
[[["0","1"],"0"]]
```

The outermost list is Oak's memory-stack collection. The active data stack is `[["0","1"],"0"]`. Nothing is printed.

## A3 — C-call receiver only

Patch:

```diff
- Ctx.(lx.0)(std.slice(lx, 1)...)
+ sc.(lx.0)(std.slice(lx, 1)...)
```

`std.int` really exists in official Oak v0.3. The unchanged truth sample now reaches `gotoVec`, where subtracting integer `1` from character `"0"` fails. This is a new barrier, not a successful execution.

## A4 — receiver, indexing, coordinate conversion

Patch coordinates explicitly:

```diff
- [Env.pop() - 1, Env.pop() - 1]
+ [int(Env.pop()) - 1, int(Env.pop()) - 1]
```

With these repairs and a separate 80-instruction watchdog, original `truth.utf` prints `????` and is stopped by the watchdog. The numeric input is compared against text `"0"`; `=` consumes both values; `$` sees an empty stack and Oak stringifies its null result as `?`. EOF also produces null-like behavior in the original rather than terminating this loop.

The Fortran port reports these unsafe/undefined-for-the-port accesses instead of claiming that `????` is a successful truth result.

## A5 — user revision

The later revision adds an initial `0` and changes the return jump to `21^`. It has its own preserved fixture and four regression tests. It fixes the first empty-stack print; the second pass skips the seed and still underflows. Full analysis: `../REVISED_TRUTH.md`.

## Additional type ablations

A direct comparison of 31 initially expected successful reductions exposed three more assumptions:

- `{0}` is a float, not an integer, so it is not a valid unconverted list index in Oak.
- Brace-constructed coordinates remain floats after subtraction and fail when used as execution indices.
- A taken numeric conditional therefore also exposes float-index failure; a non-taken branch does not transfer control.

The Fortran port was corrected to distinguish float and integer tags for these paths. Those three reductions were moved to expected-diagnostic or explicitly repaired tests rather than relabeled as source successes. Numeric storage is still binary64, not a full 64-bit integer emulation.

## Relevant source locations

In the preserved `reference/urotif/main.oak`:

| Lines | Behavior |
|---|---|
| 131–133 | ASCII character-push macro installation |
| 139, 145 | Text input; reverse pop order for `+` |
| 157–166 | Coordinates and consuming equality branch |
| 177–189 | Executable construction frames; float conversion |
| 192–195 | Indexing operand reversal |
| 218–220 | Ignored call receiver |
| 239–244 | Array printing, stringify, join |
| 302–305 | Unconditional post-instruction column increment |
| 316–319 | Header-prefix skip, independent of extension/header name |

Evidence files retain raw stdout, including failures. Negative tests are expected barriers, not fabricated successful outputs.
