# RustTop Tahoe Native Shell

RustTop Tahoe is the first native macOS shell for RustTop. It keeps the Rust
collector as the source of truth and presents the data through a SwiftUI/AppKit
interface that targets macOS 26 and the Liquid Glass design system.

## Current Architecture

- `macos/RustTopTahoe` is a Swift Package executable for the native app shell.
- Tahoe v1 remains a separate product bundle named `RustTopTahoe.app` with the
  bundle identifier `io.github.sudoshi.RustTopTahoe`. It does not replace the
  existing Rust/iced macOS `RustTop.app` identity during this implementation
  phase.
- The shell decodes RustTop's existing `--export-json` snapshot schema.
- The Swift bridge has fixture-backed tests for valid, partial, and incompatible
  schema v1 snapshots plus provider path resolution.
- The current helper bridge measures refresh latency, writes structured OSLog
  events for snapshot and artifact workflows, and classifies failures as missing
  helper, timeout, process failure, bad JSON, schema mismatch, permissions
  issue, collector panic, or destination/configuration errors.
- The Rust helper exports optional macOS memory pressure fields from `vm_stat`
  and optional battery health/cycle/power fields from `AppleSmartBattery`
  `ioreg` output when the hardware exposes them.
- The Rust helper filters duplicate APFS system companion volumes from summary
  disk rows and exports per-interface network rates/counters in snapshot JSON.
- `scripts/build-macos-tahoe.sh` builds the Rust helper, builds the SwiftUI app,
  embeds the helper in `RustTopTahoe.app/Contents/Resources/rust_top`, generates
  the app icon, assembles a macOS 26 app bundle, and can optionally create
  versioned release archives.
- The provider can also use `RUSTTOP_BINARY=/path/to/rust_top` during local
  development.

This keeps the first native slice intentionally small: SwiftUI owns the Tahoe UI
and Rust owns metric collection.

## Build

```bash
./scripts/build-macos-tahoe.sh
open RustTopTahoe.app
```

The script keeps local builds single-architecture by default. To build Intel
and Apple Silicon slices and combine the helper and app binaries with `lipo`:

```bash
RUSTTOP_TAHOE_ARCHS=universal ./scripts/build-macos-tahoe.sh
```

For development without assembling an app bundle:

```bash
cargo build --release
cd macos/RustTopTahoe
RUSTTOP_BINARY=../../target/release/rust_top swift run
```

## QA/Audit Harness

`scripts/qa-macos-tahoe.sh` is a lightweight evidence harness for the current
Tahoe quality gates. It builds or reuses `RustTopTahoe.app`, records static
bundle/helper evidence, runs the embedded helper through repeated JSON snapshot
refreshes, and, when the local macOS GUI environment permits it, launches the
app, resizes the main window, captures screenshots, and samples accessibility
metadata.

Default local audit:

```bash
./scripts/qa-macos-tahoe.sh
```

Headless or CI-style helper smoke with no GUI work:

```bash
./scripts/qa-macos-tahoe.sh --no-gui

# Reuse an already-built bundle:
./scripts/qa-macos-tahoe.sh --no-build --no-gui
```

Static visual/accessibility source guardrail audit:

```bash
./scripts/audit-macos-tahoe-static.sh
```

The static audit writes `checks.tsv` and `metrics.tsv` under
`dist/tahoe-static-audit/<timestamp>`. It verifies source-level guardrails such
as minimum window sizing, target screenshot sizes, Accessibility preflight
coverage, VoiceOver labels/values, reduced-motion handling, high-contrast hooks,
and theme application. It is designed for clean CI runners, but it does not
replace manual screenshot review, Accessibility Inspector, VoiceOver review, or
Instruments.

Thirty-minute helper refresh smoke:

```bash
RUSTTOP_TAHOE_SMOKE_SECONDS=1800 ./scripts/qa-macos-tahoe.sh --no-gui
```

Persistent helper stream smoke with process resource samples:

```bash
./scripts/qa-macos-tahoe.sh \
  --no-build \
  --no-gui \
  --stream-seconds 300 \
  --stream-sample-interval 5

# Thirty-minute stream evidence:
RUSTTOP_TAHOE_STREAM_SECONDS=1800 \
  RUSTTOP_TAHOE_STREAM_SAMPLE_INTERVAL_SECONDS=5 \
  ./scripts/qa-macos-tahoe.sh --no-build --no-gui
```

