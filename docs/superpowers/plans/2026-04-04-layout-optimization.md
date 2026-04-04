# Layout Optimization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate scrolling on 1080p by reducing left panel height from ~1400px to ~560px.

**Architecture:** Pure UI refactoring — no changes to metrics collection. Five widget files change, plus the main app layout. Graph height becomes parameterizable. GPU panel switches from arc gauges to horizontal bars.

**Tech Stack:** Rust, iced 0.13 (canvas widget), sysinfo

**Machine context:** 32-core CPU, AMD GPU present, 1080p+ display.

---

### Task 1: Add configurable height to graph_view

**Files:**
- Modify: `src/ui/widgets/graph.rs:157-168`

The graph currently hardcodes 160px. Add an optional height parameter so callers can request different sizes (120px for main graphs, 80px for network sparklines).

- [ ] **Step 1: Add `graph_view_sized` function alongside existing `graph_view`**

In `src/ui/widgets/graph.rs`, add a new public function after the existing `graph_view` that accepts a height parameter. Change `graph_view` to call it with the new default of 120px:

```rust
pub fn graph_view<'a, Message: 'a>(
    data: &[f32],
    max_value: f32,
    color: Color,
    label: &str,
    current_value: &str,
) -> Element<'a, Message> {
    graph_view_sized(data, max_value, color, label, current_value, 120.0)
}

pub fn graph_view_sized<'a, Message: 'a>(
    data: &[f32],
    max_value: f32,
    color: Color,
    label: &str,
    current_value: &str,
    height: f32,
) -> Element<'a, Message> {
    Canvas::new(Graph::new(data, max_value, color, label, current_value))
        .width(Length::Fill)
        .height(Length::Fixed(height))
        .into()
}
```

- [ ] **Step 2: Verify it compiles**

Run: `cargo build --release 2>&1 | tail -5`
Expected: `Finished` with no errors (warnings OK)

- [ ] **Step 3: Commit**

```bash
git add src/ui/widgets/graph.rs
git commit -m "feat: add graph_view_sized for configurable graph heights"
```

---

### Task 2: Remove gauge row from main layout

**Files:**
- Modify: `src/ui/app.rs:1-21` (imports), `src/ui/app.rs:55-139` (view method)

Remove the three arc gauges (CPU, Memory, Swap) from the left panel. They duplicate information already shown in the graph headers.

- [ ] **Step 1: Remove gauge import and gauge construction from app.rs**

In `src/ui/app.rs`, remove `gauge::gauge_view` from the import block (line 14) and remove `MemoryMetrics` import (line 8, no longer needed here). Then in the `view` method, remove lines 62-91 (the entire gauge construction block from `let cpu_gauge =` through the `let gauges = row![...]`).

Updated imports (lines 1-20):
```rust
use std::time::Duration;

use iced::widget::{column, container, row, scrollable};
use iced::{Element, Length, Padding, Subscription, Theme};

use crate::metrics::SystemMetrics;
use crate::metrics::memory::MemoryMetrics;
use crate::metrics::process::SortField;
use crate::theme;
use crate::theme::colors;
use crate::ui::widgets::{
    cpu_cores::cpu_cores_view,
    disk_bar::disk_view,
    gpu_view::gpu_panel_view,
    graph::graph_view,
    header::header_view,
    network_view::network_view,
    process_table::process_table_view,
};
```

Note: Keep `MemoryMetrics` import — it's still used in the memory graph format strings.

- [ ] **Step 2: Update left_content to remove gauges row**

Replace the `left_content` column (currently lines 127-139) with this version that removes the `gauges` row:

```rust
        // Left panel: graphs + cores + GPU + network/disk
        let left_content = column![
            cpu_graph,
            cores_view,
            mem_graph,
            gpu_panel,
            row![
                container(net_view).width(Length::FillPortion(1)),
                container(disks).width(Length::FillPortion(1)),
            ]
            .spacing(8),
        ]
        .spacing(8);
```

- [ ] **Step 3: Verify it compiles**

Run: `cargo build --release 2>&1 | tail -5`
Expected: `Finished` with no errors

- [ ] **Step 4: Commit**

```bash
git add src/ui/app.rs
git commit -m "feat: remove redundant gauge row from main layout"
```

---

### Task 3: Side-by-side CPU + Memory graphs

**Files:**
- Modify: `src/ui/app.rs` (view method, left_content layout)

Place the CPU and Memory graphs in a horizontal row instead of stacking vertically. Each gets half the width.

- [ ] **Step 1: Wrap CPU and Memory graphs in a row**

In `src/ui/app.rs`, update the `left_content` column to place `cpu_graph` and `mem_graph` side by side. Replace the left_content from Task 2 with:

```rust
        // Left panel: side-by-side graphs + cores + GPU + network/disk
        let left_content = column![
            row![
                container(cpu_graph).width(Length::FillPortion(1)),
                container(mem_graph).width(Length::FillPortion(1)),
            ]
            .spacing(8),
            cores_view,
            gpu_panel,
            row![
                container(net_view).width(Length::FillPortion(1)),
                container(disks).width(Length::FillPortion(1)),
            ]
            .spacing(8),
        ]
        .spacing(8);
```

- [ ] **Step 2: Verify it compiles and run to check visual**

Run: `cargo build --release 2>&1 | tail -5`
Expected: `Finished` with no errors

- [ ] **Step 3: Commit**

```bash
git add src/ui/app.rs
git commit -m "feat: place CPU and memory graphs side by side"
```

---

### Task 4: 4-column CPU cores

**Files:**
- Modify: `src/ui/widgets/cpu_cores.rs:73-74` (column count) and `src/ui/widgets/cpu_cores.rs:163-167` (height calculation)

Change from 2 columns to 4 columns. On 32 cores: 8 rows × 18px instead of 16 rows × 18px (saves ~144px).

- [ ] **Step 1: Change column count to 4**

In `src/ui/widgets/cpu_cores.rs`, change line 73 from:
```rust
        let cols = 2;
```
to:
```rust
        let cols = 4;
```

And change the height calculation in `cpu_cores_view` (line 165) from:
```rust
    let cols = 2;
```
to:
```rust
    let cols = 4;
```

- [ ] **Step 2: Verify it compiles**

Run: `cargo build --release 2>&1 | tail -5`
Expected: `Finished` with no errors

- [ ] **Step 3: Commit**

```bash
git add src/ui/widgets/cpu_cores.rs
git commit -m "feat: use 4 columns for CPU cores to reduce vertical height"
```

---

### Task 5: Compact GPU panel with horizontal bars

**Files:**
- Modify: `src/ui/widgets/gpu_view.rs` (full rewrite of the panel)

Replace the two 140×140 arc gauges with compact horizontal progress bars. Keep one small GPU utilization graph (120px). Show stats in a compact row. This saves ~200px per GPU device.

- [ ] **Step 1: Rewrite gpu_view.rs**

Replace the entire contents of `src/ui/widgets/gpu_view.rs` with a compact layout that uses:
- Horizontal progress bars (via iced `progress_bar` or canvas rectangles) for GPU util and VRAM
- A single 120px graph for GPU utilization history
- A compact stats row for temp/clock/power/fan

