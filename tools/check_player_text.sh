#!/usr/bin/env bash
# RB01 release text gate (ADR-019 point 4): no internal ID, phase label, raw snake_case or developer wording on any
# player screen of a release build. Isolates user:// like tools/run_tests.sh (SAVE22), because opening the main menu
# creates a local profile.
#   bash tools/check_player_text.sh [--visible-only] [--report=build/rb01/player_text.json]
set -uo pipefail
cd "$(dirname "$0")/.."
source tools/find_tools.sh
GODOT_BIN="${GODOT_BIN:-$(find_godot)}"
[ -n "$GODOT_BIN" ] || { echo "no Godot found (set GODOT_BIN)"; exit 2; }
isolate_godot_user_dir || { echo "FAIL: cannot create an isolated Godot user dir"; exit 2; }
trap 'rm -rf "$LBO_TEST_USER_ROOT"' EXIT
# Fonts and icons must be imported, or a fresh checkout renders no text at all.
"$GODOT_BIN" --headless --path . --import >/dev/null 2>&1 || { echo "FAIL: Godot import failed"; exit 2; }
OUT="$(mktemp)"
"$GODOT_BIN" --headless --path . -s "$PWD/tools/godot/check_player_text.gd" -- "$@" 2>&1 | tee "$OUT"
STATUS="${PIPESTATUS[0]}"
if grep -qE "SCRIPT ERROR|Parse Error" "$OUT"; then echo "FAIL: Godot reported script errors"; STATUS=1; fi
grep -q "PLAYER_TEXT_RESULT ok" "$OUT" || STATUS=$(( STATUS == 0 ? 1 : STATUS ))
rm -f "$OUT"
exit "$STATUS"