The stream evidence writes `helper-stream/snapshots.jsonl` and
`helper-stream/process-samples.csv`. It verifies the embedded helper can keep
the JSONL bridge alive and gives a lightweight RSS/CPU trail for review. It is
not a substitute for Instruments or a full app live-refresh memory pass.

Screenshot audit only when a desktop session, Accessibility permission, and
Screen Recording permission are available:

```bash
./scripts/qa-macos-tahoe.sh --no-build --strict-gui
```

Strict GUI mode now records `gui-environment.txt` and
`accessibility-preflight.txt` before launch. If
`System Events` reports `UI elements enabled=false`, the harness fails before
opening the app because AppleScript cannot resize windows or sample
accessibility metadata from that session. During GUI QA the harness temporarily
forces the main window launch defaults and restores the previous defaults on
exit; set `RUSTTOP_TAHOE_QA_FORCE_MAIN_WINDOW=0` to disable that override.
Set `RUSTTOP_TAHOE_QA_OPEN_FRESH=0` to use plain `open` instead of `open -F`.

The default screenshot sizes are `980x680`, `1280x820`, and `1728x1117`. The
first two match the implementation plan's explicit visual QA targets; the wide
desktop size is configurable:

```bash
RUSTTOP_TAHOE_WINDOW_SIZES="980x680 1280x820 1920x1080" \
  ./scripts/qa-macos-tahoe.sh --no-build
```

QA artifacts are written under `dist/tahoe-qa/<timestamp>` by default. The
summary, logs, helper-smoke CSV, optional helper-stream JSONL/resource CSV,
bundle evidence, window evidence, screenshots, and accessibility element sample
are audit inputs only. Static audit artifacts are written under
`dist/tahoe-static-audit/<timestamp>`. Release validation evidence is also
collected by default under `release-validation/`. Missing Developer ID
signatures, notary credentials, DMG paths, staples, or GUI launch access are
recorded as `not-ready` or `skipped` instead of a release pass.

Release candidate gate with a packaged DMG:

```bash
./scripts/qa-macos-tahoe.sh \
  --no-build \
  --strict-release \
  --dmg dist/RustTopTahoe-<version>-macos.dmg
```

Use `--no-release-validation` only for development loops where signing and
notarization evidence is not relevant. The full signed/notarized evidence
runbook lives in
[docs/macos-tahoe-release-validation.md](macos-tahoe-release-validation.md).

## CI

`.github/workflows/macos-tahoe.yml` covers the native app path on
`macos-latest`:

- Builds the Swift package with `swift build --package-path macos/RustTopTahoe`.
- Runs `swift test` only when Swift test sources exist.
- Runs the static Tahoe visual/accessibility source audit.
- Runs `cargo check --locked` and `cargo test --locked`.
- Builds `RustTopTahoe.app` with `scripts/build-macos-tahoe.sh` on pushes and
  manual workflow runs.
- Validates the bundle plist and runs the embedded helper's `--export-json`
  path when the bundle build runs.
- Runs the no-GUI QA helper refresh and persistent stream smoke when the bundle
  build runs.
- Uses `scripts/build-macos-tahoe.sh` to create versioned zip and DMG artifacts
  on tag builds, verifies their SHA-256 sidecars, and uploads `dist/`.

## Release, Signing, and Notarization

The local build script produces an unsigned development bundle by default. That
is useful for iteration. When a signing identity is provided, the same script
signs the embedded helper and the app bundle with hardened runtime enabled.
Release packaging, notarization, and stapling are all opt-in so local builds do
not require Developer ID certificates or Apple notary credentials.

The Tahoe entitlement file is
`macos/RustTopTahoe/Packaging/RustTopTahoe.entitlements`. It intentionally has
an empty entitlement dictionary because the current app/helper design does not
need the app sandbox, JIT, Apple Events, network client/server, file-provider,
or private security exceptions. The app launches the bundled `rust_top` helper
as nested signed code and reads the helper's temporary JSON snapshot output.

The intended release shape is:

1. Build the app bundle.
2. Sign nested code first, including `Contents/Resources/rust_top`.
3. Sign the outer `.app` with hardened runtime and a timestamp.
4. Verify the helper and app signatures locally.
5. Optionally submit the signed app to Apple's notary service.
6. Optionally staple the accepted ticket to the app bundle.
7. Create a versioned zip, DMG, or both.
8. Write SHA-256 sidecar checksums for packaged artifacts.
9. Optionally submit and staple the final DMG.
10. Verify Gatekeeper assessment on a clean Mac.

Unsigned local build:

