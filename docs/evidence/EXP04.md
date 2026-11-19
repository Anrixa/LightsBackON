# EXP04 — Host-authoritative lore pickups and bounded personal field points

**Branch:** `task/EXP04-authoritative-collectibles-and-points`  
**Baseline:** verified EXP03 merged-main commit `969ad9d67b52a5bb620a99563f2b4cdccf995d1b` (19 November 2026).  
**Status:** engineering changes submitted; exact-head Linux/Windows CI and QA57 export/smoke must be confirmed before merge or source verification claim.

## Implementation and contract

- The original 12-contract campaign, `content/`, C01 profile/credits/stars, offline identity and C01 checkpoints are **not modified** by EXP04.
- All 200 previously authored `FIND_001`–`FIND_200` story collectibles now have independently interactive physical-stage markers. They are cosmetic/lore artifacts: **no power grid, equipment, currency or purchase effects**. The authoritative interaction is `collect_lore`, not a client-side score toggle.
- F03 `SessionHost.receive` performs the original byte size, shape, sender admission, session, seq/dedupe, rate and host position/physical line-of-sight checks **before** invoking EXP04's opt-in host callback. Legacy sessions without a handler reject the intent. The host requires the correct source-pinned collectible ID and a previously accepted optional evidence inspection; the optional objective remains non-blocking.
- EXP03 task stages still advance only from host-accepted evidence and mission completion. A task advances an expedition receipt exactly once per live host run. No preview score field or client-reported quantity can grant rewards.
- Expedition points are a **different non-spendable field score** from V08 credits. The fixed host-authoritative schedule per completed task is: investigation 40, power routing 55, field repair 70, optional discovery 35, restoration 85. One account can earn at most **57,000** points across all 1,000 tasks (200 levels × 285). Replaying a level never re-credits a task. Lore pickups award **zero** points and can be archived once per account.
- The existing pseudonymous offline account key is passed only via local menu/scene state. The new versioned, checksum/backup-protected records reside separately under `user://profiles/<account_key>/expeditions.json` and `expedition_receipts.json` (isolated `user://test_runtime/headless_offline` for headless probing). Existing `profile.json`, `receipts.json`, campaign checkpoints and identity files are never migrated or overwritten by EXP04.
- On receipt delivery: validate source level, exact task/collectible, account, fixed amount, deterministic receipt ID; write an inbox **before** the atomic profile; acknowledge to the host only after a successful profile write. Unreadable/newer/wrong-kind records fail closed; a crash after the inbox write can replay idempotently. The local checksum protects integrity/corruption; this is **not** an anti-cheat signature or remote identity proof.

## Test scope

`tests/integration/test_EXP04_rewards.gd` exercises host-denied early, remote, replay, out-of-range and forged pickups; source-authenticated optional evidence; profile replay, save separation, all **1,000** point-bearing task IDs plus **200** lore receipts, maximum field cap and interrupted-inbox recovery.

`tests/integration/test_EXP04_stage.gd` verifies the physical-stage host marker and its separation from the existing equipment/grid.

Regression gates: run full Godot suite on Linux and Windows, 200 EXP03 mission replays, all existing C01–C12 mission solutions/reference parity, source catalog validation, Windows QA57 UID and EXE/PCK export/smoke; verify independent merged-main CI.

## Explicit hold

Human/controller continuous traversal, accessibility and target selection in real gameplay, GPU P95, Steam F02/F06/network transport, anti-cheat/server-account verification, public economy/credit promotion, production release and save migration remain **HOLD**. EXP05 will add campaign unlocks/branching using separate source-vetted progression, not silently convert preview values into authoritative credits.
