# RustTop v2.0 Plan

Prepared: 2026-07-07

Goal: make RustTop the strongest cross-platform system monitoring application in its category: a local-first, beautiful, low-overhead, deeply accurate monitor that combines the best of GUI task managers, terminal monitors, hardware sensor suites, and observability dashboards without becoming bloated or privacy-invasive.

## Executive Summary

RustTop is already a credible v0.2 desktop monitor: it has a clean Rust/iced architecture, real-time CPU/memory/network/disk/process panels, AMD/NVIDIA/Linux GPU support, macOS IOKit GPU support, release CI for Linux/Windows/macOS, and a compact visual identity. The v2.0 opportunity is to move from "good-looking local monitor" to "professional-grade cross-platform monitoring workstation."

The competitive bar is high:

- `btop` wins on fast TUI ergonomics, deep configurability, process tree/signals, disk I/O, battery, theming, and GPU support.
- `bottom` wins on Rust-based cross-platform terminal support, layout customization, zoomable graphs, battery/temperature/disk I/O widgets, config files, and broad package distribution.
- `Glances` wins on remote monitoring, web/API modes, exports, containers, plugins, and machine-readable output.
- `Mission Center` wins on modern Linux GUI polish, GPU encoder/decoder/power, fans, app/process grouping, minified summary view, and Windows Task Manager-like information hierarchy.
- Apple Activity Monitor wins on memory-pressure semantics, energy view, Dock graph, and user-friendly process actions.
- Microsoft Sysinternals wins on process diagnostics depth: handles, DLLs, file/registry/thread activity, filtering, stacks, and logging.
- iStat Menus and Stats win on always-visible menu bar monitoring, sensors, battery, fan control, Apple Silicon support, and hardware-aware polish.
- HWiNFO/Open Hardware Monitor/Libre Hardware Monitor win on sensor depth, voltages, clocks, fans, thermal data, reporting, and tray/gadget visibility.
- Netdata wins on local/remote dashboards, alerts, per-second history, integrations, and infrastructure-scale thinking.

RustTop v2.0 should not copy one app. It should become the first app that feels native and trustworthy on Linux, macOS, and Windows while offering:

- A world-class local dashboard.
- A world-class process explorer.
- Hardware sensor depth that can satisfy power users.
- Configurable layouts and themes without needing to edit code.
- Local history, alerts, exports, and APIs.
- Optional remote/agent mode that stays private by default.
- First-class packaging, signing, and update paths.
- Measurable low overhead.

## Current Repo Findings

### Shipped Baseline

Evidence from the current repository:

- `Cargo.toml` declares `rust_top` at version `0.2.0`, built with Rust 2021, `iced` 0.13, `iced_winit`, `sysinfo`, `tokio`, `chrono`, `palette`, and `nvml-wrapper`.
- `src/main.rs` launches a single iced desktop app with a 1200x800 default window, 800x500 minimum size, bundled icon, antialiasing, and Wayland app id `rust_top`.
- `src/metrics/collector.rs` owns `SystemMetrics`, refreshes CPU/memory/processes every tick, updates network/GPU each tick, and refreshes disks every 10 ticks.
- `src/ui/app.rs` refreshes from TOML/CLI runtime options, renders header, CPU graph, per-core CPU view, GPU panel, network, disk, memory, virtualized process table, and bottom help bar.
- `src/metrics/gpu.rs` supports:
  - Linux AMD via `/sys/class/drm/card*/device`.
  - Linux NVIDIA via NVML.
  - macOS GPU metrics via `ioreg`/IOKit for IOAccelerator performance statistics.
- `src/metrics/process.rs` supports process sorting/filtering, tree ordering, process detail metadata, signal actions, and immediate sort-direction reordering.
- `src/config.rs` provides TOML config loading, startup config generation, CLI parsing, refresh interval overrides, panel visibility, window sizing, default process sort settings, saved filters, and persisted process-column presets.
- `.github/workflows/release.yml` builds Linux x86_64, Windows x86_64, and universal macOS artifacts on tag push.
- `io.github.sudoshi.RustTop.yml` provides a Flatpak manifest, but it still expects `cargo-sources.json`.
- `assets/` contains desktop entry, icon assets, and screenshot assets.
- `scripts/build-macos-app.sh` provides macOS app-bundle assembly.

### Validation Snapshot

Local validation on this checkout:

- `cargo check --locked` passes.
- `cargo test --locked` passes with 52 unit tests.
- `cargo clippy --all-targets --all-features --locked -- -D warnings` passes.
- `cargo fmt --check` passes.
- `git diff --check` passes.

### Current Product Strengths

- Strong visual identity and concise dashboard.
- Clean separation between `metrics/`, `theme/`, and `ui/widgets/`.
- GPU support already exceeds many basic GUI system monitors.
- Cross-platform build intent exists in CI.
- Compact layout work from the previous layout plan is mostly present.
- Process search and keyboard shortcuts are already implemented.
- Linux package metadata, desktop file, Flatpak manifest, and macOS bundling are already started.

### Current Gaps

- Settings UI exists for layout, theme, compact mode, and alert enablement; richer profile switching and full preference editing remain open.
- Process app grouping, priority control, affinity, and richer pause/suspend/resume workflows are still missing beyond the current signal picker.
- Metric fixture tests exist for Linux GPU/sysfs and network rates, but UI snapshot tests and platform contract tests are still missing.
- Disk collection uses a persistent refreshable `sysinfo::Disks` handle for I/O rates; SMART/health and richer physical-disk views remain open.
- In-memory ring buffers and optional JSONL persistent history exist; downsampling and retained-series analysis remain open.
- No per-process I/O, SMART/health, filesystem alerts, or removable/media treatment beyond the current disk throughput baseline.
- No fan panel, voltage/power sensor model, or full CPU package/core temperature taxonomy beyond the current general thermal baseline.
- GPU coverage is incomplete: Linux AMD/NVIDIA/Intel baselines and macOS IOAccelerator path exist; no Windows GPU path, limited Apple Silicon/macOS sensor coverage, no encoder/decoder details, no PCI/driver diagnostics.
- Windows build exists, but Windows runtime feature parity is not designed or tested in-repo.
- Local API, JSON/CSV exports, incident bundles, and Prometheus text endpoint exist; WebSocket, OpenTelemetry, remote pairing, and retained-series export remain open.
- No containers/services view for Docker, Podman, cgroups, systemd, launchd, or Windows services.
- No documented privacy/security model, privileged-helper strategy, code signing/notarization plan, or plugin trust model.
- Flatpak manifest is incomplete until cargo sources are generated and permissions are validated.

## Competitive Research

### Research Set

The comparison covered representative leaders across the full system-monitor category:

