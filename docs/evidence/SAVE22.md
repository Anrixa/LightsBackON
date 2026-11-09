# Evidence: SAVE22 checkpoint content revision (ADR draft) and isolated test user dir

- Status claimed: test isolation DONE (tooling, verified on the owner's PC); checkpoint change **proposed only** (ADR-018 draft, owner decision).
  Not a backlog task: quality follow-up to DS08 ("Finding: content revision and checkpoints").
- Date (UTC): 2026-11-09
- Branch / commit: `task/SAVE22-checkpoint-content-revision` (code commit 33596fe, evidence and ADR in the following commit)
- Environment: local desktop session on the owner's PC (Windows 11, Git Bash), headless Godot
- Engine: Godot 4.7.2.stable.official.ed1daf0bf (console exe, `C:\Tools\Godot`)
- Content revision / protocol version / save schema: unchanged by this task (no `content/` file touched); protocol 1; save schema 1

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
- `tests/unit/test_SAVE22_isolated_user_dir.gd`: this run's user://, the headless offline sandbox and `user://profiles` all globalize inside
  `LBO_TEST_USER_ROOT`; the guard refuses a missing root, the real `%APPDATA%` path, a same-prefix sibling, the root itself and a `..` escape;
  accepts Windows paths with backslashes and different case; Linux stays case-sensitive.
- `tests/python/test_qa_resource_probe.py::test_SAVE22_probe_runs_point_godot_user_dir_at_the_temp_root`.

## Not verified / pending
- Linux CI and the `windows` CI job run the same `run_tests.sh`; their result is on the PR, not here. The QA51 probe workflow runs only on
  matching paths (this PR touches `tests/run_tests.gd`, so it should trigger); not run locally.
- macOS (Godot reads `$HOME/Library/Application Support`) is not isolated; not a target platform.
- ADR-018 is a draft: nothing in `scripts/persistence/` or the save format changed. Existing checkpoints behave exactly as before.
- No save data was deleted or moved. The stale test checkpoint from earlier suite runs is still in the PC's real user dir
  (`test_runtime/headless_offline/...`, plus older `test_saves/`, `test_offline_checkpoint/`); tests no longer read it. The owner may delete
  those test folders; the real profile (`profiles/solo_042ed...`, `offline_identity.json`) must stay.

## Resume notes (for the next session)
- Test isolation is merged with this PR. Anyone launching `run_tests.gd` directly must set `APPDATA`/`XDG_DATA_HOME` and `LBO_TEST_USER_ROOT`
  to a temp dir (the runner says so).
- Next, only after the owner approves ADR-018 (change it to Accepted, record the date): implement decision 7's guards first, then the
  `rules_revision` hash (Godot + `build_manifest.py` + cross-check), `content/save_compat.json`, the envelope field and the load branch.
  The DS08 dressing/look files exist only on `task/DS08-stormglass-look` until it merges; the list's globs match them once it does.
