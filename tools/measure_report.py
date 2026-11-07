#!/usr/bin/env python3
"""MEASURE21: validate and summarize explicitly consented C01 measurements offline.

No identifiers, paths, raw events, external packages, or network traffic are
included in the output. This tool does not establish a playtest or release gate.
"""
from __future__ import annotations

import argparse
import hashlib
import json
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


def read_report(path: Path) -> dict[str, Any]:
    """Bound work before parsing; avoid following files outside a selected folder."""
    if path.is_symlink() or not path.is_file():
        raise InvalidReport("UNSAFE_REPORT_FILE")
    if path.stat().st_size > MAX_FILE_BYTES:
        raise InvalidReport("REPORT_TOO_LARGE")
    try:
        data = json.loads(path.read_text(encoding="utf-8"),
                          object_pairs_hook=_object_no_duplicates,
                          parse_constant=_bad_constant)
    except (UnicodeError, json.JSONDecodeError, RecursionError) as exc:
        raise InvalidReport("INVALID_JSON") from exc
    report = validate(data)
    # The file is strictly size-bounded, schema-validated and allowlisted.
    # Derive a transient canonical fingerprint from the same parsed input,
    # without another filesystem read or following a path a second time.
    canonical = json.dumps(data, sort_keys=True, separators=(",", ":"))
    report["_internal_fingerprint"] = hashlib.sha256(canonical.encode("utf-8")).digest()
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


def analyze_input(source: Path) -> dict[str, Any]:
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
    return summarize([read_report(path) for path in paths])


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