- Terminal/TUI monitors: `htop`, `btop`, `bottom`.
- Cross-platform CLI/web monitors: `Glances`.
- Linux desktop GUI monitors: GNOME System Monitor, KDE Plasma System Monitor, Mission Center, Resources, Astra Monitor.
- Platform-native tools: Apple Activity Monitor, Microsoft Sysinternals Process Explorer and Process Monitor.
- Hardware/sensor tools: HWiNFO, Open Hardware Monitor, Libre Hardware Monitor.
- macOS menu bar monitors: iStat Menus, Stats.
- Observability systems: Netdata.
- Library baseline: psutil.

### Feature Matrix

| Product | Best ideas to learn from | RustTop v2.0 implication |
| --- | --- | --- |
| htop | Cross-platform process viewer, scrollable full command lines, process interaction, terminal reliability | RustTop needs deeper process actions, tree navigation, horizontal detail panes, and reliable keyboard-first operation |
| btop | Beautiful fast UI, mouse support, detailed process stats, process filter, tree mode, arbitrary signals, pause process list, config UI, network autoscaling, disk I/O, battery, themes, presets, Linux/macOS/BSD support, AMD/NVIDIA/Intel GPU coverage | RustTop needs config UI, tree/signals, disk I/O, battery, theme/preset system, GPU matrix, and power-user keyboard/mouse workflow |
| bottom | Rust TUI, official Linux/macOS/Windows support, zoomable graph intervals, CPU/memory/network/temperature/disk I/O/battery widgets, process search/sort/tree/signals, CLI/config layout customization, broad packaging | RustTop needs official platform support definitions, zoomable/persistent graphs, config file, layout editor, battery/temp/disk I/O, and distribution breadth |
| Glances | TUI, web UI, API, client/server, REST/XML-RPC, stdout/CSV/JSON exports, time-series exports, Docker/LXC monitoring, plugins/export modules, MCP server | RustTop needs local API/export mode, optional remote agent, container view, plugin model, and machine-readable output |
| Mission Center | Modern GTK GUI, per-thread CPU, process/thread/handle counts, memory breakdown, disk transfer rates, network interface identity, GPU encoder/decoder/power, fans, app/process usage breakdown, minified summary view, hardware-accelerated graphs | RustTop needs GUI-level polish, app grouping, fans, memory breakdowns, network identity, GPU sub-engines, and compact mode |
| GNOME System Monitor | Simple process/resource/filesystem tabs, process state/priority actions | RustTop needs approachable tabs/views for mainstream users, not only dense power-user panels |
| KDE Plasma System Monitor | Sensor-centric system monitor interface | RustTop needs a sensor model and configurable sensor pages |
| Apple Activity Monitor | CPU graph in Dock, energy view, memory pressure, detailed memory categories, clear process closing workflow | RustTop needs energy/battery semantics, memory pressure, safe process termination UX, and OS-native tray/dock/menu-bar presence |
| Sysinternals Process Explorer | Handles/DLLs, tree/process relationships, rich process metadata | RustTop needs deep inspection panels, open file/socket/module views where platform APIs permit |
| Sysinternals Process Monitor | Real-time file/registry/process/thread events, powerful non-destructive filtering, event properties, stacks, logging | RustTop should add optional event tracing and incident capture without making the default dashboard heavy |
| HWiNFO | Hardware inventory, real-time monitoring, reporting, latest sensor coverage | RustTop needs hardware inventory, sensor provenance, updateable sensor backends, and reporting |
| Open/Libre Hardware Monitor | Temperatures, fan speeds, voltages, loads, clocks, SMART/hard disk temperatures, tray/gadget display | RustTop needs voltages/clocks/fans/SMART, tray/menu-bar compact widgets, and hardware compatibility documentation |
| iStat Menus | Efficient menu-bar monitoring, CPU/GPU/memory/network/disk/sensors/battery/fans, Apple Silicon focus, fan control, theme options | RustTop needs always-visible compact monitors, macOS polish, Apple Silicon support, fan safety policy, and high-efficiency mode |
| Stats | Free/open-source macOS menu-bar modules for CPU/GPU/RAM/disk/sensors/network/battery/Bluetooth/clock | RustTop needs modular compact widgets and battery/Bluetooth-style peripheral awareness where useful |
| Netdata | Per-second collection, local/remote dashboards, alerts, anomaly detection, integrations, long retention, low advertised overhead | RustTop needs local history, alerting, optional remote/fleet mode, integrations, and measurable overhead targets |
| psutil | Cross-platform process/system metrics spanning CPU, memory, disk, network, sensors, process management, many OSes | RustTop should formalize a platform abstraction layer and avoid Linux-only semantics in core data models |

## Product Positioning

### North Star

RustTop v2.0 is the system monitor people install on every machine because it answers three questions better than anything else:

1. What is happening right now?
2. What changed over time?
3. What can I safely do about it?

### Principles

- Local-first: everything useful works without an account or cloud.
- Cross-platform by contract: every feature declares supported OSes, fallback behavior, and permission requirements.
- Accurate before pretty: graphs must be mathematically correct, timestamped, unit-aware, and testable.
- Low overhead by design: RustTop must never become the performance problem it is diagnosing.
- Expert depth, approachable defaults: beginners get a clean dashboard; power users get drill-downs, filters, exports, and process control.
- Safe control surfaces: process kills, fan controls, privileged actions, and remote access require clear confirmation and least privilege.
- Privacy-respecting: no telemetry by default; any sharing/export is explicit.
- Extensible without fragility: plugins and integrations use stable schemas and permission boundaries.

## v2.0 Definition of Done

RustTop v2.0 ships only when all of the following are true:

- Linux, macOS, and Windows are officially supported with documented parity tiers.
- Core CPU, memory, disk, network, process, battery, sensor, and GPU panels work on all supported OSes with graceful degradation.
- The process view supports tree mode, app grouping, search, filters, details, signals/actions, safe termination, and per-process histories.
- Metric rates are timestamp-based and tested with fixture data.
- Local history, snapshots, alerts, and exports are available.
- Config file, CLI flags, settings UI, layout presets, and theme system are implemented.
- Optional remote/API mode exists and is off by default.
- Packaging covers GitHub Releases, crates.io, deb/rpm/AppImage or equivalent, Flatpak, Homebrew, Windows installer/winget, and signed/notarized macOS artifacts.
- CI covers formatting, linting, unit tests, fixture tests, no-run UI builds, packaging dry runs, and cross-platform build smoke.
- Runtime overhead is measured and published.
- Documentation includes user guide, troubleshooting, architecture, privacy/security model, hardware support matrix, and contributor guide.

## Target Architecture

### Module Layout

Refactor toward this shape over several releases:

