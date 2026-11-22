#!/usr/bin/env python3
"""EXP018 A01: fail-closed source and regression-assertion qualification.

The inherited Godot tests execute via run_tests.sh. This gate cannot promote
test inventory or a Linux result into Windows, hardware, or release approval.
"""
from __future__ import annotations

import argparse
import copy
import json
from pathlib import Path

from tools import qualify_exp015_integration as a15
from tools import exp015_stacked_qualification as stack
from tools import qualify_exp014_a10 as baseline

ROOT = Path(__file__).resolve().parents[1]
SUITE = "tests/integration/test_EXP015_A12_13_stale_snapshots.gd"
REQUIRED = (
    "test_EXP015_A12_15_25_regions_reject_rebound_guards_and_cached_success",
    "test_EXP015_A12_15_legacy_duplicate_reply_remains_idempotent",
    "test_EXP015_A12_17_25_regions_reject_stale_reconfiguration",
    "test_EXP015_A14_25_region_adverse_recovery_preserves_finite_source",
)

def verify_regressions(root: Path = ROOT) -> dict:
    """Check exact regression assertions, not only declared test names."""
    source = (root / SUITE).read_text(encoding="utf-8")
    found = stack.check_inventory(root)
    for name in REQUIRED:
        if source.count("func " + name + "(") != 1:
            raise ValueError("EXP018_A01_MISSING_REGRESSION: " + name)
    cached = source.split("func " + REQUIRED[0] + "(")[1].split("\nfunc ", 1)[0]
    for token in (
        "EXP015_A12_15_STALE_REPLAY",
        "EXP015_A12_9_STALE_HOST_DISPATCH",
        "denied_again", "old.mission.canonical_state()",
        "reserve_after_first", "stale_hash",
    ):
        if token not in cached:
            raise ValueError("EXP018_A01_STALE_REPLAY_GUARD_MISSING: " + token)
    reconfigure = source.split("func " + REQUIRED[2] + "(")[1].split("\nfunc ", 1)[0]
    steps = (
        "var new_context: Dictionary = _start(",
        "previous.host.authoritative_state()",
        "var original_hash: String = previous.host.state_hash()",
        "previous.host.configure(",
        "assert_eq(previous.host.state_hash(), original_hash)",
    )
    positions = [reconfigure.find(item) for item in steps]
    if -1 in positions or positions != sorted(positions):
        raise ValueError("EXP018_A01_POST_TAKEOVER_HASH_BASELINE_INVALID")
    return {
        "regression_methods": list(REQUIRED),
        "source_assertions": "PASS",
        "inventory_execution_claimed": bool(found["test_execution_proved_by_inventory"]),
    }

def qualify(root: Path = ROOT) -> dict:
    if root.resolve() != ROOT.resolve():
        raise ValueError("EXP018_A01_ROOT_MISMATCH")
    inherited = a15.qualify(root)
    assertions = verify_regressions(root)
    if assertions["inventory_execution_claimed"]:
        raise ValueError("EXP018_A01_INVENTORY_CLAIMS_EXECUTION")
    atlas, regions = a15.load_sources(root)
    before = copy.deepcopy((atlas, regions))
    graph = a15.audit_original_regions(atlas, regions)
    if (atlas, regions) != before:
        raise ValueError("EXP018_A01_AUDIT_MUTATED_AUTHORED_SOURCE")
    for key, expected in (
        ("regions", 25), ("authored_levels", 200),
        ("source_task_ids", 1000), ("original_primary_feeders", 175),
    ):
        if graph[key] != expected:
            raise ValueError("EXP018_A01_AUTHORING_DRIFT: " + key)
    workflow = (root / ".github/workflows/ci.yml").read_text(encoding="utf-8")
    if not all(s in workflow for s in ("linux:", "windows:", "pull_request:", "tools/run_tests.sh")):
        raise ValueError("EXP018_A01_DUAL_PLATFORM_CI_NOT_WIRED")
    if not all(x == "HOLD" for x in baseline.HOLDS.values()):
        raise ValueError("EXP018_A01_RELEASE_HOLD_DRIFT")
    return {
        "phase": "EXP018_A01",
        "qualified_head": inherited["head_commit"],
        "protected_objects": inherited["protected_objects"],
        "regional_source": graph,
        "regressions": assertions,
        "linux_windows_ci": "EXACT_HEAD_EXTERNAL_RESULTS_REQUIRED",
        "release_and_hardware": "HOLD",
        "ready_for_merge": False,
        "ready_for_release": False,
    }

def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report", type=Path, default=Path("build/exp018-a01/qualification.json"))
    args = parser.parse_args()
    try:
        report = qualify()
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(report, sort_keys=True, indent=2) + "\n", encoding="utf-8")
    except (OSError, ValueError, TypeError, KeyError, baseline.QualificationError) as exc:
        print("[FAIL][EXP018_A01] " + str(exc), flush=True)
        return 1
    print("[PASS][EXP018_A01] restored_stale_reply_guard=PASS hash_baseline=PASS "
          "source=25/200/1000", flush=True)
    print("[HOLD][EXP018_A01] Linux/Windows exact-head status and all owner holds "
          "require separate CI/review evidence; report=" + str(args.report), flush=True)
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
