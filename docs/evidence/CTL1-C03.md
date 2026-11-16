# CT-L1/C03 Roof Route: implementation evidence

- Date: 17 November 2026.
- Branch: `task/CTL1-C03-roof-route-logic`; base main `4d71ca6c66bdf76852f25a91e631714cc2ba8013`.
- Status: **IN_PROGRESS** until exact-head CI is verified.
- Authority: ADR-017 separate content-only workstream. Canonical backlog CT03 stays blocked by D08.
- Specification: `docs/design/CT-L1-C03-contract-spec.md`.

## Implemented

Eight C03 definitions, replayable host-intent solution, rooftop 12 PU bypass versus overloaded 12 PU west crossfeed, optional 1 PU beacon, one gated rooftop splice, and durable/idempotent host-authorized ladder receipt. English labels and focused regressions. Existing C01/C02 definitions, save schema, Steam configuration and release status unchanged.

## Automated acceptance pending

Run `bash tools/run_tests.sh --filter=CTL1_C03`, full `bash tools/run_tests.sh`, `python3 tools/validate_content.py`, reference parity, every solution trace, Linux and Windows CI including internal export/headless smoke. Attach actual CI links and test counts only after observed.

## Not verified

Physical C03 scene/ladder travel, live 3D interaction or host movement range, human/controller test, actual GPU P95/memory, Steam F02/F06 and global content-rules save continuity. No save migration or production promotion.

## Resume

Inspect first branch CI, fix genuine failures, record evidence, and merge only after required Linux/Windows checks. Do not promote canonical CT03 without D08.
