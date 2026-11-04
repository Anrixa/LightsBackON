#!/usr/bin/env python3
"""Validate the DS02 source log without fetching data or changing game content.

This gate checks provenance fields and the reproducibility of the recorded
sample. It cannot verify whether a storefront changed after the dated snapshot.
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LOG_PATH = ROOT / "docs" / "design" / "DS02-source-sample.json"
FAMILIES = {"restoration", "technical", "cooperation", "systems"}
AXES = (
    "task_pattern",
    "visible_transformation",
    "tool_or_interaction_identity",
    "cooperative_task_signals",
    "accessibility_quality",
    "hardware_performance",
)
REVIEW_SCOPES = {"English", "All"}
STORE_URL = re.compile(r"https://store\.steampowered\.com/app/([1-9][0-9]*)/\Z")


def validate(log: object) -> list[str]:
    """Return stable, actionable validation failures for one in-memory log."""
    errors: list[str] = []
    if not isinstance(log, dict):
        return ["root: expected JSON object"]
    if log.get("schema_version") != 1 or log.get("study_id") != "DS02":
        errors.append("root: unexpected study/schema")
    sample = log.get("sample_size", {})
    records = log.get("records")
    if not isinstance(records, list):
        return errors + ["records: expected list"]
    if not 20 <= len(records) <= 30:
        errors.append("records: deep scored sample must contain 20..30 titles")
    if not isinstance(sample, dict):
        errors.append("sample_size: expected object")
    elif (sample.get("metadata_screened") != len(records)
          or sample.get("deep_scored") != len(records)
          or sample.get("attempted_1000_candidate_crawl") is not False):
        errors.append("sample_size: declared counts/screening method mismatch")
    ids: set[int] = set()
    families: set[str] = set()
    for index, row in enumerate(records):
        where = f"records[{index}]"
        if not isinstance(row, dict):
            errors.append(f"{where}: expected object")
            continue
        app_id = row.get("steam_app_id")
        if type(app_id) is not int or app_id < 1 or app_id in ids:
            errors.append(f"{where}: invalid or duplicate Steam app ID")
        else:
            ids.add(app_id)
        url = row.get("source_url")
        match = STORE_URL.fullmatch(url) if isinstance(url, str) else None
        if match is None or int(match.group(1)) != app_id:
            errors.append(f"{where}: primary store URL must match app ID")
        if not isinstance(row.get("title"), str) or not row["title"].strip():
            errors.append(f"{where}: missing game title")
        if row.get("review_snapshot_utc") != log.get("as_of_utc"):
            errors.append(f"{where}: untracked review snapshot date")
        if row.get("source_kind") != "Steam product listing":
            errors.append(f"{where}: unverified primary source")
        family = row.get("mechanic_family")
        if family not in FAMILIES:
            errors.append(f"{where}: invalid mechanic family")
        else:
            families.add(family)
        metric = row.get("review_metric")
        if not isinstance(metric, dict):
            errors.append(f"{where}: missing review metric")
        elif (
            metric.get("scope") not in REVIEW_SCOPES
            or type(metric.get("count")) is not int
            or metric["count"] < 1
            or type(metric.get("positive_percent")) is not int
            or not 0 <= metric["positive_percent"] <= 100
        ):
            errors.append(f"{where}: malformed review count/scope/percent")
        for key in ("storefront_observation", "transfer_hypothesis", "confidence_note"):
            value = row.get(key)
            if not isinstance(value, str) or len(value.strip()) < 25:
                errors.append(f"{where}: missing defensible {key}")
        if row.get("confidence") not in ("low", "medium", "high"):
            errors.append(f"{where}: missing confidence grade")
        rubric = row.get("rubric")
        if not isinstance(rubric, dict) or set(rubric) != set(AXES):
            errors.append(f"{where}: rubric must contain exactly six axes")
            continue
        for axis, score in rubric.items():
            if score is not None and (type(score) is not int or not 0 <= score <= 4):
                errors.append(f"{where}.{axis}: score must be 0..4 or null")
        # Storefront copy establishes feature relevance, not verified accessibility
        # or measured GTX1650 performance. Null is a positive evidence boundary.
        if rubric["accessibility_quality"] is not None or rubric["hardware_performance"] is not None:
            errors.append(f"{where}: unverified accessibility/performance claim")
    if families != FAMILIES:
        errors.append("records: all four justified mechanic families required")
    return errors


def main() -> int:
    try:
        log = json.loads(LOG_PATH.read_text(encoding="utf-8"))
    except (OSError, ValueError) as exc:
        print(f"DS02: cannot read source log: {exc}")
        return 1
    errors = validate(log)
    for error in errors:
        print("DS02 ERROR:", error)
    print(
        f"DS02 source log: {len(log.get('records', []))} entries, "
        f"{len(errors)} errors; review facts are dated snapshots"
    )
    return int(bool(errors))


if __name__ == "__main__":
    sys.exit(main())
