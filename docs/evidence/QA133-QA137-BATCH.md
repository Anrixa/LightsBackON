# QA133–QA137 — Tablet semantic topology and inspection evidence

**Baseline:** `main` dbedb8d2d6b8cf8fa99a7ce5254c60aba0f83f6c, with successful post-merge CI run #42262089764.
**Status:** IMPLEMENTED / CI PENDING. Five additive regression phases; not part of the original 66-task backlog.

| Phase | Integrity invariant | Regression |
| --- | --- | --- |
| QA133 | Directed edge endpoints cannot portray consumers as feeders or sources as downstream nodes | `test_QA133_directed_edges_never_start_at_consumers_or_end_at_sources` |
| QA134 | Source and consumer records cannot invent meter findings | `test_QA134_non_meter_nodes_cannot_invent_diagnostic_findings` |
| QA135 | Uninspected junctions cannot substitute measured load evidence for unknown/reinspect text | `test_QA135_uninspected_junction_cannot_claim_numeric_evidence` |
| QA136 | Current junction readings must have an inspectable meter panel | `test_QA136_measured_junction_requires_inspectable_panel_id` |
| QA137 | Controller focus order must remain row-major with the authored map coordinates | `test_QA137_tablet_focus_catalog_preserves_spatial_order` |

## Implementation

Harden `scripts/ui/network_tablet.gd` at its read-only snapshot validation boundary. Reject reversed directed feeders, fabricated findings on non-junctions, measured text on unknown junctions, measured junctions without meter panels, and mismatched row-major focus order. Rejection must leave the working map, selected node, keyboard/controller focus and pending host Ping intact. The known-valid C01 presenter output must still render.

The implementation neither changes authoritative grid logic nor introduces new puzzle hints. Preserve mission, content, saves, networking, offline play and the locked 66-task roadmap. No Steam account, GPU or new third-party asset is required.

## CI gates

1. Full Godot suite in Linux + Windows on the exact PR head; check for script errors.
2. Windows release export and exported headless smoke.
3. QA51 isolated lifetime probes on both hosted operating systems.
4. Merge commit only after all required checks succeed; exact merged-main push CI must then pass.

## Scope limit and resume

Code-side tests are not physical GPU, controller-only UX, external study or two-network Steam qualification. Those remain pending. Record actual check run IDs and measured assertion counts after CI; do not infer a PASS from code inspection.
