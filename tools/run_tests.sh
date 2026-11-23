#!/usr/bin/env bash
# Run every automated check that exists. Works on Linux (cloud) and Git Bash on Windows.
#   tools/run_tests.sh                 # all
#   tools/run_tests.sh --filter=grid   # only Godot test files/methods containing "grid"
# GODOT_BIN / PYTHON override discovery. Without them: `godot` on PATH, then the PC-RUNBOOK install path
# C:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe; python3, python, then py -3, skipping the Windows Store stub.
set -uo pipefail
cd "$(dirname "$0")/.."
source tools/find_tools.sh

GODOT_BIN="${GODOT_BIN:-$(find_godot)}"
PY="${PYTHON:-$(find_python)}"
FAIL=0

echo "== backlog =="
if [ -n "$PY" ]; then "$PY" tools/backlog.py validate || FAIL=1; else echo "no python found"; FAIL=1; fi

echo "== EXP01 dispatch atlas: generator, 200/200/1000 content validator =="
if [ -n "$PY" ]; then
  "$PY" tools/build_dispatch_atlas.py --check || FAIL=1
  "$PY" tools/validate_dispatch_atlas.py || FAIL=1
fi

echo "== EXP06 source-pinned 200 encounters: independent safety and puzzle audit =="
if [ -n "$PY" ]; then "$PY" tools/validate_exp06_encounters.py || FAIL=1; fi

echo "== EXP07: 200 device graphs, 1100 nodes and deterministic jam/recovery audit =="
if [ -n "$PY" ]; then "$PY" tools/validate_exp07_device_graphs.py || FAIL=1; fi

echo "== EXP08: 200 source-pinned diagnoses, 400 sensors, dual routes and recovery ==" 
if [ -n "$PY" ]; then "$PY" tools/validate_exp08_faults.py || FAIL=1; fi

echo "== EXP009: 200 source-validated consequence graphs, 600 linked services and recovery =="
if [ -n "$PY" ]; then "$PY" tools/validate_exp009_consequences.py || FAIL=1; fi

echo "== EXP010: 200 emergency logistics manifests, 400 jobs and finite stock oracle =="
if [ -n "$PY" ]; then "$PY" tools/validate_exp010_logistics.py || FAIL=1; fi

echo "== EXP011: 200 critical load boards, 600 circuits and capacity recovery oracle =="
if [ -n "$PY" ]; then "$PY" tools/validate_exp011_loads.py || FAIL=1; fi

echo "== EXP012: 200 source-pinned worksite encounter graphs and 400 routes =="
if [ -n "$PY" ]; then "$PY" tools/validate_exp012_worksites.py || FAIL=1; fi

echo "== EXP012 A02: 40 authored site-specific host interventions / 80 executable routes =="
if [ -n "$PY" ]; then "$PY" tools/validate_exp012_a02_sites.py || FAIL=1; fi

echo "== EXP013 A01: 40 additional authored sites / 80 route replays / source pins =="
if [ -n "$PY" ]; then "$PY" tools/validate_exp013_sites.py || FAIL=1; fi

echo "== EXP013 A02-A04: all available 40-site expansions and recovery oracles =="
if [ -n "$PY" ]; then "$PY" tools/validate_exp013_expansions.py || FAIL=1; fi

echo "== EXP013 A04: final 200 source-bound sites, 1000 tasks and 400 operating routes =="
if [ -n "$PY" ]; then "$PY" tools/validate_exp013_completion.py || FAIL=1; fi

echo "== EXP014 A01: 200 host-bound schematic compositions and honest mechanical diversity metrics =="
if [ -n "$PY" ]; then "$PY" tools/validate_exp014_composition.py || FAIL=1; fi

echo "== EXP014 A02: 200 source-pinned host contingencies, all 400 route oracles and >=150 noncosmetic structures =="
if [ -n "$PY" ]; then "$PY" tools/validate_exp014_contingencies.py || FAIL=1; fi

echo "== EXP014 A03: 25 authored regional facility geometries, all 200 source sites, task standoffs =="
if [ -n "$PY" ]; then "$PY" tools/validate_exp014_regions.py || FAIL=1; fi

