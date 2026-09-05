# Third-party material and provenance

## Supplied Urotif reference material

`reference/urotif/`, `reference/smp/`, and `reference/USAGE.original.md` preserve the supplied Oak prototype, samples, and accompanying usage text. `reference/SHA256.json` records the twelve original file hashes. They are retained as compatibility/test fixtures, not relicensed as part of the new implementation.

Their author/redistribution terms were not established by the material included in this bundle. The repository owner must confirm the applicable terms before public redistribution. No authorship is inferred merely from the programming language used.

`ablations/`, the revised-truth fixture, and `tests/oak-probes/` support behavior comparisons with those inputs. Keep provenance and deliberate repairs visible rather than presenting modified samples as originals.

## External dependencies and tools

- Rust dependencies are declared in `rust-chain/Cargo.toml` and resolved by `Cargo.lock`; they are downloaded through Cargo, not vendored here. Their upstream license terms continue to apply. `cargo metadata --locked --format-version 1` exposes dependency package metadata for review.
- The optional [Oak interpreter](https://github.com/thesephist/oak) is not included. The independent comparison tool requires a separately installed interpreter.
- GCC/gfortran, Rust/rustup, Node.js, Python, Make, and the GitHub Actions referenced by CI are external tools, not bundled executables.
- Research links identify design references; links are not claims of ownership or redistribution permission.

See [docs/LICENSING.md](docs/LICENSING.md) for the remaining publication checklist. This file is a provenance notice, not a substitute license.
