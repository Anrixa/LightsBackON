"""MEASURE27: diagnostic aggregates must never imply study eligibility."""
from __future__ import annotations

import copy
import json
import os
import tempfile
import unittest
from pathlib import Path

from tools import measure_review


class CohortEvidenceGateTests(unittest.TestCase):
    NOW = 2_000_000_000.0

    def setUp(self) -> None:
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.folder = Path(temporary.name)
        self.report = {
            "schema_version": 1, "contract": "C01", "tick_rate_hz": 10,
            "opted_in": True, "dropped_events": 0, "outcome": "completed",
            "last_tick": 30,
            "events": [
                {"kind": "session_started", "tick": 0},
                {"kind": "first_repair", "tick": 10},
                {"kind": "session_completed", "tick": 28},
                {"kind": "results_opened", "tick": 30},
            ],
        }

    def record(self, content: dict | None = None, name: str = "c01-one.json",
               age_days: int = 0) -> Path:
        path = self.folder / name
        path.write_text(json.dumps(self.report if content is None else content),
                        encoding="utf-8")
        timestamp = self.NOW - age_days * measure_review.SECONDS_PER_DAY
        os.utime(path, (timestamp, timestamp))
        return path

    def review(self) -> dict:
        return measure_review.review_input(self.folder, now_utc=self.NOW)

    def test_MEASURE27_complete_report_is_not_human_approved(self) -> None:
        self.record()
        result = self.review()
        self.assertEqual(result["cohort_evidence"]["gate"], "STRUCTURAL_REVIEW_ONLY")
        self.assertEqual(result["cohort_evidence"]["reasons"], [])
        self.assertEqual(result["cohort_evidence"]["human_study_approval"], "REQUIRED")
        self.assertTrue(result["cohort_evidence"]["aggregate_is_diagnostic_only"])
        self.assertEqual(result["study_gate"], "HUMAN_PLAYTEST_REVIEW_REQUIRED")
        self.assertEqual(result["release_gate"], "NOT_EVALUATED")
        self.assertEqual(result["aggregate"]["sessions"], 1)

    def test_MEASURE27_old_report_is_integrity_hold(self) -> None:
        self.record(age_days=31)
        result = self.review()
        self.assertEqual(result["cohort_evidence"]["gate"], "INPUT_INTEGRITY_HOLD")
        self.assertIn("RETENTION_REVIEW_REQUIRED",
                      result["cohort_evidence"]["reasons"])
        self.assertIsNone(result["aggregate"])

    def test_MEASURE27_identical_reports_are_integrity_hold(self) -> None:
        self.record(name="c01-a.json")
        self.record(name="c01-b.json")
        result = self.review()
        self.assertEqual(result["cohort_evidence"]["gate"], "INPUT_INTEGRITY_HOLD")
        self.assertIn("IDENTICAL_REPORT_PAYLOADS",
                      result["cohort_evidence"]["reasons"])
        self.assertIsNone(result["aggregate"])

    def test_MEASURE27_dropped_events_hold_even_with_diagnostic_summary(self) -> None:
        report = copy.deepcopy(self.report)
        report["dropped_events"] = 2
        report["events"] = report["events"][:2]
        self.record(report)
        result = self.review()
        self.assertEqual(result["cohort_evidence"]["gate"], "DATA_QUALITY_HOLD")
        self.assertIn("EVENTS_DROPPED", result["cohort_evidence"]["reasons"])
        self.assertIn("TERMINAL_EVENT_NOT_OBSERVED",
                      result["cohort_evidence"]["reasons"])
        self.assertEqual(result["aggregate"]["data_completeness"], "EVENTS_DROPPED")

    def test_MEASURE27_missing_debrief_is_quality_hold(self) -> None:
        report = copy.deepcopy(self.report)
        report["events"].pop()
        self.record(report)
        result = self.review()
        self.assertEqual(result["cohort_evidence"]["gate"], "DATA_QUALITY_HOLD")
        self.assertIn("RESULTS_OPEN_EVENT_NOT_OBSERVED",
                      result["cohort_evidence"]["reasons"])
        self.assertEqual(result["aggregate"]["completed_sessions"], 1)

    def test_MEASURE27_missing_first_repair_is_review_not_fabricated(self) -> None:
        report = copy.deepcopy(self.report)
        report["events"].pop(1)
        self.record(report)
        result = self.review()
        self.assertEqual(result["cohort_evidence"]["gate"], "DATA_QUALITY_HOLD")
        self.assertIn("FIRST_REPAIR_NOT_OBSERVED",
                      result["cohort_evidence"]["reasons"])
        self.assertIsNone(result["aggregate"]["first_repair_median_ticks"])

    def test_MEASURE27_output_remains_read_only_and_anonymous(self) -> None:
        path = self.record()
        original = path.read_bytes()
        result = self.review()
        serialized = json.dumps(result)
        self.assertEqual(path.read_bytes(), original)
        self.assertNotIn(str(path), serialized)
        self.assertNotIn("c01-one", serialized)
        self.assertNotIn("_internal_fingerprint", serialized)
        self.assertFalse(result["network_upload"])
        self.assertFalse(result["automatic_deletion"])


if __name__ == "__main__":
    unittest.main()
