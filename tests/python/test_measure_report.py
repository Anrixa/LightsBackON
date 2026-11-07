"""MEASURE21 regression suite: privacy-safe local C01 report analysis."""
from __future__ import annotations

import copy
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from tools import measure_report


class MeasurementReportTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.folder = Path(self.temp.name)
        self.sample = {
            "schema_version": 1, "contract": "C01", "tick_rate_hz": 10,
            "opted_in": True, "dropped_events": 0, "outcome": "completed",
            "last_tick": 65,
            "events": [
                {"kind": "session_started", "tick": 0},
                {"kind": "objective_visible", "tick": 10, "objective_index": 0},
                {"kind": "idle_started", "tick": 20},
                {"kind": "idle_ended", "tick": 30, "value_ticks": 10},
                {"kind": "first_repair", "tick": 32},
                {"kind": "objective_completed", "tick": 50, "objective_index": 0},
                {"kind": "session_completed", "tick": 60},
                {"kind": "results_opened", "tick": 65},
            ],
        }

    def write(self, data: dict, name: str = "c01-synthetic.json") -> Path:
        path = self.folder / name
        path.write_text(json.dumps(data), encoding="utf-8")
        return path

    def test_MEASURE21_consentful_session_has_only_aggregate_statistics(self) -> None:
        result = measure_report.analyze_input(self.write(self.sample))
        self.assertEqual(result["sessions"], 1)
        self.assertEqual(result["completed_sessions"], 1)
        self.assertEqual(result["first_repair_median_ticks"], 32)
        self.assertEqual(result["visible_to_completed_median_ticks"], 40)
        self.assertEqual(result["idle_total_ticks"], 10)
        self.assertEqual(result["event_counts"]["session_completed"], 1)
        self.assertEqual(result["release_gate"], "NOT_EVALUATED")
        self.assertNotIn("events", result)
        self.assertNotIn("account_key", json.dumps(result))

    def test_MEASURE21_no_consent_or_unknown_identity_fields_are_refused(self) -> None:
        for change in ({"opted_in": False}, {"account_key": "private"},
                       {"schema_version": 2}, {"contract": "SECRET"}):
            report = copy.deepcopy(self.sample)
            report.update(change)
            with self.subTest(change=change), self.assertRaises(measure_report.InvalidReport):
                measure_report.validate(report)
        report = copy.deepcopy(self.sample)
        report["events"][1]["peer_id"] = "secret"
        with self.assertRaisesRegex(measure_report.InvalidReport, "INVALID_EVENT_KEYS"):
            measure_report.validate(report)

    def test_MEASURE21_rejects_bad_order_malformed_kinds_and_fake_intervals(self) -> None:
        edits = [
            (1, {"tick": 66}),
            (1, {"tick": -1}),
            (1, {"kind": "account_id"}),
            (1, {"objective_index": 64}),
            (3, {"value_ticks": 0}),
            (4, {"value_ticks": 99}),
        ]
        for index, change in edits:
            report = copy.deepcopy(self.sample)
            report["events"][index].update(change)
            with self.subTest(index=index, change=change), self.assertRaises(measure_report.InvalidReport):
                measure_report.validate(report)

    def test_MEASURE21_rejects_duplicate_json_keys_and_invalid_utf8(self) -> None:
        path = self.folder / "c01-test.json"
        path.write_text('{"schema_version":1,"schema_version":1}', encoding="utf-8")
        with self.assertRaisesRegex(measure_report.InvalidReport, "DUPLICATE_KEY"):
            measure_report.read_report(path)
        path.write_bytes(bytes([255, 254]))
        with self.assertRaisesRegex(measure_report.InvalidReport, "INVALID_JSON"):
            measure_report.read_report(path)

    def test_MEASURE21_multiple_reports_do_not_emit_identifiers_or_paths(self) -> None:
        self.write(self.sample, "c01-first.json")
        left = copy.deepcopy(self.sample)
        left["outcome"] = "left"
        left["events"] = [left["events"][0], {"kind": "session_left", "tick": 15}]
        left["last_tick"] = 15
        left["dropped_events"] = 3
        self.write(left, "c01-second.json")
        result = measure_report.analyze_input(self.folder)
        self.assertEqual(result["sessions"], 2)
        self.assertEqual(result["completed_sessions"], 1)
        self.assertEqual(result["left_sessions"], 1)
        self.assertEqual(result["data_completeness"], "EVENTS_DROPPED")
        self.assertNotIn("c01-first", json.dumps(result))
        self.assertNotIn(str(self.folder), json.dumps(result))

    def test_MEASURE21_cli_rejects_bad_reports_without_echoing_content(self) -> None:
        bad = copy.deepcopy(self.sample)
        bad["steam_id"] = "VERY_SENSITIVE_STRING"
        path = self.write(bad)
        command = [sys.executable, str(Path(measure_report.__file__).resolve()), str(path)]
        result = subprocess.run(command, capture_output=True, text=True, check=False)
        self.assertEqual(result.returncode, 2)
        self.assertIn("MEASURE21_ERROR: INVALID_ROOT_KEYS", result.stderr)
        self.assertNotIn("VERY_SENSITIVE_STRING", result.stderr + result.stdout)
        self.assertNotIn(str(path), result.stderr + result.stdout)

    def test_MEASURE21_refuses_forged_idle_durations_and_unbounded_nesting(self) -> None:
        report = copy.deepcopy(self.sample)
        report["events"][3]["value_ticks"] = 11
        with self.assertRaisesRegex(measure_report.InvalidReport, "INVALID_IDLE_DURATION"):
            measure_report.validate(report)
        report["events"][3]["value_ticks"] = 10
        report["events"].insert(3, {"kind": "idle_started", "tick": 25})
        with self.assertRaisesRegex(measure_report.InvalidReport, "OVERLAPPING_IDLE_SPANS"):
            measure_report.validate(report)
        path = self.folder / "c01-nested.json"
        path.write_text("[" * 10000 + "0" + "]" * 10000, encoding="utf-8")
        with self.assertRaisesRegex(measure_report.InvalidReport, "INVALID_JSON"):
            measure_report.read_report(path)

    def test_MEASURE21_rejects_overflow_and_bad_final_state(self) -> None:
        report = copy.deepcopy(self.sample)
        report["events"] = report["events"][:2]
        with self.assertRaisesRegex(measure_report.InvalidReport, "MISSING_TERMINAL_EVENT"):
            measure_report.validate(report)
        report["dropped_events"] = 1
        result = measure_report.validate(report)
        self.assertEqual(result["dropped_events"], 1)
        report["events"] = [report["events"][0]] * (measure_report.MAX_EVENTS + 1)
        with self.assertRaisesRegex(measure_report.InvalidReport, "INVALID_EVENT_COUNT"):
            measure_report.validate(report)


if __name__ == "__main__":
    unittest.main()
