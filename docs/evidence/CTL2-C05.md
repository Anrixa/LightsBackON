# CT-L2 C05 — Canal Yard Pump Access (implementation candidate)

- Date: 17 November 2026.
- Branch: `task/CTL2-C05-canal-pump-access` from `main` `71b9b6e05de94eac9daf1318dcd26230e1627295`.
- Authority: ADR-017 allows C02–C12 independent logic content; canonical CT04 remains NOT_STARTED because CT01/CT03 are gated.
- Status: **IN_PROGRESS, NOT_YET_CI_VERIFIED**.
- Source: `content/contracts/c05_canal_pump_access`.
- No physical Canal Yard implementation, GUI, controller testing, Steam transport or real GPU data.

## Content and tests added

- 8 C05 JSON definitions, English strings, CT-L2 tracker, authoring spec and 9 new host regression tests.
- 5 mandatory services, split 8/11 PU across two 12 PU feeders, 2 PU optional beacon, 6 PU temporary generator.
- 80-tick and 100-tick independent pump access latches; 4+4 > 6 PU simultaneous temporary feed trips TEMP protection after 15 ticks; one-at-a-time repair access route.
- Known-valid host-intent solution with explicit generator stowing and 10 s stable grid verification/5 s extraction.

## Verification to collect

- [ ] Linux/Windows exact-head full suite and JSON schema validation.
- [ ] C01–C05 host-intent solution traces and reference parity.
- [ ] Windows export-release/headless smoke and QA57.
- [ ] Physical Canonical C05 contract-sheet comparison, real 3D Canal Yard scene, controller/human/GPU checks, cross-network Steam and save compatibility.

## Resume

If CI fails, correct source and rerun both platforms on the same head. Only update to CLOUD_VERIFIED after observed passing CI; keep original sheet/canonical qualification pending. Merge only on final-head passing CI. No Steam action, third-party assets, or data deletion.