```text
src/
  app/
    state.rs
    messages.rs
    commands.rs
    settings.rs
  core/
    metric.rs
    sample.rs
    units.rs
    history.rs
    alert.rs
    snapshot.rs
  collectors/
    mod.rs
    scheduler.rs
    cpu.rs
    memory.rs
    disk.rs
    network.rs
    process.rs
    gpu.rs
    sensors.rs
    battery.rs
    services.rs
    containers.rs
  platform/
    linux/
    macos/
    windows/
    bsd/
  process_control/
    mod.rs
    signals.rs
    priority.rs
    affinity.rs
    details.rs
  storage/
    ring_buffer.rs
    sqlite.rs
    export.rs
  remote/
    api.rs
    websocket.rs
    agent.rs
    auth.rs
  plugins/
    manifest.rs
    host.rs
    permissions.rs
  ui/
    app.rs
    views/
    widgets/
    settings/
    command_palette.rs
  theme/
  telemetry/
    diagnostics.rs
```

### Core Data Model

- [ ] Define `MetricId` with namespace, device id, source id, and metric name.
- [ ] Define `MetricValue` as typed values: ratio, bytes, bytes/sec, hertz, watts, volts, amps, deg C, rpm, count, duration, string, enum.
- [ ] Define `Sample` with monotonic timestamp, wall timestamp, value, unit, source, quality, and permissions/error state.
- [ ] Define `Device` with stable id, display name, vendor, model, bus/path, OS handle, and capabilities.
- [ ] Define `ProcessIdentity` with PID, start time, executable path, command, user, parent PID, session, cgroup/job/container, and app group.
- [ ] Define `CollectionStatus` for ok, unavailable, permission denied, unsupported, stale, degraded, and backend error.
- [ ] Define `HistorySeries` with retention, sample interval, downsampling, min/max/avg, and zoom windows.
- [ ] Define a platform capability registry that the UI can query.

### Collector Scheduler

- [ ] Move collection off the UI update path.
- [ ] Use async/background tasks with bounded channels.
- [ ] Sample fast metrics at 500 ms to 1 s, medium metrics at 2 s to 5 s, slow inventory at 30 s to 5 min.
- [ ] Calculate all rates using elapsed monotonic time, not assumed tick interval.
- [ ] Keep collector-owned refresh handles where libraries support them.
- [ ] Add backpressure so slow disk/sensor/GPU calls do not freeze rendering.
- [ ] Expose collector latency, error count, and last successful sample in a diagnostics panel.
- [ ] Support pause/resume sampling.
- [ ] Support low-power sampling mode.

## Workstream 1: Metric Accuracy and Core Stability

### Goals

Make RustTop trustworthy. Every visible number must be timestamped, unit-safe, and testable.

### TODOs

- [x] Fix network rate calculation to divide byte deltas by actual elapsed seconds.
- [x] Add tests for network delta/rate math using synthetic timestamps.
- [ ] Add tests for history truncation, retention, min/max/avg, and downsampling.
- [x] Replace `Vec::remove(0)` history trimming with ring buffers to avoid O(n) shifts.
- [ ] Track collector sample timestamps in every metric group.
- [ ] Add unit formatting tests for bytes, rates, hertz, watts, temperatures, percentages, and durations.
- [ ] Introduce typed units instead of formatting raw numbers directly in widgets.
- [ ] Normalize memory semantics by OS:
  - [ ] Linux: total, used, available, cache, buffers, swap, pressure if available.
  - [ ] macOS: memory pressure, app/wired/compressed/cached/swap where possible.
  - [ ] Windows: commit, working set, standby/cache, pagefile, memory compression where possible.
- [ ] Add stale-data indicators for collectors that fail or time out.
- [ ] Add "data source" tooltips or detail rows for each metric.
- [ ] Add a diagnostics view listing all collectors, sample times, errors, and permissions.
- [ ] Add `cargo fmt`, `cargo clippy`, and `cargo test` to the normal validation contract.

### Acceptance Criteria

- [ ] Synthetic tests prove rates remain correct at 250 ms, 500 ms, 1 s, 2 s, and jittered intervals.
- [ ] UI never labels a raw delta as a per-second rate.
- [ ] All user-visible units are produced by shared unit formatters.
- [ ] Collector failure appears as degraded state, not silent zero.

## Workstream 2: Cross-Platform Platform Layer

### Goals

Stop treating cross-platform as "compiles everywhere." v2.0 must have explicit OS feature contracts and stable fallbacks.

### TODOs

- [ ] Create `platform` traits for CPU, memory, disk, network, process, GPU, sensor, battery, service, and container providers.
- [ ] Create a support matrix generated from platform capability declarations.
- [ ] Document each provider's OS support, permissions, and known limitations.
- [ ] Make Linux/macOS/Windows official Tier 1 targets.
- [ ] Make FreeBSD/OpenBSD/NetBSD Tier 2 exploratory targets after Linux/macOS/Windows parity.
- [ ] Add platform fixture tests where direct hardware access is unavailable in CI.
- [ ] Add runtime capability discovery so the UI only shows supported actions.
- [ ] Add clear fallback messages for unsupported or permission-denied features.

### Linux TODOs

- [ ] Keep `sysinfo` for common metrics where accurate.
- [ ] Add direct `/proc` and `/sys` parsers for fields `sysinfo` does not cover.
- [ ] Add cgroup v2 awareness for process/container attribution.
- [ ] Add pressure stall information (CPU/memory/I/O PSI) when `/proc/pressure/*` exists.
- [ ] Add `hwmon` sensor discovery for CPU/package temps, fans, voltages, power, and labels.
- [ ] Add battery and AC adapter support through `/sys/class/power_supply` and optional UPower integration.
- [ ] Add disk I/O from `/proc/diskstats` with per-device rates.
- [ ] Add filesystem details from mounts and statvfs.
- [ ] Add network interface metadata from sysfs/netlink where available.
- [ ] Add process I/O from `/proc/[pid]/io`.
- [ ] Add process open files and sockets from `/proc/[pid]/fd` with permission-aware fallbacks.
- [ ] Add systemd services view through D-Bus when systemd is present.

### macOS TODOs

- [ ] Implement CPU/memory/process details with `sysctl`, `libproc`, and host statistics where needed.
- [ ] Add memory pressure and compressed/wired/app/cache breakdown.
- [ ] Add battery, power source, cycle count, and health via IOKit.
- [ ] Add temperature/fan/sensor support through safe APIs where available, with documented limitations.
- [ ] Add Apple Silicon GPU metrics and thermal/power metrics where available.
- [ ] Add per-process energy impact or approximations if APIs permit.
- [ ] Add menu-bar compact mode.
- [ ] Add Dock live graph option.
- [ ] Add signed/notarized app workflow.

