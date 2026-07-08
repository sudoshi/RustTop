# RustTop macOS Tahoe Implementation Plan

This plan tracks the native macOS Tahoe edition of RustTop. It is intentionally
implementation-facing: every completed goal is checked off, and every remaining
goal has an acceptance target that can be validated in the repo.

## Product Target

Build a premium macOS 26 system monitor that feels native to Tahoe while keeping
RustTop's Rust telemetry engine as the trustworthy collection core.

The end state is not an `iced` theme. It is a native SwiftUI/AppKit Mac app with
Liquid Glass materials, platform-standard navigation, menu-bar monitoring,
macOS-specific telemetry, signed distribution, and a path toward a lower-latency
Rust bridge.

## Current Status

- [x] Created a native macOS shell at `macos/RustTopTahoe`.
- [x] Targeted Swift 6.2 and macOS 26 in `macos/RustTopTahoe/Package.swift`.
- [x] Added a SwiftUI app entrypoint with a hidden-title-bar Mac window.
- [x] Added a `NavigationSplitView` structure with Overview, Processes, Storage,
      and Sensors sections.
- [x] Added toolbar controls using macOS 26 glass button styles.
- [x] Added process search, CPU/memory/PID/name sorting, selected-process
      inspector, copy action, and dashboard keyboard commands.
- [x] Added native JSON snapshot export, CSV snapshot export, and incident
      bundle commands through the embedded Rust helper.
- [x] Added native Settings backed by `UserDefaults` for refresh interval,
      helper override, startup preference, panel visibility toggles, and
      menu-bar module preferences.
- [x] Wired panel visibility settings into native sidebar section availability.
- [x] Added a configurable `MenuBarExtra` with compact CPU, memory, and network
      monitoring.
- [x] Added accessibility labels, values, hints, reduced-motion handling, and
      high-contrast readability adjustments across the main Tahoe surfaces.
- [x] Added an AppKit-backed `NSGlassEffectView` wrapper for custom glass panels.
- [x] Added Tahoe-oriented dashboard visuals: metric cards, pressure rings,
      sparklines, process rows, storage cards, sensor/GPU/battery cards, system
      symbols, monospaced values, and adaptive pressure colors.
- [x] Added Swift models for RustTop's current `schema_version = 1`
      `--export-json` snapshot.
- [x] Added Swift schema compatibility checks and fixture-backed tests for
      valid, partial, and incompatible snapshots.
- [x] Added a replaceable snapshot provider that can find an embedded helper,
      `RUSTTOP_BINARY`, or local `target` binaries.
- [x] Added Swift tests for provider path resolution.
- [x] Added live refresh, pause/resume, manual refresh, preview fallback, and
      error surfacing in `DashboardModel`.
- [x] Added macOS `vm_stat` memory pressure/app/wired/compressed/file-cache
      export fields.
- [x] Added macOS `AppleSmartBattery` capacity, health, cycle count, power
      source, and adapter-watt export fields.
- [x] Added APFS system companion volume filtering and per-interface network
      rows to exported snapshots.
- [x] Added `scripts/build-macos-tahoe.sh` to build the Rust helper, build the
      Swift shell, embed `rust_top`, generate `.icns`, and assemble
      `RustTopTahoe.app`.
- [x] Added least-privilege Developer ID entitlements at
      `macos/RustTopTahoe/Packaging/RustTopTahoe.entitlements`.
- [x] Added optional hardened-runtime Developer ID signing to
      `scripts/build-macos-tahoe.sh` for the embedded helper and app bundle when
      signing environment variables are provided.
- [x] Added opt-in versioned zip and DMG packaging to
      `scripts/build-macos-tahoe.sh`, with SHA-256 sidecar checksums for
      packaged artifacts.
- [x] Added explicit-env notarization and stapling hooks to
      `scripts/build-macos-tahoe.sh` without requiring notary credentials for
      unsigned local builds.
- [x] Documented the long-term bridge target in `docs/macos-tahoe-bridge.md`:
      a signed XPC service hosting the Rust collector lifecycle, with the JSON
      helper retained as fallback.
- [x] Added bridge refresh latency measurement, structured OSLog events, and
      typed bridge failure states for missing helper, timeout, process failure,
      bad JSON, schema mismatch, permissions issue, collector panic, and
      configuration/destination errors.
