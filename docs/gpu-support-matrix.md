# RustTop GPU Support Matrix

This matrix reflects the current checkout, not the full v2.0 target.

| GPU family | Linux | macOS | Windows | Current backend |
| --- | --- | --- | --- | --- |
| AMD | Supported baseline | Partial | Unsupported | Linux AMDGPU sysfs for utilization, VRAM, thermal, clocks, power, and fans where exposed; macOS IOAccelerator path where exposed. |
| NVIDIA | Supported when NVML is available | Unsupported | Experimental when NVML is available | Runtime NVML initialization through `nvml-wrapper` on non-macOS targets. |
| Intel | Linux detection baseline | Unsupported | Unsupported | Linux DRM sysfs vendor detection with thermal/power/utilization fields where kernel files exist. |
| Apple Silicon | Unsupported | Unsupported | Not applicable | No Metal/IOReport backend yet. |

## Current Limits

- GPU support is read-only monitoring.
- Intel support is a Linux sysfs baseline, not a full i915/xe engine telemetry backend.
- Windows GPU support still needs a DXGI/PDH/WMI strategy.
- Apple Silicon still needs a separate macOS backend.
- Multi-GPU rendering exists through the current device list, but detailed per-device workflows are still basic.