### Windows TODOs

- [ ] Implement process details through Windows APIs, not only `sysinfo`.
- [ ] Add CPU/memory/disk/network metrics through PDH, performance counters, WMI/CIM, or native APIs as appropriate.
- [ ] Add GPU support through DXGI/performance counters/NVML/vendor backends where available.
- [ ] Add battery/power plan/AC status support.
- [ ] Add services view.
- [ ] Add process handles/modules/threads where permissions allow.
- [ ] Add per-process I/O and network where available.
- [ ] Add Windows notification support for alerts.
- [ ] Add installer, Start Menu shortcut, code signing plan, and winget manifest.

### Acceptance Criteria

- [ ] Each Tier 1 platform has a documented capability matrix.
- [ ] A missing backend produces a visible unsupported/degraded state.
- [ ] CI builds Tier 1 platforms on every PR.
- [ ] Manual smoke scripts exist for hardware-only checks on each OS.

## Workstream 3: Hardware Sensors and GPU Excellence

### Goals

Become the monitor users trust for CPUs, GPUs, fans, batteries, thermals, power, and storage health.

### TODOs

- [ ] Create a unified `SensorMetric` model with source, label, chip/device, unit, min/max, critical thresholds, and trust level.
- [ ] Add CPU package temperature, per-core temperature where possible, CPU frequency, CPU power, and throttling indicators.
- [ ] Add fan RPM and fan percentage display with source labels.
- [ ] Add voltage sensors where available.
- [ ] Add battery charge, health, cycle count, power draw, time remaining, and charging state.
- [ ] Add disk SMART health and temperatures through optional backend integration.
- [ ] Add disk I/O utilization, read/write throughput, read/write IOPS, queue depth where available.
- [ ] Add GPU vendor abstraction.
- [ ] Add Intel GPU support:
  - [ ] Linux i915.
  - [ ] Linux xe driver path.
  - [ ] Windows Intel path.
  - [ ] macOS Intel path where applicable.
- [ ] Expand AMD support:
  - [ ] Keep sysfs fallback.
  - [ ] Evaluate optional ROCm SMI backend for richer Linux AMD telemetry.
  - [ ] Add VRAM/GTT distinction where available.
  - [ ] Add encoder/decoder/copy engines where available.
- [ ] Expand NVIDIA support:
  - [ ] Keep NVML.
  - [ ] Add utilization domains, encoder/decoder, PCIe throughput, performance state, throttle reasons where available.
- [ ] Expand macOS GPU support:
  - [ ] Apple Silicon GPU metrics.
  - [ ] AMD/Intel GPU metrics where available.
  - [ ] Graceful fallback when metrics require privileges or are unavailable.
- [ ] Add multi-GPU UI with compact cards, detailed drill-down, and aggregate summary.
- [x] Add GPU support matrix in docs.
- [ ] Add sensor privacy/safety notes, especially for fan control or privileged collection.
- [ ] Do not ship fan-control write actions until read-only monitoring is stable and a safety policy exists.

### Acceptance Criteria

- [ ] RustTop can explain why each GPU/sensor is or is not available.
- [ ] Multi-GPU systems are readable without vertical overflow.
- [ ] Sensor values show units, source, and stale/error state.
- [ ] Hardware support docs include Linux/macOS/Windows matrices.

## Workstream 4: Process Explorer and Control Center

### Goals

Surpass basic task managers by combining htop/btop ergonomics, Activity Monitor safety, and Sysinternals-style detail.

### TODOs

- [ ] Add process tree mode.
- [ ] Add app/group mode that aggregates child processes under a user-facing app name.
- [ ] Add process detail pane with:
  - [ ] Full command line.
  - [ ] Executable path.
  - [ ] Working directory where available.
  - [ ] Parent/children.
  - [ ] User.
  - [ ] Start time.
  - [ ] Runtime.
  - [ ] Threads.
  - [ ] Handles/file descriptors.
  - [ ] Open files.
  - [ ] Network sockets.
  - [ ] Memory maps/modules.
  - [ ] Environment variables with secret redaction.
  - [ ] CPU/memory/I/O/network histories.
  - [ ] Container/cgroup/job/service association.
- [ ] Add process actions:
  - [ ] Terminate gracefully.
  - [ ] Force kill.
  - [ ] Suspend/resume where supported.
  - [ ] Stop/continue signals on Unix.
  - [ ] Renice/change priority.
  - [ ] Change CPU affinity where supported.
  - [ ] Open file location.
  - [ ] Copy PID/name/command/path.
- [ ] Replace immediate kill with a confirmation flow.
- [ ] Add signal/action picker.
- [ ] Add platform-specific action availability and permission messaging.
- [ ] Add process-list pause/freeze mode.
- [ ] Add "follow selected process" toggle.
- [ ] Add advanced filtering syntax:
  - [ ] `name:chrome`.
  - [ ] `pid:1234`.
  - [ ] `user:root`.
  - [ ] `cpu>50`.
  - [ ] `mem>1gb`.
  - [ ] `status:running`.
  - [ ] `path:/usr/bin`.
  - [ ] `container:foo`.
- [ ] Add saved filters.
- [ ] Add search highlighting.
- [ ] Add horizontal detail expansion for long command lines.
- [ ] Add column chooser and column persistence.
- [ ] Add process table virtualization for thousands of processes.
- [ ] Add mouse support for sort, select, context menu, and details.
- [ ] Add keyboard command palette actions for process operations.

### Acceptance Criteria

- [ ] No destructive process action can fire by accidental single keypress unless explicitly configured.
- [ ] Process tree and flat views preserve selection across refreshes using PID plus start time.
- [ ] Process details degrade gracefully when permissions block fields.
- [ ] Filters are tested and documented.

## Workstream 5: World-Class UI/UX

### Goals

Build an app that feels rich and professional without hiding power-user depth.

### View Model

RustTop v2.0 should have these first-class views:

- Overview: concise dashboard for CPU, memory, GPU, disk, network, battery, top processes, alerts.
- Processes: table/tree/app-grouping, process details, actions.
- Performance: CPU/memory/GPU/network/disk deep charts with zoomable timelines.
- Sensors: temperatures, fans, voltages, power, clocks, batteries, hardware inventory.
- Storage: filesystems, disks, I/O, SMART, mount health, removable drives.
- Network: per-interface rates, addresses, Wi-Fi details, sockets, top talkers where available.
- Services: systemd/launchd/Windows services, startup status, resource usage.
- Containers: Docker/Podman/cgroup workloads and resource attribution.
- History: snapshots, alerts, bookmarked incidents, comparisons.
- Settings: layout, theme, refresh rates, alerts, privacy, remote/API, plugins.
- Diagnostics: collector health, permissions, backend status, logs.

