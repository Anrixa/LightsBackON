#!/usr/bin/env python3
"""Read-only, fail-closed evidence reconciliation of the 66 original roadmap tasks.

The original backlog is the acceptance authority. Later feature work can provide
source overlap without automatically promoting a task to DONE.
"""

from __future__ import annotations

import argparse
import json
from collections import Counter
from pathlib import Path
from typing import Any

REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_AUDIT = REPOSITORY_ROOT / "docs/progress/roadmap-reconciliation.json"
DEFAULT_BACKLOG = REPOSITORY_ROOT / "docs/backlog.json"

PRE_BETA = frozenset({"F", "G", "V", "A", "D", "CT", "H"})
VALID_OVERLAY = frozenset({
    "ACCEPTED", "CLOUD_VERIFIED", "SOURCE_OVERLAP",
    "BLOCKED", "NO_ACCEPTED_EVIDENCE",
})
EVIDENCE_COVERED = frozenset({"ACCEPTED", "CLOUD_VERIFIED", "SOURCE_OVERLAP"})
RELEASE_HOLDS = frozenset({"RL03", "RL04", "RL05", "RL06", "RL07", "RL08",
                           "RL09", "RL10", "RL11", "RL12"})
ALPHA_HOLDS = frozenset({"AL07", "AL08", "AL09", "AL10", "AL11", "AL12",
                         "AL13", "AL14", "AL15", "AL16"})


def _read_json(path: Path) -> dict[str, Any]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(payload, dict):
        raise ValueError(f"Expected JSON object: {path}")
    return payload


def _assert_evidence_paths(paths: Any, root: Path, owner: str) -> None:
    if not isinstance(paths, list):
        raise ValueError(f"{owner}: evidence_paths/refs must be a list")
    for text in paths:
        if not isinstance(text, str) or not text or "\\" in text:
            raise ValueError(f"{owner}: invalid evidence path {text!r}")
        relative = Path(text)
        if relative.is_absolute() or ".." in relative.parts:
            raise ValueError(f"{owner}: unsafe evidence path {text!r}")
        actual = root / relative
        if not actual.is_file():
            raise ValueError(f"{owner}: evidence not found: {text}")


