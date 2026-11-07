# PERF21 — preserve tablet control tree across identical 10 Hz snapshots

## Root cause
`NetworkTablet.show_data()` fully rebuilt the map, evidence scroll, footer, and focus graph even when a validated incoming host snapshot carried no changed presentation state. The authoritative host ticks at 10 Hz; repeatedly allocating controls when nothing changed wastes rendering and allocation work.

## Code
- Preserve validation/defensive copying of actual incoming data.
- After validation, skip `_rebuild()` only when the host view, objectives, header context and **rendered UI locale** are unchanged.
- Rebuild normally for changed objectives, changed map evidence, tab/scale/device navigation or locale changes. No authority or game command changes.

## Regression
`tests/unit/test_tablet_snapshot_hardening.gd` verifies identical snapshots reuse map/evidence controls and preserve focus/pending replies; real objective changes rebuild; pseudo-localization rerenders even with identical host data.

## Gates and nonclaims
Final-head Linux/Windows tests, Windows export/headless smoke and CodeQL required. Physical GTX1650-class P95, VRAM stability and human 720p/150% reading tests remain unmeasured. This is a structural optimization, **not** a claim of measured frame-time improvement.

## Resume notes
After CI, measure exported-build tablet update and frame time on a physical Windows GPU. Do not claim performance benefit based solely on reduced allocations.