### TODOs

- [ ] Add top-level navigation with keyboard shortcuts.
- [ ] Add command palette for navigation and actions.
- [ ] Add layout presets:
  - [ ] Daily driver.
  - [ ] Laptop/battery.
  - [ ] Gaming/GPU.
  - [ ] Server/storage.
  - [ ] Developer/process.
  - [ ] Minimal/compact.
  - [ ] Wallboard.
- [ ] Add user-editable layouts.
- [ ] Add panel visibility toggles.
- [ ] Add panel resize/reorder where iced supports it or via preset editor.
- [ ] Add compact always-on-top window mode.
- [ ] Add tray/menu-bar mode:
  - [ ] Linux tray/AppIndicator where available.
  - [ ] macOS menu bar item.
  - [ ] Windows notification area.
- [ ] Add high-density mode for power users.
- [ ] Add accessible mode with higher contrast and reduced glow.
- [ ] Add color-blind-safe heat palettes.
- [ ] Add theme editor and theme import/export.
- [ ] Add keyboard/mouse help overlay.
- [ ] Add tooltips for labels, units, and unsupported states.
- [ ] Add onboarding that asks for preferred layout and permissions.
- [ ] Add empty/degraded states for missing sensors/GPU/network.
- [ ] Add responsive behavior for small laptop screens, ultrawide monitors, and HiDPI scaling.
- [ ] Add snapshot comparison UI: "now vs 5 minutes ago" and "before vs after launch".
- [ ] Add alert timeline integrated into charts.
- [ ] Add copy/export actions from charts and tables.

### Acceptance Criteria

- [ ] Core workflow is usable at 800x500.
- [ ] Overview remains readable on 1080p without mandatory scrolling.
- [ ] All destructive actions require visible affordances and confirmation.
- [ ] Keyboard-only navigation can reach all major actions.
- [ ] Theme contrast passes accessibility checks for core text.

## Workstream 6: Configuration, Profiles, and Themes

### Goals

Match or exceed btop/bottom configurability while keeping first-run defaults excellent.

### TODOs

- [ ] Add `clap` for CLI flags:
  - [ ] `--config`.
  - [ ] `--interval`.
  - [ ] `--profile`.
  - [ ] `--theme`.
  - [ ] `--no-gpu`.
  - [ ] `--safe-mode`.
  - [ ] `--export`.
  - [ ] `--api`.
  - [ ] `--version`.
  - [ ] `--help`.
- [ ] Add `serde`/`toml` configuration.
- [ ] Use platform config locations:
  - [ ] Linux: `$XDG_CONFIG_HOME/rust_top/config.toml`.
  - [ ] macOS: `~/Library/Application Support/RustTop/config.toml`.
  - [ ] Windows: `%APPDATA%/RustTop/config.toml`.
- [ ] Auto-generate config on first launch.
- [ ] Add schema versioning and migration.
- [ ] Add settings UI that writes config safely.
- [ ] Add profile system:
  - [ ] Default.
  - [ ] Laptop.
  - [ ] Workstation.
  - [ ] Server.
  - [ ] Low overhead.
  - [ ] Presentation/wallboard.
- [ ] Persist window size, position, maximized/fullscreen, and selected view.
- [ ] Persist process columns, sort, filters, and selected layout.
- [ ] Add theme files with color roles rather than hard-coded palette constants.
- [ ] Include built-in themes:
  - [ ] RustTop dark.
  - [ ] High contrast dark.
  - [ ] Light.
  - [ ] Tokyo Night.
  - [ ] Gruvbox-inspired.
  - [ ] Catppuccin-inspired.
  - [ ] Terminal/TTY inspired.
- [ ] Add theme validation to prevent unreadable color combinations.
- [ ] Add import/export for settings and themes.
- [ ] Add safe-mode startup that disables plugins, remote, GPU, and custom themes.

### Acceptance Criteria

- [ ] Config changes round-trip without losing unknown future fields.
- [ ] Settings UI and file config produce the same runtime state.
- [ ] Invalid config reports exact field errors and falls back safely.

## Workstream 7: History, Snapshots, Alerts, and Analysis

### Goals

Turn RustTop from a live-only monitor into a short-term diagnostic tool.

### TODOs

- [x] Add local persistent history with user-configurable retention.
- [x] Keep default retention conservative to preserve disk and privacy.
- [x] Store history in a compact local database or log-structured store.
- [ ] Add downsampling tiers for longer windows.
- [ ] Add chart zoom/pan:
  - [ ] 1 minute.
  - [ ] 5 minutes.
  - [ ] 15 minutes.
  - [ ] 1 hour.
  - [ ] 6 hours.
  - [ ] 24 hours.
  - [ ] Custom.
- [x] Add snapshots:
  - [x] Manual snapshot.
  - [ ] Snapshot on alert.
  - [ ] Snapshot on process kill.
  - [ ] Snapshot on app launch.
- [ ] Add alert rules:
  - [x] CPU over threshold.
  - [x] Memory pressure.
  - [x] Swap spike.
  - [x] Disk near full.
  - [ ] Disk I/O saturation.
  - [ ] Network saturation.
  - [x] GPU temperature/VRAM.
  - [ ] GPU power.
  - [x] Battery health/low battery.
  - [ ] Fan failure/stall.
  - [ ] Process runaway.
  - [ ] Service crash.
- [ ] Add per-platform desktop notifications.
- [ ] Add snooze/mute.
- [ ] Add alert timeline.
- [ ] Add anomaly detection only after deterministic threshold alerts are solid.
- [ ] Add "what changed" analysis:
  - [ ] New top process.
  - [ ] Process started/stopped.
  - [ ] Service restarted.
  - [ ] New disk mounted.
  - [ ] Interface changed.
  - [ ] Thermal throttling began.
- [x] Add incident export bundle with snapshot, process list, and diagnostics.
- [ ] Add chart images to incident bundles.

### Acceptance Criteria

- [x] History and alerts can be disabled completely.
- [x] Default history is local-only and documented.
- [x] Live and persisted history alerts include source metric, threshold, duration, and current value.
- [x] Snapshot exports redact sensitive command/env data by default.

## Workstream 8: Remote, API, and Automation

### Goals

Offer Glances/Netdata-style power without forcing a server model on casual users.

### Modes

- Desktop mode: current local GUI.
- Headless agent mode: collector runs without GUI.
- Connect mode: desktop connects to local or remote agents.
- Web/API mode: optional local web dashboard and machine-readable API.

### TODOs

