# RustTop Platform Support

This page documents what the current checkout actually supports. It is not a
v2.0 target matrix and does not promise parity across operating systems.

## Current Support Summary

| Platform | Current status | Notes |
| --- | --- | --- |
| Linux | Primary current runtime target | Common metrics are collected through `sysinfo`; AMD GPU metrics use Linux sysfs; NVIDIA GPU metrics use NVML when available. |
| macOS | Build path exists; runtime support is partial | Common metrics are collected through `sysinfo`; GPU metrics use an IOKit/`ioreg` IOAccelerator path when those performance fields are exposed. |
| Windows | Build path exists; runtime support is experimental | Release CI builds a Windows binary, but there is no Windows-specific metrics backend beyond `sysinfo` and the non-macOS NVML path. |
| BSD and other Unix platforms | Unsupported | No CI target, packaging, or platform-specific support contract exists. |

## Feature Matrix

| Feature | Linux | macOS | Windows | Current implementation |
| --- | --- | --- | --- | --- |
| Desktop UI | Supported | Partial | Experimental | `iced` desktop app with bundled icon and a 1200x800 default window. |
| CPU usage | Supported | Partial | Experimental | `sysinfo` global and per-core usage with in-memory history. |
| Memory and swap | Supported | Partial | Experimental | `sysinfo` total, used, available, swap, and usage percentages. |
| Disk filesystem usage and I/O | Supported | Partial | Experimental | `sysinfo::Disks`; mount point, filesystem, used/total, removable flag, and read/write throughput from `Disk::usage()`. No SMART metrics. |
| Network counters | Supported | Partial | Experimental | `sysinfo::Networks`; rates are calculated from byte deltas and elapsed monotonic time. |
| Process list | Supported | Partial | Experimental | `sysinfo` process list, sort, filter, selected-row navigation, tree mode, saved filters, and virtualized scrolling. |
| Process details/actions | Limited | Limited | Limited | Details, guarded TERM/KILL/STOP/CONT action picker, and process tree are implemented; priority, affinity, handles, modules, open files, and sockets are not. |
| AMD GPU | Supported on Linux AMDGPU sysfs | Partial through macOS IOAccelerator path | Unsupported | Linux discovers vendor `0x1002` under `/sys/class/drm`; macOS reads IOAccelerator performance statistics where present. |
| NVIDIA GPU | Supported when NVML is available | Unsupported in current macOS build | Experimental when NVML is available | `nvml-wrapper` is compiled on non-macOS targets and dynamically initializes NVML at runtime. |
| Intel GPU | Linux detection baseline | Unsupported | Unsupported | Linux discovers vendor `0x8086` under `/sys/class/drm`; telemetry is limited to sysfs fields where exposed. |
| Battery and power | Linux baseline | Unsupported | Unsupported | Linux reads `/sys/class/power_supply` battery capacity, status, and health where exposed; other platforms show an empty fallback. |
| CPU temperature, fans, voltages, sensors | Thermal baseline | Thermal baseline if exposed by `sysinfo` | Thermal baseline if exposed by `sysinfo` | General thermal sensors use `sysinfo::Components`; fan/voltage/power hwmon parsing is not implemented yet. |
| Tray, menu bar, or notification area | Unsupported | Unsupported | Unsupported | No always-visible compact monitor exists. |
| Local history/export/API mode | Supported | Partial | Experimental | JSON/CSV snapshots, JSONL history, incident bundles, default-off token-protected local HTTP API, and Prometheus text endpoint exist. No WebSocket, OpenTelemetry, or remote pairing yet. |

## Linux Details

Linux is the only platform with first-class in-repo monitoring paths beyond the
cross-platform `sysinfo` collectors.

- CPU, memory, swap, disk usage, network counters, and process data come from
  `sysinfo`.
- Disk read/write throughput uses `sysinfo::Disk::usage()` deltas from a
  persistent `Disks` handle.
- Battery capacity/status/health is read from `/sys/class/power_supply` where
  the kernel exposes battery entries.
- General thermal readings come from `sysinfo::Components`.
- AMD GPUs are discovered from `/sys/class/drm/card*/device` when the device
  vendor is `0x1002`.
- AMD GPU fields include utilization, VRAM total/used, edge/junction/memory
  temperatures where exposed, clocks, power, and fan readings where the sysfs
  or hwmon files exist.
- NVIDIA GPUs are discovered through NVML when the NVIDIA driver exposes NVML
  to the process.
- Intel GPU monitoring has a Linux sysfs detection baseline, but no full i915/xe engine telemetry.
- Process kill requires a second `k` or `Delete` keypress for the selected PID.
  Signal selection is available in the process table workflow.
- One-shot JSON/CSV exports, JSONL history, incident bundles, and the token-protected local API are available on Linux.

## macOS Details

macOS has a build and app-bundle path, but the runtime matrix is not yet backed
by in-repo macOS smoke tests.

- Common CPU, memory, disk, network, and process data relies on `sysinfo`.
- General thermal readings rely on `sysinfo::Components` when available.
- `scripts/build-macos-app.sh` assembles a local `.app` bundle.
- Release CI builds a universal macOS artifact on tagged releases.
- GPU metrics use `ioreg -r -c IOAccelerator -l -w 0` and
  `system_profiler SPDisplaysDataType`.
- Apple Silicon GPU, energy, battery, fan, and menu-bar support are not
  implemented.

## Windows Details

Windows currently has build coverage but not a documented runtime support
contract.

- Release CI builds an `x86_64-pc-windows-msvc` binary on tagged releases.
- Common metrics depend on `sysinfo`.
- General thermal readings rely on `sysinfo::Components` when available.
- There is no Windows-specific backend for battery, PDH, WMI/CIM, DXGI, services,
  handles, modules, per-process I/O, notifications, installers, or code
  signing.
- NVIDIA GPU data may be available only if the non-macOS NVML path initializes
  successfully at runtime.
- AMD and Intel GPU monitoring are not implemented.

## Packaging Status

| Package path | Status |
| --- | --- |
| GitHub release binaries | Release workflow exists for Linux, macOS, and Windows tag builds. |
| Debian package | `cargo-deb` metadata and Debian maintainer scripts exist. |
| macOS app bundle | Local app-bundle script and release workflow assembly exist. |
| Flatpak | Incomplete; see `docs/flatpak-status.md`. |
| crates.io, Homebrew, AUR, winget, Snap | Not documented as complete in this checkout. |

## Known Validation Gaps

- The committed Rust test suite now exercises collector math and selected
  Linux fixture fallbacks, but runtime platform smoke tests are still missing.
- No in-repo platform smoke scripts exist for Linux, macOS, or Windows runtime
  behavior.
- CI build coverage and runtime feature support are separate; a platform that
  compiles is not necessarily feature-complete.
- The Flatpak manifest has not been validated with generated cargo sources or
  the required sandbox permissions.
- Local API and export paths have Linux smoke coverage, but no macOS or Windows
  runtime smoke coverage yet.
