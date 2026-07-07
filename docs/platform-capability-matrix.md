# RustTop Platform Capability Matrix

This matrix summarizes current runtime capability by platform.

| Capability | Linux | macOS | Windows |
| --- | --- | --- | --- |
| Desktop UI | Supported | Build path exists | Build path exists |
| CPU and memory | Supported through `sysinfo` | Partial through `sysinfo` | Experimental through `sysinfo` |
| Disk capacity and I/O | Supported through `sysinfo::Disks` | Partial through `sysinfo::Disks` | Experimental through `sysinfo::Disks` |
| Network rates | Supported through `sysinfo::Networks` | Partial through `sysinfo::Networks` | Experimental through `sysinfo::Networks` |
| Processes | Supported through `sysinfo` | Partial through `sysinfo` | Experimental through `sysinfo` |
| Battery | Linux `/sys/class/power_supply` baseline | Unsupported | Unsupported |
| Thermal sensors | `sysinfo::Components` baseline | `sysinfo::Components` baseline if exposed | `sysinfo::Components` baseline if exposed |
| AMD GPU | Supported baseline | Partial IOAccelerator path | Unsupported |
| NVIDIA GPU | NVML baseline | Unsupported | Experimental NVML baseline |
| Intel GPU | Linux sysfs detection baseline | Unsupported | Unsupported |
| JSON/CSV export and incident bundles | Supported | Partial | Experimental |
| Local HTTP API and Prometheus endpoint | Supported | Partial | Experimental |
| Remote pairing/WebSocket/OpenTelemetry | Unsupported | Unsupported | Unsupported |

## Tiering Notes

- "Supported" means there is current code and local tests or a stable generic backend.
- "Partial" means code exists, but runtime parity and smoke coverage are incomplete.
- "Experimental" means the build path exists, but runtime behavior is not yet a Tier 1 contract.