- [x] Define stable JSON schema for current metrics.
- [x] Add `rust_top --export-json PATH` for one-shot snapshot output.
- [x] Add `rust_top --export-csv PATH` for one-shot summary output.
- [ ] Add selected metric-series export from retained history.
- [x] Add `rust_top --api` local HTTP API, disabled by default.
- [ ] Add WebSocket stream for live dashboards.
- [x] Add Prometheus endpoint option.
- [ ] Add OpenTelemetry metrics export option.
- [ ] Add remote agent pairing:
  - [ ] Explicit user opt-in.
  - [x] Localhost only by default.
  - [x] Bearer token authentication for local API data endpoints.
  - [ ] mTLS or stronger pairing for remote agents.
  - [ ] Clear UI indicator when remote/API mode is active.
- [ ] Add SSH-based remote mode as an alternative to persistent agents.
- [ ] Add fleet dashboard only after single remote host is stable.
- [x] Add API docs and examples.
- [ ] Add scripting examples:
  - [x] Get top CPU processes.
  - [ ] Export a 5-minute CPU/memory snapshot.
  - [ ] Watch disk-free alerts.
  - [x] Query collector health.
- [ ] Add MCP integration only after API schemas and auth boundaries are stable.

### Acceptance Criteria

- [x] No network listener starts unless explicitly enabled.
- [x] API mode prints/listens on an explicit address and port.
- [x] Remote connections are authenticated.
- [x] Export schemas are versioned and tested.

## Workstream 9: Containers, Services, and Workloads

### Goals

Modern systems are workload hosts. RustTop should show not only processes but also the workloads they belong to.

### TODOs

- [ ] Add cgroup v2 attribution on Linux.
- [ ] Add Docker container discovery and resource usage.
- [ ] Add Podman container discovery and resource usage.
- [ ] Add container process grouping.
- [ ] Add local Kubernetes context view after Docker/Podman support is stable.
- [ ] Add systemd services view:
  - [ ] Service name.
  - [ ] State.
  - [ ] Main PID.
  - [ ] Restart count where available.
  - [ ] CPU/memory attribution where possible.
  - [ ] Logs link or recent status text where safe.
- [ ] Add macOS launchd services/agents view.
- [ ] Add Windows services view.
- [ ] Add WSL distribution/process awareness on Windows.
- [ ] Add service actions with confirmation:
  - [ ] Start.
  - [ ] Stop.
  - [ ] Restart.
  - [ ] Disable/enable only after read-only service view is stable.
- [ ] Add workload filters to the process table.

### Acceptance Criteria

- [ ] Workload views are read-only by default.
- [ ] Service actions respect platform permissions and show exact failure reasons.
- [ ] Container view works without Docker when Podman/cgroups are present and vice versa.

## Workstream 10: Storage and Network Depth

### Storage TODOs

- [ ] Add disk I/O graph per physical disk.
- [ ] Add read/write throughput and IOPS.
- [ ] Add mount/fstab metadata where available.
- [ ] Add filesystem type, free/used, reserved space, inode usage on Unix.
- [ ] Add removable/external drive indicators.
- [ ] Add SMART health and temperature through optional backend.
- [ ] Add warnings for:
  - [ ] Low free space.
  - [ ] High disk temperature.
  - [ ] SMART failure/pre-fail.
  - [ ] High I/O wait.
  - [ ] Mount disappeared.
- [ ] Add storage detail panel.

### Network TODOs

- [ ] Correct rate math with elapsed timestamps.
- [ ] Add per-interface graph rows.
- [ ] Add interface metadata:
  - [ ] Link speed.
  - [ ] Duplex where available.
  - [ ] MAC address.
  - [ ] IP addresses.
  - [ ] Wi-Fi SSID/frequency/signal where available.
  - [ ] VPN/tunnel indicators where available.
- [ ] Add total data transferred counters.
- [ ] Add top sockets/connections where platform permits.
- [ ] Add per-process network attribution where feasible.
- [ ] Add packet/error/drop counters.
- [ ] Add network alerts:
  - [ ] High bandwidth.
  - [ ] Link down/up.
  - [ ] Packet errors.
  - [ ] IP address changed.
- [ ] Add copy/export interface stats.

### Acceptance Criteria

- [ ] Storage and network rates are tested with fixture deltas.
- [ ] Per-interface UI scales from 1 to 20+ interfaces.
- [ ] Unsupported per-process network attribution is explicitly labeled.

## Workstream 11: Performance Engineering

### Targets

Initial v2.0 performance targets:

- Idle dashboard CPU: under 1% on a modern desktop in default mode.
- Default memory footprint: under 150 MB target, with platform variance documented.
- UI frame stutter: no visible stalls from slow collectors.
- Collector latency: visible in diagnostics and bounded by timeout.
- Disk history overhead: predictable and configurable.

### TODOs

- [ ] Add benchmark harness for collectors.
- [ ] Add benchmark harness for rendering common views.
- [ ] Add synthetic high-process-count test.
- [ ] Add synthetic high-core-count test.
- [ ] Add multi-GPU layout stress test.
- [ ] Add 20-interface network UI stress test.
- [ ] Add history storage write/read benchmarks.
- [ ] Move expensive string formatting out of hot render loops where possible.
- [ ] Avoid allocating full process filtered vectors every frame when possible.
- [ ] Use stable process identity to update rows incrementally.
- [ ] Add UI virtualization for process and sensor tables.
- [ ] Add collector timeouts.
- [ ] Add render-rate throttling independent from sample rate.
- [ ] Add low-power mode:
  - [ ] Slower sampling.
  - [ ] Reduced animation.
  - [ ] Less history retention.
  - [ ] Disable expensive sensors by default.
- [ ] Add profiler docs for maintainers.

### Acceptance Criteria

- [ ] Release notes include measured overhead on representative Linux/macOS/Windows systems.
- [ ] Performance regression benchmarks run in CI where practical.
- [ ] Slow collectors never block the UI thread.

## Workstream 12: Security, Privacy, and Privileges

### Goals

System monitors naturally touch sensitive data. RustTop must be explicit and conservative.

### TODOs

- [ ] Write a privacy model.
- [ ] Write a permissions model.
- [ ] Redact environment variables and command-line secrets by default in exports.
- [ ] Mark sensitive fields in the data model.
- [ ] Add export options:
  - [ ] Full local export.
  - [ ] Redacted support bundle.
  - [ ] Metrics-only export.
- [ ] Never start remote/API listeners by default.
- [ ] Add visible active-listener indicator.
- [ ] Add local API authentication when binding beyond localhost.
- [ ] Add plugin permission manifest.
- [ ] Add plugin signing or trusted-directory model before third-party plugin support.
- [ ] Add privileged helper design only if necessary:
  - [ ] Small attack surface.
  - [ ] Read-only by default.
  - [ ] Separate process.
  - [ ] Auditable protocol.
  - [ ] No broad root GUI.
