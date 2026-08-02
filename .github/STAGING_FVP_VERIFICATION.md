# PocketKernel 1.0 FVP staging verification

This marker keeps the full rebuild isolated while the draft pull request runs the macOS 26 Intel test, device build, IPA validation, and artifact gates. It is removed before the final squashed merge.

Current verification includes the Swift 6-safe static SQLite bootstrap with WAL and foreign keys enabled before actor-isolated access begins.
