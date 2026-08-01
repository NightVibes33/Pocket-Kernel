# PocketKernel

PocketKernel is an iOS 26 SwiftUI host for safe, declarative micro-apps. A `.pocketapp` is data, never executable code. The host validates a bounded manifest, renders known native components, executes typed actions, and keeps generated apps inside PocketKernel's sandbox.

## Build

Use **Actions → Build PocketKernel Unsigned IPA → Run workflow**. The one workflow lints, tests against a dynamically selected iOS 26 simulator, builds an ARM64 device app, validates the unsigned IPA, uploads diagnostics, and can publish a release.

The Intel runner compiles the Foundation Models integration but uses `MockBlueprintGenerator` in tests. A signed build tests `SystemLanguageModel` on a supported real device. If Apple Intelligence is unavailable, the app falls back to deterministic templates.

## Security boundary

PocketKernel executes no JavaScript, WebAssembly, dylibs, native downloads, or JIT code. Packages declare capabilities and allowed HTTPS domains. Import validation rejects bad hashes, unsupported kinds, broken references, traversal strings, excessive nesting, and oversized assets.