- [x] Added guarded selected-process TERM actions with native confirmation and
      visible success/failure status.
- [x] Added active alert details and optional Notification Center delivery for
      sustained alerts.
- [x] Added native CPU and memory alert threshold settings with sustained-alert
      gating and merged alert presentation across the dashboard and menu bar.
- [x] Added dashboard density controls, startup behavior handling, and optional
      menu-bar GPU/temperature monitoring.
- [x] Added restore-previous startup behavior persistence with Swift tests.
- [x] Added retained metric history buffers for CPU, memory, network in/out,
      GPU utilization, disk read/write, and thermal samples.
- [x] Added persisted system/light/dark theme and accent settings that respect
      SwiftUI system appearance and contrast behavior.
- [x] Added compact missing-telemetry cards for GPU, thermal sensor, and battery
      states that are not applicable or not exposed.
- [x] Added `scripts/qa-macos-tahoe.sh` for helper refresh smoke, optional
      screenshot capture, optional accessibility evidence, and extensible
      sustained-run evidence collection.
- [x] Added release-validation evidence scaffolding to
      `scripts/qa-macos-tahoe.sh` plus
      `docs/macos-tahoe-release-validation.md` for codesign, Gatekeeper,
      stapling, DMG, signed-launch, and clean-machine install checks.
- [x] Added release validation checks for package checksum sidecars and signed
      embedded-helper schema-v1 export.
- [x] Added persistent embedded-helper JSONL streaming with
      `--stream-json --interval-ms`, plus Swift provider fallback to the
      original one-shot `--export-json` path.
- [x] Bounded the Swift streaming bridge backlog to the newest complete
      snapshot so helper output cannot accumulate unbounded stale JSON lines.
- [x] Added optional QA evidence for persistent embedded-helper streaming:
      JSONL snapshot capture plus process RSS/CPU samples.
- [x] Added `scripts/audit-macos-tahoe-static.sh` for source-level Tahoe
      visual/accessibility guardrails that can run without GUI permissions.
- [x] Added a read-only launchd Services section backed by `launchd_jobs`
      exported from standard plist locations.
- [x] Added `RUSTTOP_TAHOE_ARCHS` support for local, explicit Intel, explicit
      Apple Silicon, and universal Tahoe bundle builds with `lipo` architecture
      verification.
- [x] Validated the default Tahoe build and explicit
      `RUSTTOP_TAHOE_ARCHS=x86_64` build on the current Intel host. Universal
      validation is gated on installing the missing `aarch64-apple-darwin` Rust
      standard library in this toolchain.
- [x] Added `docs/macos-tahoe.md` and linked the Tahoe shell from `README.md`.
- [x] Added `.github/workflows/macos-tahoe.yml` for Swift package builds,
      conditional Swift tests, Rust checks/tests, bundle smoke validation, and
      tag artifact upload.
- [x] Added static Tahoe visual/accessibility audit and no-GUI Tahoe QA smoke
      steps to `.github/workflows/macos-tahoe.yml`.
- [x] Extended Tahoe app bundle smoke and no-GUI QA workflow gates to pull
      requests as well as pushes/manual runs.
- [x] Switched tag artifact packaging in `.github/workflows/macos-tahoe.yml` to
      the Tahoe build script's versioned zip/DMG path with checksum validation.
- [x] Documented current macOS Tahoe collector status, privacy notes, release
      signing, and notarization guidance.
- [x] Added `.gitignore` coverage for Swift package build products.
- [x] Built `RustTopTahoe.app` locally.
- [x] Validated the app bundle plist with `plutil`.
- [x] Validated the embedded helper can export a real JSON snapshot.
- [x] Ran `swift build --package-path macos/RustTopTahoe`.
- [x] Ran `swift test --package-path macos/RustTopTahoe`; 34 tests passed.
- [x] Ran `swift build -c release --package-path macos/RustTopTahoe`.
- [x] Ran `cargo check --locked`.
- [x] Ran `cargo test --locked`; 63 tests passed.
- [x] Validated `target/debug/rust_top --stream-json --interval-ms 250`
      produces schema-versioned JSONL.
