# EXP05 — Campaign Progression, Unlocks and Branching Level Design

**Source base:** EXP04 certified and merged at `9ab5dae6e06c0aed9f392440df3998adfd0d82da`.
**Scope:** additive expedition campaign; original C01–C12 contract gameplay,
credit economy, checkpoint format, and existing save identity remain intact.

## Authored routing contract

`scenes/expeditions/campaign_routes.json` contains 25 distinct chapter
narratives and 200 source-pinned level nodes. Each eight-level corridor has:

1. Chapter entry (level 1, gated on prior region finale except REG_01).
2. Two independently replayable field approaches (levels 2 and 3).
3. First reconvergence (level 4, **either** approach restored).
4. Two independently replayable supply approaches (levels 5 and 6).
5. Second reconvergence (level 7, **either** approach restored).
6. Chapter finale (level 8, opens the next region's entry).

Neither fork is exclusive. Every region can complete its spine in 6 restored
levels. Fifty optional alternate routes remain accessible at the end of a
minimum 150-level completion, and all 200 levels can be restored. Source
requirements are exact, acyclic, and validated against the immutable atlas.

## Authority and persistence

- EXP05 unlocks are **derived** from `completed_levels`, unique restoration
  `earned_tasks` and matching `applied_receipts` in the separate EXP04
  `expeditions.json`. No new unlock file, currency or reward inflation.
- A scored launch is checked in the atlas UI and then independently rechecked
  by the **host** reading the account's saved expedition profile. A locked
  source level cannot launch in EXP05 campaign mode. No client event can set an
  unlocked flag.
- SaveService already writes the EXP04 inbox before the atomic profile update.
  An interrupted restoration becomes an unlock only after a validated inbox
  replay. Duplicate receipts remain idempotent.
- Unreadable profiles, unknown level IDs, rewritten route edges, orphaned
  completed-level flags and missing matching restoration receipts fail closed.
- Unscored source-only/demo sessions retain their original EXP03 semantics
  for engineering probes, without persisted campaign progress.
- `profile.json`, the C01 checkpoint and the original 12-contract rules are
  **not** mutated or migrated. Checksums are corruption detection, **not**
  an anti-cheat attestation.

## Certification acceptance gates

- `test_EXP05_graph_contains_25_authored_chapters_and_200_exact_source_nodes`
- `test_EXP05_first_entry_only_then_both_forks_and_either_join`
- `test_EXP05_all_25_region_spines_reach_finale_and_leave_50_optional_routes`
- `test_EXP05_rejects_forged_edges_unknown_progress_and_orphan_restorations`
- `test_EXP05_host_gate_rejects_locked_levels_and_accepts_saved_restoration`
- `test_EXP05_inbox_recovery_unlocks_once_without_legacy_profile_mutation`
- Re-run **all existing** EXP01–EXP04 tests, 200 EXP03 host solutions,
  C01–C12 original contract solutions, independent Python/Godot consistency,
  both Linux and Windows, and Windows QA57 source-pinned EXE/PCK export.
- Publish the exact tested source SHA, independent post-merge main CI result,
  and artifact hash before calling EXP05 automated source-qualified.

## Explicit holds

No continuous human/controller walkthrough, interaction timing, real GPU P95,
physical multi-machine/Steam F02/F06, online anticheat, full art or production
release qualification is inferred from automated tests. These remain held
until explicitly authorized.
