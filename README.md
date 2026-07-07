<p align="center">
  <img src="assets/icons/rust_top_1024.png" width="160" height="160" alt="RustTop icon">
</p>

<h1 align="center">RustTop</h1>

<p align="center">
  <strong>A fast, polished, cross-platform system monitor built with Rust and iced.</strong>
</p>

<p align="center">
  <a href="#features">Features</a> &bull;
  <a href="#installation">Installation</a> &bull;
  <a href="#building-from-source">Build</a> &bull;
  <a href="#configuration">Configuration</a> &bull;
  <a href="#architecture">Architecture</a> &bull;
  <a href="docs/api.md">API</a> &bull;
  <a href="ROADMAP.md">Roadmap</a>
</p>

---

![RustTop Screenshot](assets/screenshot.png)

## Overview

RustTop is a desktop system monitor for Linux, macOS, and Windows. It pairs a GPU-accelerated `iced` interface with Rust-native collectors for CPU, memory, disk, network, process, GPU, battery, and sensor data.

The default dashboard is designed for real-time triage: large speedometer gauges show CPU, GPU, and memory pressure; detailed CPU, GPU, network, memory, and disk panels stay visible in the main window; and the right rail can switch between process inspection and thermal sensor detail.

## Current Release

The current release target is `v0.2.5`.

Release builds are produced by GitHub Actions from tags matching `v*`:

- Linux x86_64 release binary.
- Linux `.deb` package.
- Windows x86_64 executable.
- macOS universal `.app` zip for Intel and Apple Silicon.

## Features

- **System Load Gauges** - CPU, GPU, and system memory are shown side by side at the top of the app with speedometer-style gauges, colored green/yellow/red pressure bands, and live needles.
- **CPU** - Full-width utilization history plus a btop-style per-core panel. The layout reserves enough height for all visible cores before lower-priority GPU content.
- **Memory** - Dedicated system memory graph with percentage and used/total stats placed under the memory label. The memory panel sits above disk usage in the lower metrics column.
- **GPU** - Linux AMD discovery via sysfs, NVIDIA discovery through NVML, Intel Linux detection baselines, and macOS IOKit support. The panel shows VRAM, temperature, clock, power, fan RPM where available, and utilization history.
- **Disks** - Each mounted disk is represented by a text-free used-vs-available pie display plus mount point, filesystem, used/total space, free space, and read/write throughput details.
- **Network** - Download and upload rates with compact sparklines. Network remains prioritized over lower-urgency sensor details in the default layout.
- **Battery** - Battery status is represented in the header as a compact battery-shaped indicator with the percentage inside it when battery data is available.
- **Sensors** - Thermal readings from `sysinfo::Components` are available in the right-side Sensors view.
- **Processes** - Sortable process table with filter input, match highlighting, saved filters, tree/detail modes, configurable signal actions, keyboard navigation, persisted column presets, and virtualized scrolling for large hosts.
- **Processes/Sensors Toggle** - The right rail can switch between the process table and sensors, keeping the primary dashboard dense without hiding disk or network panels.
- **Settings + Layouts** - In-app settings strip for layout presets, compact mode, theme cycling, alert enablement, and process-table column presets.
- **History, Alerts, and Exports** - Persistent JSONL history, sustained-threshold alert evaluation, JSON/CSV snapshots, and incident bundle export for scripts, reports, and troubleshooting.
- **Optional Local API** - Default-off HTTP API with versioned JSON snapshots, active alerts, health checks, and Prometheus text metrics. Loopback is the safe default; non-loopback binds require a bearer token.
- **Adaptive Desktop Layout** - Panels use proportional sizing, rounded containers, and a compact 1200x800 default window with an 800x500 minimum.
- **Keyboard Workflow** - Common process and layout operations are available without leaving the keyboard.

## Installation

### Linux - GitHub Releases