```rust
use iced::widget::canvas::{self, Canvas, Frame, Geometry, Path, Stroke};
use iced::widget::{column, container, row, text};
use iced::{mouse, Element, Length, Padding, Rectangle, Renderer, Theme};

use crate::metrics::gpu::{self, GpuMetrics};
use crate::theme::colors;
use crate::ui::widgets::graph::graph_view;

/// Compact horizontal bar for GPU metrics
#[derive(Debug)]
struct HorizontalBar {
    percent: f32,
    color: iced::Color,
    label: String,
    detail: String,
}

impl HorizontalBar {
    fn new(percent: f32, color: iced::Color, label: &str, detail: &str) -> Self {
        Self {
            percent: percent.clamp(0.0, 100.0),
            color,
            label: label.to_string(),
            detail: detail.to_string(),
        }
    }
}

impl<Message> canvas::Program<Message> for HorizontalBar {
    type State = ();

    fn draw(
        &self,
        _state: &Self::State,
        renderer: &Renderer,
        _theme: &Theme,
        bounds: Rectangle,
        _cursor: mouse::Cursor,
    ) -> Vec<Geometry> {
        let mut frame = Frame::new(renderer, bounds.size());
        let w = bounds.width;
        let h = bounds.height;
        let bar_h = 12.0;
        let bar_y = (h - bar_h) / 2.0;

        // Label on the left
        frame.fill_text(canvas::Text {
            content: self.label.clone(),
            position: iced::Point::new(0.0, bar_y + bar_h / 2.0),
            color: colors::TEXT_SECONDARY,
            size: iced::Pixels(11.0),
            vertical_alignment: iced::alignment::Vertical::Center,
            ..canvas::Text::default()
        });

        let label_w = 48.0;
        let detail_w = 100.0;
        let bar_x = label_w;
        let bar_w = w - label_w - detail_w - 8.0;

        // Bar background
        let bg = Path::rectangle(
            iced::Point::new(bar_x, bar_y),
            iced::Size::new(bar_w.max(0.0), bar_h),
        );
        frame.fill(&bg, colors::SURFACE_LIGHT);

        // Bar fill
        let fill_w = bar_w * (self.percent / 100.0);
        if fill_w > 0.0 {
            let bar_color = colors::heat_color(self.percent);
            let fill = Path::rectangle(
                iced::Point::new(bar_x, bar_y),
                iced::Size::new(fill_w.max(0.0), bar_h),
            );
            frame.fill(&fill, colors::with_alpha(bar_color, 0.7));

            // Bright tip
            if fill_w > 2.0 {
                let tip = Path::rectangle(
                    iced::Point::new(bar_x + fill_w - 2.0, bar_y),
                    iced::Size::new(2.0, bar_h),
                );
                frame.fill(&tip, bar_color);
            }
        }

        // Border around bar
        let bar_border = Path::rectangle(
            iced::Point::new(bar_x + 0.5, bar_y + 0.5),
            iced::Size::new((bar_w - 1.0).max(0.0), bar_h - 1.0),
        );
        frame.stroke(
            &bar_border,
            Stroke::default()
                .with_color(colors::SURFACE_BORDER)
                .with_width(0.5),
        );

        // Percentage + detail on the right
        let detail_text = format!("{:.0}%  {}", self.percent, self.detail);
        frame.fill_text(canvas::Text {
            content: detail_text,
            position: iced::Point::new(bar_x + bar_w + 8.0, bar_y + bar_h / 2.0),
            color: self.color,
            size: iced::Pixels(11.0),
            vertical_alignment: iced::alignment::Vertical::Center,
            ..canvas::Text::default()
        });

        vec![frame.into_geometry()]
    }
}

fn horizontal_bar_view<'a, Message: 'a>(
    percent: f32,
    color: iced::Color,
    label: &str,
    detail: &str,
) -> Element<'a, Message> {
    Canvas::new(HorizontalBar::new(percent, color, label, detail))
        .width(Length::Fill)
        .height(Length::Fixed(24.0))
        .into()
}

pub fn gpu_panel_view<'a, Message: 'a>(gpu: &GpuMetrics) -> Element<'a, Message> {
    if !gpu.available || gpu.devices.is_empty() {
        return container(
            column![
                text("GPU").size(14).color(colors::ACCENT_GREEN),
                text("No AMD GPU detected")
                    .size(12)
                    .color(colors::TEXT_DIM),
                text("(AMD sysfs monitoring requires Linux)")
                    .size(10)
                    .color(colors::TEXT_DIM),
            ]
            .spacing(4),
        )
        .padding(Padding::from([8, 12]))
        .style(|_theme: &iced::Theme| container::Style {
            background: Some(colors::SURFACE.into()),
            border: iced::Border {
                color: colors::SURFACE_BORDER,
                width: 1.0,
                radius: 6.0.into(),
            },
            ..Default::default()
        })
        .width(Length::Fill)
        .into();
    }

    let mut panels: Vec<Element<'a, Message>> = Vec::new();

    for dev in &gpu.devices {
        let title = text(format!("GPU — {}", dev.name))
            .size(14)
            .color(colors::ACCENT_GREEN);

        // Horizontal bars for GPU and VRAM usage
        let gpu_bar = horizontal_bar_view(
            dev.gpu_usage,
            colors::ACCENT_GREEN,
            "GPU",
            &format!("{:.0}%", dev.gpu_usage),
        );
        let vram_bar = horizontal_bar_view(
            dev.vram_usage_percent,
            colors::ACCENT_MAGENTA,
            "VRAM",
            &format!(
                "{} / {}",
                gpu::format_vram(dev.vram_used),
                gpu::format_vram(dev.vram_total),
            ),
        );

        // Compact stats row
        let mut stats: Vec<Element<'a, Message>> = Vec::new();

        if let Some(temp) = dev.temperature_edge {
            let temp_color = colors::heat_color((temp / 100.0 * 100.0).min(100.0));
            stats.push(
                text(format!("{:.0}°C", temp))
                    .size(10)
                    .color(temp_color)
                    .into(),
            );
        }
        if let Some(clock) = dev.gpu_clock_mhz {
            stats.push(
                text(format!("{} MHz", clock))
                    .size(10)
                    .color(colors::ACCENT_CYAN)
                    .into(),
            );
        }
        if let Some(power) = dev.power_watts {
            let cap_str = dev
                .power_cap_watts
                .map(|c| format!("/{:.0}W", c))
                .unwrap_or_default();
            stats.push(
                text(format!("{:.1}W{}", power, cap_str))
                    .size(10)
                    .color(colors::ACCENT_ORANGE)
                    .into(),
            );
        }
        if let Some(rpm) = dev.fan_rpm {
            stats.push(
                text(format!("{} RPM", rpm))
                    .size(10)
                    .color(colors::TEXT_SECONDARY)
                    .into(),
            );
        }

        let mut stats_row = row![].spacing(12);
        for stat in stats {
            stats_row = stats_row.push(stat);
        }

        // Single GPU utilization graph (compact)
        let gpu_graph = graph_view(
            &dev.gpu_history,
            100.0,
            colors::ACCENT_GREEN,
            "GPU Utilization",
            &format!("{:.0}%", dev.gpu_usage),
        );

        let gpu_col = column![title, gpu_bar, vram_bar, stats_row, gpu_graph].spacing(4);
        panels.push(gpu_col.into());
    }

    container(column(panels).spacing(8))
        .padding(Padding::from([8, 12]))
        .style(|_theme: &iced::Theme| container::Style {
            background: Some(colors::SURFACE.into()),
            border: iced::Border {
                color: colors::SURFACE_BORDER,
                width: 1.0,
                radius: 6.0.into(),
            },
            ..Default::default()
        })
        .width(Length::Fill)
        .into()
}
```