- [x] Ran `bash -n scripts/build-macos-tahoe.sh`.
- [x] Ran `bash -n scripts/qa-macos-tahoe.sh`.
- [x] Ran `bash -n scripts/audit-macos-tahoe-static.sh`.
- [x] Ran
      `plutil -lint macos/RustTopTahoe/Packaging/RustTopTahoe.entitlements`.
- [x] Ran `git diff --check`.
- [x] Ran
      `npx prettier --check` across the new Tahoe docs and implementation
      plan.
- [x] Validated embedded helper CSV export and incident bundle output.
- [x] Ran `scripts/qa-macos-tahoe.sh --no-build --no-gui` with helper refresh
      smoke and persistent stream smoke evidence.
- [x] Ran `scripts/audit-macos-tahoe-static.sh` and archived source-level
      visual/accessibility guardrail evidence.
- [x] Ran the filtered Swift streaming bridge tests; 5 passed, including
      stale-backlog prevention.
- [x] Ran release QA against the local unsigned DMG; checksum sidecars and DMG
      readability passed, while signing/notarization checks correctly remained
      `not-ready`.
- [x] Ran strict GUI preflight; the harness now records Accessibility status
      and fails before launch when the current session lacks control.
- [x] Fixed a local first-launch hang caused by SwiftUI no-op publish loops and
      heavy menu-bar snapshot copying: startup/dialog/sidebar/menu bindings now
      ignore same-value writes, first live refresh is deferred until after the
      initial frame, and the menu-bar label stores lightweight metrics instead
      of the full `launchd_jobs` snapshot.
- [x] Rebuilt and relaunched the patched `RustTopTahoe.app`; the app and
      streaming helper stayed alive, the SwiftUI "Publishing changes from within
      view updates" warning did not recur in the fresh launch window, and a
      live sample no longer showed `MenuBarMonitorLabel` copying
      `LaunchdJobSnapshot` rows.

## Architecture Decisions

- [x] Keep the current Rust collector as the source of truth.
- [x] Start with RustTop's existing JSON snapshot export instead of beginning
      with a risky FFI refactor.
- [x] Keep the native app in `macos/RustTopTahoe` so the cross-platform Rust app
      remains intact.
- [x] Use real macOS 26 glass APIs where available: SwiftUI glass button styles
      for toolbar controls and AppKit `NSGlassEffectView` for custom panels.
- [x] Make the data provider replaceable so JSON helper execution can later be
      swapped for FFI, XPC, or a streaming IPC bridge.
- [x] Decide whether the long-term data bridge should be Rust FFI, XPC service,
      local loopback API, Unix domain socket, or embedded async subprocess. The
      target is a signed XPC service with a Rust FFI-backed collector boundary;
      see `docs/macos-tahoe-bridge.md`.
- [x] Decide whether the Tahoe app remains a separate product bundle
      `RustTopTahoe.app` or eventually replaces the current macOS `RustTop.app`.
      Tahoe v1 remains a separate bundle and identity.

## Phase 0: Repo Integration Baseline

Goal: keep the first native slice easy to build, review, and revert if needed.

- [x] Add Swift package manifest.
- [x] Add app source under a single `macos/RustTopTahoe` boundary.
- [x] Keep generated `.build` products out of Git.
- [x] Keep the existing Rust app untouched except for docs/build integration.
- [x] Add a build script rather than requiring Xcode project generation.
- [x] Add a short docs page describing architecture and build commands.
- [x] Link the docs page from README.
- [x] Add a CI job for `swift build --package-path macos/RustTopTahoe` on
      `macos-latest`.
- [x] Add a CI job that runs `scripts/build-macos-tahoe.sh` on tagged macOS
      release builds.
- [x] Add a lightweight smoke test that launches the helper export path and
      decodes the snapshot schema.

Acceptance:

- [x] `swift build --package-path macos/RustTopTahoe` succeeds.
- [x] `./scripts/build-macos-tahoe.sh` assembles `RustTopTahoe.app`.
- [x] `RustTopTahoe.app/Contents/Resources/rust_top --export-json <path>`
      writes a valid snapshot.
- [ ] CI proves the same gates on a clean macOS runner.

