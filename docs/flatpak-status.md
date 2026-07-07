# RustTop Flatpak Status

Status: incomplete and not release-ready.

The repository includes `io.github.sudoshi.RustTop.yml`, but the Flatpak path is
not complete until Rust crate sources are generated and the sandbox permissions
are validated on real systems.

## Current Manifest State

The manifest currently:

- Uses `org.freedesktop.Platform` and `org.freedesktop.Sdk` `24.08`.
- Adds the Rust stable SDK extension.
- Builds with `cargo --offline fetch` and `cargo --offline build --release`.
- Installs the `rust_top` binary, desktop file, and icons.
- Requests GPU rendering and display access through `--device=dri`,
  `--socket=wayland`, `--socket=fallback-x11`, and `--share=ipc`.
- Requests read-only `/sys` and `/proc` access plus `--share=network`.
- References `cargo-sources.json` as a source file.

## Blocking Issue: `cargo-sources.json`

`cargo-sources.json` is required because the manifest builds Cargo dependencies
offline. It is not present in the current checkout, so a Flatpak build cannot be
treated as complete.

Generate it with the Flatpak cargo source generator before attempting a release
or Flathub submission. A typical workflow is:

```bash
python3 flatpak-cargo-generator.py Cargo.lock -o cargo-sources.json
flatpak-builder --force-clean build-dir io.github.sudoshi.RustTop.yml
```

Do not mark Flatpak packaging complete until the generated source list is
committed or otherwise supplied by the packaging workflow.

## Blocking Issue: Sandbox Permission Validation

The requested permissions must be validated because RustTop is a system monitor,
and a Flatpak sandbox can change what the app can see.

Validate at minimum:

- The app launches under Wayland and X11 fallback.
- `iced` can render through the requested DRI access.
- CPU, memory, disk, and network data are visible and not sandbox-only views.
- The process table shows the intended host processes, or the limitation is made
  explicit in the UI and docs.
- AMD GPU sysfs and hwmon paths are visible enough for useful telemetry.
- NVIDIA NVML discovery works only if the host driver libraries are accessible;
  document the expected failure mode otherwise.
- Process kill behavior is either blocked, limited, or clearly documented inside
  the sandbox.
- `/proc` and `/sys` access pass Flathub review expectations for a system
  monitor.

## Release Checklist

- [ ] Generate `cargo-sources.json` from the committed `Cargo.lock`.
- [ ] Run `flatpak-builder --force-clean` locally.
- [ ] Test launch on Wayland.
- [ ] Test launch on X11 fallback.
- [ ] Test on a system with no discrete GPU.
- [ ] Test on Linux AMD GPU hardware.
- [ ] Test on Linux NVIDIA GPU hardware with NVML available.
- [ ] Confirm whether process listing and kill actions are host-visible,
  sandbox-limited, or disabled.
- [ ] Document any sandbox-limited panels in `docs/platform-support.md`.
- [ ] Review requested permissions before Flathub submission.

Until those items are complete, Flatpak should be advertised only as a draft
manifest, not as a supported installation path.
