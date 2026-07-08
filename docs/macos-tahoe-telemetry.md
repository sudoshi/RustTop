# RustTop Tahoe macOS Telemetry Strategy

This document records the next native macOS collector boundaries for the Tahoe
app. It separates public, supportable system APIs from private or privileged
paths that RustTop should avoid unless the user explicitly installs a separate
helper in a future product decision.

## Apple Silicon GPU

Current status: partial.

RustTop already surfaces GPU fields when the Rust helper can read
IOAccelerator and display data. The next Apple Silicon strategy is:

1. Keep the existing IOAccelerator/system-profiler path as best-effort input.
2. Add fixture-backed parsers for Apple Silicon examples that expose utilization,
   VRAM/shared-memory, temperature, and power-like fields.
3. Treat missing GPU fields as expected on some OS/hardware combinations.
4. Avoid private frameworks and kernel extensions.
5. Prefer a future signed XPC collector boundary before adding any more
   expensive polling.

Acceptance for implementation is a documented fixture set for at least one
Apple Silicon laptop and one Apple Silicon desktop, plus UI empty states that
explain when fields are unavailable.

## Energy Impact

Current status: documented approximation.

Activity Monitor's Energy Impact is not a stable public formula RustTop can
claim to reproduce. Tahoe should present an explicitly named approximation when
implemented, such as `Energy Pressure`, based on process CPU, wakeups if
available through a supportable source, GPU contribution if present, and recent
runtime trend. It must not be labeled `Energy Impact` unless it matches Apple's
semantics.

The first implementation should:

1. Add no privileged helper.
2. Use only local process metrics RustTop already collects, plus public
   macOS-safe additions when available.
3. Mark the value as an approximation in UI accessibility text and export docs.
4. Keep the raw inputs visible or exportable so users can understand the score.

## Thermal And Fan Boundaries

Current status: partial.

RustTop can show sensor temperatures when `sysinfo` exposes them. For native
macOS behavior, Tahoe should also watch the public `ProcessInfo.thermalState`
surface and reduce refresh cadence or visual work when the system reaches
elevated thermal states.

Fan speed, fan control, voltage rails, and SMC-style hardware details are not a
Tahoe v1 target. They can require private or fragile interfaces and should stay
out of the default app unless a future privileged-helper design is approved.

## Wi-Fi Metadata

Current status: intentionally unavailable.

CoreWLAN is the supportable macOS framework for Wi-Fi interface metadata. If
RustTop adds Wi-Fi cards, the first pass should be opt-in and limited to local
interface facts such as link rate, RSSI/noise, channel, PHY mode, and security
where permitted. SSID/BSSID display should be user-configurable because it can
reveal location or workplace context.

RustTop should not collect nearby-network scan results by default.

## launchd Services And Agents

Current status: read-only Tahoe inventory.

The Rust helper inventories standard launchd plist locations and exports
`launchd_jobs` with label, domain, kind, source path, and read-only installed
state. The native Tahoe app surfaces these rows in a Services section for
search and inspection.

The first version intentionally does not call `launchctl`, enable, disable,
unload, bootout, or bootstrap jobs. Any future launchd actions need a separate
confirmation model, clear privilege failure states, and a release-signing audit.

## Missing Telemetry UX

Every unavailable macOS telemetry card should explain one of these states:

- `not_applicable`: expected for hardware such as desktops without batteries.
- `not_exposed`: the hardware or OS does not expose a public field.
- `permission_limited`: the user or system denied access.
- `not_implemented`: RustTop has not added a supportable collector yet.

The UI should prefer compact inline empty states over blank panels.
