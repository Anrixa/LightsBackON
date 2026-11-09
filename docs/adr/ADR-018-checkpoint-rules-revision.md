# ADR-018: Checkpoints check a rules revision, so presentation-only content edits keep a shift resumable

- Status: **Proposed (draft, SAVE22, 9 Nov 2026). Not implemented. Needs the owner's yes**, because it changes when an existing
  checkpoint is accepted (CLAUDE.md section 6 stop-and-ask: "deleting or migrating save data"; ADR-008 defines the envelope).
- Amends ADR-008 decision 1 (envelope) and the offline load check in `scripts/persistence/offline_persistence.gd`. Leaves the join handshake
  (ADR-010, `session_host.gd` / `session_client.gd`) and the build manifest's `content_revision` unchanged.
- Found in DS08 (`docs/evidence/DS08.md`, "Finding: content revision and checkpoints"). Evidence for this draft: `docs/evidence/SAVE22.md`.

## Context
`content_revision` is one SHA-256 over every file under `content/` (sorted relative path + bytes; `scripts/network/content_hash.gd`, mirrored by
`tools/build_manifest.py` and checked by `tools/cross_check_reference.py`). Three places use it:

| Use | Where | On mismatch |
|---|---|---|
| Save envelope field | `save_service.gd` (ADR-008), written into every record | nothing by itself |
| Offline checkpoint load and autosave | `offline_persistence.gd` `_validate_envelope(..., check_revision = true)` for `checkpoint` only | `CONTENT_MISMATCH`: resume refused, autosave refuses to overwrite, file preserved |
| Co-op join | `session_host.gd` `admit`, `session_client.gd` manifest | join refused before spawning |

So editing a string in `content/ui/strings/en.json`, a colour in `content/world/look_stormglass.json` or a sign in
`content/world/alder_street_dressing.json` (all DS08) makes every existing offline checkpoint unresumable. The player sees
"Saving disabled: CONTENT_MISMATCH. Existing progress was not erased." and cannot continue the shift; nothing is lost, but nothing can be done
with it either. That is the right outcome when the rules changed and the wrong one when only words and looks changed.

What a checkpoint actually depends on (ADR-008 decision 4, `checkpoint_codec.gd`): stable IDs and rules of the contract (grid edges, junctions,
consumers, capacities, repair steps, switches, equipment anchors, mission predicates and clocks), the interaction and movement limits that make a
saved state reachable, and the district layout that makes the saved player position (`view.position_cm`) valid. It does not depend on display
strings, UI tokens, status icon styling, the lighting look or non-colliding dressing.

## Decision (proposed)
1. **Two revisions.** Keep `content_revision` exactly as it is (every file). Add `rules_revision`: the same algorithm over every file under
   `content/` **except** an explicit list of presentation-only paths. Default is "it counts": a new file, or one nobody classified, is in the
   rules revision, so forgetting to classify a file fails safe (refuse, preserve), never open.
2. **The list lives in `content/save_compat.json`**, which is itself inside the rules revision (moving a file onto the list changes the rules
   revision once, so the move cannot silently re-label old saves). Initial list, each with a one-line reason:
   - `content/ui/strings/*.json`: display text only; on 9 Nov 2026 only `scripts/ui/ui_text.gd` loads it.
   - `content/ui/tokens.json`, `content/ui/status_states.json`: colours, sizes, icon mapping; loaded by `scripts/ui/` and by
     `mission_root.gd` for the HUD. (`meter_model.gd` names `status_states.json` in a comment only; a test already ties its finding codes to it.)
   - `content/world/look_*.json`: sky, fog, tonemap, materials (DS08).
   - `content/world/*_dressing.json`: signs, plaques, lamps, van; DS08's test proves it adds no collision and moves no gameplay node.
   Not on the list (mixed or gameplay, so they stay in the rules revision until split): `offline_solo.json` (player, selection radius and
   presentation in one file), `world/alder_street.json` and `world/kit_*.json` (layout and collision), `accessibility.json` (presentation by its own note,
   but it holds the tutorial step IDs and events; a good second candidate once that is checked), `movement.json`, `interaction.json`, `comms.json`, `network.json`, `economy.json`, `campaign.json`,
   `diagnostics/shift_measurements.json`, every `contracts/**` file, `versions.json`.
