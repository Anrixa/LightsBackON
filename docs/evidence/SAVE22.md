# Evidence: SAVE22 checkpoint rules revision (ADR-018) and isolated test user dir

- Status claimed: test isolation and ADR-018 implemented, headless-tested on the owner's PC. ADR-018 approved by the owner in the session
  on 9 Nov 2026 ("Approve ADR-018"). Not a backlog task: quality follow-up to DS08 ("Finding: content revision and checkpoints").
- Date (UTC): 2026-11-09
- Branch / commit: `task/SAVE22-checkpoint-content-revision` (isolation 33596fe, ADR draft 943ac7f, implementation in the following commits)
- Environment: local desktop session on the owner's PC (Windows 11, Git Bash), headless Godot
- Engine: Godot 4.7.2.stable.official.ed1daf0bf (console exe, `C:\Tools\Godot`)
- Content revision: changes (new `content/save_compat.json`), so checkpoints written by earlier builds refuse once, as any content edit did
  before; rules revision introduced. Protocol 1, save schema 1 (unchanged: the new envelope field is optional).

## What the task required
1. Find where the content revision is computed and checked; propose the smallest safe change so presentation-only edits do not strand an
   offline checkpoint; write it up as an ADR draft with tradeoffs; do **not** implement anything that changes what an existing save means.
2. Make the Godot test runner use an isolated user dir so tests never read the PC's real checkpoints, with tests.

## Findings
- Computed: `scripts/network/content_hash.gd` `content_revision()` (SHA-256 over every file under `content/`), mirrored by
  `tools/build_manifest.py` `content_revision()` and compared Python vs Godot in `tools/cross_check_reference.py`.
- Written into every save envelope by `scripts/persistence/save_service.gd` (ADR-008).
- Checked for offline checkpoints only, in `scripts/persistence/offline_persistence.gd` `_validate_envelope(..., check_revision = true)`:
  resume and autosave both return `CONTENT_MISMATCH` and leave the file alone. Profile and identity records are not revision-checked.
- Also checked by the co-op join (`session_host.gd` `admit`, `session_client.gd` manifest). ADR-018 leaves that strict.
- Why tests failed on this PC: in a headless run `OfflinePersistence.runtime_root()` is `user://test_runtime/headless_offline`, which is
  still inside the PC's real Godot user dir (`%APPDATA%\Godot\app_userdata\Lights Back On (working title)`). A checkpoint left there by an
  earlier suite run survives into the next run; once any `content/` byte differs, V07 scene tests see the `CONTENT_MISMATCH` banner
  instead of the feedback they assert.

## What was built
- `tools/find_tools.sh` `isolate_godot_user_dir`: `mktemp -d`, converted with `cygpath -m` on Git Bash, exported as `APPDATA` (Godot's
  Windows user-data base), `XDG_DATA_HOME` (Linux) and `LBO_TEST_USER_ROOT`.
- `tools/run_tests.sh`: calls it after `--import` (import still uses the real editor settings) and before every Godot run (test suite,
  solution traces, Python vs Godot cross-check); removes the directory on exit.
- `tests/support/user_dir_guard.gd` + `tests/run_tests.gd`: the runner exits 2 (`RUNNER ERROR`) unless `OS.get_user_data_dir()` resolves
  inside `LBO_TEST_USER_ROOT` (separator- and dot-segment-normalized, case-insensitive on Windows, trailing slash so a same-prefix sibling does
  not pass). It prints the isolated path at start.
- `tools/qa_resource_probe.py` `isolated_env`: the QA51 probe calls `run_tests.gd` directly, so each case now gets its own temp user dir
  (otherwise the new guard would refuse it).
- `docs/adr/ADR-018-checkpoint-rules-revision.md` (**Proposed**): keep `content_revision`, add a `rules_revision` that excludes an explicit
  presentation-only list (`content/save_compat.json`, itself in the rules hash); accept a checkpoint on equal full revision (today) or equal
  rules revision when the save carries one; existing saves unchanged; joins stay strict. Options A-E with tradeoffs in the ADR.

### ADR-018 implementation (after the owner's approval)
- `content/save_compat.json`: exact paths, each with a reason: `content/ui/strings/en.json`, `content/ui/tokens.json`,
  `content/ui/status_states.json`. Explicit paths instead of the draft's globs (a glob could swallow a future gameplay file); the DS08 look and
  dressing files get added when DS08 merges.
- `scripts/network/content_hash.gd`: `rules_revision()` and `presentation_paths()`; empty on a missing or malformed list (fail safe).
  `content_revision()` is byte-identical to before.
- `tools/build_manifest.py`: same functions in Python, `rules_revision` in the manifest; `tools/cross_check_reference.py` and
  `tools/godot/dump_grid_cases.gd` compare it Python vs Godot. Python's sort is now on the relative-path string, which is what Godot sorts.
- `scripts/persistence/save_service.gd`: optional `rules_revision` envelope field (written when configured, never required on read).
- `scripts/persistence/offline_persistence.gd`: checkpoint accepted on equal `content_revision`, or on equal `rules_revision` when the save
  has one and this build's is non-empty (`presentation_changed: true` in the status, no player-facing notice); otherwise `CONTENT_MISMATCH`,
  bytes preserved, autosave refuses. Profile and identity records are not revision-checked (unchanged).
