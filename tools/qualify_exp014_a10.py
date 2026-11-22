#!/usr/bin/env python3
"""EXP014 A10.4: fail-closed source and Windows export qualification evidence.

This is a *source/headless* verification tool. It must never turn passing
automated tests, synthetic EXP04 receipts, or a headless boot into a human,
physical, Steam multiplayer, hardware, production-save or release certificate.

Run:
  python tools/qualify_exp014_a10.py --report build/exp014-a10-4/source.json
  python tools/qualify_exp014_a10.py --windows-export-dir build/windows \
      --build-manifest build_manifest.json --smoke-log build/smoke.log \
      --report build/exp014-a10-4/windows.json

Every read of Git is local/read-only. No remote API, clean, reset, merge, tag,
file deletion or modification of protected production content is performed.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path
from typing import Any

if __package__:
    from .validate_exp014_a10 import audit, read_sources, canonical_sha, investigation_schedule
    from .validate_exp014_outcomes import parse_script as parse_risks
else:
    from validate_exp014_a10 import audit, read_sources, canonical_sha, investigation_schedule
    from validate_exp014_outcomes import parse_script as parse_risks

ROOT = Path(__file__).resolve().parents[1]
PHASE = "EXP014_A10_4"
QUALIFICATION = "SOURCE_AND_HEADLESS_ONLY_RELEASE_HELD"

# Git object IDs were independently read from the vetted A10.3 exact-head tree.
# The complete original 12-contract subtree is pinned as ONE tree object:
# modifying, adding, or deleting any contract file changes this object ID.
PROTECTED_GIT_OBJECTS: dict[str, str] = {
    "content/contracts": "f286055a1c976fce39e5a954eb355b3d0dc53eda",
    "scripts/progression/reward_service.gd": "10ebb388458d9c0dd0f885719dabdc134e9e993d",
    "scripts/progression/expedition_ledger.gd": "c576e7de586d79922ce5f27c5c29e88e94fb8063",
    "scripts/progression/expedition_campaign.gd": "cd1fc1df2b7cc9df9a45d5ccf65cc31577e2f64a",
    "scripts/persistence/save_service.gd": "f207ce900468c62b8a8685bcf23af9ef11991823",
    "scripts/persistence/offline_persistence.gd": "858eba2f027bacc7142bb86ac7ded977d437ca75",
    "scenes/expeditions/atlas.json": "333ff26fd8cc83c7398f1eca2103ff6acd156669",
    "scenes/expeditions/campaign_routes.json": "909d29571256e8dcef03beea03d7d2b2b1181f92",
    "scripts/network/session_host.gd": "e6e5be08fca46d7307396245cd5fdfc1715d2577",
}

# Preserve A10.3's exact host baseline while recognizing one source-only
# later host authorization revision. Any other SessionHost blob is refused.
# This is a hash exception, not an independent review or production approval.
PINNED_SESSION_HOST_EVOLUTIONS: dict[str, str] = {
    "EXP015_A12_11_HOST_TICK_FENCE": "c42c0b89bd8a798e242cf6f512b1c2d435ed80bf",
    "EXP015_A12_13_STALE_SNAPSHOT_FENCE": "892734a303dc2fdeec414c7f83d86cdb1c3c8083",
    "EXP015_A12_14_STALE_LIFECYCLE_FENCE": "e9ab7d3f409537070d48c792f8a1e889279f54c8",
    "EXP015_A12_15_BIND_ONCE_REPLAY_FENCE": "78001f7c3cd360226440f6fa8483f9395bbfaa9c",
    # Original baseline preserved. A12.15 CI repair adds the exact revised blob.
    "EXP015_A12_15_DENIED_REPLAY_COMPAT": "53b34e5680e1774930c77c974433cde315f3a0b6",
}

# Exact, descriptive tests are pinned, not just total test counts. All run in
# the unmodified recursive Godot suite; this inventory proves their presence,
# not their execution. Exact-head CI must prove execution separately.
REQUIRED_GODOT_TESTS: dict[str, tuple[str, ...]] = {
    "tests/integration/test_EXP014_A10_2_host_scenarios.gd": (
        "test_EXP014_A10_2_all_25_regions_both_strategies_use_real_host_ingress",
        "test_EXP014_A10_2_cross_dispatch_regions_keep_strategy_but_not_forged_progress",
        "test_EXP014_A10_2_host_commands_preserve_break_before_make_and_recovery",
        "test_EXP014_A10_2_saved_receipt_rollback_rejected_by_existing_live_host",
        "test_EXP014_A10_2_regional_preparation_does_not_bypass_a07_a08_host_gates",
    ),
    "tests/integration/test_EXP014_A10_3_adversarial_invariants.gd": (
        "test_EXP014_A10_3_all_25_regions_reject_fault_forgery_and_broken_source_schemas",
        "test_EXP014_A10_3_all_25_regions_finite_standby_and_bbm_under_missing_supply",
        "test_EXP014_A10_3_forged_duplicate_receipts_never_rewrite_legacy_economy",
        "test_EXP014_A10_3_host_rejects_malformed_foreign_stale_and_client_progress",
    ),
}

HOLDS: dict[str, str] = {
    "human_controller_playability": "HOLD",
    "physical_collisions_routes_and_los": "HOLD",
    "hardware_gpu_performance": "HOLD",
    "steam_real_two_peer_multiplayer": "HOLD",
    "process_restart_regional_durability": "HOLD",
    "production_saves_rewards_and_economy": "HOLD",
    "independent_integration_review": "HOLD",
    "production_release": "HOLD",
}


class QualificationError(ValueError):
    """An audit dependency or explicit invariant has been violated."""


def require(condition: bool, code: str, detail: str = "") -> None:
    if not condition:
        raise QualificationError(f"{PHASE}_{code}" + (f": {detail}" if detail else ""))


def git(*args: str) -> str:
    try:
        proc = subprocess.run(
            ["git", *args], cwd=ROOT, text=True, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, check=True, timeout=20,
        )
    except (FileNotFoundError, subprocess.CalledProcessError,
            subprocess.TimeoutExpired) as exc:
        raise QualificationError(f"{PHASE}_GIT_ERROR: {' '.join(args)}: {exc}") from exc
    return proc.stdout.strip()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def protected_git_audit() -> dict[str, Any]:
    """Check the original contracts and monetary/saving authorities by Git OID.

    Checking Git's tree IDs AND the actual tracked working files prevents a
    dirty worktree from masquerading as the reviewed commit.
    """
    head = git("rev-parse", "HEAD")
    require(bool(re.fullmatch(r"[a-f0-9]{40}", head)), "BAD_HEAD")
    paths = list(PROTECTED_GIT_OBJECTS)
    dirty = git("status", "--porcelain", "--untracked-files=all", "--", *paths)
    require(not dirty, "PROTECTED_WORKTREE_DIRTY", dirty[:500])
    found: dict[str, str] = {}
    host_evolution: str | None = None
    host_path = "scripts/network/session_host.gd"
    for path, expected in PROTECTED_GIT_OBJECTS.items():
        actual = git("rev-parse", f"HEAD:{path}")
        accepted = actual == expected
        if path == host_path and not accepted:
            for label, pinned_oid in PINNED_SESSION_HOST_EVOLUTIONS.items():
                if actual == pinned_oid:
                    accepted = True
                    host_evolution = label
                    break
        require(accepted, "PROTECTED_SOURCE_DRIFT",
                f"{path}: baseline={expected}, actual={actual}")
        # For the tree, Git status above checks tracked/untracked modifications.
        # Check the actual accepted blob rather than overwriting the A10.3
        # protected-source baseline with a newly generated value.
        if path != "content/contracts":
            disk_oid = git("hash-object", "--", path)
            require(disk_oid == actual, "PROTECTED_DISK_DRIFT", path)
        found[path] = actual
    return {"head_commit": head, "baseline": "A10.3_EXACT_HEAD",
            "original_contract_tree_object": found["content/contracts"],
            "protected_objects": found, "protected_worktree_clean": True,
            "source_host_baseline_oid": PROTECTED_GIT_OBJECTS[host_path],
            "source_host_evolution": host_evolution,
            "source_host_evolution_independently_reviewed": False}


def mechanical_structure(contingency: dict, inquiry: dict) -> dict[str, Any]:
    """Mechanics-only fingerprint, normalizing source-specific target IDs.

    Never count level ID, task ID, stage prose, step action names or clock
    durations as independent mechanical differentiation. Station *roles*
    and actual guard/dependency/choice topology do count.
    """
    targets = contingency.get("targets", {})
    require(isinstance(targets, dict) and set(targets) == {"A", "B", "C"} and
            len(set(targets.values())) == 3,
            "MISSING_MECHANICAL_TARGET_ROLES")
    inverse = {value: role for role, value in targets.items()}
    branches = inquiry.get("branches", {})
    require(isinstance(branches, dict) and
            set(branches) == {"forensic", "field"}, "BAD_MECHANICAL_BRANCHES")
    routes = contingency.get("routes", {})
    require(isinstance(routes, dict) and
            set(routes) == {"priority", "resilience"}, "BAD_MECHANICAL_ROUTES")
    steps: dict[str, list[list[str]]] = {}
    for mode in ("priority", "resilience"):
        route = routes[mode]
        require(isinstance(route, list) and len(route) == 3,
                "BAD_MECHANICAL_ROUTE_STEPS", mode)
        path: list[list[str]] = []
        for step in route:
            require(isinstance(step, dict) and
                    all(step.get(field) in inverse
                        for field in ("target", "support", "witness")),
                    "FORGED_MECHANICAL_TARGET", mode)
            path.append([
                step["mode"], step["guard"], step["failure"],
                inverse[step["target"]], inverse[step["support"]],
                inverse[step["witness"]],
            ])
        steps[mode] = path
    return {
        "risk_class": inquiry["risk_class"],
        "investigations": {
            mode: investigation_schedule(branches[mode], mode)
            for mode in ("forensic", "field")
        },
        "contingency_role_graphs": steps,
    }


def id_normalized_mechanical_audit(contingencies: dict,
                                   investigations: dict) -> dict[str, Any]:
    """Independent 200-site diversity check with no numeric site identities."""
    old = contingencies.get("entries", [])
    revised = investigations.get("entries", [])
    require(isinstance(old, list) and len(old) == 200 and
            isinstance(revised, list) and len(revised) == 200,
            "MECHANICAL_SOURCE_CARDINALITY")
    by_site = {item.get("level_id"): item for item in revised}
    require(len(by_site) == 200, "MECHANICAL_DUPLICATE_INVESTIGATION")
    unique: set[str] = set()
    for entry in old:
        level = entry.get("level_id")
        require(level in by_site, "MECHANICAL_SOURCE_JOIN", str(level))
        digest = canonical_sha(mechanical_structure(entry, by_site[level]))
        require(digest not in unique, "RENAMED_SITE_MECHANICAL_COLLISION",
                str(level))
        unique.add(digest)
    require(len(unique) == 200, "RENAMED_SITE_MECHANICAL_COVERAGE")
    return {"site_count": 200, "unique_mechanics_without_ids": 200,
            "normalized_signature_set_sha256": canonical_sha(sorted(unique)),
            "ignored": ["level_id", "target_numeric_id", "action_prose",
                        "titles", "clock_dwell_or_window_ticks"]}


def source_audit() -> dict[str, Any]:
    classes, _ = parse_risks()
    sources = read_sources()
    full = audit(**sources, risk_classes=classes)
    independent = id_normalized_mechanical_audit(
        sources["contingencies"], sources["investigations"])
    expectations = {
        "regions": 25, "locations": 200, "levels": 200,
        "immutable_task_ids": 1000, "original_lore_ids": 200,
        "distinct_mechanical_source_fingerprints": 200,
        "distinct_unlabeled_regional_networks": 25,
        "cross_system_campaign_branch_scenarios": 50,
        "branch_dispatch_source_visits": 300,
    }
    require(full.get("ok") is True, "SOURCE_ORACLE_NOT_PASS")
    for field, expected in expectations.items():
        require(full.get(field) == expected, "SOURCE_COVERAGE_DRIFT",
                f"{field} expected {expected}, found {full.get(field)}")
    require(full.get("distinct_investigation_source_graphs") ==
            {"forensic": 200, "field": 200}, "A08_GRAPH_COVERAGE")
    require(full.get("all_branch_scenarios_reach_finale") is True,
            "ABSTRACT_BRANCH_REACHABILITY")
    require(full.get("physical_playability_certified") is False and
            full.get("hardware_steam_release_certified") is False,
            "SOURCE_ORACLE_FALSE_CERTIFICATION")
    return {
        "source_oracle": "EXP014_A10_1",
        "expected": expectations,
        "investigation_graphs": {"forensic": 200, "field": 200},
        "mechanical_fingerprint_sha256": full["source_fingerprint_sha256"],
        "independent_id_normalized_mechanics": independent,
        "source_coverage_checked": True,
        "note": "Abstract source paths are NOT host replay, physical play or release",
    }


def discover_host_tests(path: Path) -> tuple[str, ...]:
    require(path.is_file(), "MISSING_HOST_TEST_FILE", str(path))
    content = path.read_text(encoding="utf-8")
    names = re.findall(
        r"^func (test_EXP014_A10_[23]_[a-zA-Z0-9_]+)\(\) -> void:\s*$",
        content, flags=re.MULTILINE,
    )
    require(len(names) == len(set(names)), "DUPLICATE_HOST_TEST", str(path))
    return tuple(names)


def host_test_inventory() -> dict[str, Any]:
    found: dict[str, list[str]] = {}
    all_names: set[str] = set()
    for rel, required in REQUIRED_GODOT_TESTS.items():
        names = set(discover_host_tests(ROOT / rel))
        missing = set(required) - names
        require(not missing, "MISSING_GODOT_TESTS",
                f"{rel}: {sorted(missing)}")
        require(not all_names.intersection(names), "CROSS_FILE_DUPLICATE_TEST", rel)
        all_names.update(names)
        sidecar = ROOT / (rel + ".uid")
        require(sidecar.is_file() and
                bool(re.fullmatch(r"uid://[a-zA-Z0-9_]+",
                                  sidecar.read_text(encoding="utf-8").strip())),
                "MISSING_GODOT_UID", rel)
        found[rel] = sorted(names)
    return {"expected_test_methods": sum(map(len, REQUIRED_GODOT_TESTS.values())),
            "discovered_test_methods": len(all_names),
            "test_files": found,
            "execution_proved_by_this_check": False,
            "execution_requires_exact_head_linux_windows_ci": True}


def exported_windows_evidence(exe_dir: Path, build_manifest: Path,
                              smoke_log: Path, head: str) -> dict[str, Any]:
    """Prove source-pinned headless Windows export identity; NOT real device use."""
    require(build_manifest.is_file(), "WINDOWS_MANIFEST_MISSING",
            str(build_manifest))
    main = json.loads(build_manifest.read_text(encoding="utf-8"))
    build_id = main.get("build_id")
    require(isinstance(build_id, str) and
            bool(re.fullmatch(r"[0-9]{8}T[0-9]{6}Z-[a-f0-9]{10}", build_id)),
            "WINDOWS_BUILD_ID", repr(build_id))
    require(main.get("git_commit") == head and main.get("git_dirty") is False,
            "WINDOWS_EXPORT_SOURCE_NOT_PINNED",
            f"expected HEAD={head}, found {main.get('git_commit')}")
    require(isinstance(main.get("content_revision"), str) and
            bool(re.fullmatch(r"[a-f0-9]{64}", main["content_revision"])),
            "WINDOWS_CONTENT_REVISION")
    require(isinstance(main.get("rules_revision"), str) and
            bool(re.fullmatch(r"[a-f0-9]{64}", main["rules_revision"])),
            "WINDOWS_RULES_REVISION")
    packaged = exe_dir / "build_manifest.json"
    require(packaged.is_file() and packaged.read_bytes() == build_manifest.read_bytes(),
            "WINDOWS_PACKAGED_MANIFEST_MISMATCH")
    binaries: dict[str, dict[str, Any]] = {}
    for name in ("LightsBackOn.exe", "LightsBackOn.pck"):
        candidate = exe_dir / name
        require(candidate.is_file() and candidate.stat().st_size > 4096,
                "WINDOWS_EXPORTED_BINARY_MISSING", str(candidate))
        binaries[name] = {"bytes": candidate.stat().st_size,
                          "sha256": sha256_file(candidate)}
    require(smoke_log.is_file(), "WINDOWS_SMOKE_LOG_MISSING",
            str(smoke_log))
    smoke = smoke_log.read_text(encoding="utf-8", errors="replace")
    require(any("Lights Back On boot" in line and f"build {build_id}" in line
                for line in smoke.splitlines()),
            "WINDOWS_BOOT_SOURCE_MISMATCH", build_id)
    return {
        "status": "WINDOWS_HEADLESS_EXPORTED_BOOT_EVIDENCE_ONLY",
        "build_id": build_id, "git_commit": head,
        "packaged_manifest_sha256": sha256_file(packaged),
        "boot_log_sha256": sha256_file(smoke_log),
        "artifacts": binaries,
        "physical_and_multiplayer_certified": False,
    }


def qualify(*, windows_export_dir: Path | None = None,
            build_manifest: Path | None = None,
            smoke_log: Path | None = None) -> dict[str, Any]:
    git_evidence = protected_git_audit()
    source = source_audit()
    tests = host_test_inventory()
    windows: dict[str, Any] | None = None
    if any(v is not None for v in (windows_export_dir, build_manifest, smoke_log)):
        require(all(v is not None for v in
                    (windows_export_dir, build_manifest, smoke_log)),
                "PARTIAL_WINDOWS_EVIDENCE_ARGUMENTS")
        assert windows_export_dir is not None
        assert build_manifest is not None
        assert smoke_log is not None
        windows = exported_windows_evidence(
            windows_export_dir, build_manifest, smoke_log,
            git_evidence["head_commit"],
        )
    return {
        "ok": True, "phase": PHASE, "qualification": QUALIFICATION,
        "source_git": git_evidence, "source_coverage": source,
        "host_test_inventory": tests,
        "windows_export": windows,
        "windows_export_verified": windows is not None,
        "prior_exact_head_ci_status": "EXTERNAL_EVIDENCE_NOT_INFERRED",
        "current_exact_head_ci_status": "EXTERNAL_EVIDENCE_NOT_INFERRED",
        "independent_review_status": "PENDING",
        "all_owner_release_holds": dict(HOLDS),
        "ready_for_merge_or_release": False,
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report", type=Path, help="Write JSON evidence")
    parser.add_argument("--windows-export-dir", type=Path)
    parser.add_argument("--build-manifest", type=Path)
    parser.add_argument("--smoke-log", type=Path)
    args = parser.parse_args(argv)
    try:
        result = qualify(
            windows_export_dir=args.windows_export_dir,
            build_manifest=args.build_manifest, smoke_log=args.smoke_log,
        )
    except (QualificationError, ValueError, OSError, KeyError) as exc:
        result = {"ok": False, "phase": PHASE, "qualification": QUALIFICATION,
                  "failure": str(exc), "all_owner_release_holds": dict(HOLDS),
                  "ready_for_merge_or_release": False}
        status = 1
    else:
        status = 0
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(
            json.dumps(result, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
    print(f"{PHASE} qualification={'PASS_SOURCE_ONLY' if status == 0 else 'FAIL_CLOSED'}")
    print(json.dumps(result, sort_keys=True))
    return status


if __name__ == "__main__":
    sys.exit(main())
