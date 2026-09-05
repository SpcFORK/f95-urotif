# Security policy and boundaries

Urotif is experimental. Do not treat it as a hardened sandbox or expose the native compiler/runtime to arbitrary workloads without external isolation.

## Trust model

- Native `--link` libraries run trusted code, including constructors. ABI, pointer-alignment, capacity, and finite-number checks cannot prove allocation validity, prevent native memory corruption, undo writes, or stop a blocked callback.
- Do not unwind through the C ABI, retain/free borrowed storage, mutate read-only inputs, replace caller-owned pointers/capacities, change floating-point configuration, or reenter the running VM.
- Urotif instruction fuel does not meter host callback work or elapsed time. Use OS/process/worker timeouts and resource limits where appropriate.
- WASM isolates linear memory, not the JavaScript provider. Providers execute with host privileges and must be explicitly granted and validated.
- Source includes access local files during assembly. A future hosted compiler must isolate the filesystem and restrict includes, options, and imports; a working directory alone is not a sandbox.
- `--extern` / `--extern-v2` are declarations, not library loading. Prefer metadata-only emission for untrusted compilation inputs.
- Source capsules and link catalogs are unauthenticated metadata. CRC checks detect corruption, not malicious edits or provenance. Reapply resource policy and grants after recovery.

## Reporting

If private vulnerability reporting is enabled on the GitHub repository, use its Security tab. Otherwise ask the repository maintainer for a private reporting channel without posting exploit details or secrets in a public issue. This bundle does not invent a maintainer email address or promise a response SLA.

Provide the source/profile, toolchain and OS versions, policy limits, exact command, and a minimized reproducer when possible. Avoid attaching credentials or unrelated private files.

## CI and dependencies

The supplied workflow uses read-only repository permissions and does not publish packages or deploy software. Cargo dependencies are locked, not vendored; inspect their upstream licenses and advisories. A successful build/test run is not security certification.
