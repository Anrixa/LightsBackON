"""MEASURE27: report eligibility is not the same as claimed completion."""
from __future__ import annotations

import copy
import json
import os
import tempfile
import unittest
from pathlib import Path

from tools import measure_review


class AggregateEligibilityTests(unittest.TestCase):
    NOW = 2_000_000_000.0

    def setUp(self) -> None:
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.folder = Path(temp.name)
        self.sample = {
            "schema_version": 1, "contract": "C01", "tick_rate_hz": 10,
            "opted_in": True, "outcome": "completed",
            "dropped_events": 0, "last_tick": 20,
            "events": [
                {"kind": "session_started", "tick": 0},
                {"kind": "first_repair", "tick": 4},
                {"kind": "session_completed", "tick": 18},
                {"kind": "results_opened", "tick": 20},
            ],
        }

    def write(self, data: dict | None = None, name: str = "c01-a.json",
              age_days: int = 0) -> None:
        file = self.folder / name
        file.write_text(json.dumps(self.sample if data is None else data), encoding="utf-8")
        clock = self.NOW - age_days * measure_review.SECONDS_PER_DAY
        os.utime(file, (clock, clock))

    def review(self) -> dict:
        return measure_review.review_input(self.folder, now_utc=self.NOW)

    def test_MEASURE27_full_observed_completion_is_structurally_available(self) -> None:
        self.write()
        result = self.review()
        self.assertEqual(result["aggregate_gate"], "STRUCTURAL_AGGREGATE_AVAILABLE")
        self.assertEqual(result["aggregate"]["completed_sessions"], 1)
        self.assertEqual(result["quality"]["sessions_incomplete_observation"], 0)
        self.assertEqual(result["study_gate"], "HUMAN_PLAYTEST_REVIEW_REQUIRED")

    def test_MEASURE27_dropped_events_hold_counts_and_timings(self) -> None:
        report = copy.deepcopy(self.sample)
        report["dropped_events"] = 2
        report["events"] = report["events"][:2]
        self.write(report)
        result = self.review()
        self.assertEqual(result["aggregate_gate"], "HOLD_INCOMPLETE_OBSERVATIONS")
        self.assertEqual(result["quality"]["sessions_incomplete_observation"], 1)
        self.assertIsNone(result["aggregate"])

    def test_MEASURE27_missing_debrief_holds_completed_cohort(self) -> None:
        report = copy.deepcopy(self.sample)
        report["events"].pop()
        self.write(report)
        result = self.review()
        self.assertIsNone(result["aggregate"])
        self.assertEqual(result["aggregate_gate"], "HOLD_INCOMPLETE_OBSERVATIONS")

    def test_MEASURE27_unclosed_idle_span_holds_time_statistics(self) -> None:
        report = copy.deepcopy(self.sample)
        report["events"].insert(1, {"kind": "idle_started", "tick": 1})
        self.write(report)
        result = self.review()
        self.assertEqual(result["quality"]["sessions_incomplete_observation"], 1)
        self.assertIsNone(result["aggregate"])

    def test_MEASURE27_missing_first_repair_only_is_review_not_fabrication(self) -> None:
        report = copy.deepcopy(self.sample)
        report["events"].pop(1)
        self.write(report)
        result = self.review()
        self.assertEqual(result["aggregate"]["first_repair_median_ticks"], None)
        self.assertEqual(result["aggregate_gate"], "STRUCTURAL_AGGREGATE_AVAILABLE")
        self.assertEqual(result["quality"]["gate"], "REVIEW_REQUIRED")
        self.assertIn("FIRST_REPAIR_NOT_OBSERVED", result["quality"]["flags"])

    def test_MEASURE27_many_flags_on_one_session_count_once(self) -> None:
        report = copy.deepcopy(self.sample)
        report["dropped_events"] = 5
        report["events"] = [
            {"kind": "session_started", "tick": 0},
            {"kind": "idle_started", "tick": 2},
        ]
        self.write(report)
        result = self.review()
        self.assertEqual(result["quality"]["sessions_incomplete_observation"], 1)
        self.assertGreaterEqual(len(result["quality"]["flags"]), 2)
        self.assertIsNone(result["aggregate"])

    def test_MEASURE27_retention_hold_has_priority(self) -> None:
        report = copy.deepcopy(self.sample)
        report["events"].pop()
        self.write(report, age_days=31)
        result = self.review()
        self.assertEqual(result["aggregate_gate"], "HOLD_RETENTION_REVIEW")
        self.assertIsNone(result["aggregate"])

    def test_MEASURE27_duplicate_hold_has_priority_over_missingness(self) -> None:
        report = copy.deepcopy(self.sample)
        report["events"].pop()
        self.write(report, name="c01-a.json")
        self.write(report, name="c01-b.json")
        result = self.review()
        self.assertEqual(result["aggregate_gate"], "HOLD_DUPLICATE_REVIEW")
        self.assertEqual(result["quality"]["sessions_incomplete_observation"], 2)
        self.assertIsNone(result["aggregate"])

    def test_MEASURE27_complete_mixed_outcomes_retain_real_denominator(self) -> None:
        self.write()
        left = copy.deepcopy(self.sample)
        left["outcome"] = "left"
        left["events"] = [
            {"kind": "session_started", "tick": 0},
            {"kind": "session_left", "tick": 20},
        ]
        self.write(left, name="c01-b.json")
        result = self.review()
        self.assertEqual(result["aggregate"]["sessions"], 2)
        self.assertEqual(result["aggregate"]["completed_sessions"], 1)
        self.assertEqual(result["aggregate"]["left_sessions"], 1)
        self.assertEqual(result["quality"]["sessions_incomplete_observation"], 0)


if __name__ == "__main__":
    unittest.main()
