#!/usr/bin/env python3
"""MEASURE28: validate aggregate C01 study denominators without personal data.

The input is a manually prepared, identity-free set of self-reported funnel
counts. It is NOT proof of consent, recruitment bias, usability or playtests.
No networking, tracking, report upload, or input-file mutation is performed.
"""
from __future__ import annotations

import argparse
import json
import os
import stat
import sys
from pathlib import Path
from typing import Any

SCHEMA_VERSION = 1
TARGET_PAIRS = 6
TARGET_SOLO = 3
MAX_BYTES = 32_768
MAX_COUNT = 10_000
COHORTS = ("outside_pairs", "solo")
STAGES = ("approached", "eligible", "consented", "started", "completed", "included")


class InvalidCohort(ValueError):
    """Fixed non-sensitive error code; never display input or file names."""


def _no_duplicate_keys(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise InvalidCohort("DUPLICATE_JSON_KEY")
        result[key] = value
    return result


def _no_nonfinite(_value: str) -> None:
    raise InvalidCohort("INVALID_JSON")


def _checked_funnel(value: Any) -> dict[str, int]:
    if not isinstance(value, dict) or set(value) != set(STAGES):
        raise InvalidCohort("INVALID_FUNNEL_FIELDS")
    if any(type(value[stage]) is not int or not 0 <= value[stage] <= MAX_COUNT
           for stage in STAGES):
        raise InvalidCohort("INVALID_FUNNEL_COUNT")
    for earlier, later in zip(STAGES, STAGES[1:]):
        if value[later] > value[earlier]:
            raise InvalidCohort("INCONSISTENT_FUNNEL")
    return {stage: value[stage] for stage in STAGES}


def analyze(data: Any) -> dict[str, Any]:
    """Validate a six-stage funnel and produce explicitly UNVERIFIED counts.

    An outside pair is one two-person *session*, not two independent runs.
    A count marked consented is an operator declaration, never consent proof.
    """
    if not isinstance(data, dict) or set(data) != {
        "schema_version", "contract", "cohorts"
    }:
        raise InvalidCohort("INVALID_ROOT_FIELDS")
    if type(data["schema_version"]) is not int or data["schema_version"] != SCHEMA_VERSION:
        raise InvalidCohort("INVALID_VERSION")
    if data["contract"] != "C01":
        raise InvalidCohort("INVALID_CONTRACT")
    if not isinstance(data["cohorts"], dict) or set(data["cohorts"]) != set(COHORTS):
        raise InvalidCohort("INVALID_COHORTS")

    checked = {kind: _checked_funnel(data["cohorts"][kind]) for kind in COHORTS}
    targets = {"outside_pairs": TARGET_PAIRS, "solo": TARGET_SOLO}
    observed: dict[str, Any] = {}
    for kind in COHORTS:
        funnel = checked[kind]
        attrition = {
            f"{earlier}_not_{later}": funnel[earlier] - funnel[later]
            for earlier, later in zip(STAGES, STAGES[1:])
        }
        # Return an exact numerator/denominator; no small-sample percentages
        # imply a precision or sampling validity these counts do not have.
        observation = {
            "unit": "pair_sessions" if kind == "outside_pairs" else "solo_sessions",
            "planned": targets[kind],
            "declared_funnel": funnel,
            "declared_attrition": attrition,
            "completion_fraction": (
                {"numerator": funnel["completed"], "denominator": funnel["started"]}
                if funnel["started"] else None
            ),
            "inclusion_fraction": (
                {"numerator": funnel["included"], "denominator": funnel["completed"]}
                if funnel["completed"] else None
            ),
            "declared_included_shortfall": max(0, targets[kind] - funnel["included"]),
        }
        observed[kind] = observation
    pair = checked["outside_pairs"]
    solo = checked["solo"]
    return {
        "schema_version": SCHEMA_VERSION,
        "contract": "C01",
        "scope": "declared_aggregate_external_study_funnel",
        "planned_pair_sessions": TARGET_PAIRS,
        "planned_solo_sessions": TARGET_SOLO,
        "planned_total_sessions": TARGET_PAIRS + TARGET_SOLO,
        "planned_participant_seats": TARGET_PAIRS * 2 + TARGET_SOLO,
        "cohorts": observed,
        "declared_total_started_sessions": pair["started"] + solo["started"],
        "declared_total_completed_sessions": pair["completed"] + solo["completed"],
        "declared_total_included_sessions": pair["included"] + solo["included"],
        "declared_total_included_participant_seats": pair["included"] * 2 + solo["included"],
        "declared_missing_target_sessions": (
            max(0, TARGET_PAIRS - pair["included"])
            + max(0, TARGET_SOLO - solo["included"])
        ),
        "source_attestation": "OPERATOR_DECLARATION_ONLY",
        "consent_gate": "HUMAN_PARTICIPANT_CONSENT_VERIFICATION_REQUIRED",
        "bias_gate": "HUMAN_RECRUITMENT_BIAS_REVIEW_REQUIRED",
        "playtest_gate": "REAL_SESSION_EVIDENCE_NOT_VERIFIED",
        "release_gate": "NOT_EVALUATED",
        "network_upload": False,
    }


def read_input(source: Path) -> dict[str, Any]:
    """Read at most 32 KiB from one ordinary file, refusing symlinks and swaps."""
    try:
        initial = source.lstat()
        if not stat.S_ISREG(initial.st_mode):
            raise InvalidCohort("UNSAFE_INPUT")
        if initial.st_size > MAX_BYTES:
            raise InvalidCohort("INPUT_TOO_LARGE")
        flags = os.O_RDONLY | getattr(os, "O_BINARY", 0) | getattr(os, "O_NOFOLLOW", 0)
        with os.fdopen(os.open(source, flags), "rb") as stream:
            opened = os.fstat(stream.fileno())
            if (not stat.S_ISREG(opened.st_mode)
                    or (initial.st_dev, initial.st_ino) != (opened.st_dev, opened.st_ino)):
                raise InvalidCohort("UNSAFE_INPUT")
            if opened.st_size > MAX_BYTES:
                raise InvalidCohort("INPUT_TOO_LARGE")
            raw = stream.read(MAX_BYTES + 1)
            after = os.fstat(stream.fileno())
            if (opened.st_size != after.st_size
                    or opened.st_mtime_ns != after.st_mtime_ns):
                raise InvalidCohort("INPUT_CHANGED")
        if len(raw) > MAX_BYTES:
            raise InvalidCohort("INPUT_TOO_LARGE")
    except OSError as exc:
        raise InvalidCohort("INPUT_READ_FAILURE") from exc

    try:
        data = json.loads(raw.decode("utf-8"),
                          object_pairs_hook=_no_duplicate_keys,
                          parse_constant=_no_nonfinite)
    except (UnicodeError, json.JSONDecodeError, RecursionError) as exc:
        raise InvalidCohort("INVALID_JSON") from exc
    return analyze(data)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Read-only local aggregate recruitment funnel review; no upload"
    )
    parser.add_argument("input", type=Path, help="An identity-free aggregate JSON file")
    args = parser.parse_args(argv)
    try:
        result = read_input(args.input)
    except InvalidCohort as exc:
        print("MEASURE28_ERROR: " + str(exc), file=sys.stderr)
        return 2
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main())