## Phase 1: Native Tahoe Shell

Goal: establish the Mac-native application frame and visual language.

- [x] Create a SwiftUI `@main` app entrypoint.
- [x] Use a hidden-title-bar window with a roomy default size.
- [x] Use `NavigationSplitView` for platform-native hierarchy.
- [x] Add top-level sections: Overview, Processes, Storage, Sensors.
- [x] Add a toolbar with live status, pause/resume, and refresh actions.
- [x] Use `.glass` and `.glassProminent` button styles for toolbar controls.
- [x] Add a Tahoe backdrop with depth and subtle motion-ready structure.
- [x] Build reusable glass panel surfaces with `NSGlassEffectView`.
- [x] Use SF Symbols for navigation, toolbar, and panel identity.
- [x] Use monospaced numeric values for metrics.
- [x] Use adaptive color semantics for healthy/warning/critical pressure.
- [x] Add keyboard shortcuts for section navigation.
- [x] Add search in the toolbar for processes, disks, and sensors.
- [x] Add an inspector column for selected process details.
- [x] Add native Settings scene.
- [x] Add accessibility labels, VoiceOver names, and reduced-motion checks.
- [ ] Add light/dark/high-contrast visual passes.
- [x] Add screenshot-based visual QA for default, small, and wide windows.

Acceptance:

- [x] The app presents a native sidebar and detail surface.
- [x] The app has real glass toolbar controls and glass dashboard panels.
- [x] The app remains inspectable using preview data when the helper is missing.
- [ ] Visual QA confirms no overlapping text at 980x680, 1280x820, and wide
      desktop sizes.
- [ ] Accessibility Inspector confirms meaningful labels for major controls and
      metric cards.

## Phase 2: Data Bridge Hardening

Goal: make the native app reliable enough for continuous live monitoring.

- [x] Decode RustTop `--export-json` snapshots.
- [x] Resolve helper path from app resources.
- [x] Support `RUSTTOP_BINARY` for development overrides.
- [x] Support local `target/release/rust_top` and `target/debug/rust_top`
      fallback paths.
- [x] Add subprocess timeout and stderr reporting.
- [x] Keep UI responsive by fetching snapshots off the main actor.
- [x] Maintain a short metric sample history for sparklines.
- [x] Add schema compatibility checks with user-facing messages for unknown
      versions.
- [x] Add unit tests for JSON decoding using a fixture.
- [x] Add sample fixtures under `macos/RustTopTahoe/Tests/RustTopTahoeTests/Fixtures`.
- [x] Add a `swift test` target for snapshot decoding and provider path logic.
- [x] Add retained history buffers for CPU, memory, network in/out, GPU, disk
      I/O, and thermal data.
- [x] Avoid launching a new helper process every refresh by implementing one of:
      FFI, XPC, Unix domain socket, persistent subprocess, or WebSocket API mode.
- [x] Define bridge failure states: missing helper, timeout, bad JSON, schema
      mismatch, permissions issue, collector panic.
- [x] Add structured logging through `OSLog`.

Acceptance:

- [x] The app can read live data from the embedded helper.
- [x] The helper bridge fails visibly instead of silently.
- [x] Bridge tests cover valid, partial, and incompatible snapshots.
- [ ] Live refresh can run for 30 minutes without growing memory unexpectedly.
- [x] Refresh latency is measured and documented.

## Phase 3: macOS Telemetry Depth

Goal: make RustTop feel hardware-aware on macOS instead of merely portable.

- [x] Reuse current Rust CPU, memory, disk, network, process, GPU, battery, and
      sensor snapshot fields.
- [x] Surface GPU temperature, power, utilization, and VRAM when available.
- [x] Surface disk read/write rates and capacity.
- [x] Surface battery cards when RustTop provides batteries.
- [x] Add macOS memory pressure and app/wired/compressed/cache breakdown.
- [x] Add power source, battery cycle count, battery health, and adapter details
      through `AppleSmartBattery` `ioreg` output.
