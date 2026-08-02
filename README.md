# PocketKernel 1.0

PocketKernel is a native iOS/iPadOS 26 host for creating, validating, installing, and running multiple declarative `.pocketapp` micro-apps. Packages contain typed screens, components, actions, collections, permissions, assets, and SHA-256 integrity metadata. They contain no Swift source, JavaScript, WebAssembly, native binaries, dylibs, JIT payloads, or private API calls.

## Product flow

1. Describe an app.
2. Foundation Models generates a bounded multi-screen blueprint on device.
3. PocketKernel repairs identifiers and references deterministically.
4. The complete manifest is validated.
5. The user previews or edits the blueprint.
6. The approved app is installed into PocketKernel.
7. Its records, state, assets, permissions, and activity remain isolated locally.

When Apple Intelligence is unavailable, the manual blueprint editor, deterministic template generator, package import, and five complete built-in apps remain available.

## Build

The production workflow is designed to be manual through `workflow_dispatch`. It pins Xcode 26.5 on `macos-26-intel`, uses the deterministic model in tests, runs the complete source/test/package gates, builds an unsigned ARM64 device app, validates the IPA, and publishes diagnostics. The Intel runner compiles Foundation Models but does not execute the real system language model.

The output `PocketKernel-unsigned.ipa` must be signed before installation.

## Security boundary

- Known native SwiftUI components only.
- Bounded expression parser with no loops, recursion, reflection, or filesystem access.
- Typed action engine with bounded sequential chains and session undo.
- Exact HTTPS domain allowlists, redirect revalidation, ephemeral sessions, 15-second timeouts, and 1 MB responses.
- Per-app permission decisions and activity logs.
- Single-JSON `.pocketapp` packages with SHA-256 manifest and asset validation.