- [ ] **Step 2: Verify it compiles**

Run: `cargo build --release 2>&1 | tail -5`
Expected: `Finished` with no errors

- [ ] **Step 3: Commit**

```bash
git add src/ui/widgets/gpu_view.rs
git commit -m "feat: compact GPU panel with horizontal bars instead of arc gauges"
```

---

### Task 6: Compact network sparklines

**Files:**
- Modify: `src/ui/widgets/network_view.rs` (use `graph_view_sized` with 80px height)

Reduce network graphs from 120px (new default) to 80px sparkline-style.

- [ ] **Step 1: Update network_view.rs to use graph_view_sized**

Change the import in `src/ui/widgets/network_view.rs` from:
```rust
use super::graph::graph_view;
```
to:
```rust
use super::graph::graph_view_sized;
```

Then replace the two `graph_view` calls (rx_graph and tx_graph) with `graph_view_sized` using 80px:

```rust
    let rx_graph = graph_view_sized(
        &rx_f32,
        max_net as f32,
        colors::NET_RX_COLOR,
        "Download",
        &NetworkMetrics::format_rate(net.total_rx_rate),
        80.0,
    );

    let tx_graph = graph_view_sized(
        &tx_f32,
        max_net as f32,
        colors::NET_TX_COLOR,
        "Upload",
        &NetworkMetrics::format_rate(net.total_tx_rate),
        80.0,
    );
```

- [ ] **Step 2: Verify it compiles**

Run: `cargo build --release 2>&1 | tail -5`
Expected: `Finished` with no errors

- [ ] **Step 3: Commit**

```bash
git add src/ui/widgets/network_view.rs
git commit -m "feat: compact 80px network sparklines"
```

---

### Task 7: Final layout tuning and panel proportions

**Files:**
- Modify: `src/ui/app.rs` (panel width proportions)

Adjust the left/right panel split from 3:2 to 1:1 since the left panel is now more compact and the process table benefits from extra width.

- [ ] **Step 1: Update panel proportions**

In `src/ui/app.rs`, change the left and right panel widths:

From:
```rust
        let left_panel = scrollable(left_content)
            .width(Length::FillPortion(3))
            .height(Length::Fill);

        // Right panel: process table
        let right_panel = container(process_table_view(&m.processes))
            .width(Length::FillPortion(2))
            .height(Length::Fill);
```

To:
```rust
        let left_panel = scrollable(left_content)
            .width(Length::FillPortion(1))
            .height(Length::Fill);

        // Right panel: process table
        let right_panel = container(process_table_view(&m.processes))
            .width(Length::FillPortion(1))
            .height(Length::Fill);
```

- [ ] **Step 2: Build final release and verify**

Run: `cargo build --release 2>&1 | tail -5`
Expected: `Finished` with no errors

- [ ] **Step 3: Run the app and visually verify**

Run: `./target/release/rust_top`
Verify:
- No scrolling needed on 1080p
- CPU and Memory graphs render side-by-side
- CPU cores show in 4 columns
- GPU shows horizontal bars + single graph
- Network shows compact sparklines
- Process table has adequate width

- [ ] **Step 4: Commit**

```bash
git add src/ui/app.rs
git commit -m "feat: adjust panel proportions to 1:1 for compact layout"
```

---

### Task 8: Rebuild .deb package

**Files:** None (packaging only)

- [ ] **Step 1: Build the .deb**

Run: `cargo deb 2>&1 | tail -3`
Expected: Path to new `.deb` file

- [ ] **Step 2: Reinstall**

Run: `sudo apt install --reinstall ./target/debian/rust-top_0.1.0-1_amd64.deb`

- [ ] **Step 3: Commit all remaining changes**

```bash
git add -A
git commit -m "chore: rebuild .deb package with compact layout"
```