echo "== EXP014 A04: 25 host-observed risk evidence sequences, 200 preserved cases ==" 
if [ -n "$PY" ]; then "$PY" tools/validate_exp014_feedback.py || FAIL=1; fi

echo "== EXP014 A05: 25 noncosmetic approach protocols, 200 source pins and 400 decision routes =="
if [ -n "$PY" ]; then "$PY" tools/validate_exp014_approach.py || FAIL=1; fi

echo "== EXP014 A06: five risk-specific consequence graphs, 200 sites and authenticated host gates =="
if [ -n "$PY" ]; then "$PY" tools/validate_exp014_outcomes.py || FAIL=1; fi

echo "== EXP014 A07: 25 risk-locked regions, five real hazard graphs and host authority gates =="
if [ -n "$PY" ]; then "$PY" tools/validate_exp014_hazards.py || FAIL=1; fi

echo "== EXP014 A08: 200 independently pinned nonlinear investigation graphs per route, 1000 immutable task IDs =="
if [ -n "$PY" ]; then "$PY" tools/validate_exp014_puzzles.py || FAIL=1; fi

echo "== EXP014 A09.1: 25 noncosmetic regional network structures and safe standby ties =="
if [ -n "$PY" ]; then "$PY" tools/validate_exp014_networks.py || FAIL=1; fi

echo "== EXP014 A10.1: 25-region cross-system source fingerprints and 50 original OR-join scenarios =="
if [ -n "$PY" ]; then
  "$PY" tools/validate_exp014_a10.py --report build/exp014-a10-1/source-audit.json || FAIL=1
fi

echo "== EXP016 A01: semantic mechanics variation and duplicate diagnosis =="
if [ -n "$PY" ]; then
  "$PY" tools/audit_exp016_mechanical_diversity.py --report build/exp016-a01/mechanical-diversity.json || FAIL=1
fi
echo "== EXP014 A10.4: source/legacy baseline, A10 host test inventory and release hold gate =="
if [ -n "$PY" ]; then
  "$PY" tools/qualify_exp014_a10.py --report build/exp014-a10-4/source-gate.json || FAIL=1
fi

echo "== EXP015 A01: 25 source-pinned emergency incidents and two recovery modes =="
if [ -n "$PY" ]; then
  "$PY" tools/validate_exp015_emergencies.py --report build/exp015-a01/source-audit.json || FAIL=1
fi

echo "== EXP015 A02: 25 second-junction host fault cascades, finite standby and managed fallback =="
if [ -n "$PY" ]; then
  "$PY" tools/validate_exp015_cascades.py --report build/exp015-a02/source-audit.json || FAIL=1
fi

echo "== EXP015 A03: 25 regional finale closeouts and 50 original strategy supply paths =="
if [ -n "$PY" ]; then
  "$PY" tools/validate_exp015_finales.py --report build/exp015-a03/source-audit.json || FAIL=1
fi

echo "== EXP015 A04: 25 post-finale true feeder trips and two recovery routes =="
if [ -n "$PY" ]; then
  "$PY" tools/validate_exp015_aftercare.py --report build/exp015-a04/source-audit.json || FAIL=1
fi

echo "== EXP015 A05: 25 source-bound critical-service incidents and reserve assurance =="
if [ -n "$PY" ]; then
  "$PY" tools/validate_exp015_assurance.py --report build/exp015-a05/source-audit.json || FAIL=1
fi

echo "== EXP015 A06: 25-region/50-route original authenticated three-dispatch source spine =="
if [ -n "$PY" ]; then
  "$PY" tools/qualify_exp015_region_replay.py --report build/exp015-a06/source-audit.json || FAIL=1
fi

echo "== EXP015 A07: 100 source-identical alternate-route sites and 150 role scenarios =="
if [ -n "$PY" ]; then
  "$PY" tools/validate_exp015_alt_routes.py --report build/exp015-a07/source-audit.json || FAIL=1
fi

