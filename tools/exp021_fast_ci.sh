#!/usr/bin/env bash
# EXP021 focused source/headless regression; no owner saves are touched.
set -Eeuo pipefail
cd "$(dirname "$0")/.."
source tools/find_tools.sh

if [ -z "$(printenv GODOT_BIN || true)" ]; then
  echo "[FAIL][EXP021_FAST] Godot 4.7.2 binary missing"; exit 1
fi
PY="$(find_python)"
if [ -z "$PY" ]; then
  echo "[FAIL][EXP021_FAST] Python 3 is required"; exit 1
fi
echo "[STAGE 1/5][EXP021_FAST] Godot engine"
"$GODOT_BIN" --headless --version
echo "[STAGE 2/5][EXP021_FAST] Original sources and alpha holds"
"$PY" tools/qualify_exp021_a04.py --report build/exp021-a04/fast-preflight.json
"$PY" tools/qualify_exp021_a05.py --preflight --report build/exp021-a05/fast-preflight.json
echo "[STAGE 3/5][EXP021_FAST] Isolate user:// and import"
isolate_godot_user_dir
trap 'rm -rf "$LBO_TEST_USER_ROOT"' EXIT
printf '[INFO][EXP021_FAST] Godot user root: %s\n' "$LBO_TEST_USER_ROOT"
"$GODOT_BIN" --headless --path . --import
echo "[STAGE 4/5][EXP021_FAST] Actual EXP021 A01–A05 Godot suites"
"$GODOT_BIN" --headless --path . -s res://tests/run_tests.gd -- --filter=EXP021 --settle-frames=6
echo "[STAGE 5/5][EXP021_FAST] Independent A04 and A05 evidence"
"$PY" tools/qualify_exp021_a04.py --post-run --report build/exp021-a04/fast-independent.json
"$PY" - <<'PY'
import json
from pathlib import Path
p = Path("build/exp021-a05/scene-host-evidence.json")
if not p.is_file():
    raise SystemExit("[FAIL][EXP021_FAST] Actual Godot A05 report missing")
d = json.loads(p.read_text(encoding="utf-8"))
expected = {
    "phase": "EXP021_A05", "status": "PASS", "scene_builds": 200,
    "host_startups": 200, "original_task_ids": 1000,
    "full_audio_fx_samples": 25,
    "actual_mission_director_completions": "NOT_ESTABLISHED",
}
for key, value in expected.items():
    if d.get(key) != value:
        raise SystemExit(f"[FAIL][EXP021_FAST] {key}: {d.get(key)!r} != {value!r}")
print("[PASS][EXP021_FAST] 200 constructed scenes/hosts and 1000 original task IDs")
print("[HOLD][EXP021_FAST] Alpha, mission completion, GPU, controller and Steam")
PY
echo "[PASS][EXP021_FAST] Focused source/headless qualification"
