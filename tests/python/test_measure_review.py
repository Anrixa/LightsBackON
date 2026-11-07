"""MEASURE24: regression tests for read-only C01 consent and quality review."""
from __future__ import annotations

import copy
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from tools import measure_report, measure_review


class MeasurementReviewTests(unittest.TestCase):
    NOW = 2_000_000_000.0  # A fixed UTC epoch for deterministic age checks.

    def setUp(self) -> None:
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.folder = Path(temporary.name)
        self.sample = {
            "schema_version": 1, "contract": "C01", "tick_rate_hz": 10,
            "opted_in": True, "dropped_events": 0, "outcome": "completed",
            "last_tick": 32,
            "events": [
                {"kind": "session_started", "tick": 0},
                {"kind": "first_repair", "tick": 10},
                {"kind": "session_completed", "tick": 30},
                {"kind": "results_opened", "tick": 32},
            ],
        }

    def write(self, report: dict | None = None, name: str = "c01-first.json",
              age_days: float = 0) -> Path:
        path = self.folder / name
        path.write_text(json.dumps(self.sample if report is None else report),
                        encoding="utf-8")
        when = self.NOW - age_days * measure_review.SECONDS_PER_DAY
        os.utime(path, (when, when))
        return path

    def review(self, source: Path | None = None) -> dict:
        return measure_review.review_input(
            self.folder if source is None else source, now_utc=self.NOW
        )

    def test_MEASURE24_valid_local_report_still_needs_real_consent_review(self) -> None:
        path = self.write()
        before = path.read_bytes()
        result = self.review()
        self.assertEqual(result["files_scanned"], 1)
        self.assertEqual(result["retention"]["gate"], "WITHIN_REVIEW_WINDOW")
        self.assertEqual(result["quality"]["gate"], "STRUCTURAL_CHECKS_PASSED")
        self.assertEqual(result["consent_gate"], "HUMAN_PARTICIPANT_CONSENT_REVIEW_REQUIRED")
        self.assertEqual(result["study_gate"], "HUMAN_PLAYTEST_REVIEW_REQUIRED")
        self.assertEqual(result["release_gate"], "NOT_EVALUATED")
        self.assertEqual(result["aggregate"]["completed_sessions"], 1)
        self.assertFalse(result["automatic_deletion"])
        self.assertFalse(result["network_upload"])
        self.assertEqual(path.read_bytes(), before)
        self.assertNotIn(str(path), json.dumps(result))
        self.assertNotIn(str(self.folder), json.dumps(result))
        self.assertNotIn("c01-first", json.dumps(result))

    def test_MEASURE24_old_data_blocks_aggregate_but_is_not_deleted(self) -> None:
        path = self.write(age_days=31)
        before = path.read_bytes()
        result = self.review()
        self.assertEqual(result["retention"]["outside_review_window"], 1)
        self.assertEqual(result["retention"]["gate"], "REVIEW_REQUIRED")
        self.assertIsNone(result["aggregate"])
        self.assertTrue(path.exists())
        self.assertEqual(path.read_bytes(), before)

    def test_MEASURE24_future_mtime_requires_clock_review(self) -> None:
        path = self.write(age_days=-2)
        result = self.review(path)
        self.assertEqual(result["retention"]["future_clock_anomalies"], 1)
        self.assertIsNone(result["aggregate"])
        self.assertTrue(path.exists())

    def test_MEASURE24_identical_copies_hold_aggregation(self) -> None:
        self.write(name="c01-a.json")
        self.write(name="c01-b.json")
        result = self.review()
        self.assertEqual(result["files_scanned"], 2)
        self.assertEqual(result["quality"]["identical_report_payloads"], 1)
        self.assertIn("IDENTICAL_REPORT_PAYLOADS", result["quality"]["flags"])
        self.assertIsNone(result["aggregate"])
        self.assertEqual(len(list(self.folder.iterdir())), 2)

    def test_MEASURE24_distinct_sessions_aggregate_without_personal_data(self) -> None:
        self.write(name="c01-completed.json")
        left = copy.deepcopy(self.sample)
        left["outcome"] = "left"
        left["events"] = [
            {"kind": "session_started", "tick": 0},
            {"kind": "session_left", "tick": 20},
        ]
        left["last_tick"] = 20
        self.write(left, "c01-left.json")
        result = self.review()
        self.assertEqual(result["aggregate"]["sessions"], 2)
        self.assertEqual(result["aggregate"]["completed_sessions"], 1)
        self.assertEqual(result["aggregate"]["left_sessions"], 1)
        self.assertEqual(result["quality"]["flags"], [])
        self.assertNotIn("c01-left", json.dumps(result))

    def test_MEASURE24_dropped_events_do_not_masquerade_as_complete(self) -> None:
        report = copy.deepcopy(self.sample)
        report["dropped_events"] = 5
        report["events"] = [
            {"kind": "session_started", "tick": 0},
            {"kind": "first_repair", "tick": 10},
        ]
        self.write(report)
        result = self.review()
        self.assertEqual(result["quality"]["sessions_with_dropped_events"], 1)
        self.assertEqual(result["quality"]["sessions_without_terminal_event"], 1)
        self.assertIn("EVENTS_DROPPED", result["quality"]["flags"])
        self.assertIn("TERMINAL_EVENT_NOT_OBSERVED", result["quality"]["flags"])
        self.assertEqual(result["quality"]["gate"], "REVIEW_REQUIRED")
        self.assertEqual(result["aggregate"]["data_completeness"], "EVENTS_DROPPED")

    def test_MEASURE24_missing_repair_or_results_are_quality_flags_not_invented(self) -> None:
        report = copy.deepcopy(self.sample)
        report["events"] = [
            {"kind": "session_started", "tick": 0},
            {"kind": "session_completed", "tick": 30},
        ]
        self.write(report)
        result = self.review()
        self.assertIn("FIRST_REPAIR_NOT_OBSERVED", result["quality"]["flags"])
        self.assertIn("RESULTS_OPEN_EVENT_NOT_OBSERVED", result["quality"]["flags"])
        self.assertEqual(result["quality"]["completions_without_observed_first_repair"], 1)
        self.assertEqual(result["quality"]["completions_without_results_opened"], 1)
        self.assertEqual(result["aggregate"]["completed_sessions"], 1)

    def test_MEASURE24_open_idle_span_warns_without_fabricating_duration(self) -> None:
        report = copy.deepcopy(self.sample)
        report["events"].insert(1, {"kind": "idle_started", "tick": 5})
        self.write(report)
        result = self.review()
        self.assertEqual(result["quality"]["sessions_with_open_idle_span"], 1)
        self.assertEqual(result["aggregate"]["idle_total_ticks"], 0)
        self.assertIn("IDLE_SPAN_OPEN_AT_EXIT", result["quality"]["flags"])

    def test_MEASURE24_nonconsent_or_identity_fields_are_rejected(self) -> None:
        for update in ({"opted_in": False}, {"peer_id": "SECRET"},
                       {"account_key": "VERY_PRIVATE"}):
            report = copy.deepcopy(self.sample)
            report.update(update)
            path = self.write(report)
            with self.subTest(update=update), self.assertRaises(measure_report.InvalidReport):
                self.review(path)

    def test_MEASURE24_symlink_input_is_rejected_without_following(self) -> None:
        original = self.write()
        alias = self.folder / "c01-alias.json"
        try:
            alias.symlink_to(original)
        except (OSError, NotImplementedError):
            self.skipTest("test environment cannot create file symlinks")
        with self.assertRaisesRegex(measure_report.InvalidReport, "UNSAFE_INPUT"):
            self.review(alias)
        with self.assertRaisesRegex(measure_report.InvalidReport, "UNSAFE_REPORT_FILE"):
            self.review()

    def test_MEASURE24_empty_or_oversized_selection_fails_closed(self) -> None:
        with self.assertRaisesRegex(measure_report.InvalidReport, "INVALID_REPORT_COUNT"):
            self.review()
        for index in range(measure_report.MAX_REPORTS + 1):
            self.write(name=f"c01-{index:03d}.json")
        with self.assertRaisesRegex(measure_report.InvalidReport, "INVALID_REPORT_COUNT"):
            self.review()

    def test_MEASURE24_cli_error_does_not_expose_file_path_or_content(self) -> None:
        secret = "DO_NOT_REVEAL_PERSONAL_PAYLOAD"
        report = copy.deepcopy(self.sample)
        report["steam_id"] = secret
        path = self.write(report)
        process = subprocess.run(
            [sys.executable, str(Path(measure_review.__file__).resolve()), str(path)],
            capture_output=True, text=True, check=False,
        )
        self.assertEqual(process.returncode, 2)
        self.assertIn("MEASURE24_ERROR: INVALID_ROOT_KEYS", process.stderr)
        self.assertNotIn(secret, process.stdout + process.stderr)
        self.assertNotIn(str(path), process.stdout + process.stderr)

    def test_MEASURE24_cli_valid_result_has_no_source_paths(self) -> None:
        # No injection of test clocks into the CLI: use the actual filesystem now.
        path = self.folder / "c01-current.json"
        path.write_text(json.dumps(self.sample), encoding="utf-8")
        process = subprocess.run(
            [sys.executable, str(Path(measure_review.__file__).resolve()), str(path)],
            capture_output=True, text=True, check=False,
        )
        self.assertEqual(process.returncode, 0, process.stderr)
        output = json.loads(process.stdout)
        self.assertEqual(output["files_scanned"], 1)
        self.assertIn("HUMAN", output["consent_gate"])
        self.assertNotIn(str(path), process.stdout)
        self.assertNotIn("c01-current", process.stdout)

    def test_MEASURE24_review_window_boundary_is_inclusive(self) -> None:
        self.write(age_days=30)
        result = self.review()
        self.assertEqual(result["retention"]["gate"], "WITHIN_REVIEW_WINDOW")
        self.assertIsNotNone(result["aggregate"])


if __name__ == "__main__":
    unittest.main()