def validate(
    audit: dict[str, Any],
    backlog: dict[str, Any],
    root: Path,
) -> dict[str, Any]:
    """Validate a conservative source-coverage mapping and return scorecards."""
    if audit.get("schema_version") != 1:
        raise ValueError("Unsupported roadmap reconciliation schema")
    originals = backlog.get("tasks")
    mapped = audit.get("tasks")
    if not isinstance(originals, list) or len(originals) != 66:
        raise ValueError("Expected exactly 66 original blueprint tasks")
    if not isinstance(mapped, list) or len(mapped) != 66:
        raise ValueError("Expected exactly 66 reconciled task records")

    original_ids = [entry["id"] for entry in originals]
    mapped_ids = [entry["id"] for entry in mapped]
    if len(set(original_ids)) != 66 or len(set(mapped_ids)) != 66:
        raise ValueError("Duplicate task IDs are forbidden")
    if original_ids != mapped_ids:
        raise ValueError("Reconciled IDs/order differ from the canonical backlog")

    canonical_states = Counter()
    overlay_states = Counter()
    covered_pre_beta = 0
    pre_beta = 0

    for original, row in zip(originals, mapped):
        task_id = original["id"]
        status = original["status"]
        stage = row.get("evidence_class")
        if row.get("backlog_status") != status:
            raise ValueError(f"{task_id}: original acceptance status was rewritten")
        if row.get("title") != original["title"]:
            raise ValueError(f"{task_id}: title drift")
        if row.get("milestone") != original["milestone"]:
            raise ValueError(f"{task_id}: milestone drift")
        if row.get("original_acceptance") != original["acceptance"]:
            raise ValueError(f"{task_id}: original acceptance criteria changed")
        if stage not in VALID_OVERLAY:
            raise ValueError(f"{task_id}: invalid reconciliation class: {stage!r}")

        expected_stage = {
            "DONE": "ACCEPTED",
            "CLOUD_VERIFIED": "CLOUD_VERIFIED",
            "BLOCKED": "BLOCKED",
        }.get(status)
        if expected_stage is not None and stage != expected_stage:
            raise ValueError(f"{task_id}: invalid promotion or demotion of {status}")
        if status == "NOT_STARTED" and stage not in {
            "SOURCE_OVERLAP", "NO_ACCEPTED_EVIDENCE",
        }:
            raise ValueError(f"{task_id}: NOT_STARTED cannot be promoted by overlap")
        if stage == "SOURCE_OVERLAP" and not row.get("evidence_paths"):
            raise ValueError(f"{task_id}: source overlap must cite an existing file")
        if not isinstance(row.get("remaining_acceptance"), str) or not row["remaining_acceptance"]:
            raise ValueError(f"{task_id}: remaining acceptance must be explicit")

        _assert_evidence_paths(row.get("evidence_paths"), root, task_id)
        canonical_states[status] += 1
        overlay_states[stage] += 1
        if original["milestone"] in PRE_BETA:
            pre_beta += 1
            covered_pre_beta += stage in EVIDENCE_COVERED

    if canonical_states != Counter({
        "DONE": 5, "CLOUD_VERIFIED": 15,
        "NOT_STARTED": 45, "BLOCKED": 1,
    }):
        raise ValueError("Original 2026-11-23 baseline changed; re-audit intentionally")
    if pre_beta != 54:
        raise ValueError("Original pre-beta denominator changed; re-audit intentionally")

    def gate_counts(name: str, prefix: str, size: int, mandatory_holds: frozenset[str]) -> tuple[int, int]:
        records = audit.get(name)
        if not isinstance(records, list) or len(records) != size:
            raise ValueError(f"{name}: expected {size} gates")
        codes = [g.get("id") for g in records]
        if len(set(codes)) != size or any(not isinstance(code, str) or not code.startswith(prefix) for code in codes):
            raise ValueError(f"{name}: duplicate or invalid gate identifier")
        for gate in records:
            ident, state = gate["id"], gate.get("status")
            if state not in {"PASS", "HOLD"}:
                raise ValueError(f"{ident}: invalid gate verdict")
            if ident in mandatory_holds and state != "HOLD":
                raise ValueError(f"{ident}: hold cannot be lifted without new qualification audit")
            if not isinstance(gate.get("label"), str) or not gate["label"]:
                raise ValueError(f"{ident}: gate label required")
            if state == "PASS" and not gate.get("refs"):
                raise ValueError(f"{ident}: passing gate lacks evidence")
            _assert_evidence_paths(gate.get("refs"), root, ident)
        return sum(g["status"] == "PASS" for g in records), size

    alpha_pass, alpha_total = gate_counts("alpha_gates", "AL", 16, ALPHA_HOLDS)
    release_pass, release_total = gate_counts("release_gates", "RL", 12, RELEASE_HOLDS)

    return {
        "audited_main_sha": audit["audited_main_sha"],
        "original_backlog": dict(sorted(canonical_states.items())),
        "reconciled_evidence_classes": dict(sorted(overlay_states.items())),
        "engineering_coverage": {
            "qualifying_evidence_tasks": covered_pre_beta,
            "original_pre_beta_tasks": pre_beta,
            "percent": round(covered_pre_beta / pre_beta * 100, 1),
            "meaning": "source overlap coverage; NOT full engineering or gameplay completion",
        },
        "playable_alpha": {
            "qualified_gates": alpha_pass, "total_gates": alpha_total,
            "percent": round(alpha_pass / alpha_total * 100, 1),
            "acceptance": "HOLD",
        },
        "commercial_release": {
            "qualified_gates": release_pass, "total_gates": release_total,
            "percent": round(release_pass / release_total * 100, 1),
            "acceptance": "HOLD",
        },
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--audit", type=Path, default=DEFAULT_AUDIT)
    parser.add_argument("--backlog", type=Path, default=DEFAULT_BACKLOG)
    parser.add_argument("--json", action="store_true", help="Print verified metrics as JSON")
    args = parser.parse_args()
    result = validate(_read_json(args.audit), _read_json(args.backlog), REPOSITORY_ROOT)
    if args.json:
        print(json.dumps(result, indent=2, sort_keys=True))
    else:
        print("[PASS] ROADMAP RECONCILIATION — 66 original tasks; no acceptance promotions")
        print(f"[SOURCE] audited main={result['audited_main_sha']}")
        print(f"[PASS] backlog states: {result['original_backlog']}")
        print(f"[PASS] overlay states: {result['reconciled_evidence_classes']}")
        for key in ("engineering_coverage", "playable_alpha", "commercial_release"):
            value = result[key]
            print(f"[RESULT] {key}: {value['percent']:.1f}% — {value}")
        print("[HOLD] Percentages measure evidence coverage, not work effort or release approval.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