- [x] Add Apple Silicon GPU telemetry strategy.
- [x] Add per-process energy impact or a documented approximation.
- [x] Add fan/thermal sensor support with safe API boundaries and limitations.
- [x] Add launchd services/agents view.
- [x] Add per-interface network rates and counters to JSON snapshots.
- [x] Add Wi-Fi metadata strategy where permitted.
- [x] Add APFS volume grouping to avoid duplicate root/Data presentation.
- [x] Add privacy notes for every macOS-specific collector.

Acceptance:

- [x] `docs/platform-support.md` documents each macOS collector as supported,
      partial, unsupported, or intentionally unavailable.
- [x] Apple Silicon and Intel Mac behavior are both tested or explicitly scoped.
- [x] The app explains missing telemetry without looking broken.

## Phase 4: Interaction Model

Goal: turn the shell from a dashboard into a productive Mac utility.

- [x] Add pause/resume.
- [x] Add manual refresh.
- [x] Add process table display.
- [x] Add storage display.
- [x] Add sensors/GPU/battery display.
- [x] Add process search and filter.
- [x] Add process sort controls.
- [x] Add process details inspector.
- [x] Add guarded process actions with native confirmation dialogs.
- [x] Add alert detail view.
- [x] Add export snapshot command.
- [x] Add incident bundle command.
- [x] Add copy-to-clipboard for selected metric/process rows.
- [x] Add dashboard layout density controls.
- [x] Add command menu entries for common actions.

Acceptance:

- [x] A user can find, inspect, and act on a process without touching the Rust
      `iced` UI.
- [x] Destructive actions require a native confirmation path.
- [x] Keyboard and menu commands cover core workflows.

## Phase 5: Menu Bar And Ambient Monitoring

Goal: deliver the Mac utility behavior users expect from iStat Menus and Stats.

- [x] Add a `MenuBarExtra`.
- [x] Add compact CPU monitor.
- [x] Add compact memory monitor.
- [x] Add compact network monitor.
- [x] Add optional GPU/temperature monitor.
- [x] Add preferences for which menu-bar modules appear.
- [x] Add click-through menu with quick stats and "Open RustTop Tahoe".
- [x] Add low-power update cadence for menu-bar-only mode.
- [x] Add Dock live graph option.
- [x] Add native notifications for sustained alerts.

Acceptance:

- [x] App can run primarily from the menu bar.
- [x] Menu-bar refresh cadence is configurable and low overhead.
- [x] Alerts can notify through macOS Notification Center.

## Phase 6: Settings And Persistence

Goal: make the native app configurable without editing TOML.

- [x] Add native Settings window.
- [x] Add refresh interval control.
- [x] Add helper path override.
- [x] Add startup behavior: open main window, menu-bar only, or restore previous.
- [x] Add persisted startup behavior picker with open-main-window,
      menu-bar-only, and restore-previous handling.
- [x] Add panel visibility settings.
- [x] Add alert threshold settings.
- [x] Add dashboard density settings that respect system appearance.
- [x] Add theme/accent/density settings that respect system appearance.
- [x] Decide whether settings write RustTop's existing TOML, native
      `UserDefaults`, or both.
- [x] Add migration path for existing RustTop config.

Acceptance:

- [x] Settings persist across launches.
- [x] Settings do not corrupt the existing RustTop TOML config.
- [x] Invalid helper/config paths show native recovery UI.

## Phase 7: Packaging, Signing, And Release

Goal: ship a Mac app users can install without developer workarounds.

- [x] Add local app bundle assembly.
- [x] Generate an app icon from existing RustTop assets.
- [x] Sync app version from `Cargo.toml` in the Tahoe build script.
- [x] Embed the Rust helper in app resources.
- [x] Rename or brand the final app bundle decision: `RustTop.app` vs
      `RustTopTahoe.app`.
- [x] Add universal Swift/Rust build support for Intel and Apple Silicon.
- [x] Add entitlements file.
- [x] Add hardened runtime settings.
- [x] Add Developer ID signing.
- [x] Add opt-in notarization.
- [x] Add opt-in stapling.
- [x] Add DMG packaging.
- [x] Add versioned release zip packaging.
- [x] Add SHA-256 checksums for release packages.
- [x] Add release workflow artifact upload.
- [x] Document Developer ID signing, hardened runtime, notarization, and
      stapling command shape without requiring CI secrets.
- [x] Add Sparkle or another update strategy if automatic updates are desired.
- [x] Add Homebrew cask update path.

