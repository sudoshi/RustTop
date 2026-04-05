# RustTop — Beautiful System Monitor

## Project Status
Fully working Rust GUI system monitor built with `iced` (GPU-accelerated) and `sysinfo`.
Running on Ubuntu Linux with .deb packaging, GitHub Releases CI, and AMD GPU support verified.
v0.1.1 released via GitHub Actions.

## What's Built
- **CPU**: Global gauge, history graph, per-core bars with btop-style activity dots
- **Memory/Swap**: Gauges + history graphs
- **Network**: RX/TX rate graphs per interface
- **Disks**: Usage per mount point with heat-colored percentages
- **GPU (AMD + NVIDIA)**: AMD via sysfs (`/sys/class/drm/card*/device/`), NVIDIA via NVML (nvml-wrapper crate, dynamically loads libnvidia-ml). Both show utilization, VRAM, temp, clocks, power, fan. Auto-discovers at startup. Shows "No GPU detected" gracefully when none found.
- **Processes**: Sortable (PID/Name/CPU/Mem/Status), filterable, keyboard-navigable with selection and kill support
- **Keyboard Shortcuts**: q quit, / filter, Esc clear, Up/Down select, k/Del kill, F1-F5 sort, Tab reverse. Help bar at bottom.
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
    ├── app.rs                 # Main app state, update, view, keyboard subscription
    └── widgets/               # All visual components
        ├── graph.rs           # Canvas sparkline with gradient fill + glow dot
        ├── gauge.rs           # Arc gauge with heat coloring (available, unused)
        ├── cpu_cores.rs       # btop-style 4-column per-core bars + activity dots
        ├── gpu_view.rs        # GPU panel (AMD red / NVIDIA green, bars + stats + graph)
        ├── header.rs          # System info bar (hostname, kernel, uptime)
        ├── disk_bar.rs        # Disk usage with heat-colored percentages
        ├── network_view.rs    # RX/TX sparkline graphs
        └── process_table.rs   # Sortable, filterable, selectable process list
```

## Packaging & Distribution
- **GitHub Actions CI**: `.github/workflows/release.yml` — builds on tag push, creates GitHub Release with binary + .deb
- **cargo-deb**: `[package.metadata.deb]` in Cargo.toml
- **Flatpak**: `io.github.sudoshi.RustTop.yml` manifest (needs `cargo-sources.json` from `flatpak-cargo-generator.py`)
- **crates.io**: Cargo.toml has repository, homepage, keywords, categories — ready for `cargo publish`
- **Desktop file**: `assets/rust_top.desktop`
- **Icons**: `assets/icons/rust_top.svg` + PNG at 48/128/256px
- **Post-install scripts**: `debian/postinst`, `debian/postrm`

## Known Issues to Watch For
- If iced fails to find a GPU backend on Linux, it falls back to tiny-skia (CPU rendering) — still works but slower
- Wayland vs X11: iced supports both, but if there are issues try `WAYLAND_DISPLAY= ./target/release/rust_top` to force X11
- The `$auto` depends in cargo-deb will properly detect shared lib deps when built natively on Linux
- AMD GPU sysfs paths may vary — `gpu.rs` auto-discovers by scanning `/sys/class/drm/card*/device/vendor` for 0x1002
- NVIDIA GPU requires NVIDIA drivers with libnvidia-ml.so — nvml-wrapper loads it dynamically at runtime, compiles fine without it