3. **Envelope.** New saves write one extra envelope field, `rules_revision`. It is optional on read (`ENVELOPE_FIELDS` stays the required set),
   so `schema_version` stays 1: today's reader already ignores unknown envelope fields and the checksum covers the new field.
4. **Checkpoint load rule** (`_validate_envelope`, checkpoint kind only):
   - `content_revision` equal: accept (today's rule, unchanged).
   - else `rules_revision` present in the save **and** equal to this build's: accept, and add the read issue `PRESENTATION_CHANGED`
     (diagnostics only; no player-facing notice, because nothing the player did is affected).
   - else: `CONTENT_MISMATCH`, file preserved, autosave refuses to overwrite (today's rule).
   Autosave after an accepted load rewrites the envelope with the current build's two revisions.
5. **Existing saves keep their meaning.** A checkpoint written before this change has no `rules_revision`, so it is accepted only on an equal
   full `content_revision`, exactly as now. No file is rewritten, migrated or deleted. The first autosave by a build with this change adds the
   field, and from then on presentation-only edits no longer strand that shift.
6. **Joins stay strict.** The co-op handshake keeps comparing the full `content_revision`: two peers on different builds should update, and
   ADR-010's "every peer builds identical gameplay node paths" is easier to trust that way. Revisit only if real players hit it.
7. **Guards that ship with the implementation**: `rules_revision` in `build_manifest.py` and in the Python vs Godot cross-check (byte-equal);
   a test that no authoritative module (`scripts/simulation/`, `scripts/interaction/`, `scripts/persistence/`, `scripts/network/`, the session's
   rule loading in `scripts/gameplay/offline_c01_session.gd`) loads a path on the presentation list; a test that editing a listed file changes
   `content_revision` but not `rules_revision`, and editing any other file changes both; load tests for all three branches of rule 4 and for an
   old save without the field; `validate_content.py` fails if a list entry matches no file.

## Options considered
| Option | For | Against |
|---|---|---|
| A. Keep today's rule (any byte refuses) | No work; strictest | Every look/string/dressing update strands every in-progress shift; DS phases will do this weekly |
| **B. Rules revision with a presentation list (proposed)** | Small (one hash variant, one list, one load branch); additive; existing saves unchanged; fails safe on unclassified files | The list is a judgement that tests can only partly check; a mixed file (offline_solo.json) keeps stranding saves until it is split |
| C. Per-file hash map in each save; compare only files the codec "uses" | Precise | Bigger saves; "uses" is hard to define (layout affects positions, limits affect reachability); more code in the save path |
| D. Hand-bumped `checkpoint_compat_version` in `versions.json` | Tiny | Relies on a person remembering; a forgotten bump loads a save under changed capacities or IDs. Codec validation catches missing IDs but not changed numbers. Fails open |
| E. Migrate: table of old full revisions known to be presentation-only variants | Rescues saves written before this change | Grows forever; needs every historical revision classified; this is the save migration the owner must approve; little value while the only checkpoints are the owner's dev runs |

## Consequences
- Presentation work (DS08 onward) stops costing players their shift, once a save has been written by a build with this change.
- Saves written before the change (today: the owner's own dev checkpoints) still refuse after the next content edit, as they do now. If the
  owner wants those rescued, that is option E and a separate decision.
- Splitting a mixed file (for example moving the `presentation` block out of `offline_solo.json`) changes the rules revision once, which strands
  in-progress shifts once. Do it before release, not after.
- The list becomes part of every content review: "is this file presentation-only?" is a question a reviewer must answer when adding a file.
  The default (counts as rules) means a skipped review costs resumability, not correctness.

## Not decided here
- Whether the player-facing text for `CONTENT_MISMATCH` should change (for example offer "start a new shift, keep the old file") — a UX task.
- Steam Cloud / multi-profile behaviour (H-milestone); campaign and receipt records, which are not revision-checked today and stay so.