Acceptance:

- [ ] A downloaded app opens normally on a clean Mac after notarization.
- [ ] The embedded helper runs inside the signed bundle.
- [x] Release artifacts include versioned app zip or DMG plus checksums.

## Phase 8: Quality Gates

Goal: keep the Tahoe app polished as it grows.

- [x] Run Swift debug build.
- [x] Run Swift release build.
- [x] Run Rust check.
- [x] Run Rust tests.
- [x] Run app bundle build.
- [x] Run plist validation.
- [x] Run Tahoe entitlements plist validation.
- [x] Run build script shell syntax validation.
- [x] Run embedded helper snapshot validation.
- [x] Run whitespace check.
- [x] Run Prettier on new Tahoe docs.
- [x] Run QA harness helper refresh smoke.
- [x] Run QA harness persistent helper stream smoke.
- [x] Run strict GUI preflight for launch/Accessibility gating.
- [x] Run static Tahoe source audit for visual/accessibility guardrails.
- [x] Run local GUI launch smoke after the first-launch hang fix.
- [x] Run a live `sample` pass to confirm the menu-bar label no longer copies
      full snapshots containing `launchd_jobs`.
- [x] Add GitHub Actions gates for Swift build/tests when present, Rust
      check/tests, bundle plist validation, and helper JSON smoke validation.
- [x] Add Swift tests.
- [x] Add UI snapshot tests or scripted screenshot checks.
- [ ] Add accessibility audit.
- [ ] Add Instruments pass for CPU/memory overhead.
- [x] Add sustained-run smoke test.
- [x] Add signed-app launch evidence test to the QA harness.
- [x] Add clean-machine install evidence checklist to the QA harness.

Recommended validation commands:

```bash
swift build --package-path macos/RustTopTahoe
swift test --package-path macos/RustTopTahoe
swift build -c release --package-path macos/RustTopTahoe
cargo check --locked
cargo test --locked
./scripts/build-macos-tahoe.sh
RUSTTOP_TAHOE_PACKAGE_ZIP=1 RUSTTOP_TAHOE_PACKAGE_DMG=1 ./scripts/build-macos-tahoe.sh
bash -n scripts/build-macos-tahoe.sh
plutil -lint RustTopTahoe.app/Contents/Info.plist
plutil -lint macos/RustTopTahoe/Packaging/RustTopTahoe.entitlements
RustTopTahoe.app/Contents/Resources/rust_top --export-json /tmp/rusttop-tahoe-smoke.json
RustTopTahoe.app/Contents/Resources/rust_top --export-csv /tmp/rusttop-tahoe-smoke.csv
RustTopTahoe.app/Contents/Resources/rust_top --incident-bundle /tmp/rusttop-tahoe-incident
npx prettier --check docs/macos-tahoe.md docs/macos-tahoe-bridge.md docs/platform-support.md docs/plans/MACOS-TAHOE-IMPLEMENTATION-PLAN.md
git diff --check
```

## Near-Term Execution Order

1. [x] Add Swift test target and JSON snapshot fixture.
2. [x] Add schema compatibility guard for snapshot decoding.
3. [x] Add process search/filter in the process view.
4. [x] Add selected process inspector.
5. [x] Add native Settings scene for refresh interval and helper path.
6. [x] Add macOS CI build for the Swift package.
7. [x] Add app bundle CI smoke build.
8. [x] Add menu-bar extra prototype.
9. [x] Decide and document the long-term bridge architecture.
10. [x] Start signing/notarization workflow design.

## Definition Of Done For Tahoe v1

- [ ] Native app can run from a signed and notarized app bundle.
- [x] Native app can monitor CPU, memory, disk, network, processes, GPU, battery,
      and sensors at parity or documented partial parity with the Rust app.
- [x] Menu-bar monitoring exists for CPU, memory, network, and alerts.
- [x] Settings persist safely.
- [x] App has native search, inspector, dialogs, alerts, and export workflows.
- [ ] App passes Swift tests, Rust tests, bundle validation, accessibility audit,
      and visual QA.
- [x] Docs describe supported macOS versions, privacy behavior, limitations,
      installation, troubleshooting, and release process.
