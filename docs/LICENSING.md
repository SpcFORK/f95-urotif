# Licensing checklist

No project-wide license file or confirmed reference-fixture license was supplied with the source tree used for this bundle. The cleanup does not assign ownership or silently add an open-source license.

Before publishing the repository publicly or describing it as open source:

1. Confirm who can license the Urotif implementation and documentation.
2. Choose a license for those materials and add the appropriate license text with accurate notices. Do not leave a guessed copyright holder/year.
3. Confirm redistribution permissions and any attribution requirements for `reference/` and the supplied prototype/sample material. These files are preserved verbatim for testing; preservation is not a license grant.
4. Review licenses of Cargo dependencies and any binaries distributed in future releases. Dependencies are not vendored into this source bundle.
5. Record the scope clearly if different files use different licenses. Do not assume a root license can override third-party terms.

The optional Oak interpreter is a separate upstream tool. Writing a program in Oak does not automatically give that program the interpreter's license. See [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md).

A GitHub upload, source checksum, or successful test run does not resolve licensing. If these decisions are not yet settled, review them before making a public release; no publishing action has been performed by preparing this bundle.
