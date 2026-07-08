# RustTop Tahoe Bridge Architecture

This document records the long-term bridge decision for the native macOS Tahoe
app. The current implementation prefers a persistent embedded Rust helper
started with `--stream-json --interval-ms <ms>`. The helper emits one compact
`schema_version: 1` snapshot per stdout line and flushes each line, allowing the
Swift provider to keep one process alive across refreshes. If the stream cannot
start, exits early, times out, or emits an incompatible payload, the app falls
back to the original one-shot `--export-json` path.

## Decision

The long-term Tahoe bridge should be a signed XPC service that owns the RustTop
collector lifecycle and streams typed snapshot updates back to the SwiftUI app.

The XPC service should eventually call the Rust collector through a small C ABI
or Swift-compatible FFI boundary after the collector is split into a reusable
Rust library. Until then, the app keeps the persistent JSON helper stream as the
transitional bridge, with one-shot JSON export retained as the development and
emergency fallback path.

## Why XPC

- It matches macOS app architecture better than a local loopback API.
- It avoids exposing a listening port for a local-only desktop monitor.
- It gives the collector a separate crash and logging boundary.
- It fits signed and sandboxed distribution better than ad hoc subprocess
  management.
- It keeps a clean ownership line: SwiftUI owns presentation, XPC owns bridge
  transport, Rust owns collection.
- It can later support lower update latency without forcing the app process to
  directly host all collector state.

## Options Considered

| Option                            | Decision         | Reason                                                                                                         |
| --------------------------------- | ---------------- | -------------------------------------------------------------------------------------------------------------- |
| Per-refresh helper subprocess     | Keep as fallback | Simple, already working, easy to smoke test; too much process churn for long-lived monitoring.                 |
| Persistent async subprocess       | Implemented      | Removes per-refresh launches now, but remains weaker than XPC for signing, lifecycle, and structured failures. |
| Rust FFI directly inside app      | Not first        | Lowest latency, but increases crash blast radius and couples SwiftUI directly to collector lifetime.           |
| XPC service plus Rust FFI         | Target           | Best balance of native macOS packaging, crash isolation, lower latency, and testability.                       |
| Unix domain socket                | Not target       | Useful internally, but XPC is the native equivalent with better tooling and identity.                          |
| Local loopback HTTP/WebSocket API | Not target       | Existing Rust API remains useful for explicit API mode; it should not be the default private app bridge.       |

## Migration Plan

1. Keep `RustTopSnapshotProvider` as the stable Swift protocol-shaped seam.
2. Add structured logging and latency measurement to the current helper bridge.
3. Add a persistent `--stream-json` helper mode as the transitional bridge.
4. Extract Rust collection and snapshot serialization into a reusable library
   crate boundary.
5. Add an XPC service target that hosts the collector and exposes snapshot
   requests plus a streaming update channel.
6. Gate XPC usage behind a provider implementation while preserving the helper
   provider as fallback.
7. Move sustained-run tests from helper subprocess refreshes to the XPC service.
8. Update signing, entitlements, and notarization checks to verify both the app
   and service.

## Acceptance Criteria

- The app can refresh without launching a new helper process for every sample.
- The bridge reports typed failures for missing service, timeout, bad payload,
  schema mismatch, permission/config problems, and collector crash.
- The service and app are signed together and pass `codesign --verify --deep`.
- A 30-minute refresh run shows bounded memory and stable latency.
- The helper JSON path remains available for development and emergency fallback
  until XPC has equivalent coverage.