- `tools/validate_content.py`: list entries must name a real file, once, with a reason, no globs/backslashes/`..`, never
  `save_compat.json`, `versions.json` or `content/contracts/`.
- ADR-008 gets amendment 7 pointing at ADR-018.

## What was run
| Step | Command | Result |
|---|---|---|
| Reproduce (before) | added a scratch `content/zz_probe.txt`, then `"$GODOT_BIN" --headless --path . -s res://tests/run_tests.gd -- --filter=V07_live` with the real APPDATA | **3 failed** (`test_QA60_action_refusal_is_legible...`, `test_QA60_feedback_clock...`, `test_QA60_heartbeat_and_tool_ack...`): got "Saving disabled: CONTENT_MISMATCH. Existing progress was not erased." Probe file removed after |
| Guard refuses a direct call | `"$GODOT_BIN" --headless --path . -s res://tests/run_tests.gd -- --filter=SAVE22` (no isolation) | `RUNNER ERROR: LBO_TEST_USER_ROOT is not set; ...`, exit 2 |
| Isolation fixes it | same scratch `content/zz_probe.txt`, `bash tools/run_tests.sh --filter=V07_live` | `tests: 25 passed, 0 failed`; user:// at `C:/Users/user/AppData/Local/Temp/lbo_test_user.sCbhKV/Godot/app_userdata/...`; ALL CHECKS PASSED. Probe file removed after |
| New tests | `bash tools/run_tests.sh --filter=SAVE22` | 6 passed, 14 assertions |
| Temp dirs cleaned | `ls -d /tmp/lbo_test_user.*` after runs | none left |
| Full suite | `bash tools/run_tests.sh` | backlog OK, Python 19 + 172 OK, **Godot 486 passed, 0 failed, 9671 assertions**, C01 solution SOLVED, cross-check passed, **ALL CHECKS PASSED** |
| Probe helper | `python -m unittest tests.python.test_qa_resource_probe` | 11 OK |

## Tests
- `tests/integration/test_SAVE22_rules_revision.gd` (10): shipped list gives a distinct rules revision; on a copy of `content/` in the isolated
  user dir, editing every listed file changes only the full revision, editing a contract, the layout, `offline_solo.json` or the list itself
  changes both, a new unlisted file changes both, five kinds of broken list give ""; no script in simulation/interaction/persistence/network
  loads a listed file (the offline session's UiText prompts are allowed as display only, never compared); new checkpoints carry both
  revisions; a presentation-only difference resumes, restores and is rewritten by autosave; a rules difference and an old save without the
  field are refused with bytes preserved (and the old save still loads on equal content); a build with a broken list accepts nothing by rules.
- `tests/python/test_save22_rules_revision.py` (7): the Python mirror on a temp copy (same cases) and the `validate_content.py` list check.
- `tests/unit/test_SAVE22_isolated_user_dir.gd`: this run's user://, the headless offline sandbox and `user://profiles` all globalize inside
  `LBO_TEST_USER_ROOT`; the guard refuses a missing root, the real `%APPDATA%` path, a same-prefix sibling, the root itself and a `..` escape;
  accepts Windows paths with backslashes and different case; Linux stays case-sensitive.
- `tests/python/test_qa_resource_probe.py::test_SAVE22_probe_runs_point_godot_user_dir_at_the_temp_root`.

## Not verified / pending
- Linux CI and the `windows` CI job run the same `run_tests.sh`; their result is on the PR, not here. The QA51 probe workflow runs only on
  matching paths (this PR touches `tests/run_tests.gd`, so it should trigger); not run locally.
- macOS (Godot reads `$HOME/Library/Application Support`) is not isolated; not a target platform.
- ADR-018 was exercised headless only (saves written by fabricated "other builds" via SaveService). Not tried: resuming a real windowed
  shift across two exported builds that differ only in a string. Suggested manual check when DS08 merges.
- Checkpoints written before this change carry no rules revision and are refused after any content edit, including this PR's new
  `save_compat.json` (the owner's own dev checkpoint, if one exists, will show CONTENT_MISMATCH once; the file is preserved).
- No save data was deleted or moved. The stale test checkpoint from earlier suite runs is still in the PC's real user dir
  (`test_runtime/headless_offline/...`, plus older `test_saves/`, `test_offline_checkpoint/`); tests no longer read it. The owner may delete
  those test folders; the real profile (`profiles/solo_042ed...`, `offline_identity.json`) must stay.

## Resume notes (for the next session)
- Done here: test isolation and ADR-018 (Accepted). Anyone launching `run_tests.gd` directly must set `APPDATA`/`XDG_DATA_HOME` and
  `LBO_TEST_USER_ROOT` to a temp dir (the runner says so).
- When DS08 merges: add `content/world/look_stormglass.json` and `content/world/alder_street_dressing.json` to `content/save_compat.json`
  with reasons (DS08's no-collision test is the reason for the dressing file), then rerun `bash tools/run_tests.sh`.
- Later candidates for the list, each needing its own check: `accessibility.json` (tutorial step IDs), the `presentation` block of
  `offline_solo.json` (split it out first; that split changes the rules revision once).
