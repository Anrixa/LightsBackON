# EXP015 A12.17 — Exact-head CI repair, stale hash and callback invariants

This is an append-only, two-parent correction: first parent is the original A12.17 draft; second parent is the corrected A12.16 source head. All previous source commits are preserved, without force update.

**Behavior:** the combined SessionHost keeps A12.17 stale reconfiguration and callback sealing, plus A12.15 correct negative-reply replay behavior and refusal of indirect mission observation by a retired owner. Current host commands and legacy non-A09 callbacks continue unaffected.

**Test calibration, not relaxation:** A12.17's original test took the old host hash **before** source ownership was transferred, then incorrectly required that it match the host's revoked authority-marker hash. That is not a valid invariant. The corrected test asserts the exact stale marker after takeover and captures its hash then; it then confirms denied reconfiguration does not change this baseline, old revision, old session, or mission identity. It still checks all 25 original regions.

The exact unreviewed combined host blob is `904a019ff71dbcc8bd06ca4c09d03fe446c6d68a`, pinned separately from both historical blobs. The source gate permits only repaired A12.15 and A12.17 host objects, not their known-failing historical versions. Source-only / human/controller / physical / Steam / production-save-reward / independent review / release **HOLD**.
