#!/usr/bin/env python3
"""MEASURE21: validate and summarize explicitly consented C01 measurements offline.

No identifiers, paths, raw events, external packages, or network traffic are
included in the output. This tool does not establish a playtest or release gate.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import stat
import statistics
import sys
from collections import Counter
from pathlib import Path
from typing import Any

KINDS = frozenset({
    "session_started", "session_left", "session_completed", "results_opened",
    "objective_visible", "objective_completed", "idle_started", "idle_ended",
    "first_repair", "protection_trip", "hint_requested", "drain_latched",
    "supply_verified", "verification_lost", "extraction_requested",
    "extraction_cancelled", "player_recovered", "connection_lost",
})
OBJECTIVE_KINDS = frozenset({"objective_visible", "objective_completed"})
ROOT_KEYS = frozenset({
    "schema_version", "contract", "tick_rate_hz", "opted_in", "events",
    "dropped_events", "outcome", "last_tick",
})
EVENT_KEYS = frozenset({"kind", "tick", "objective_index", "value_ticks"})
MAX_FILE_BYTES = 1_000_000
MAX_REPORTS = 100
MAX_EVENTS = 4096
MAX_TICK = 86_400_000  # 100 days at 10 Hz: malformed timestamps are refused.


class InvalidReport(ValueError):
    """A stable, non-sensitive reason code for rejected local input."""


def _integer(value: Any, minimum: int, maximum: int) -> bool:
    return type(value) is int and minimum <= value <= maximum


def _object_no_duplicates(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise InvalidReport("DUPLICATE_KEY")
        result[key] = value
    return result


def _bad_constant(_value: str) -> None:
    raise InvalidReport("NONFINITE_NUMBER")


def validate(data: Any) -> dict[str, Any]:
    """Return bounded non-identifying statistics, or reject the entire report."""
    if not isinstance(data, dict) or set(data) != ROOT_KEYS:
        raise InvalidReport("INVALID_ROOT_KEYS")
    if (not _integer(data["schema_version"], 1, 1)
            or data["contract"] != "C01"
            or not _integer(data["tick_rate_hz"], 10, 10)
            or data["opted_in"] is not True
            or data["outcome"] not in ("left", "completed")):
        raise InvalidReport("INVALID_CONSENT_OR_SCHEMA")
    if (not _integer(data["last_tick"], 0, MAX_TICK)
            or not _integer(data["dropped_events"], 0, 1_000_000)):
        raise InvalidReport("INVALID_COUNTER")
    rows = data["events"]
    if not isinstance(rows, list) or not 1 <= len(rows) <= MAX_EVENTS:
        raise InvalidReport("INVALID_EVENT_COUNT")

    counts: Counter[str] = Counter()
    first_repair: int | None = None
    visible: dict[int, int] = {}
    completed: dict[int, int] = {}
    idle_ticks = 0
    idle_start: int | None = None
    previous_tick = 0
    for index, event in enumerate(rows):
        if not isinstance(event, dict) or not {"kind", "tick"} <= event.keys() \
                or not event.keys() <= EVENT_KEYS:
            raise InvalidReport("INVALID_EVENT_KEYS")
        kind, tick = event["kind"], event["tick"]
        if not isinstance(kind, str) or kind not in KINDS:
            raise InvalidReport("INVALID_EVENT_KIND")
        if not _integer(tick, previous_tick, data["last_tick"]):
            raise InvalidReport("INVALID_TICK_ORDER")
        if index == 0 and (kind != "session_started" or tick != 0):
            raise InvalidReport("MISSING_SESSION_START")
        if index > 0 and kind == "session_started":
            raise InvalidReport("REPEATED_SESSION_START")
        if kind in OBJECTIVE_KINDS:
            if "objective_index" not in event or not _integer(event["objective_index"], 0, 31):
                raise InvalidReport("INVALID_OBJECTIVE_INDEX")
            objective = event["objective_index"]
            if kind == "objective_visible":
                visible.setdefault(objective, tick)
            else:
                completed.setdefault(objective, tick)
        elif "objective_index" in event:
            raise InvalidReport("UNEXPECTED_OBJECTIVE_INDEX")
        if kind == "idle_started":
            if idle_start is not None:
                raise InvalidReport("OVERLAPPING_IDLE_SPANS")
            idle_start = tick
        if kind == "idle_ended":
            if idle_start is None:
                raise InvalidReport("INVALID_IDLE_DURATION")
            elapsed = min(tick - idle_start, 360_000)
            # The game can detect inactivity and movement in one host tick.
            # For an elapsed duration of zero, GDScript correctly omits the
            # optional value_ticks field rather than serializing a false "0".
            if elapsed == 0:
                if "value_ticks" in event:
                    raise InvalidReport("INVALID_IDLE_DURATION")
            elif ("value_ticks" not in event
                  or not _integer(event["value_ticks"], 1, 360_000)
                  or event["value_ticks"] != elapsed):
                raise InvalidReport("INVALID_IDLE_DURATION")
            idle_ticks += elapsed
            idle_start = None
        elif "value_ticks" in event:
            raise InvalidReport("UNEXPECTED_VALUE")
        if kind == "first_repair" and first_repair is None:
            first_repair = tick
        counts[kind] += 1
        previous_tick = tick

    if data["dropped_events"] == 0:
        required = "session_completed" if data["outcome"] == "completed" else "session_left"
        if counts[required] == 0:
            raise InvalidReport("MISSING_TERMINAL_EVENT")
    if counts["session_completed"] and data["outcome"] != "completed":
        raise InvalidReport("CONFLICTING_OUTCOME")
    if counts["session_left"] and data["outcome"] != "left":
        raise InvalidReport("CONFLICTING_OUTCOME")

    # MEASURE25: a terminal outcome is not a repeatable counter. A file with
    # dropped events may legitimately lack its terminal, but two observed
    # terminals, or a debrief before completion, cannot be trusted as a run.
    # The game refreshes objectives *after* the completion event and before
    # opening results, so do not disallow those same-tick objective updates.
    if counts["session_completed"] + counts["session_left"] > 1:
        raise InvalidReport("REPEATED_TERMINAL_EVENT")
    if counts["first_repair"] > 1:
        raise InvalidReport("REPEATED_FIRST_REPAIR")
    if counts["results_opened"] > 1:
        raise InvalidReport("REPEATED_RESULTS_OPEN")
    results_position = next(
        (index for index, event in enumerate(rows)
         if event["kind"] == "results_opened"), None
    )
    if results_position is not None:
        completion_position = next(
            (index for index, event in enumerate(rows)
             if event["kind"] == "session_completed"), None
        )
        if (data["outcome"] != "completed" or completion_position is None
                or results_position <= completion_position):
            raise InvalidReport("RESULTS_WITHOUT_PRIOR_COMPLETION")
        if results_position != len(rows) - 1:
            raise InvalidReport("EVENT_AFTER_RESULTS")
    if counts["session_left"] and rows[-1]["kind"] != "session_left":
        raise InvalidReport("EVENT_AFTER_SESSION_LEFT")

    durations = [completed[ordinal] - tick for ordinal, tick in visible.items()
                 if ordinal in completed and completed[ordinal] >= tick]
    return {
        "outcome": data["outcome"],
        "last_tick": data["last_tick"],
        "dropped_events": data["dropped_events"],
        "counts": counts,
        "first_repair_tick": first_repair,
        "objective_elapsed_ticks": durations,
        "idle_total_ticks": idle_ticks,
    }


def _read_bounded_snapshot(path: Path) -> tuple[bytes, float]:
    """Read from one regular-file descriptor, not a mutable path twice.

    Reject a path replacement between lstat and open. On platforms with
    O_NOFOLLOW, refuse symlink traversal in the open call too. Checking the
    opened descriptor after reading detects concurrent in-place mutation.
    """
    try:
        expected = path.lstat()
        if not stat.S_ISREG(expected.st_mode):
            raise InvalidReport("UNSAFE_REPORT_FILE")
        if expected.st_size > MAX_FILE_BYTES:
            raise InvalidReport("REPORT_TOO_LARGE")
        flags = os.O_RDONLY | getattr(os, "O_BINARY", 0) | getattr(os, "O_NOFOLLOW", 0)
        with os.fdopen(os.open(path, flags), "rb") as stream:
            opened = os.fstat(stream.fileno())
            if (not stat.S_ISREG(opened.st_mode)
                    or (opened.st_dev, opened.st_ino) !=
                    (expected.st_dev, expected.st_ino)):
                raise InvalidReport("UNSAFE_REPORT_FILE")
            if opened.st_size > MAX_FILE_BYTES:
                raise InvalidReport("REPORT_TOO_LARGE")
            payload = stream.read(MAX_FILE_BYTES + 1)
            after = os.fstat(stream.fileno())
            if (opened.st_size != after.st_size
                    or opened.st_mtime_ns != after.st_mtime_ns):
                raise InvalidReport("REPORT_CHANGED_DURING_READ")
        if len(payload) > MAX_FILE_BYTES:
            raise InvalidReport("REPORT_TOO_LARGE")
        return payload, opened.st_mtime
    except OSError as exc:
        raise InvalidReport("READ_FAILURE") from exc


def read_report(path: Path) -> dict[str, Any]:
    """Validate one bounded file snapshot with its matching review metadata."""
    payload, modified_at = _read_bounded_snapshot(path)
    try:
        data = json.loads(payload.decode("utf-8"),
                          object_pairs_hook=_object_no_duplicates,
                          parse_constant=_bad_constant)
    except (UnicodeError, json.JSONDecodeError, RecursionError) as exc:
        raise InvalidReport("INVALID_JSON") from exc
    report = validate(data)
    # The in-memory fingerprint intentionally normalizes JSON formatting.
    # Never include this or the descriptor mtime in published aggregates.
    canonical = json.dumps(data, sort_keys=True, separators=(",", ":"))
    report["_internal_fingerprint"] = hashlib.sha256(canonical.encode("utf-8")).digest()
    report["_internal_file_mtime"] = modified_at
    return report


def summarize(reports: list[dict[str, Any]]) -> dict[str, Any]:
    """Only cross-session aggregates leave this function; never raw event rows."""
    if not reports or len(reports) > MAX_REPORTS:
        raise InvalidReport("INVALID_REPORT_COUNT")
    counts: Counter[str] = Counter()
    durations: list[int] = []
    repairs: list[int] = []
    for report in reports:
        counts.update(report["counts"])
        durations.extend(report["objective_elapsed_ticks"])
        if report["first_repair_tick"] is not None:
            repairs.append(report["first_repair_tick"])
    drops = sum(report["dropped_events"] for report in reports)
    return {
        "schema_version": 1,
        "scope": "consented_local_C01_only",
        "sessions": len(reports),
        "completed_sessions": sum(r["outcome"] == "completed" for r in reports),
        "left_sessions": sum(r["outcome"] == "left" for r in reports),
        "session_duration_median_ticks": statistics.median(r["last_tick"] for r in reports),
        "first_repair_median_ticks": statistics.median(repairs) if repairs else None,
        "visible_to_completed_median_ticks": statistics.median(durations) if durations else None,
        "objective_pairs_observed": len(durations),
        "idle_total_ticks": sum(r["idle_total_ticks"] for r in reports),
        "event_counts": {kind: counts[kind] for kind in sorted(counts)},
        "dropped_events": drops,
        "data_completeness": "EVENTS_DROPPED" if drops else "RECORDED_EVENTS_ONLY",
        "review_gate": "HUMAN_PLAYTEST_REVIEW_REQUIRED",
        "release_gate": "NOT_EVALUATED",
    }


def analyze_input(source: Path, *, return_validated: bool = False) -> dict[str, Any] | list[dict[str, Any]]:
    """Existing safe input selection; internal reviewers can access validated stats.

    No raw event rows or file paths are returned, even in review mode.
    """
    if source.is_symlink():
        raise InvalidReport("UNSAFE_INPUT")
    if source.is_file():
        paths = [source]
    elif source.is_dir():
        paths = sorted(source.glob("c01-*.json"))
    else:
        raise InvalidReport("INVALID_INPUT")
    if not paths or len(paths) > MAX_REPORTS:
        raise InvalidReport("INVALID_REPORT_COUNT")
    reports = [read_report(path) for path in paths]
    return reports if return_validated else summarize(reports)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Offline, identity-free C01 report audit (no upload)")
    parser.add_argument("input", type=Path, help="One exported report or its local folder")
    args = parser.parse_args(argv)
    try:
        output = analyze_input(args.input)
    except (InvalidReport, OSError, ValueError) as exc:
        # No attacker-supplied report content or local paths are printed.
        code = str(exc) if isinstance(exc, InvalidReport) else "READ_FAILURE"
        print("MEASURE21_ERROR: " + code, file=sys.stderr)
        return 2
    print(json.dumps(output, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main())
