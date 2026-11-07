#!/usr/bin/env python3
"""MEASURE28: offline structural preflight for the V09 ten-run evidence gate.

No identification, network upload, participant inference or release approval.
This tool does not replace physical 1-4 player testing or an observer's notes.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

if __package__:
    from . import measure_report, measure_review
else:
    import measure_report
    import measure_review

V09_TARGET_RUNS = 10


def preflight(source: Path, *, now_utc: float | None = None) -> dict[str, Any]:
    """Count validated C01 reports without promoting logs to playtest proof."""
    audit = measure_review.review_input(source, now_utc=now_utc)
    aggregate = audit["aggregate"]
    if aggregate is None:
        gate = "INPUT_OR_OBSERVATION_HOLD"
        observed = None
        completed = None
    else:
        observed = aggregate["sessions"]
        completed = aggregate["completed_sessions"]
        gate = (
            "STRUCTURAL_SAMPLE_PRESENT_REQUIRES_HUMAN_VERIFICATION"
            if observed >= V09_TARGET_RUNS
            else "BELOW_TEN_RUN_TARGET"
        )

    return {
        "schema_version": 1,
        "scope": "local_C01_V09_structural_preflight_only",
        "target_run_count": V09_TARGET_RUNS,
        "files_scanned": audit["files_scanned"],
        "structurally_aggregatable_runs": observed,
        "claimed_completed_runs": completed,
        "aggregate_gate": audit["aggregate_gate"],
        "preflight_gate": gate,
        "consent_gate": audit["consent_gate"],
        "human_playtest_gate": "REQUIRED",
        "four_player_evidence": "NOT_OBSERVABLE_IN_REPORT_SCHEMA",
        "physical_build_evidence": "NOT_OBSERVABLE_IN_REPORT_SCHEMA",
        "mission_blocker_and_recovery_review": "REQUIRES_OBSERVER_EVIDENCE",
        "distinct_participant_count": "NOT_OBSERVABLE_IN_REPORT_SCHEMA",
        "study_gate": audit["study_gate"],
        "release_gate": audit["release_gate"],
        "automatic_deletion": False,
        "network_upload": False,
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Read-only ten-run C01 preflight; never proves a V09 pass"
    )
    parser.add_argument("input", type=Path,
                        help="Explicitly selected C01 report or local folder")
    args = parser.parse_args(argv)
    try:
        result = preflight(args.input)
    except (measure_report.InvalidReport, OSError, ValueError) as exc:
        # Do not echo locally sensitive paths, names, payloads or OS errors.
        reason = str(exc) if isinstance(exc, measure_report.InvalidReport) else "READ_FAILURE"
        print("MEASURE28_ERROR: " + reason, file=sys.stderr)
        return 2
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main())
