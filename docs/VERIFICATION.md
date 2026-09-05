# Verification scope

## Recorded Urotif 0.4 results

The implementation was validated in staged local runs, not a newly claimed monolithic run of every legacy suite. The recorded toolchain was Linux/GCC/gfortran 14.2, Rust 1.98.1, Node 20.20.2, and Python 3.13.14.

| Check | Recorded result |
|---|---:|
| Preserved reference / experimental-core tests | 101 passed |
| Rust unit tests | 19 passed |
| Extension differential suites | 10 passed |
| WASM-host unit tests | 12 passed |
| Selected legacy Foundation suites | 4 passed |
| Selected legacy roundtrip suites | 4 passed |
| Typed-path generated-C / C-plugin sanitizer executions | 70 clean |
| Existing generated-C sanitizer executions | 202 clean |
| Typed examples | 10 |
| Emitted target artifacts checked | 40 |
| Initial native / C / Rust / Fortran / WASM executions | 50 matching |
| Byte-compared normalized-source recoveries | 40 |
| Recovered-source WASM re-emissions/executions | 10 matching |

Typed checks cover 24 failure cases, zero/eight-argument calls, type/arity rejection, binary bytes, flat vectors, Unicode, aliases, result capacities, GC retention, repeated runs, subroutines, metadata-only grants, descriptor rejection, and the legacy missing-result sentinel. The Fortran long-binding check compiles 63-byte module and function names. Host checks include copied inputs, memory growth, exact grants, buffer ranges/alignment, sparse vectors, and prototype-related import names.

The C sanitizer harness instruments the generated C runtime and C plugins. It does not instrument the linked Rust sample archive or establish safety of arbitrary native libraries. A successful result is smoke-test evidence, not certification or universal portability.

The earlier 0.3 validation also used split runs after correcting duplicate test discovery and active-stack GC reservation. Historical documents retain that context; their older test counts/limits are not claims about the current configuration.

## Source-only bundle checks

The GitHub cleanup preserves compiler/runtime/header/plugin/source-fixture bytes while removing build outputs, generated target files, working notes, and machine-specific logs. Original reference hashes remain in `reference/SHA256.json` and are checked by tests and `tools/check_repository.py`.

A fresh extraction of the cleaned source archive was checked locally:

- `make all core95 plugins -j2` and Rust formatting checks passed.
- 19 Rust units, all 101 reference/core tests, and all 12 WASM-host units passed.
- Four selected extension suites passed: value flow across all targets, metadata/recovery, declaration/long-binding validation, and the legacy missing-result sentinel.
- Three selected roundtrip suites passed: strict F95, recovery/re-emission across targets, and native streaming.
- The 202-execution generated-C sanitizer suite passed, including a rerun with the entire `artifacts/` directory initially absent.
- The typed showcase generator ran from the cleaned checkout: five matching executions, four exact recoveries, and recovered-WASM re-emission/execution. Generated reports/galleries remain excluded from the bundle.
- All twelve original reference hashes matched. Compiler/runtime/header/plugin and example implementation files were compared byte-for-byte with the 0.4 working tree.
- Local Markdown links, CI YAML syntax/matrix, Git-aware package selection, rejection of an intentionally tracked build product, and byte-source Git attributes were checked.
- The source ZIP is checked by CRC and per-file SHA256. Packaging normalizes ordering and ZIP timestamps; checksum/manifest sidecars are kept outside the repository payload.

This is a focused clean-source validation, not another full run of every legacy cross-target suite. The supplied GitHub Actions workflow is configuration, not evidence that a hosted run has already succeeded. CI requests Ubuntu 24.04, stable Rust, Node 22, and Python 3.13; inspect its results after upload.

## Reproduce

```sh
make all core95 plugins -j2
make test-reference
make test-typed
make test-foundation
make test-roundtrip
make sanitize sanitize-typed
make typed-examples
```

For shorter batches, use individual test names documented in [CONTRIBUTING.md](../CONTRIBUTING.md) and [TYPED_LINKS.md](../TYPED_LINKS.md). Generated reports and inspectors stay under ignored paths. Full historical logs and old release archives are deliberately not part of this source-only repository.

No new performance speedup is claimed for the GitHub cleanup or typed marshaller. Run `make benchmark` for local measurements and report compiler flags, workloads, repetitions, and limitations with any performance claim.
