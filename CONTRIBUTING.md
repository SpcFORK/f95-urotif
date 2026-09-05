# Contributing to Urotif

## Preserve the architecture

Fortran owns the native main, source decoding, assembly, and source-stable IR. Rust is the linked emission chain. Do not introduce a replacement JavaScript or Rust Urotif frontend as an incidental change to a host adapter.

The value/marshalling core must continue to compile with `-std=f95 -pedantic-errors`. Put standardized CLI and C-interoperability features in the separate F2003 adapters. Generated Fortran must remain independently compilable without the Rust compiler-chain library.

## Build and test

Follow the prerequisites in [README.md](README.md), then:

```sh
make all core95 plugins -j2
cargo fmt --manifest-path rust-chain/Cargo.toml -- --check
python3 tools/check_repository.py
make test-reference
make test-typed
```

Run relevant Foundation and roundtrip suites for changes to execution semantics, allocation, source locations, or emission. Test names can select shorter batches:

```sh
python3 tests/test_roundtrip.py Roundtrip.test_strict_f95_is_standalone_without_rust
python3 tests/test_typed.py Typed.test_gc_preserves_typed_results
```

For C/runtime/FFI changes, run `make sanitize sanitize-typed`. Sanitizers are smoke-test evidence, not proof of safety. A change to a typed ABI layout must update the C header, Rust/F2003 views, WASM offsets, signatures, and layout/contract tests together.

## Sources and fixtures

- Preserve `reference/` originals byte-for-byte; verify `reference/SHA256.json`.
- Add new reduced cases to `ablations/` or tests rather than silently repairing original fixtures.
- `.utf` and `.ufm` whitespace is not conventional formatting. A space may push data; do not globally trim or reindent these files.
- Keep explicit profiles (`--repair`, `--foundation`, `--core`) separate.
- Optimizations must retain valid entry into raw byte interiors and observable fuel/error behavior.
- Maintain the distinction between source recovery and decompilation. Recovery does not authorize libraries or restore host grants automatically.

## Repository hygiene

Generated targets, offline galleries, artifacts, logs, native libraries, and compiler caches are ignored. Regenerate them with Make/tool commands; do not commit them as source. `python3 tools/package_source.py` creates a filtered source ZIP under `release/` with external checksum/manifest sidecars.

Never commit tokens, private keys, credentials, or `.env` files. The repository checker looks for common sensitive filenames and high-confidence token/private-key patterns; it is a limited check, not a guarantee that every secret can be detected.

## Pull requests

Describe the profile affected, semantic change, tests run, and any compatibility limitations. Do not claim the entire suite passed if only selected tests ran. GitHub Actions is split into jobs to keep failures attributable.

A project license and reference-fixture redistribution rights still need confirmation by the repository owner before accepting public contributions under a defined license. No CLA or contributor license is implied by this bundle.