- [ ] Add code signing:
  - [ ] macOS Developer ID signing and notarization.
  - [ ] Windows Authenticode signing.
  - [ ] Linux package signing where possible.
- [ ] Add dependency audit:
  - [ ] `cargo audit`.
  - [ ] `cargo deny`.
  - [ ] License checks.
  - [ ] Supply-chain review for plugin/runtime dependencies.
- [ ] Add crash logging that stays local unless user exports it.

### Acceptance Criteria

- [ ] User can inspect all active permissions/listeners from the UI.
- [ ] Redacted exports are safe to attach to bug reports by default.
- [ ] Privileged collection is isolated or avoided.

## Workstream 13: Testing and Quality System

### Goals

Turn the project from "builds" to "verified."

### TODOs

- [ ] Add unit tests for:
  - [ ] Unit formatting.
  - [ ] History/ring buffer.
  - [ ] Network rates.
  - [ ] Disk rates.
  - [ ] Process sorting.
  - [ ] Process filtering.
  - [ ] Config parsing/migration.
  - [ ] Theme parsing.
  - [ ] Alert evaluation.
- [ ] Add fixture tests for:
  - [ ] Linux `/proc`.
  - [ ] Linux `/sys`.
  - [ ] Linux `hwmon`.
  - [ ] macOS `ioreg`.
  - [ ] Windows provider snapshots where possible.
  - [ ] NVML mock data.
  - [ ] AMD sysfs mock data.
  - [ ] Intel GPU mock data.
- [ ] Add integration tests for collector scheduler.
- [ ] Add UI state tests for keyboard actions.
- [ ] Add visual regression screenshots where practical.
- [ ] Add smoke test scripts for real hardware.
- [ ] Add CI gates:
  - [ ] `cargo fmt --check`.
  - [ ] `cargo clippy --all-targets --all-features -- -D warnings`.
  - [ ] `cargo test --all`.
  - [ ] `cargo check --target x86_64-pc-windows-msvc`.
  - [ ] `cargo check --target x86_64-apple-darwin`.
  - [ ] `cargo check --target aarch64-apple-darwin`.
  - [ ] Linux package dry run.
  - [ ] Flatpak manifest validation.
  - [ ] macOS bundle validation.
  - [ ] Windows installer validation.
- [ ] Add issue templates that request OS, GPU, driver, permissions, and diagnostics export.
- [ ] Add hardware compatibility test checklist.
- [ ] Add release candidate soak checklist.

### Acceptance Criteria

- [ ] PRs cannot merge with broken formatting, clippy, or tests.
- [ ] New collectors require fixtures or mocks.
- [ ] Release candidates include platform smoke results.

## Workstream 14: Packaging, Distribution, and Updates

### Goals

If users cannot install it easily, it is not the best cross-platform monitor.

### TODOs

- [ ] Publish `rust_top` to crates.io with locked, reproducible release instructions.
- [ ] Build GitHub release artifacts for:
  - [ ] Linux x86_64.
  - [ ] Linux aarch64.
  - [ ] Windows x86_64.
  - [ ] Windows arm64 when supported.
  - [ ] macOS x86_64.
  - [ ] macOS aarch64.
  - [ ] macOS universal.
- [ ] Add `.deb`.
- [ ] Add `.rpm`.
- [ ] Add AppImage or portable Linux tarball.
- [ ] Finish Flatpak:
  - [ ] Generate `cargo-sources.json`.
  - [ ] Validate filesystem/device permissions.
  - [ ] Submit to Flathub.
- [ ] Add Snap only if sandbox permissions can support useful monitoring.
- [ ] Add Arch AUR package.
- [ ] Add Homebrew formula.
- [ ] Add MacPorts formula if demand exists.
- [ ] Add Windows installer:
  - [ ] MSI or MSIX.
  - [ ] Start Menu shortcut.
  - [ ] Uninstaller.
  - [ ] Optional auto-start/tray setting.
- [ ] Add winget manifest.
- [ ] Add Chocolatey package.
- [ ] Add Scoop manifest.
- [ ] Add auto-update story:
  - [ ] Manual update check.
  - [ ] Package-manager-first guidance.
  - [ ] No silent update without user consent.
- [ ] Add signed checksums and release provenance.
- [ ] Add SBOM generation.
- [ ] Add release notes template with compatibility matrix.

### Acceptance Criteria

- [ ] A non-developer can install RustTop on Linux, macOS, and Windows from a normal package path.
- [ ] Release artifacts include checksums.
- [ ] macOS app is signed/notarized before v2.0 stable.
- [ ] Windows installer is signed before v2.0 stable.

## Workstream 15: Documentation, Website, and Community

### TODOs

- [ ] Update README to reflect actual v2.0 capabilities only as they land.
- [ ] Add `docs/architecture.md`.
- [ ] Add `docs/platform-support.md`.
- [ ] Add `docs/hardware-support.md`.
- [ ] Add `docs/configuration.md`.
- [ ] Add `docs/theme-authoring.md`.
- [ ] Add `docs/api.md`.
- [ ] Add `docs/privacy-security.md`.
- [ ] Add `docs/troubleshooting.md`.
- [ ] Add `docs/release-process.md`.
- [ ] Add man page.
- [ ] Add CLI completions.
- [ ] Add screenshots for:
  - [ ] Linux.
  - [ ] macOS.
  - [ ] Windows.
  - [ ] Compact mode.
  - [ ] Process detail.
  - [ ] Sensors.
  - [ ] Remote/API dashboard if shipped.
- [ ] Add animated demo recording.
- [ ] Add website or GitHub Pages landing page with direct install instructions.
- [ ] Add contribution guide.
- [ ] Add code of conduct if community contribution becomes active.
- [ ] Add security policy.
- [ ] Add support/debug bundle instructions.
- [ ] Add roadmap tracking with release milestones.

### Acceptance Criteria

- [ ] Docs distinguish shipped features from planned features.
- [ ] Every platform-specific feature links to its support status.
- [ ] Troubleshooting covers GPU, sensors, Wayland/X11, permissions, Flatpak sandboxing, macOS permissions, and Windows permissions.

## Workstream 16: Plugin and Integration Model

### Goals

Make RustTop extensible without compromising performance, safety, or trust.

### TODOs

- [ ] Start with built-in integrations before third-party plugins:
  - [ ] Docker.
  - [ ] Podman.
  - [ ] systemd.
  - [ ] launchd.
  - [ ] Windows services.
  - [ ] Prometheus export.
  - [x] JSON/CSV export.
- [ ] Define plugin use cases:
  - [ ] Read-only metric panel.
  - [ ] External command metric.
  - [ ] Export sink.
  - [ ] Alert notifier.
  - [ ] Theme pack.
