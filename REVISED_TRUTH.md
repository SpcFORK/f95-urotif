> **Historical regression report.** Your subsequently clarified input/zero-loop intent is now implemented in `examples/foundation/truth.utf` under the explicit Foundation profile. See [FOUNDATION.md](FOUNDATION.md). The supplied revision and these old-profile observations remain unchanged.

# Revised truth program — measured result

The user's revision is saved in `examples/truth-revised.utf`. The archive fixture `reference/smp/truth.utf` is unchanged.

```text
=) urotif
0[[int]S@`]C@030=$21^
0$30^
```

Markdown hard-break spaces were treated as formatting, not inserted as Urotif data. Both executable lines jump before reaching any trailing spaces anyway.

## Result

```sh
printf '2\n3\n' | bin/urotif probe examples/truth-revised.utf --repair
```

The Fortran implementation produces:

```json
{
  "ok": false,
  "steps": 38,
  "output": "0",
  "stack": [],
  "error": "P001: empty active stack (Oak would yield null here)",
  "line": 2,
  "column": 18
}
```

**The leading `0` fixes the first empty-stack print, but not the second pass.**

Without `--repair`, the earlier `C@` receiver bug still stops this revision at line 2, column 13, before any output. The repair switch fixes the indexing operand order, the `C@` receiver for `std.int`, and numeric conversion of coordinates. It does not change jump-column conventions or equality/consumption rules.

## First pass, bottom → top

For input `2`, immediately before `=`:

```text
["0", 2, "0", "3", "0"]
  ^    ^    ^     ^    ^
 seed input compare line column
```

1. `=` pops the two coordinates, then the two compared values.
2. The remaining seed is the character `"0"`.
3. `$` prints and removes it, producing `0`.
4. `21^` jumps back to **line 2, zero-based column 1**, which is the first `[`, not the initial `0`.
5. The second pass does not replace the seed. Its `=` consumes the compared values, and `$` then encounters an empty stack.

The source's `gotoVec` subtracts one from the requested column, but `doLoop` increments it immediately afterward. Consequently the **effective column is zero-based**, while the line is one-based. This is an observed property of `reference/urotif/main.oak`, not the coordinate convention claimed in the supplied Markdown documentation.

```text
line 2, effective column:  0 1 2 3 4 5 ...
source character:         0 [ [ i n t ...
```

## Numeric zero is a separate issue

Plain `0` pushes text `"0"`. `C@` with `int` returns numeric zero for input `0`. Those values are not equal in Oak. Testing with inputs `0` then `3` therefore reaches the same second-pass failure.

A brace construction `{0}` produces numeric zero (a float), which does compare equal to integer zero in Oak. That could replace the **comparison** operand if a numeric-zero test is intended. It does not by itself resolve the loop's missing seed.

## Controlled comparison, not an applied edit

Changing only `$21^` to `$20^` restarts on the seed. With inputs `2` and `3` and an explicit 42-instruction budget, that variant produces `00` and then reaches the fuel limit at the beginning of pass three. This demonstrates the restart-column difference; it does **not** establish that the program's intended truth behavior is correct.

No proposed change has been applied to the user's fixture.

## Independent Oak check

With only the `C@` receiver and coordinate conversions repaired in a temporary copy of the Oak interpreter, a 61-instruction watchdog observes output `0??`. The first `0` is the seed; later `?` characters come from Oak's null-on-empty-stack behavior. The watchdog stopped the run: this was not normal termination.

The Fortran port deliberately reports empty-stack access rather than continuing to print null values.

The recorded observations are covered by `tests/test_pipeline.py`; machine-specific archived JSON/logs are not included in the source repository.
Regression coverage: four dedicated revised-fixture tests in `tests/test_pipeline.py`.