echo "== EXP015 A08: original 50 regional rejoins, 150 true feeder/standby source paths =="
if [ -n "$PY" ]; then
  "$PY" tools/validate_exp015_rejoins.py --report build/exp015-a08/source-audit.json || FAIL=1
fi

echo "== EXP015 A09: 25 source root commissions and 100 real regional entry options =="
if [ -n "$PY" ]; then
  "$PY" tools/validate_exp015_entries.py --report build/exp015-a09/source-audit.json || FAIL=1
fi

echo "== EXP016 A02: 50 source-bound cases, 100 distinct host-authoritative routes =="
if [ -n "$PY" ]; then
  "$PY" tools/validate_exp016_casework.py || FAIL=1
  "$PY" -m unittest discover -s tools -p 'test_exp016_casework.py' -v || FAIL=1
fi

echo "== EXP016 A03: source-validated dual-probe diagnoses, 50 levels and 100 recovery routes =="
if [ -n "$PY" ]; then "$PY" tools/validate_exp016_a03.py || FAIL=1; fi

echo "== EXP016 A04: 50 finite host-evidence graphs, both routes and token conservation =="
if [ -n "$PY" ]; then "$PY" tools/validate_exp016_a04.py || FAIL=1; fi

echo "== EXP016 A05: LV_151-LV_200 finite source-attested case completion =="
if [ -n "$PY" ]; then "$PY" tools/validate_exp016_a05.py || FAIL=1; fi

echo "== EXP016 A06: 200 source-pinned concurrent fault conditions =="
if [ -n "$PY" ]; then
  "$PY" tools/validate_exp016_a06.py || FAIL=1
  "$PY" -m unittest discover -s tools -p 'test_exp016_a06.py' -v || FAIL=1
fi

echo "== EXP016 A07: source-pinned hazard operation order and preemption, 200 sites =="
if [ -n "$PY" ]; then "$PY" tools/validate_exp016_a07.py || FAIL=1; fi

echo "== EXP016 A08: host-admitted tool selection and bounded genuine worksite reserves =="
if [ -n "$PY" ]; then "$PY" tools/validate_exp016_a08.py || FAIL=1; fi

echo "== EXP016 A09: 400 source-pinned nonlinear priority/resilience policy outcomes =="
if [ -n "$PY" ]; then "$PY" tools/validate_exp016_a09.py || FAIL=1; fi

echo "== EXP016 A10: 25-region owner-scoped source graph cascade continuity =="
if [ -n "$PY" ]; then "$PY" tools/validate_exp016_a10.py || FAIL=1; fi

echo "== EXP016 A11: 200 source-attested optional discoveries and preserved lore receipts =="
if [ -n "$PY" ]; then "$PY" tools/validate_exp016_a11.py || FAIL=1; fi

echo "== EXP016 A12: all 200 cases, 400 host operation routes, full original-source oracles =="
if [ -n "$PY" ]; then
  "$PY" tools/qualify_exp016_a12.py --report build/exp016-a12/qualification.json || FAIL=1
  "$PY" -m unittest discover -s tools -p 'test_exp016_a12.py' -v || FAIL=1
fi

echo "== content (ADR-003 integer data) =="
if [ -n "$PY" ]; then "$PY" tools/validate_content.py || FAIL=1; fi

echo "== CT-BP original-blueprint source/receipt consistency (no physical certification) =="
if [ -n "$PY" ]; then "$PY" tools/check_ct_blueprint_gate.py || FAIL=1; fi

echo "== CT-L3 Hill original-blueprint source drift (no hardware certification) =="
if [ -n "$PY" ]; then "$PY" tools/check_ct_l3_gate.py || FAIL=1; fi

echo "== UI token contrast (WCAG 2.2 AA, ADR-004) =="
if [ -n "$PY" ]; then "$PY" tools/check_contrast.py | tail -1; [ "${PIPESTATUS[0]}" -eq 0 ] || FAIL=1; fi

echo "== EXP015 A10: 25 original finale debt-settlement source and conservation oracle =="
if [ -n "$PY" ]; then
  "$PY" tools/validate_exp015_settlements.py --report build/exp015-a10/source-audit.json || FAIL=1
