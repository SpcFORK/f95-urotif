# Changelog

## 0.4.0

- Add separate ABI-2 descriptors and number/bytes/flat-vector signatures while retaining ABI1.
- Marshal typed values through native Fortran and emitted C, Rust, Fortran, and WASM.
- Add bounded caller-owned results, checked signatures, finite-number checks, and ownership-descriptor validation.
- Add explicit typed WASM providers, embedded link catalogs, copied inputs, and refreshed memory views after growth.
- Add C buffer/vector services, a Rust Unicode/vector library, ten examples, and typed source macros.
- Add cross-target, host, contract, resource, GC, recovery, and sanitizer checks.
- Harden emitted Fortran's missing numeric-result sentinel and long canonical binding names.

The GitHub source packaging adds repository hygiene, public build/contribution/security documentation, and CI configuration. It removes generated deliverables and local logs from the source bundle without changing the compiler/runtime implementation.

## 0.3.0

- Add standalone Fortran emission, including a strict-F95 built-in-only entry.
- Add checked configurable budgets, source-sized IR, source libraries/macros, and fourteen examples.
- Add byte escapes, byte-safe diagnostics, native streaming, and optional normalized-source recovery.
- Fix stack-backed source-workspace and near-full arena reservation issues.

## 0.2.0

- Add the explicit Foundation profile, imports/references/application, coordinate subroutines, numeric C/Rust plugins, and portable targets.
- Add source-stable optimizations, differential tests, and measured local workloads.

## 0.1.0

- Preserve original supplied archives as fixtures and establish independent behavior/ablation checks.
- Implement the Fortran-owned reference path and retain the separate experimental core chain.

Source recovery is metadata recovery, not general decompilation. No dedicated browser engine, full int64 data model, or native security sandbox is introduced by these releases.
