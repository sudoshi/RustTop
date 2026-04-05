# Roadmap: v0.1.1 → v0.2.0

## Theme

**"Run anywhere, monitor everything."**

v0.1 proved the concept — a gorgeous system monitor that people actually want to look at. v0.2 closes the gaps that prevent RustTop from being someone's daily driver.

---

## Milestone 1: Complete GPU Coverage

- [ ] **Intel iGPU support** — Read from `/sys/class/drm/card*/device/` with vendor `0x8086`, expose utilization via `i915` perf counters or `xe` driver metrics. Covers the majority of Linux laptops.
- [ ] **Multi-GPU display** — Verify layout works cleanly when 2+ GPUs are detected (e.g., iGPU + discrete). Stack panels or tab between them.

## Milestone 2: Configuration

- [ ] **Config file** — `~/.config/rust_top/config.toml` with:
  - Refresh interval (default 500ms)
  - Panel visibility toggles (hide GPU, hide network, etc.)
  - Window size and position memory
  - Process table default sort field
- [ ] **Command-line flags** — `--interval`, `--no-gpu`, `--version`, `--help` via `clap`

## Milestone 3: Laptop & Power

- [ ] **Battery panel** — Charge percentage, time remaining, charging state, power draw. `sysinfo` already exposes battery data — just needs a widget.
- [ ] **Thermal overview** — CPU package temp, fan speeds (not just GPU). Read from hwmon or `sysinfo` sensors.

## Milestone 4: Process Management

- [ ] **Process detail expansion** — Press Enter on a selected process to see full command line, environment, open files, threads, parent PID, start time
- [ ] **Signal selection** — Choose signal to send (SIGTERM, SIGKILL, SIGSTOP, SIGCONT) instead of just kill
- [ ] **Tree view** — Optional parent/child process tree, toggled with `t`

## Milestone 5: Distribution

- [ ] **Publish to crates.io** — `cargo install rust_top` working end-to-end
- [ ] **AUR package** — PKGBUILD for Arch Linux users
- [ ] **Flatpak on Flathub** — Generate `cargo-sources.json`, submit to Flathub for review
- [ ] **macOS verification** — Ensure the binary builds and runs on macOS (iced + sysinfo are cross-platform, GPU panel gracefully degrades)
- [ ] **Homebrew formula** — For macOS users, once macOS build is verified

## Milestone 6: Polish

- [ ] **New screenshot** — Capture updated UI with keyboard shortcuts help bar, GPU panel, and process selection for README
- [ ] **Scroll-to-selection** — Auto-scroll process list when arrow keys move selection off-screen
- [ ] **Search highlight** — Highlight matching text in process names when filter is active
- [ ] **Swap panel** — Dedicated swap usage graph (currently folded into memory)
- [ ] **About dialog** — Version, license, links — shown with `?` key

---

## Non-Goals for v0.2.0

These are interesting but out of scope for this release:

- **Windows support** — Requires significant testing and GPU backend work. Revisit for v0.3.
- **Plugin system** — Custom metric panels (Docker, K8s, databases). Needs a stable internal API first.
- **Remote monitoring** — SSH or agent-based monitoring of other machines.
- **Logging / export** — CSV or JSON export of metric history.

---

## Release Criteria

v0.2.0 ships when:

1. Intel + AMD + NVIDIA GPUs all work (or gracefully degrade)
2. Config file exists and persists user preferences
3. Battery panel works on laptops
4. Published to crates.io and AUR
5. README screenshot reflects current UI
6. No panics on any tested Linux distribution
