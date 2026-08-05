# PocketKernel Local Linux Runtime

## Source

- Upstream: `https://github.com/dnakov/litter-ish.git`
- Pinned review commit: `c8e9dcb954963b0d9f359b3ad9da871f19b28652`
- Runtime: ARM64 Linux guest on iOS using iSH's Asbestos threaded-code interpreter
- JIT: not required; no `MAP_JIT`, RWX memory, or runtime code generation
- Embedding layer: `embed/` Rust host crate plus stable C FFI

## Why this changes PocketKernel

PocketKernel currently plans native and connected-service actions. The local Linux runtime adds a real execution plane for approved command-line work:

1. Boot an Alpine ARM64 fakefs inside the app sandbox.
2. Spawn an isolated guest process for each approved task.
3. Stream stdout and stderr into the Chat transcript.
4. Accept stdin, resize PTYs, send signals, and terminate process groups.
5. Persist only user-approved workspace files under PocketKernel's container.

This turns Chat into an agent console backed by real processes instead of status-only UI.

## Product boundaries

- Work remains the status and quick-action dashboard.
- Chat owns conversation, plans, approvals, command output, and cancellation.
- A command never starts from model output alone. The user receives an approval card containing argv, working directory, environment additions, network requirement, writable paths, and timeout.
- The guest cannot access arbitrary iOS files. Imports are copied into a dedicated workspace after an explicit document-picker action.
- Secrets are injected per process and are not written into shell history or the guest filesystem.
- Background execution is bounded by normal iOS lifecycle limits. The app never claims a process continued when iOS suspended or terminated it.

## Integration phases

### 1. Build lane

- Add `litter-ish` as a pinned source dependency.
- Build `ish-embed-host` and the static AArch64 supervisor on the macOS GitHub runner.
- Build a minimal Alpine ARM64 rootfs with `sh`, `busybox`, `git`, `curl`, `python3`, `node`, and CA certificates.
- Package the runtime library and compressed rootfs into the IPA.
- Add CI smoke tests for boot, `echo`, exit status, stdin, cancellation, and concurrent sessions.

### 2. Swift bridge

Expose a Swift concurrency API:

```swift
protocol LocalRuntime {
    func boot() async throws
    func spawn(_ request: RuntimeRequest) async throws -> RuntimeSession
    func write(_ bytes: Data, to sessionID: UUID) async throws
    func signal(_ signal: Int32, sessionID: UUID) async throws
    func terminate(sessionID: UUID) async
}
```

The bridge must surface lifecycle state and actual exit information. It must never synthesize successful output.

### 3. Chat execution

Add a new proposal kind for local commands. The approval card must show:

- executable and arguments
- working directory
- readable and writable mounts
- network access
- environment keys, with secret values redacted
- timeout

After approval, output chunks append live to the Chat timeline. Cancel sends termination to the complete guest process group.

### 4. Agent workspace

The on-device model may plan file and command steps, but execution remains constrained by typed tools. A bounded loop can inspect output, request a follow-up command, and stop on success, failure, timeout, cancellation, or a step limit.

## Licensing

`litter-ish` is GPL-licensed and carries the iSH App Store permission in `LICENSE.IOS`. A distributed PocketKernel build that links this runtime must comply with the GPL in all other respects, including publishing corresponding source and license text. PocketKernel's repository and release artifacts must preserve upstream attribution and the exact source revision used for each binary.

## Definition of real

The runtime is considered integrated only when the device build passes all of these checks:

- boots the bundled rootfs on a physical ARM64 iPhone
- executes `/bin/sh -lc 'printf pocketkernel'`
- streams the exact bytes to Chat
- returns the real process exit code
- cancels a long-running process and its children
- survives a second clean launch without rebuilding the rootfs
- shows a truthful interrupted state after app suspension or termination
