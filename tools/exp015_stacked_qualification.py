#!/usr/bin/env python3
"""EXP015 A12.16: reproducible, fail-closed stacked-source qualification.

The output is deliberately NOT a GitHub Actions success claim. CI and Windows
export evidence must be attached externally to the exact commit under review.
"""
from __future__ import annotations

import argparse
import json
import re
from pathlib import Path
from typing import Any

if __package__:
    from . import qualify_exp014_a10 as baseline
else:
    import qualify_exp014_a10 as baseline

ROOT = Path(__file__).resolve().parents[1]
PHASE = "EXP015_A12_16"
REQUIRED_TESTS: dict[str, tuple[str, ...]] = {
    "tests/integration/test_EXP015_A06_region_replay.gd": (
        "test_EXP015_A06_50_auth_host_cross_dispatch_full_region_chains",
        "test_EXP015_A06_separate_accounts_do_not_share_network_state",
        "test_EXP015_A13_50_region_branch_replays_refuse_two_retired_hosts",
    ),
    "tests/integration/test_EXP015_A12_13_stale_snapshots.gd": (
        "test_EXP015_A12_13_25_region_stale_host_snapshots_fail_closed",
        "test_EXP015_A12_13_no_A09_legacy_snapshots_still_work",
        "test_EXP015_A12_14_all_25_regions_block_obsolete_host_lifecycle",
        "test_EXP015_A12_14_non_regional_transport_lifecycle_unchanged",
        "test_EXP015_A12_15_25_regions_reject_rebound_guards_and_cached_success",
        "test_EXP015_A12_15_legacy_duplicate_reply_remains_idempotent",
        "test_EXP015_A12_17_25_regions_reject_stale_reconfiguration",
        "test_EXP015_A12_17_nonregional_setup_compatibility",
    ),
}
REQUIRED_OWNER_HOLDS = tuple(sorted(baseline.HOLDS))


def check_inventory(root: Path, required: dict[str, tuple[str, ...]] | None = None) -> dict[str, Any]:
    """Verify unique exact test declarations; never mistake presence for execution."""
    required = REQUIRED_TESTS if required is None else required
    found: dict[str, list[str]] = {}
    for filename, functions in sorted(required.items()):
        path = root / filename
        if not path.is_file():
            raise ValueError(f"{PHASE}_REQUIRED_TEST_FILE_MISSING: {filename}")
        source = path.read_text(encoding="utf-8")
        declared = re.findall(r"^func (test_[A-Za-z_0-9]+)\(", source, flags=re.MULTILINE)
        if len(declared) != len(set(declared)):
            raise ValueError(f"{PHASE}_DUPLICATE_TEST_NAME: {filename}")
        for method in functions:
            if declared.count(method) != 1:
                raise ValueError(f"{PHASE}_MISSING_TEST_METHOD: {filename}: {method}")
        found[filename] = list(functions)
    return {
        "source_inventory": found,
        "expected_methods": sum(map(len, required.values())),
        "test_execution_proved_by_inventory": False,
    }


def check_workflow(root: Path) -> None:
    workflow = (root / ".github/workflows/ci.yml").read_text(encoding="utf-8")
    for expected in ("pull_request:", "linux:", "windows:", "tools/run_tests.sh"):
        if expected not in workflow:
            raise ValueError(f"{PHASE}_INHERITED_CI_GUARD_MISSING: {expected}")
    runner = (root / "tools/run_tests.sh").read_text(encoding="utf-8")
    if "unittest discover -s tests/python -p 'test_*.py'" not in runner:
        raise ValueError(f"{PHASE}_PYTHON_TEST_DISCOVERY_DISABLED")
    if "== godot ==" not in runner:
        raise ValueError(f"{PHASE}_GODOT_SUITE_DISABLED")


def qualify(root: Path = ROOT) -> dict[str, Any]:
    inventory = check_inventory(root)
    check_workflow(root)
    # Exact protected source objects and immutable original C01-C12 assets
    # still use the established Git object gate, not a textual approximation.
    if root.resolve() != ROOT.resolve():
        raise ValueError(f"{PHASE}_ROOT_MISMATCH")
    protected = baseline.protected_git_audit()
    accepted_host_objects = {
        baseline.PINNED_SESSION_HOST_EVOLUTIONS[label] for label in (
            "EXP015_A12_15_BIND_ONCE_REPLAY_FENCE",
            "EXP015_A12_17_HOST_RECONFIGURATION_SEAL",
        )
    }
    actual_host = protected["protected_objects"]["scripts/network/session_host.gd"]
    if actual_host not in accepted_host_objects:
        raise ValueError(f"{PHASE}_UNEXPECTED_SESSION_HOST_OBJECT")
    if any(baseline.HOLDS[key] != "HOLD" for key in REQUIRED_OWNER_HOLDS):
        raise ValueError(f"{PHASE}_OWNER_HOLD_DRIFT")
    return {
        "phase": PHASE,
        "head_commit": protected["head_commit"],
        "protected_source": "PINNED_UNREVIEWED_OBJECTS",
        "source_host_object": actual_host,
        **inventory,
        "inherited_ci_workflow_present": True,
        "original_contracts_preserved": True,
        "exact_head_linux_windows_ci": "EXTERNAL_EVIDENCE_REQUIRED",
        "windows_export_headless": "EXTERNAL_EVIDENCE_REQUIRED",
        "independent_review": "PENDING",
        "owner_holds": baseline.HOLDS.copy(),
        "ready_for_merge_or_release": False,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report", type=Path, default=Path("build/exp015-a12-16/source-gate.json"))
    args = parser.parse_args()
    try:
        report = qualify()
    except (ValueError, OSError, baseline.QualificationError) as exc:
        print(f"[FAIL][{PHASE}] {exc}", flush=True)
        return 1
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"[PASS][{PHASE}] head={report['head_commit']} protected_source=PINNED", flush=True)
    print(f"[HOLD][{PHASE}] CI/export/review/physical/release external; report={args.report}", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