- [ ] Define plugin manifest:
  - [ ] Name.
  - [ ] Version.
  - [ ] Author.
  - [ ] Permissions.
  - [ ] Commands.
  - [ ] Metrics emitted.
  - [ ] UI panel declarations.
- [ ] Prefer sandboxed external process or WASM only if the overhead and security model are acceptable.
- [ ] Add signed/trusted plugin directory before loading third-party code.
- [ ] Add plugin timeout and resource caps.
- [ ] Add plugin diagnostics.
- [ ] Do not block v2.0 core on third-party plugins; make plugin foundation stable but minimal.

### Acceptance Criteria

- [ ] Built-in integrations prove the schema before public plugin API.
- [ ] Plugins cannot run silently with broad permissions.
- [ ] Plugin failures cannot crash the app.

## Release Roadmap

### v0.3: Foundation and Correctness

- [x] Fix network rate math.
- [x] Add ring-buffer history.
- [x] Add unit formatting and tests.
- [x] Add collector timestamps and status.
- [x] Add basic config file and CLI.
- [x] Add process kill confirmation.
- [x] Add CI fmt/clippy/test.
- [x] Add first fixture tests for Linux GPU/sysfs and network rates.

### v0.4: Daily Driver Process Monitor

- [x] Process tree.
- [x] Signal/action picker.
- [x] Process detail pane.
- [x] Search highlighting.
- [x] Saved filters.
- [x] Process table virtualization.
- [x] Column persistence.
- [x] Process action safety model.

### v0.5: Sensors, Battery, and Disk I/O

- [x] Battery panel.
- [x] Thermal/fan/sensor panel.
- [x] Disk I/O rates.
- [ ] SMART health optional backend.
- [ ] Linux hwmon fan/voltage/power expansion.
- [ ] macOS battery/thermal improvements.
- [ ] Windows battery and disk metrics baseline.

### v0.6: Layouts, Themes, and Settings UI

- [x] Settings UI strip.
- [x] Layout presets.
- [x] Built-in themes and persisted theme selection.
- [ ] External theme files.
- [x] Compact/minified mode.
- [ ] Tray/menu-bar proof of concept.
- [ ] Accessibility pass.

### v0.7: GPU and Platform Parity

- [x] Intel GPU Linux detection baseline.
- [ ] Windows GPU baseline.
- [ ] Apple Silicon GPU path.
- [ ] Multi-GPU detail view.
- [x] GPU support matrix.
- [x] Platform capability matrix.

### v0.8: History, Alerts, and Exports

- [x] Persistent local history.
- [x] Snapshots.
- [x] Threshold alerts.
- [ ] Desktop notifications.
- [x] JSON/CSV export.
- [x] Incident bundle export.

### v0.9: Remote/API and Workloads

- [x] Local API.
- [ ] WebSocket live stream.
- [x] Prometheus endpoint.
- [ ] Optional agent mode.
- [ ] Docker/Podman/cgroup view.
- [ ] systemd/launchd/Windows services read-only views.

### v1.0: Stable Daily Driver

- [ ] Linux/macOS/Windows official Tier 1.
- [ ] Packaging breadth.
- [ ] Code signing plan active.
- [ ] Documentation complete for current features.
- [ ] Performance targets published.
- [ ] Support bundle/export.
- [ ] Hardware compatibility matrix.

### v1.5: Power User and Fleet Features

- [ ] Remote host management.
- [ ] SSH connect mode.
- [ ] More event tracing.
- [ ] App/service/container correlation.
- [ ] Plugin foundation.
- [ ] Advanced alerting.

### v2.0: Best-in-Class Release

- [ ] Feature parity targets from this plan met or consciously descoped.
- [ ] Signed/notarized macOS release.
- [ ] Signed Windows release.
- [ ] Linux package ecosystem coverage.
- [ ] Remote/API secure by default.
- [ ] Stable plugin/integration foundation.
- [ ] Full docs, troubleshooting, and support matrix.
- [ ] Public performance report.
- [ ] v2.0 launch screenshots and demo.

## Immediate Next Sprint

The next sprint should make the project safer and more credible before adding large new surfaces.

- [x] Add `clap`, `serde`, and `toml` dependencies for config/CLI.
- [x] Add config model with refresh interval, panel visibility, default sort, and window settings.
- [x] Add CLI flags for `--interval`, `--no-gpu`, `--version`, and `--help`.
- [x] Fix network rate math using elapsed time.
- [x] Replace history vectors with ring buffers.
- [x] Add unit tests for network rates and byte/rate formatting.
- [x] Add process kill confirmation and remove unused `show_kill_confirm` dead state if not needed.
- [x] Add `cargo fmt --check`, `cargo clippy`, and `cargo test` workflow.
- [x] Decide whether to remove the unused `gauge` widget or keep it behind a planned dashboard/preset story.
- [x] Generate Flatpak `cargo-sources.json` or document Flatpak as incomplete.
- [x] Add `docs/platform-support.md` with current actual support, not aspirational support.

## Source Links

- RustTop current repo files: `README.md`, `ROADMAP.md`, `Cargo.toml`, `src/main.rs`, `src/metrics/*`, `src/ui/*`, `.github/workflows/release.yml`, `io.github.sudoshi.RustTop.yml`.
- htop: https://htop.dev/ and https://man7.org/linux/man-pages/man1/htop.1.html
- btop: https://github.com/aristocratos/btop
- bottom: https://github.com/ClementTsang/bottom
- Glances: https://github.com/nicolargo/glances
- Mission Center: https://missioncenter.io/ and https://gitlab.com/mission-center-devs/mission-center
- GNOME System Monitor: https://apps.gnome.org/SystemMonitor/
- KDE Plasma System Monitor: https://apps.kde.org/plasma-systemmonitor/
- Apple Activity Monitor: https://support.apple.com/guide/activity-monitor/welcome/mac and https://support.apple.com/guide/activity-monitor/view-memory-usage-actmntr1004/mac
- Microsoft Process Explorer: https://learn.microsoft.com/en-us/sysinternals/downloads/process-explorer
- Microsoft Process Monitor: https://learn.microsoft.com/en-us/sysinternals/downloads/procmon
- HWiNFO: https://www.hwinfo.com/
- Open Hardware Monitor: https://openhardwaremonitor.org/
- Libre Hardware Monitor: https://github.com/LibreHardwareMonitor/LibreHardwareMonitor
- iStat Menus: https://bjango.com/mac/istatmenus/
- Stats: https://mac-stats.com/ and https://github.com/exelban/stats
- Netdata: https://www.netdata.cloud/ and https://www.netdata.cloud/features/
- psutil: https://psutil.readthedocs.io/