```bash
unset RUSTTOP_TAHOE_SIGN_IDENTITY DEVELOPER_ID_APPLICATION
./scripts/build-macos-tahoe.sh
open RustTopTahoe.app
```

Signed local build:

```bash
export RUSTTOP_TAHOE_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
./scripts/build-macos-tahoe.sh
codesign --verify --deep --strict --verbose=2 RustTopTahoe.app
```

Versioned zip and DMG packaging:

```bash
RUSTTOP_TAHOE_PACKAGE_ZIP=1 \
  RUSTTOP_TAHOE_PACKAGE_DMG=1 \
  ./scripts/build-macos-tahoe.sh
ls dist/RustTopTahoe-*-macos.*
```

Build environment variables:

- `RUSTTOP_TAHOE_ARCHS`: optional architecture selector. Unset, `local`,
  `native`, or `host` keeps the default local single-architecture build.
  `universal`, `all`, or `both` builds `x86_64` and `arm64` slices and combines
  them with `lipo`. Explicit lists such as `x86_64,arm64`, `intel`, or `arm64`
  are also accepted. Universal builds require the matching Rust standard library
  targets and a Swift toolchain that can build the requested macOS triples.

Signing environment variables:

- `RUSTTOP_TAHOE_SIGN_IDENTITY`: preferred Developer ID Application signing
  identity. When unset, the script falls back to `DEVELOPER_ID_APPLICATION` for
  compatibility with older local release shells.
- `RUSTTOP_TAHOE_ENTITLEMENTS`: optional entitlement plist override. Defaults to
  `macos/RustTopTahoe/Packaging/RustTopTahoe.entitlements`.
- `RUSTTOP_TAHOE_SIGN_KEYCHAIN`: optional keychain name or path passed to
  `codesign --keychain` after importing the Developer ID certificate.

Packaging environment variables:

- `RUSTTOP_TAHOE_PACKAGE_ZIP=1`: create
  `dist/RustTopTahoe-<Cargo.toml version>-macos.zip`.
- `RUSTTOP_TAHOE_PACKAGE_DMG=1`: create
  `dist/RustTopTahoe-<Cargo.toml version>-macos.dmg` with the app and an
  `/Applications` symlink.
- `RUSTTOP_TAHOE_DIST_DIR`: optional output directory. Defaults to `dist`.
- `RUSTTOP_TAHOE_PACKAGE_BASENAME`: optional artifact basename override.
- Packaged artifacts always receive adjacent `.sha256` files.

Notarization is intentionally not automatic. Submit and staple only when a
Developer ID signing identity and notary credentials are explicitly present:

```bash
export RUSTTOP_TAHOE_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
export RUSTTOP_TAHOE_NOTARY_PROFILE="rusttop-tahoe"

RUSTTOP_TAHOE_NOTARIZE=1 \
  RUSTTOP_TAHOE_STAPLE=1 \
  RUSTTOP_TAHOE_PACKAGE_ZIP=1 \
  RUSTTOP_TAHOE_PACKAGE_DMG=1 \
  ./scripts/build-macos-tahoe.sh
spctl --assess --type execute --verbose=4 RustTopTahoe.app
```

Notary credentials can come from `RUSTTOP_TAHOE_NOTARY_PROFILE` or from
`RUSTTOP_TAHOE_NOTARY_APPLE_ID`, `RUSTTOP_TAHOE_NOTARY_TEAM_ID`, and
`RUSTTOP_TAHOE_NOTARY_PASSWORD`. The script also accepts `APPLE_ID`,
`APPLE_TEAM_ID`, and `APPLE_APP_SPECIFIC_PASSWORD` for compatibility with common
release shells.

When `RUSTTOP_TAHOE_NOTARIZE=1` is set, the script submits a temporary zip of
the signed app bundle. When `RUSTTOP_TAHOE_STAPLE=1` is also set, it staples and
validates the app before creating final archives. If DMG packaging is enabled,
the final DMG is also submitted and stapled before its checksum is written.

After producing signed artifacts, collect release evidence with:

```bash
./scripts/qa-macos-tahoe.sh \
  --no-build \
  --strict-release \
  --dmg dist/RustTopTahoe-<version>-macos.dmg
```

The release validation runbook lists the exact codesign, Gatekeeper, stapler,
DMG, signed-launch, and clean-machine install checks:
[docs/macos-tahoe-release-validation.md](macos-tahoe-release-validation.md).

