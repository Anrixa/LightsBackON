# QA128–QA132 — Tablet semantic status and host reply integrity

**Baseline:** main `94f7312a36ac712091b0af77f24bdaceb844faa5` (QA108–QA127 merged).
**Status:** CLOUD_VERIFIED for the headless scope; merged-main confirmation still outstanding. Five supplementary regression phases, not items in the original 66-task blueprint.

| Phase | Scoped defect | Regression |
| --- | --- | --- |
| QA128 | Bound panel inspection target identifiers | `test_QA128_panel_target_identifiers_cannot_escape_inspect_namespace` |
| QA129 | Match displayed status semantics to node kind | `test_QA129_status_chip_must_match_power_node_kind` |
| QA130 | Preserve unknown readings on uninspected junctions | `test_QA130_uninspected_junction_must_not_claim_supply_or_fault` |
| QA131 | Keep measured junction finding and banner consistent | `test_QA131_measured_junction_primary_finding_must_match_evidence` |
| QA132 | Restrict host refusal translation namespace | `test_QA132_refusal_uses_only_known_host_reason_namespace` |

The production fix is confined to `scripts/ui/network_tablet.gd`. The test fixture drives a real C01 network tablet opened with controller focus and a pending correlated Ping. Bad data is refused before teardown; valid data and host refusal keys remain available. The 66-task backlog and authoritative simulation, save, content, network protocol and Steam are unchanged.

## Observed hosted verification

- **Code commit:** `9c4531c1ab15ddc6ac512e3d07f88aa7f428b8c3`. PR checkout/test commit `14cffb3d1de12b10d7a73c6cd8e4a048ef625002` has the exact same Git tree `84f7eb6ae5ae00c84c4a7d72a18a38ebe633c11c`.
- [PR #115 Linux/Windows CI #42261175484](https://github.com/Anrixa/LightsBackON/actions/runs/42261175484) **PASS**: 353 Godot tests, zero failed, 9,121 assertions on both OSes; Windows release export, headless smoke and QA57 source pin passed.
- [QA51 lifetime probes #42261175403](https://github.com/Anrixa/LightsBackON/actions/runs/42261175403) **PASS** on Linux and Windows, with zero unexpected CanvasItem, ObjectDB, DummyTexture, ShapedText and FontRID deltas.

## Verification gates

- Run full Linux/Windows Godot suites on the exact PR head; require Windows export and headless smoke.
- Run QA51 resource probes on the exact PR head; require zero unexpected deltas.
- Merge with a merge commit only after green PR-head checks, then verify exact main push CI.
- Local physical GPU/controller UX, two-PC Steam transport and external tester gates remain unverified.

## Resume notes

Headless code tree verification and QA51 passed. Verify the final documentation-only PR head before merge, then verify exact merged-main push CI; retain physical/controller/Steam/human pending gates.