fi
echo "== EXP015 A11: original 25-region root-to-finale resource continuity oracle =="
if [ -n "$PY" ]; then
  "$PY" tools/qualify_exp015_debt_handoff.py --report build/exp015-a11/source-audit.json || FAIL=1
fi
echo "== EXP015 A12.1: 25 original reserve-anchor feeder paths, real dark-route and fault scenarios =="
if [ -n "$PY" ]; then
  "$PY" tools/validate_exp015_anchor_routes.py --report build/exp015-a12/source-audit.json || FAIL=1
fi
echo "== EXP015 A15: integrated original source graph and evidence closeout =="
if [ -n "$PY" ]; then
  "$PY" tools/qualify_exp015_integration.py --report build/exp015-a15/qualification.json || FAIL=1
fi
echo "== EXP015 A12.16: protected-source and inherited CI coverage gate =="
if [ -n "$PY" ]; then
  "$PY" tools/exp015_stacked_qualification.py --report build/exp015-a12-16/source-gate.json || FAIL=1
fi
echo "== EXP015 A12.3: adversarial original feeder recovery versus missing receipts =="
if [ -n "$PY" ]; then
  "$PY" tools/validate_exp015_anchor_recovery.py --report build/exp015-a12-3/source-audit.json || FAIL=1
fi
echo "== EXP018 A01: regression repairs, immutable source, dual-platform CI gate =="
if [ -n "$PY" ]; then
  "$PY" tools/qualify_exp018_a01.py --report build/exp018-a01/qualification.json || FAIL=1
fi
echo "== EXP018 A02: integration ancestry and immutable source bindings =="
if [ -n "$PY" ]; then
  "$PY" tools/qualify_exp018_a02.py --report build/exp018-a02/qualification.json || FAIL=1
fi
echo "== EXP018 A03: authenticated original regional + bespoke mission host integration =="
if [ -n "$PY" ]; then
  "$PY" tools/qualify_exp018_a03.py --report build/exp018-a03/qualification.json || FAIL=1
fi
echo "== EXP018 A04: 25 region art identities / 200 host-grounded site visual bindings =="
if [ -n "$PY" ]; then
  "$PY" tools/qualify_exp018_a04.py --report build/exp018-a04/qualification.json || FAIL=1
fi
echo "== EXP018 A05: independent preflight for 200/1000/400 replay evidence =="
if [ -n "$PY" ]; then
  "$PY" tools/qualify_exp018_a05.py --report build/exp018-a05/source-preflight.json || FAIL=1
fi
echo "== python reference model (re-derived, reference/tests) =="
if [ -d reference/tests ] && [ -n "$PY" ]; then
  ( cd reference && "$PY" -m unittest discover -s tests -v ) || FAIL=1
else
  echo "skipped: reference/tests not present"
fi

echo "== F02 real-network evidence validator unit tests (preflight only) =="
if [ -n "$PY" ]; then "$PY" -m unittest discover -s tests/python -p 'test_*.py' -v || FAIL=1; fi

echo "== godot =="
if [ -f project.godot ] && [ -z "$GODOT_BIN" ]; then
  echo "FAIL: Godot 4.7.2 not found; set GODOT_BIN to the console exe (see docs/PC-RUNBOOK.md A.3)"; FAIL=1
