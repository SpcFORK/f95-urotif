# Urotif

**Fortran Main → Fortran frontend / IR → Rust chain → C · Rust · Fortran · WebAssembly**

Urotif is an experimental, subroutine/goto-based byte language with a BNF-described source-assembly layer. The native main, source decoder, and value runtime remain Fortran-owned. Rust supplies the linked emission backend—not a replacement source-language frontend.

Current source version: **0.4.0**.

## Features

- Native execution and standalone C, Rust, Fortran, and WASM emission.
- Strict-F95 value/marshalling core, with separate F2003 CLI and C-interoperability adapters.
- Labels, subroutines, source includes, and nonrecursive convenience macros.
- ABI-1 numeric plugins and ABI-2 number / bytes / flat-numeric-vector plugins.
- Explicit WASM host grants, checked resource budgets, byte-safe output, and native streaming.
- Optional normalized-source capsules for recovery and re-emission.
- Preserved reference fixtures, differential tests, and sanitizer harnesses.

Generated programs contain decoded instruction tables and an execution kernel. Source recovery retrieves metadata: it is **not arbitrary target-language decompilation, edit synchronization, or self-hosting**.

## Build

The supported/tested configuration is Linux with GCC/gfortran, Rust/Cargo via rustup, Python 3.11+, Make, and Node.js 20+ (CI requests Node 22). System-library flags for other operating systems have not been validated.

```sh
# Install the native build tools using your system's package manager.
# Install rustup separately if it is not already available.
rustup toolchain install stable --profile minimal --component rustfmt \
  --target wasm32-unknown-unknown
make all core95 plugins -j2
```

`rust-toolchain.toml` selects stable Rust and the WASM target. Cargo dependencies are locked in `rust-chain/Cargo.lock`; a first build needs network access to obtain missing toolchains/dependencies.

## Run an example

```sh
bin/urotif assemble examples/typed/showcase.ufm -o build/showcase.utf
bin/urotif run build/showcase.utf --foundation \
  --link build/buffers.so --link build/unicode.so
```

```text
00ff43
[21, 41]
62
STRASSE CAFÉ
```

The C library transforms binary bytes and numeric vectors; the Rust library handles Unicode. The same reference/`@` mechanism invokes both. New library functions are supplied through metadata and implementations, not new language opcodes.

## Emit and recover

A built-in-only example needs no external host library:

```sh
bin/urotif wasm examples/next/factorial.utf --foundation --embed-source \
  -o build/factorial.wasm
node tools/foundation-wasm.mjs build/factorial.wasm --json
# Output: 720 followed by a newline

bin/urotif recover build/factorial.wasm -o build/factorial-recovered.utf
cmp examples/next/factorial.utf build/factorial-recovered.utf
```

Use `c`, `rust`, or `fortran` instead of `wasm` for source emission. `--f95` supplies a strict-F95 standalone entry for built-in-only Fortran output. Foreign bindings require the separate F2003 adapter. For plugins, see the metadata-only `--extern-v2` and static-link commands in [TYPED_LINKS.md](TYPED_LINKS.md).

A dedicated browser playground or web-application engine is **not included in 0.4**. The WASM runtime and typed host adapter are reusable building blocks; the supplied execution host is currently Node-based.

## Documentation

- [Typed libraries and target commands](TYPED_LINKS.md)
- [Source libraries, resource budgets, streaming, and recovery](ROUNDTRIP.md)
- [Foundation semantics](FOUNDATION.md) — historical 0.2 baseline; later guides supersede its limits
- [Linking and host interfaces](docs/LINKING.md)
- [Compiler IR](docs/FOUNDATION_IR.md)
- [BNF: base profile](docs/foundation.bnf), [source assembly](docs/roundtrip.bnf), [typed metadata](docs/typed.bnf)
- [Verification scope](docs/VERIFICATION.md), [research](docs/RESEARCH.md), [reference provenance](reference/README.md)
- [Contributing](CONTRIBUTING.md), [security boundaries](SECURITY.md), [publishing this bundle](docs/PUBLISHING.md)

The repository keeps source and reproducible tooling, not generated target files, galleries, compiler caches, local logs, or release ZIPs. To generate the typed examples and offline inspector locally:

```sh
make typed-examples
# Produces artifacts/typed/ and TYPED_LINKS.html; these outputs are ignored by Git.
```

## Tests

```sh
make test-reference       # Rust units + preserved reference / core tests
make test-typed           # Typed differential suites + WASM-host units
make test-foundation     # Compilation-heavy legacy differential suites
make test-roundtrip      # Recovery, budgets, examples, streaming
make sanitize            # Generated C: ASan / UBSan
make sanitize-typed      # Generated C and C plugins: ASan / UBSan
```

For a shorter check:

```sh
python3 tests/test_typed.py Typed.test_value_flow_all_targets
node --test tests/test_wasm_links.mjs
python3 tools/check_repository.py
```

Cross-target tests invoke real compilers and can take minutes. GitHub Actions separates the suites into jobs; the workflow is provided but must run on GitHub before it can be treated as a passing hosted build. Local and historical verification are distinguished in [docs/VERIFICATION.md](docs/VERIFICATION.md).

## Profiles and limits

- Default `run` / `probe`: preserved reference behavior; repairs require explicit `--repair`.
- `--foundation`: portable byte-language profile, imports/references, coordinate calls, source libraries, and typed extensions.
- `--core`: quarantined earlier numeric/text experiment, not a replacement for the reference language.

Native plugins are **trusted code, not sandboxed**. Buffer checks cannot stop native corruption, crashes, constructors, or hangs. WASM providers execute with host privileges. Fuel counts Urotif instructions, not callback wall time. Numbers remain binary64 rather than int64; foreign vectors remain flat. See [SECURITY.md](SECURITY.md).

## Licensing

No project license was supplied with this source tree, so this bundle does not invent one. Before a public/open-source release, select a license for the implementation and confirm redistribution rights for the preserved reference fixtures. See [docs/LICENSING.md](docs/LICENSING.md) and [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
