# RustTop Platform Support

This page documents what the current checkout actually supports. It is not a
v2.0 target matrix and does not promise parity across operating systems.

## Current Support Summary

| Platform                     | Current status                                                      | Notes                                                                                                                                                                                                                        |
| ---------------------------- | ------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Linux                        | Primary current runtime target                                      | Common metrics are collected through `sysinfo`; AMD GPU metrics use Linux sysfs; NVIDIA GPU metrics use NVML when available.                                                                                                 |
| macOS                        | Rust and native Tahoe build paths exist; runtime support is partial | Common metrics are collected through `sysinfo`; GPU metrics use an IOKit/`ioreg` IOAccelerator path when those performance fields are exposed; the native Tahoe shell embeds the Rust helper and decodes snapshot schema v1. |
| Windows                      | Build path exists; runtime support is experimental                  | Release CI builds a Windows binary, but there is no Windows-specific metrics backend beyond `sysinfo` and the non-macOS NVML path.                                                                                           |
| BSD and other Unix platforms | Unsupported                                                         | No CI target, packaging, or platform-specific support contract exists.                                                                                                                                                       |

## Feature Matrix

| Feature                                  | Linux                            | macOS                                    | Windows                                  | Current implementation                                                                                                                                                                                  |
| ---------------------------------------- | -------------------------------- | ---------------------------------------- | ---------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Desktop UI                               | Supported                        | Partial                                  | Experimental                             | `iced` desktop app with bundled icon and a 1200x800 default window. macOS also has a native SwiftUI Tahoe shell under `macos/RustTopTahoe`.                                                             |
| CPU usage                                | Supported                        | Partial                                  | Experimental                             | `sysinfo` global and per-core usage with in-memory history.                                                                                                                                             |
| Memory and swap                          | Supported                        | Partial                                  | Experimental                             | `sysinfo` total, used, available, swap, and usage percentages. macOS also samples `vm_stat` for optional pressure, app, wired, compressed, and file-cache fields.                                       |
| Disk filesystem usage and I/O            | Supported                        | Partial                                  | Experimental                             | `sysinfo::Disks`; mount point, filesystem, used/total, removable flag, and read/write throughput from `Disk::usage()`. macOS filters APFS system companion volumes from summary rows. No SMART metrics. |
| Network counters                         | Supported                        | Partial                                  | Experimental                             | `sysinfo::Networks`; rates are calculated from byte deltas and elapsed monotonic time. JSON snapshots include total and per-interface rates/counters.                                                   |
| Process list                             | Supported                        | Partial                                  | Experimental                             | `sysinfo` process list, sort, filter, selected-row navigation, tree mode, saved filters, and virtualized scrolling.                                                                                     |
| Process details/actions                  | Limited                          | Limited                                  | Limited                                  | Details, guarded TERM/KILL/STOP/CONT action picker, and process tree are implemented; priority, affinity, handles, modules, open files, and sockets are not.                                            |
| AMD GPU                                  | Supported on Linux AMDGPU sysfs  | Partial through macOS IOAccelerator path | Unsupported                              | Linux discovers vendor `0x1002` under `/sys/class/drm`; macOS reads IOAccelerator performance statistics where present.                                                                                 |
| NVIDIA GPU                               | Supported when NVML is available | Unsupported in current macOS build       | Experimental when NVML is available      | `nvml-wrapper` is compiled on non-macOS targets and dynamically initializes NVML at runtime.                                                                                                            |
| Intel GPU                                | Linux detection baseline         | Unsupported                              | Unsupported                              | Linux discovers vendor `0x8086` under `/sys/class/drm`; telemetry is limited to sysfs fields where exposed.                                                                                             |
| Battery and power                        | Linux baseline                   | Partial                                  | Unsupported                              | Linux reads `/sys/class/power_supply` battery capacity, status, and health where exposed. macOS reads `AppleSmartBattery` fields where `ioreg` exposes them.                                            |
| CPU temperature, fans, voltages, sensors | Thermal baseline                 | Thermal baseline if exposed by `sysinfo` | Thermal baseline if exposed by `sysinfo` | General thermal sensors use `sysinfo::Components`; fan/voltage/power hwmon parsing is not implemented yet.                                                                                              |
| Tray, menu bar, or notification area     | Unsupported                      | Partial                                  | Unsupported                              | The native Tahoe shell includes a `MenuBarExtra` for compact CPU, memory, and network monitoring; the Rust `iced` app has no tray/menu-bar surface.                                                     |
| Local history/export/API mode            | Supported                        | Partial                                  | Experimental                             | JSON/CSV snapshots, JSONL history, incident bundles, default-off token-protected local HTTP API, and Prometheus text endpoint exist. No WebSocket, OpenTelemetry, or remote pairing yet.                |

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

macOS has the existing Rust app-bundle path plus a native Tahoe shell. The Tahoe
shell is currently a Swift Package executable at `macos/RustTopTahoe`; the local
bundle script embeds the Rust helper at
`RustTopTahoe.app/Contents/Resources/rust_top` and the app decodes the helper's
current `schema_version = 1` JSON snapshot.