CI signing should import a Developer ID Application certificate into a temporary
keychain, set `RUSTTOP_TAHOE_SIGN_IDENTITY`, optionally set
`RUSTTOP_TAHOE_SIGN_KEYCHAIN`, and pass notary credentials through repository
secrets. The current workflow intentionally does not require those secrets; tag
artifacts remain unsigned unless the signing environment is provided.

## Troubleshooting

- If `RUSTTOP_TAHOE_ARCHS=universal` fails before building, install the missing
  Rust target standard library and rerun the build.
- If the app opens in Preview mode, run
  `RustTopTahoe.app/Contents/Resources/rust_top --export-json /tmp/rusttop.json`
  to confirm the embedded helper can write a snapshot.
- If a helper override fails, clear the override in Settings or choose an
  executable `rust_top` binary.
- If screenshot or accessibility QA is skipped, rerun
  `scripts/qa-macos-tahoe.sh --strict-gui` inside a logged-in macOS desktop
  session after granting Screen Recording and Accessibility permissions.
  `accessibility-preflight.txt` must contain `true`; if it contains `false`,
  grant Accessibility permission to the terminal/Codex host process and rerun.
- If notarization or stapling fails, verify that Developer ID signing succeeded
  first with `codesign --verify --deep --strict --verbose=2 RustTopTahoe.app`.

## Implementation Plan

The detailed execution checklist lives in
[docs/plans/MACOS-TAHOE-IMPLEMENTATION-PLAN.md](plans/MACOS-TAHOE-IMPLEMENTATION-PLAN.md).
It tracks completed goals, remaining phases, acceptance criteria, and validation
commands for the native macOS Tahoe app.

The long-term bridge decision is documented in
[docs/macos-tahoe-bridge.md](macos-tahoe-bridge.md). The target architecture is
a signed XPC service that hosts the Rust collector lifecycle, with the current
JSON helper bridge retained as the fallback and development path.

The next macOS telemetry boundaries are documented in
[docs/macos-tahoe-telemetry.md](macos-tahoe-telemetry.md). That document covers
Apple Silicon GPU strategy, energy-pressure approximation, thermal/fan safety
boundaries, Wi-Fi metadata privacy, launchd scope, and missing-telemetry UI
states.

Tahoe settings and config migration are documented in
[docs/macos-tahoe-settings.md](macos-tahoe-settings.md). Tahoe v1 stores native
preferences in `UserDefaults` and leaves existing RustTop TOML files read-only.

Update and distribution strategy is documented in
[docs/macos-tahoe-updates.md](macos-tahoe-updates.md). Tahoe v1 keeps updates
manual until Developer ID signing, notarization, stapling, and clean-Mac launch
are proven.

## Design Direction

- Native `NavigationSplitView` structure with Overview, Processes, Storage, and
  Sensors sections.
- Floating toolbar controls using macOS 26 glass button styles.
- AppKit-backed `NSGlassEffectView` panels for high-value dashboard surfaces.
- System symbols, dynamic materials, monospaced metric values, and adaptive
  pressure colors.
- Preview fallback when the helper is unavailable, so the UI remains inspectable
  while the bridge is being developed.
- Process search, CPU/memory/PID/name sorting, a selected-process inspector, and
  copy-to-clipboard actions.
- Native Settings backed by `UserDefaults` for refresh interval, helper path,
  panel visibility, startup preference, and menu-bar modules.
- A configurable `MenuBarExtra` with compact CPU, memory, network, active-alert,
  and optional GPU/temperature status.
- File-menu commands for JSON snapshot export, CSV snapshot export, and incident
  bundle generation through the embedded helper.
- Guarded process termination through a native confirmation dialog.
- Active alert details and optional Notification Center delivery for sustained
  alerts.
- Dashboard density, startup behavior, and menu-bar module settings persisted
  through `UserDefaults`.
- Native CPU and memory alert thresholds with sustained-alert gating.
- Optional live Dock tile graph with CPU and memory trend lines plus alert
  badging.
- A read-only Services section for launchd agents and daemons discovered from
  standard plist locations.
- Accessibility labels, values, hints, reduced-motion behavior, and
  high-contrast readability adjustments across the primary native surfaces.

## Next Implementation Steps

- Replace the transitional persistent JSON helper stream with a signed XPC/FFI
  bridge.
- Extend alert routing preferences beyond local threshold and Notification
  Center delivery.
- Validate universal Intel and Apple Silicon release builds on a toolchain with
  both Rust target standard libraries installed.
- Verify notarized zip and DMG artifacts on a clean Mac.
