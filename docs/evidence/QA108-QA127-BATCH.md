# QA108–QA127 — Read-only tablet boundary hardening

**Source:** baseline main `d78d78a23136a87447a94e4be57e252f6b122046` (QA107 complete).

**Status:** 20 targeted regression phases **CLOUD_VERIFIED** at tested code commit `b1d8bb8d87a37f700c4e5ca885998cbdd9541f14`. These are newly scoped supplemental validations, **not** 20 pre-existing blueprint tasks or full release-level completions.

## Production findings and fixes
- **Scope:** `scripts/ui/network_tablet.gd` schema/size checks; 20 new Godot regression tests in `tests/unit/test_tablet_snapshot_hardening.gd`. An existing QA77 stress fixture was corrected to use unique objective IDs while retaining 300 rows.
- **Validation:** Atomic rejection of malformed node, edge, objective IDs, inappropriate localization namespaces and status groups, unexpected types and excessive resource allocation. Authentic C01 data stays usable with controller focus, selection and pending Ping preserved.
- **Presentation-only ceilings:** 128 nodes, 512 edges, 384 objectives, 32 evidence rows/node, 16 findings/node, 2048 text characters/field, 128 ASCII identifier characters. No canonical simulation, authored contract, save, network or Steam changes.
- **Inventory:**
  - QA108: Empty node ID
  - QA109: Unsafe node path separator
  - QA110: Wrong-category node localization
  - QA111: Wrong-category access localization
  - QA112: Network status group confusion
  - QA113: Nonboolean measured flag
  - QA114: Nonboolean reinspection flag
  - QA115: Nontext source detail
  - QA116: Nontext worker detail
  - QA117: Excessive source caption
  - QA118: Excessive worker caption
  - QA119: Excessive evidence rows
  - QA120: Excessive evidence line length
  - QA121: Excessive finding badges
  - QA122: Unsafe edge identifier
  - QA123: Unbounded edge fanout
  - QA124: Unbounded node allocation
  - QA125: Absent or invalid objective ID
  - QA126: Duplicate objective identity
  - QA127: Wrong-category objectives and unbounded list

## Measured CI
- [Hosted Linux/Windows CI #42253302597](https://github.com/Anrixa/LightsBackON/actions/runs/42253302597): **PASS**, code SHA `b1d8bb8d87a37f700c4e5ca885998cbdd9541f14`; 348 Godot tests, 0 failed, 9,053 assertions, plus C01 solution, reference parity and Windows release export/headless smoke.
- [QA51 resource probes #42253303005](https://github.com/Anrixa/LightsBackON/actions/runs/42253303005): **PASS**, Linux and Windows, zero unexpected resource deltas.
- Subsequent evidence-only PR commit and exact merged main still require CI verification. No physical gamepad, GPU/VRAM/P95/memory or separate-network Steam test was executed.

## Product gate boundaries
- Original `docs/backlog.json` 66 milestone tasks remain unchanged.
- Steam F02/F06, human UX and Windows GPU acceptance remain blocked/pending. QA issue #51 and design UX issue #48 stay open.
- No implication that 20 passing defensive tests qualify a game build for release.

## Resume notes
Review PR #114 and its exact-head CI. Merge through a merge commit only with green checks and verify postmerge main CI. Follow original backlog for the next substantive product phase.
