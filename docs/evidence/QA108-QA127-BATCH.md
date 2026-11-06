# QA108–QA127 — Read-only network tablet boundary hardening

**Source:** Main `d78d78a23136a87447a94e4be57e252f6b122046` after QA107 passed Linux/Windows CI.

**Status:** 20 targeted regression implementations, **NOT** 20 release-level acceptance completions. Do not promote until exact-head/merged-main CI gates have actually passed.

## Scope
One production validator (`scripts/ui/network_tablet.gd`) and 20 new integration-style Godot tests added to the existing live-tablet suite (`tests/unit/test_tablet_snapshot_hardening.gd`). The same C01-authoritative fixture drives every test; the focus/selection/pending Ping state must survive all rejected snapshots. Each regression is independently numbered and documented; the changes are bundled as a single reviewable hardening patch.

## Inventory
- **QA108** — Empty node ID
- **QA109** — Unsafe node path separator
- **QA110** — Wrong-category node localization
- **QA111** — Wrong-category access localization
- **QA112** — Network status group confusion
- **QA113** — Nonboolean measured flag
- **QA114** — Nonboolean reinspection flag
- **QA115** — Nontext source detail
- **QA116** — Nontext worker detail
- **QA117** — Excessive source caption
- **QA118** — Excessive worker caption
- **QA119** — Excessive evidence rows
- **QA120** — Excessive evidence line length
- **QA121** — Excessive finding badges
- **QA122** — Unsafe edge identifier
- **QA123** — Unbounded edge fanout
- **QA124** — Unbounded node allocation
- **QA125** — Absent or invalid objective ID
- **QA126** — Duplicate objective identity
- **QA127** — Wrong-category objectives and unbounded list

## Resource ceilings
- Maximum **128 nodes**, **512 edges**, **64 objectives**, **32 evidence lines per node**, **16 findings per node**, and **2048 characters per text field**; stable IDs at most **128 ASCII alphanumeric/underscore characters**. These are presentation safety limits only and do not change the Godot canonical grid or authored contract schema.
- Reject unexpected field types, known-but-wrong localization namespaces, unsupported network-node status groups, malformed/missing/duplicate objective IDs and pathological record sizes **atomically**, before rebuilding the real tablet.

## CI gate (do not infer pass from code review)
- `bash tools/run_tests.sh` — PR exact head on Linux and Windows.
- Windows export + manifest SHA smoke and QA51 resource probes.
- Merge only if required CI jobs succeed, then confirm exact merged-main CI.
- No release claim until physical GPU and gamepad UX, Steam co-op network tests and human review.

## Risk and compatibility
- No modification to `content/`, C01 content revision, network authority, save schemas, Steam transport or backlog status. The host-built C01 fixture must still render.
- The node/key namespace and ID whitelist are intentional contracts for *internal* presentation records. A future contract using differently named keys must extend the validator with explicit tests instead of silently bypassing it.

## Resume notes
Use actual CI run links and commit SHAs to update this file after verification. Pending physical QA remains in issue #51 and design UX issue #48.
