# PocketKernel 1.0 FVP staging verification

This marker keeps the full rebuild isolated while the draft pull request runs the macOS 26 Intel test, device build, IPA validation, and artifact gates. It is removed before the final squashed merge.

Current verification includes the Swift 6-safe static SQLite bootstrap with WAL and foreign keys enabled before actor-isolated access begins.

The XCTest suite evaluates actor calls before entering synchronous assertion autoclosures, allowing Swift 6 concurrency checking to proceed into real unit and UI execution.

The shipped built-in apps are now real validated `.pocketapp` resources with screens, collections, actions, capability declarations, and matching integrity hashes.

Run 137 isolated four Swift compiler ambiguities in the runtime renderer and permission dialog. This marker triggers their atomic, self-cleaning patch.