Download the latest Linux binary or `.deb` package from the [Releases page](https://github.com/sudoshi/RustTop/releases).

```bash
# Portable binary
chmod +x rust_top-linux-amd64
./rust_top-linux-amd64

# Debian/Ubuntu package
sudo apt install ./rust-top_*.deb
rust_top
```

The `.deb` installs the desktop entry and icons, so RustTop should also appear in your application launcher.

### macOS

Download the macOS universal release zip, or build and install locally:

```bash
git clone https://github.com/sudoshi/RustTop.git
cd RustTop
./scripts/build-macos-app.sh --install
```

This builds the release binary, generates a proper `.icns` icon, assembles `RustTop.app`, and optionally installs it to `/Applications`.

First launch on macOS may require right-clicking the app and choosing **Open**, or clearing quarantine metadata:

```bash
xattr -cr /Applications/RustTop.app
```

### Windows

Download `rust_top-windows-x86_64.exe` from the [Releases page](https://github.com/sudoshi/RustTop/releases) and run it directly.

Windows support is improving. The release binary builds from CI, while deeper Windows-specific process, sensor, GPU, and installer work remains on the roadmap.

### From Source

The crate is not published to crates.io yet. Until then, install from GitHub Releases or build from source.

## Building From Source

### Prerequisites

Rust toolchain:

```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
```

Ubuntu/Debian system dependencies:

```bash
sudo apt install -y build-essential pkg-config libfontconfig1-dev \
    libxkbcommon-dev libwayland-dev libvulkan-dev
```

macOS requires Xcode Command Line Tools and Rust. Windows release builds use the MSVC Rust target.

### Build And Run

```bash
git clone https://github.com/sudoshi/RustTop.git
cd RustTop
cargo build --release --locked
./target/release/rust_top
```

### Build A Debian Package

```bash
cargo install cargo-deb
cargo build --release --locked
cargo deb --no-build
sudo apt install ./target/debian/rust-top_*.deb
```

### Build A macOS App Bundle

```bash
./scripts/build-macos-app.sh

# Or install to /Applications
./scripts/build-macos-app.sh --install
```

## CLI Usage

RustTop can run as a GUI, a one-shot exporter, or a headless API process.

```bash
# GUI
rust_top

# Custom config and refresh interval
rust_top --config ./rusttop.toml --interval 500

# Disable GPU collection and hide the GPU panel
rust_top --no-gpu

# Export one snapshot and exit
rust_top --export-json snapshot.json
rust_top --export-csv snapshot.csv
rust_top --export-json snapshot.json --export-csv snapshot.csv

# Append one JSONL history sample and exit
rust_top --record-history

# Write an incident bundle directory and exit
rust_top --incident-bundle rusttop-incident

# Start the local API
rust_top --api --api-addr 127.0.0.1:9977 --api-token local-dev-token
curl -H "Authorization: Bearer local-dev-token" http://127.0.0.1:9977/api/v1/snapshot
curl -H "Authorization: Bearer local-dev-token" http://127.0.0.1:9977/metrics
```

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `q` | Quit |
| `,` | Toggle settings |
| `/` | Focus process filter |
| `Esc` | Clear filter/selection |
| `Up` / `Down` | Select process |
| `Del` / `k` | Confirm then send selected signal |
| `s` | Cycle process signal action |
| `Enter` | Toggle process details |
| `t` | Toggle process tree mode |
| `f` / `w` | Cycle or save process filters |
| `c` | Cycle process column preset |
| `l` | Cycle layout preset |
| `m` | Toggle compact mode |
| `g` | Cycle theme |
| `F1` - `F5` | Sort process table |
| `Tab` | Reverse process sort direction |

## Configuration

RustTop creates a TOML config automatically when needed. You can also provide one explicitly:

```bash
rust_top --config ./rusttop.toml
```

Representative config:

```toml
[refresh]
interval_ms = 500

[appearance]
theme = "tokyo-night"
layout_preset = "balanced"
compact_mode = false

[panels]
cpu = true
memory = true
gpu = true
network = true
disk = true
battery = true
sensors = true
processes = true

[window]
width = 1200
height = 800
min_width = 800
min_height = 500

[process_table]
default_sort = "cpu"
sort_ascending = false
columns = ["pid", "name", "cpu", "memory", "status"]
saved_filters = []

[history]
enabled = false
interval_seconds = 60
retention_samples = 1440

[alerts]
enabled = true
desktop_notifications = false
min_duration_seconds = 10
cpu_percent = 90.0
memory_percent = 90.0
swap_percent = 50.0
disk_used_percent = 90.0
sensor_warm_c = 75.0
sensor_critical_c = 90.0
gpu_temperature_c = 85.0
gpu_vram_percent = 90.0
battery_low_percent = 15.0
battery_health_percent = 70.0

[api]
enabled = false
address = "127.0.0.1:9977"
# token = "replace-me"
```

Layout presets:

- `balanced` - default dashboard with CPU, GPU, network, memory, disks, and right-side process/sensor views.
- `focus-processes` - keeps CPU, memory, network, and process inspection prominent.
- `minimal` - trims the interface to core CPU, memory, and network monitoring.

## Architecture

```text
src/
├── api.rs                     # Default-off local HTTP API and Prometheus endpoint
├── alerts.rs                  # Sustained-threshold alert engine
├── config.rs                  # TOML config, CLI, runtime options
├── export.rs                  # JSON/CSV snapshots, JSONL history, incident bundles
├── main.rs                    # Entry point, window config, icon, mode selection
├── metrics/                   # Data collection with no GUI dependencies
│   ├── battery.rs             # Battery capacity/health/status
│   ├── collector.rs           # SystemMetrics orchestration
│   ├── cpu.rs                 # CPU totals, per-core usage, history
│   ├── disk.rs                # Mount points, capacity, disk I/O rates
│   ├── gpu.rs                 # AMD/NVIDIA/Intel/macOS GPU telemetry
│   ├── history.rs             # Ring-buffer metric history
│   ├── memory.rs              # RAM and swap metrics
│   ├── network.rs             # Interface RX/TX rates
│   ├── process.rs             # Process sorting, filtering, tree state, signals
│   ├── sensors.rs             # Thermal component readings
│   └── units.rs               # Shared binary byte/rate formatting
├── theme/
│   ├── colors.rs              # Palette, alpha helpers, heat colors
│   └── mod.rs                 # Custom iced theme definitions
└── ui/
    ├── app.rs                 # Main app state, update, layout, subscriptions
    └── widgets/
        ├── cpu_cores.rs       # Per-core bars and activity dots
        ├── disk_bar.rs        # Disk pie displays and capacity details
        ├── gpu_view.rs        # VRAM, GPU stats, utilization graph
        ├── graph.rs           # Canvas sparkline graphs
        ├── header.rs          # Host summary and header battery indicator
        ├── network_view.rs    # RX/TX sparklines
        ├── power_sensors.rs   # Sensor panel
        ├── process_table.rs   # Sortable/filterable virtualized process table
        ├── settings_panel.rs  # Layout/theme/compact/settings controls
        └── utilization_gauges.rs # CPU/GPU/memory speedometer gauges
```

The intended boundary is simple: `metrics/` collects and normalizes data, `ui/widgets/` renders data, and `app.rs` coordinates state, input, refresh, history persistence, and layout.

## Tech Stack

| Component | Choice |
|-----------|--------|
| Language | Rust 2021 |
| GUI | `iced` 0.13 with canvas, tokio, advanced, and image features |
| Windowing | `iced_winit` with Wayland support |
| System info | `sysinfo` |
| CLI | `clap` |
| Config | `serde`, `serde_json`, `toml` |
| Time | `chrono` |
| Color | `palette` plus project theme helpers |
| NVIDIA GPU | `nvml-wrapper`, dynamically loaded at runtime |
| Linux AMD/Intel GPU | sysfs discovery and metrics where exposed |
| macOS GPU | IOKit data via `ioreg` |

## Platform Support

| Capability | Linux | macOS | Windows |
|------------|-------|-------|---------|
| Desktop UI | Supported | Supported | Experimental |
| CPU and memory | Supported | Supported | Supported through `sysinfo` |
| Process table | Supported | Supported | Baseline support |
| Disk and network | Supported | Supported | Baseline support |
| Battery | Supported where exposed | Partial | Partial |
| Sensors | Platform dependent | Platform dependent | Platform dependent |
| AMD GPU | sysfs | IOKit baseline | Planned |
| NVIDIA GPU | NVML | NVML if available | NVML if available |
| Release artifact | Binary + `.deb` | Universal app zip | `.exe` |

See `docs/platform-support.md`, `docs/platform-capability-matrix.md`, and `docs/gpu-support-matrix.md` for deeper detail.

## Release Process

Local preflight:

```bash
cargo fmt --check
git diff --check
cargo check --locked
cargo clippy --all-targets --all-features --locked -- -D warnings
cargo test --locked
cargo build --release --locked
cargo deb --no-build
```

Cut a release:

```bash
git tag -a v0.2.5 -m "Release v0.2.5"
git push origin main
git push origin v0.2.5
```

Pushing the tag starts `.github/workflows/release.yml`, which builds platform artifacts and creates the GitHub release.

## Troubleshooting

**No GPU panel on Linux?** AMD and Intel discovery use `/sys/class/drm/card*/device/`. NVIDIA requires installed NVIDIA drivers and NVML. Use `--no-gpu` if GPU probing is not useful on a host.

**No GPU panel on macOS?** macOS GPU telemetry depends on IOKit `IOAccelerator` data. You can inspect availability with:

```bash
ioreg -r -c IOAccelerator -l -w 0 | grep PerformanceStatistics
```

**Wayland rendering issue?** Force X11 for a quick comparison:

```bash
WAYLAND_DISPLAY= rust_top
```

**Linux icon not showing?** Refresh the icon cache:

```bash
sudo gtk-update-icon-cache -f -t /usr/share/icons/hicolor
```

**macOS Dock icon not refreshing?** Restart Finder and Dock:

```bash
killall Finder && killall Dock
```

## Contributing

Contributions are welcome. Useful areas include:

- Deeper Intel GPU telemetry.
- Windows-native GPU, process, sensor, and installer support.
- Apple Silicon GPU metrics.
- Flatpak completion.
- Additional package formats such as RPM, AppImage, Homebrew, winget, and Chocolatey.
- Accessibility, keyboard workflow, and performance profiling.

## License

MIT