elif [ -f project.godot ]; then
  # Godot import errors must be visible and actionable. Do not swallow parser failures.
  IMPORT_OUT="$(mktemp)"
  if ! "$GODOT_BIN" --headless --path . --import >"$IMPORT_OUT" 2>&1; then
    echo "FAIL: Godot import returned non-zero (details below)"
    cat "$IMPORT_OUT"
    FAIL=1
  elif grep -qE "SCRIPT ERROR|Parse Error" "$IMPORT_OUT"; then
    echo "FAIL: Godot import reported script/parser errors (details below)"
    cat "$IMPORT_OUT"
    FAIL=1
  fi
  rm -f "$IMPORT_OUT"
  echo "== EXP015 A03: direct Godot host script parser preflight =="
  HOST_PARSE_OUT="$(mktemp)"
  if ! "$GODOT_BIN" --headless --path . --check-only --script res://scripts/gameplay/expedition_host_session.gd >"$HOST_PARSE_OUT" 2>&1; then
    echo "FAIL: Godot host script parser rejected expedition_host_session.gd"
    cat "$HOST_PARSE_OUT"
    FAIL=1
  elif grep -qE "SCRIPT ERROR|Parse Error" "$HOST_PARSE_OUT"; then
    echo "FAIL: Godot host script parser reported source errors"
    cat "$HOST_PARSE_OUT"
    FAIL=1
  else
    echo "EXP015_A03_HOST_SCRIPT_PARSE=PASS"
  fi
  rm -f "$HOST_PARSE_OUT"
  echo "== EXP015 A09: Godot original root commissioning source parser =="
  A09_PARSE_OUT="$(mktemp)"
  if ! "$GODOT_BIN" --headless --path . --check-only --script res://scripts/gameplay/expedition_regional_entry_commissioning.gd >"$A09_PARSE_OUT" 2>&1; then
    echo "FAIL: Godot cannot parse EXP015 A09 regional entry commissioning controller"
    cat "$A09_PARSE_OUT"
    FAIL=1
  elif grep -qE "SCRIPT ERROR|Parse Error" "$A09_PARSE_OUT"; then
    echo "FAIL: Godot A09 entry controller parser returned source errors"
    cat "$A09_PARSE_OUT"
    FAIL=1
  else
    echo "EXP015_A09_ENTRY_CONTROLLER_PARSE=PASS"
  fi
  rm -f "$A09_PARSE_OUT"
  echo "== EXP015 A09: Godot authenticated root and 100 option regression parser =="
  A09_TEST_OUT="$(mktemp)"
  if ! "$GODOT_BIN" --headless --path . --check-only --script res://tests/integration/test_EXP015_A09_region_entries.gd >"$A09_TEST_OUT" 2>&1; then
    echo "FAIL: Godot cannot parse EXP015 A09 root / host test"
    cat "$A09_TEST_OUT"
    FAIL=1
  elif grep -qE "SCRIPT ERROR|Parse Error" "$A09_TEST_OUT"; then
    echo "FAIL: Godot A09 root / host parser returned source errors"
    cat "$A09_TEST_OUT"
    FAIL=1
  else
    echo "EXP015_A09_ENTRY_REPLAY_PARSE=PASS"
  fi
  rm -f "$A09_TEST_OUT"
  echo "== EXP015 A08: direct Godot regional rejoin controller parse =="
  A08_PARSE_OUT="$(mktemp)"
  if ! "$GODOT_BIN" --headless --path . --check-only --script res://scripts/gameplay/expedition_regional_rejoin_consequences.gd >"$A08_PARSE_OUT" 2>&1; then
    echo "FAIL: Godot cannot parse EXP015 A08 regional rejoin controller"
    cat "$A08_PARSE_OUT"
    FAIL=1
  elif grep -qE "SCRIPT ERROR|Parse Error" "$A08_PARSE_OUT"; then
    echo "FAIL: Godot A08 controller parser reported source errors"
    cat "$A08_PARSE_OUT"
    FAIL=1
  else
    echo "EXP015_A08_REJOIN_CONTROLLER_PARSE=PASS"
  fi
  rm -f "$A08_PARSE_OUT"
  echo "== EXP015 A08: direct Godot host rejoin regression parse =="
  A08_TEST_PARSE_OUT="$(mktemp)"
  if ! "$GODOT_BIN" --headless --path . --check-only --script res://tests/integration/test_EXP015_A08_regional_rejoins.gd >"$A08_TEST_PARSE_OUT" 2>&1; then
    echo "FAIL: Godot cannot parse EXP015 A08 host/network rejoin tests"
    cat "$A08_TEST_PARSE_OUT"
    FAIL=1
  elif grep -qE "SCRIPT ERROR|Parse Error" "$A08_TEST_PARSE_OUT"; then
    echo "FAIL: Godot A08 host/network test parser reported source errors"
    cat "$A08_TEST_PARSE_OUT"
    FAIL=1
  else
    echo "EXP015_A08_REJOIN_TEST_PARSE=PASS"
  fi
  rm -f "$A08_TEST_PARSE_OUT"
  echo "== EXP015 A07: direct Godot original alternate route controller parse =="
  A07_PARSE_OUT="$(mktemp)"
  if ! "$GODOT_BIN" --headless --path . --check-only --script res://scripts/gameplay/expedition_regional_alt_routes.gd >"$A07_PARSE_OUT" 2>&1; then
    echo "FAIL: Godot cannot parse EXP015 A07 original regional route controller"
    cat "$A07_PARSE_OUT"
    FAIL=1
  elif grep -qE "SCRIPT ERROR|Parse Error" "$A07_PARSE_OUT"; then
    echo "FAIL: Godot alternate route controller parser reported source errors"
    cat "$A07_PARSE_OUT"
    FAIL=1
  else
    echo "EXP015_A07_CONTROLLER_PARSE=PASS"
  fi
  rm -f "$A07_PARSE_OUT"
  echo "== EXP015 A07: direct Godot source and host replay test parse =="
  A07_TEST_PARSE_OUT="$(mktemp)"
  if ! "$GODOT_BIN" --headless --path . --check-only --script res://tests/integration/test_EXP015_A07_alt_routes.gd >"$A07_TEST_PARSE_OUT" 2>&1; then
    echo "FAIL: Godot cannot parse EXP015 A07 source/host regression tests"
    cat "$A07_TEST_PARSE_OUT"
    FAIL=1
  elif grep -qE "SCRIPT ERROR|Parse Error" "$A07_TEST_PARSE_OUT"; then
    echo "FAIL: Godot A07 source/host replay parser reported source errors"
    cat "$A07_TEST_PARSE_OUT"
    FAIL=1
  else
    echo "EXP015_A07_REPLAY_PARSE=PASS"
  fi
  rm -f "$A07_TEST_PARSE_OUT"
  echo "== EXP015 A06: direct Godot 3-dispatch headless replay test parse preflight =="
  A06_PARSE_OUT="$(mktemp)"
  if ! "$GODOT_BIN" --headless --path . --check-only --script res://tests/integration/test_EXP015_A06_region_replay.gd >"$A06_PARSE_OUT" 2>&1; then
    echo "FAIL: Godot cannot parse EXP015 A06 regional host replay tests"
    cat "$A06_PARSE_OUT"
    FAIL=1
  elif grep -qE "SCRIPT ERROR|Parse Error" "$A06_PARSE_OUT"; then
    echo "FAIL: Godot A06 direct parser reported invalid source"
    cat "$A06_PARSE_OUT"
    FAIL=1
  else
    echo "EXP015_A06_REPLAY_TEST_PARSE=PASS"
  fi
  rm -f "$A06_PARSE_OUT"
  echo "== EXP015 A05: direct Godot critical-service assurance script parse preflight =="
  ASSURANCE_PARSE_OUT="$(mktemp)"
  if ! "$GODOT_BIN" --headless --path . --check-only --script res://scripts/gameplay/expedition_regional_assurance.gd >"$ASSURANCE_PARSE_OUT" 2>&1; then
    echo "FAIL: Godot assurance script parser rejected expedition_regional_assurance.gd"
    cat "$ASSURANCE_PARSE_OUT"
    FAIL=1
  elif grep -qE "SCRIPT ERROR|Parse Error" "$ASSURANCE_PARSE_OUT"; then
    echo "FAIL: Godot assurance script parser reported source errors"
    cat "$ASSURANCE_PARSE_OUT"
    FAIL=1
  else
    echo "EXP015_A05_ASSURANCE_SCRIPT_PARSE=PASS"
  fi
  rm -f "$ASSURANCE_PARSE_OUT"
  echo "== EXP015 A04: direct Godot post-finale controller parse preflight =="
  AFTERCARE_PARSE_OUT="$(mktemp)"
  if ! "$GODOT_BIN" --headless --path . --check-only --script res://scripts/gameplay/expedition_regional_aftercare.gd >"$AFTERCARE_PARSE_OUT" 2>&1; then
    echo "FAIL: Godot aftercare script parser rejected expedition_regional_aftercare.gd"
    cat "$AFTERCARE_PARSE_OUT"
    FAIL=1
  elif grep -qE "SCRIPT ERROR|Parse Error" "$AFTERCARE_PARSE_OUT"; then
    echo "FAIL: Godot aftercare script parser reported source errors"
    cat "$AFTERCARE_PARSE_OUT"
    FAIL=1
  else
    echo "EXP015_A04_AFTERCARE_SCRIPT_PARSE=PASS"
  fi
  rm -f "$AFTERCARE_PARSE_OUT"
  # Every Godot run below (tests, solution traces, cross-check) gets its own empty user:// (SAVE22).
  isolate_godot_user_dir || { echo "FAIL: cannot create an isolated Godot user dir"; exit 1; }
  trap 'rm -rf "$LBO_TEST_USER_ROOT"' EXIT
  echo "isolated Godot user dir: $LBO_TEST_USER_ROOT"
  GD_OUT="$(mktemp)"
  "$GODOT_BIN" --headless --path . -s res://tests/run_tests.gd -- "$@" 2>&1 | tee "$GD_OUT"
  [ "${PIPESTATUS[0]}" -eq 0 ] || FAIL=1
  # GDScript cannot catch runtime errors, so a test that crashes mid-way could still report PASS: fail on any
  if grep -qE "SCRIPT ERROR|Parse Error" "$GD_OUT"; then echo "FAIL: Godot reported script errors (see above)"; FAIL=1; fi
  rm -f "$GD_OUT"
  echo "== solution traces: every contract with a solution.json must be solvable =="
  for sol in content/contracts/*/solution.json; do
    [ -f "$sol" ] || continue
    "$GODOT_BIN" --headless --path . -s "$PWD/tools/godot/validate_solution.gd" -- --contract="res://$(dirname "$sol")" 2>&1 | grep -E "SOLVED|MISMATCH|CONTENT ERRORS"
    [ "${PIPESTATUS[0]}" -eq 0 ] || FAIL=1
  done
  echo "== cross-check: python reference vs godot canonical hashes =="
  if [ -n "$PY" ]; then GODOT_BIN="$GODOT_BIN" "$PY" tools/cross_check_reference.py || FAIL=1; fi
else
  echo "skipped: no project.godot yet (task F01)"
fi

echo "== EXP021 A04: independent source/batch preflight and post-Godot stress evidence =="
if [ -n "$PY" ]; then
  "$PY" tools/qualify_exp021_a04.py --report build/exp021-a04/preflight.json || FAIL=1
  "$PY" tools/qualify_exp021_a04.py --post-run --report build/exp021-a04/independent.json || FAIL=1
else
  echo "FAIL: Python required for EXP021 A04 evidence gate"; FAIL=1
fi

echo "== EXP021 A05: source-joined 200-level alpha candidate preflight =="
if [ -n "$PY" ]; then
  "$PY" tools/qualify_exp021_a05.py --preflight --report build/exp021-a05/preflight.json || FAIL=1
else
  echo "FAIL: Python needed for EXP021 A05"; FAIL=1
fi

echo "== EXP018 A05: independent verification of Godot host replay evidence =="
if [ -n "$PY" ]; then
  "$PY" tools/qualify_exp018_a05.py --post-run --report build/exp018-a05/independent-verification.json || FAIL=1
else
  echo "FAIL: Python required to verify EXP018 A05 Godot replay evidence"; FAIL=1
fi
echo "== EXP021 A05: independent host/scene evidence and immutable source joins =="
if [ -n "$PY" ]; then
  "$PY" tools/qualify_exp021_a05.py --report build/exp021-a05/alpha-gate.json || FAIL=1
else
  echo "FAIL: Python needed for EXP021 A05 post-Godot evidence"; FAIL=1
fi
[ "$FAIL" -eq 0 ] && echo "ALL CHECKS PASSED" || echo "CHECKS FAILED"
exit "$FAIL"
