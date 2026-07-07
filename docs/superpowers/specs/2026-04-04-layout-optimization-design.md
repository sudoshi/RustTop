# RustTop Layout Optimization — Design Spec

**Date:** 2026-04-04
**Goal:** Eliminate scrolling on 1080p displays by using screen real estate more efficiently.

## Problem

The current layout stacks all widgets vertically in the left panel, producing ~1400px of content on a 16-core system. A 1080p display has ~1000px usable height, forcing constant scrolling.

### Current Layout (vertical stack)

```
Left (60%, scrollable)               | Right (40%)
─────────────────────────────────────┼──────────────
[CPU gauge 140] [Mem 140] [Swap 140] │ Process Table
[CPU graph ──────────── 160px]       │
[CPU cores ── 2 cols ─── ~300px]     │
[Memory graph ────────── 160px]      │
[GPU panel ─ gauges+graphs ~460px]   │
[Network graph 160] [Disk bars]      │
                                     │
Total: ~1400px+                      │
```

## Design

### Change 1: Remove Gauge Row (saves ~150px)

The three arc gauges (CPU, Memory, Swap) duplicate information already shown in graph headers. Each graph's header already displays the label, current value, and percentage. Remove the entire `gauges` row from `app.rs`.

**Files:** `app.rs` (remove gauge construction and `gauges` row from left_content)

### Change 2: Side-by-Side CPU + Memory Graphs (saves ~120px)

Place CPU and Memory graphs in a horizontal `row![]` instead of stacking vertically. Each gets `FillPortion(1)`. Combined height: 120px instead of 320px.

**Files:** `app.rs` (wrap cpu_graph + mem_graph in a row), `graph.rs` (reduce canvas height 160 → 120)

### Change 3: 4-Column CPU Cores (saves ~150px on 16-core)

Change `NUM_COLUMNS` from 2 to 4. On a 16-core system: 4 rows × 18px instead of 8 rows × 18px. On a 32-core system: 8 rows instead of 16.

**Files:** `cpu_cores.rs` (change column count constant)

### Change 4: Compact GPU Panel (saves ~200px)

Replace the two 140×140 arc gauges (GPU Util + VRAM) with horizontal progress bars. Keep one small history graph (120px) for GPU utilization. Show temp/clock/power/fan as a compact stats row.

**Files:** `gpu_view.rs` (rewrite to use horizontal bars + compact stats + single small graph)

### Change 5: Compact Network/Disk Row (saves ~100px)

Reduce network graph height to 80px (sparkline-style). Keep disk bars as-is (they're already compact).

**Files:** `network_view.rs` (reduce graph height), `graph.rs` (parameterize height or add a compact variant)

### Proposed Layout (~560px)

```
Left (55%)                              | Right (45%)
────────────────────────────────────────┼──────────────
[CPU graph 120px] [Memory graph 120px]  │ Process Table
[CPU cores ──── 4 columns ─── ~100px]   │
[GPU: bars + mini graph ────── ~140px]  │
[Network sparklines] [Disk bars] ~100px │
                                        │
Total: ~560px                           │
```

## Files Changed

| File | Change |
|------|--------|
| `src/ui/app.rs` | Remove gauge row, side-by-side graphs, adjust proportions |
| `src/ui/widgets/graph.rs` | Parameterize height (default 120, accept optional compact) |
| `src/ui/widgets/cpu_cores.rs` | 4 columns instead of 2 |
| `src/ui/widgets/gpu_view.rs` | Horizontal bars + compact stats + single graph |
| `src/ui/widgets/network_view.rs` | Reduced graph height (80px sparkline) |

## Non-Goals

- No changes to the process table (right panel)
- No changes to the header
- No changes to the data collection layer (metrics/)
- No changes to the color theme
- Gauge widget code (`gauge.rs`) was removed after the main layout moved fully to bars and graphs.