| Collector area                                    | Current macOS Tahoe status | Privacy and limitations                                                                                                                                                                                                                                         |
| ------------------------------------------------- | -------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| CPU, memory, disk, network, and process summaries | Partial                    | Collected by the Rust helper through `sysinfo`. Process names, PIDs, memory, CPU, status, disk, and network counters are local-only but may reveal user workload metadata on screen or in exported snapshots.                                                   |
| Memory pressure and memory class breakdown        | Partial                    | The Rust helper parses `vm_stat` for app, wired, compressed, file-cache, and approximate pressure fields. This is unprivileged and local-only, but it is an approximation rather than Activity Monitor's private memory model.                                  |
| Disk usage and rates                              | Partial                    | Uses `sysinfo` disk data and rates. APFS system companion volumes such as `/System/Volumes/Data` are hidden from summary rows to avoid duplicate root/Data presentation. SMART/health data is not implemented.                                                  |
| Network rates                                     | Partial                    | Uses interface counters from `sysinfo`. JSON snapshots include per-interface rates and counters. Wi-Fi SSID, signal, channel, and location-derived metadata are not collected.                                                                                  |
| GPU                                               | Partial                    | Uses `ioreg -r -c IOAccelerator -l -w 0` and `system_profiler SPDisplaysDataType` where fields are exposed. Apple Silicon GPU coverage is not a dedicated backend yet, and available fields vary by hardware and OS release.                                    |
| Battery and power                                 | Partial                    | The Rust helper parses unprivileged `AppleSmartBattery` `ioreg` output for capacity, health, cycle count, power source, and adapter watts when present. Field names and availability can vary by Mac model and OS release.                                      |
| Thermals and sensors                              | Partial                    | General thermal readings depend on `sysinfo::Components` availability. Public thermal-state handling is planned through `ProcessInfo.thermalState`; fan speed, fan control, voltage, and privileged sensor paths remain out of scope for Tahoe v1.              |
| Per-process energy impact                         | Unsupported                | Activity Monitor-style Energy Impact is not reproduced. The Tahoe strategy is a clearly labeled energy-pressure approximation based only on supportable local process signals.                                                                                  |
| Wi-Fi metadata                                    | Intentionally unavailable  | CoreWLAN is the supportable future path for opt-in link metadata. SSID/BSSID display and nearby-network scans are not default behavior because they can reveal location or workplace context.                                                                   |
| launchd services and agents                       | Partial                    | The Rust helper inventories readable standard launchd plist locations and the native Tahoe Services section displays labels, scope, type, source path, and installed state. Enable/disable/bootstrap actions are not part of the Tahoe v1 target.               |
| Menu bar monitoring and notifications             | Partial                    | The native Tahoe app includes a configurable `MenuBarExtra` for compact CPU, memory, network, active alerts, and optional GPU/temperature stats. Sustained alerts can be delivered through Notification Center when enabled, and an optional Dock graph exists. |

The macOS collector does not send telemetry to a remote service. Exports,
history files, incident bundles, and the optional local API can still contain
host and workload details, so users should treat them as potentially sensitive.
The local HTTP API remains default-off and token-protected when enabled.

### macOS Hardware Scope

| Mac class              | Current expectation                                                                                                                                                                                                                                              |
| ---------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Apple Silicon laptops  | CPU, memory, disk, network, process, APFS filtering, menu-bar monitoring, `vm_stat` pressure, and `AppleSmartBattery` fields should be available. GPU fields remain best-effort through IOAccelerator output and are not a dedicated Apple Silicon backend yet.  |
| Apple Silicon desktops | Same as Apple Silicon laptops except battery fields are expected to be absent. Missing battery cards are normal.                                                                                                                                                 |
| Intel laptops          | CPU, memory, disk, network, process, APFS filtering, menu-bar monitoring, `vm_stat` pressure, and `AppleSmartBattery` fields should be available where macOS exposes them. GPU fields remain best-effort and can vary by integrated/discrete GPU and OS release. |
| Intel desktops         | Same as Intel laptops except battery fields are expected to be absent. Missing battery cards are normal.                                                                                                                                                         |

The current checkout has parser and export tests plus local helper smoke tests,
but not a committed Apple Silicon and Intel hardware lab matrix. Treat hardware
specific GPU, sensor, and battery gaps as expected partial support until those
manual runs are recorded.

The more detailed Tahoe telemetry strategy lives in
[`docs/macos-tahoe-telemetry.md`](macos-tahoe-telemetry.md).

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

| Package path                           | Status                                                                                                                                                                                                                                                                                                                |
| -------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| GitHub release binaries                | Release workflow exists for Linux, macOS, and Windows tag builds.                                                                                                                                                                                                                                                     |
| Debian package                         | `cargo-deb` metadata and Debian maintainer scripts exist.                                                                                                                                                                                                                                                             |
| macOS app bundle                       | Local app-bundle scripts exist for the Rust app and native Tahoe shell. The Tahoe build script can sign when Developer ID variables are provided, can package versioned zip/DMG artifacts, writes SHA-256 sidecars, and has opt-in notarization/stapling hooks. Clean-Mac notarized install validation is still open. |
| Flatpak                                | Incomplete; see `docs/flatpak-status.md`.                                                                                                                                                                                                                                                                             |
| crates.io, Homebrew, AUR, winget, Snap | Not documented as complete in this checkout.                                                                                                                                                                                                                                                                          |

## Known Validation Gaps

- The committed Rust test suite now exercises collector math and selected
  Linux fixture fallbacks, but runtime platform smoke tests are still missing.
- The Tahoe workflow includes a macOS bundle smoke path for tag/manual runs, but
  it has not replaced hardware-specific manual validation.
- CI build coverage and runtime feature support are separate; a platform that
  compiles is not necessarily feature-complete.
- The Flatpak manifest has not been validated with generated cargo sources or
  the required sandbox permissions.
- Local API and export paths have Linux smoke coverage. The Tahoe workflow
  validates one macOS helper JSON export path when the bundle build runs, but
  broader macOS and Windows runtime smoke coverage is still missing.
