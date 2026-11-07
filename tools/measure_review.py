#!/usr/bin/env python3
"""MEASURE24: local-only consent, retention and measurement-quality review.

This is a read-only inspection of already explicitly opted-in C01 files.
A command-line capture flag does not prove informed human participant consent.
No raw event rows, paths, timestamps, identities or content hashes leave the tool.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import sys
import time
from pathlib import Path
from typing import Any

if __package__:
    from . import measure_report
else:
    import measure_report

# An operational REVIEW horizon, not permission to delete or a legal retention rule.
REVIEW_WINDOW_DAYS = 30
SECONDS_PER_DAY = 86_400
FUTURE_CLOCK_TOLERANCE_SECONDS = SECONDS_PER_DAY


def _report_paths(source: Path) -> list[Path]:
    """Resolve a bounded, flat selection without following symlink inputs."""
    if source.is_symlink():
        raise measure_report.InvalidReport("UNSAFE_INPUT")
    if source.is_file():
        paths = [source]
    elif source.is_dir():
        paths = sorted(source.glob("c01-*.json"))
    else:
        raise measure_report.InvalidReport("INVALID_INPUT")
    if not 1 <= len(paths) <= measure_report.MAX_REPORTS:
        raise measure_report.InvalidReport("INVALID_REPORT_COUNT")
    return paths


def review_input(source: Path, *, now_utc: float | None = None) -> dict[str, Any]:
    """Audit report eligibility without updating or deleting selected files.

    Filesystem modification dates are useful triage signals, not proof of when
    a person played or consented. Every report still requires human review.
    """
    now = time.time() if now_utc is None else now_utc
    if not isinstance(now, (int, float)) or not 0 < now < 10_000_000_000:
        raise measure_report.InvalidReport("INVALID_REVIEW_CLOCK")
    paths = _report_paths(source)
    reports: list[dict[str, Any]] = []
    old_files = future_files = duplicates = 0
    seen_hashes: set[bytes] = set()
    for path in paths:
        report = measure_report.read_report(path)
        # Measure report guarantees bounds and a regular, non-symlink file.
        stat = path.stat()
        if stat.st_mtime > now + FUTURE_CLOCK_TOLERANCE_SECONDS:
            future_files += 1
        elif stat.st_mtime < now - REVIEW_WINDOW_DAYS * SECONDS_PER_DAY:
            old_files += 1
        # Detect byte-identical repeated exports. This is only a review flag:
        # same gameplay can coincidentally yield the same event timeline.
        digest = hashlib.sha256(path.read_bytes()).digest()
        if digest in seen_hashes:
            duplicates += 1
        seen_hashes.add(digest)
        reports.append(report)

    dropped_sessions = sum(r["dropped_events"] > 0 for r in reports)
    terminal_gaps = sum(
        r["counts"]["session_completed" if r["outcome"] == "completed"
                    else "session_left"] == 0 for r in reports
    )
    results_gaps = sum(
        r["outcome"] == "completed" and r["counts"]["results_opened"] == 0
        for r in reports
    )
    repair_gaps = sum(
        r["outcome"] == "completed" and r["first_repair_tick"] is None
        for r in reports
    )
    idle_open = sum(
        r["counts"]["idle_started"] > r["counts"]["idle_ended"]
        for r in reports
    )

    quality_flags: list[str] = []
    if dropped_sessions:
        quality_flags.append("EVENTS_DROPPED")
    if terminal_gaps:
        quality_flags.append("TERMINAL_EVENT_NOT_OBSERVED")
    if results_gaps:
        quality_flags.append("RESULTS_OPEN_EVENT_NOT_OBSERVED")
    if repair_gaps:
        quality_flags.append("FIRST_REPAIR_NOT_OBSERVED")
    if idle_open:
        quality_flags.append("IDLE_SPAN_OPEN_AT_EXIT")
    if duplicates:
        quality_flags.append("IDENTICAL_REPORT_PAYLOADS")

    retention_review = old_files > 0 or future_files > 0
    # Never combine expired, clock-anomalous, or repeated payloads into an
    # apparently normal cohort summary. No files are modified by this hold.
    aggregate = None if retention_review or duplicates else measure_report.summarize(reports)
    return {
        "schema_version": 1,
        "scope": "local_C01_read_only_review",
        "files_scanned": len(reports),
        "consent_gate": "HUMAN_PARTICIPANT_CONSENT_REVIEW_REQUIRED",
        "consent_basis": "capture_command_line_opt_in_not_external_consent_proof",
        "retention": {
            "review_window_days": REVIEW_WINDOW_DAYS,
            "timestamp_basis": "filesystem_mtime_not_proof_of_capture_date",
            "outside_review_window": old_files,
            "future_clock_anomalies": future_files,
            "gate": "REVIEW_REQUIRED" if retention_review else "WITHIN_REVIEW_WINDOW",
        },
        "quality": {
            "gate": "REVIEW_REQUIRED" if quality_flags else "STRUCTURAL_CHECKS_PASSED",
            "flags": quality_flags,
            "sessions_with_dropped_events": dropped_sessions,
            "sessions_without_terminal_event": terminal_gaps,
            "completions_without_results_opened": results_gaps,
            "completions_without_observed_first_repair": repair_gaps,
            "sessions_with_open_idle_span": idle_open,
            "identical_report_payloads": duplicates,
        },
        "aggregate": aggregate,
        "study_gate": "HUMAN_PLAYTEST_REVIEW_REQUIRED",
        "release_gate": "NOT_EVALUATED",
        "automatic_deletion": False,
        "network_upload": False,
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Read-only C01 consent, retention and quality audit (no upload or deletion)"
    )
    parser.add_argument("input", type=Path, help="One consented local C01 JSON report or its folder")
    args = parser.parse_args(argv)
    try:
        result = review_input(args.input)
    except (measure_report.InvalidReport, OSError, ValueError) as exc:
        # Never echo user-controlled paths, payloads or exception messages.
        code = str(exc) if isinstance(exc, measure_report.InvalidReport) else "READ_FAILURE"
        print("MEASURE24_ERROR: " + code, file=sys.stderr)
        return 2
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main())
