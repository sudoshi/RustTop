# RustTop — Beautiful System Monitor

## Project Status
This is a fully working Rust GUI system monitor built with `iced` (GPU-accelerated) and `sysinfo`.
It compiles and runs on macOS. Now being moved to Ubuntu Linux for native .deb packaging and AMD GPU testing.

## What's Built
- **CPU**: Global gauge, history graph, per-core bars with btop-style activity dots
- **Memory/Swap**: Gauges + history graphs
- **Network**: RX/TX rate graphs per interface
- **Disks**: Usage per mount point with heat-colored percentages
- **GPU (AMD + NVIDIA)**: AMD via sysfs (`/sys/class/drm/card*/device/`), NVIDIA via NVML (nvml-wrapper crate, dynamically loads libnvidia-ml). Both show utilization, VRAM, temp, clocks, power, fan. Auto-discovers at startup. Shows "No GPU detected" gracefully when none found.
- **Processes**: Sortable (PID/Name/CPU/Mem/Status), filterable, scrollable
- **Theme**: Dark Tokyo Night palette, neon accents, heat colors (green->yellow->red)
- **Refresh**: 500ms interval

## Architecture
```
src/
├── main.rs                    # Entry point, iced app config (1200x800 window)
├── metrics/                   # Data collection layer
│   ├── collector.rs           # SystemMetrics orchestrator
│   ├── cpu.rs, memory.rs      # Per-core history, usage tracking
│   ├── disk.rs, network.rs    # Disk/network stats
│   ├── gpu.rs                 # GPU metrics (AMD sysfs + NVIDIA NVML)
│   └── process.rs             # Process list with sort/filter/kill
├── theme/
│   ├── mod.rs                 # Custom iced dark theme
│   └── colors.rs              # Full color palette + heat_color() + lerp
└── ui/
    ├── app.rs                 # Main app state, update, view, subscription
    └── widgets/               # All visual components
        ├── graph.rs           # Canvas sparkline with gradient fill + glow dot
        ├── gauge.rs           # Arc gauge with heat coloring
        ├── cpu_cores.rs       # btop-style per-core bars + activity dots
        ├── gpu_view.rs        # AMD GPU panel (gauges + graphs + stats)
        ├── header.rs, disk_bar.rs, network_view.rs, process_table.rs
```

## Next Steps on Ubuntu
1. **Install Rust**: `curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh`
2. **Install build deps**: `sudo apt install -y build-essential pkg-config libfontconfig1-dev libxkbcommon-dev libwayland-dev libvulkan-dev`
3. **Build release**: `cargo build --release`
4. **Test the app**: `./target/release/rust_top` — verify AMD GPU panel lights up with real data
5. **Build .deb**: `cargo install cargo-deb && cargo deb`
6. **Install**: `sudo apt install ./target/debian/rust-top_0.1.0-1_amd64.deb`
7. **Verify**: Run `rust_top` from terminal or find "RustTop" in app launcher

## Packaging
- `cargo-deb` config is in `[package.metadata.deb]` in Cargo.toml
- Desktop file: `assets/rust_top.desktop`
- Icon: `assets/icons/rust_top.svg`
- Post-install scripts: `debian/postinst`, `debian/postrm`

## Known Issues to Watch For
- If iced fails to find a GPU backend on Linux, it falls back to tiny-skia (CPU rendering) — still works but slower
- Wayland vs X11: iced supports both, but if there are issues try `WAYLAND_DISPLAY= ./target/release/rust_top` to force X11
- The `$auto` depends in cargo-deb will properly detect shared lib deps when built natively on Linux
- AMD GPU sysfs paths may vary — `gpu.rs` auto-discovers by scanning `/sys/class/drm/card*/device/vendor` for 0x1002
- NVIDIA GPU requires NVIDIA drivers with libnvidia-ml.so — nvml-wrapper loads it dynamically at runtime, compiles fine without it
