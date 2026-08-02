# PocketKernel 1.0 FVP requirements matrix

The staging branch is not eligible for merge until every required source, test, binary, package, and real-device gate from the canonical 30-section specification is verified. A green build alone is not completion.

- [x] Full declarative domain and package integrity implemented on staging
- [x] Bounded expression and binding engine implemented on staging
- [x] Every declared component has a concrete renderer path
- [x] Every action performs its named behavior
- [x] Multi-screen Foundation Models generation with deterministic CI mock
- [x] Manual builder and five complete templates
- [x] SQLite records, permissions, activity, metadata, rollback, and recovery
- [x] Home, Create, Library, Activity, and Settings implemented
- [ ] Domain, runtime, persistence, package, and UI tests pass in macOS CI
- [ ] ARM64 unsigned IPA validation passes
- [ ] Signed iPhone 16 acceptance sequence passes

The checked source rows remain provisional until the compiler and tests verify them.
