"""MEASURE32: the direct offline summary must not publish incomplete timing evidence.

The report command is independently runnable. Calling the stricter review CLI
is recommended, but never a precondition for safe direct output.
"""
from __future__ import annotations

import copy
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from tools import measure_report


class DirectSummaryCompletenessTests(unittest.TestCase):
    @staticmethod
    def complete() -> dict:
        return {
            "schema_version": 1,
            "contract": "C01",
            "tick_rate_hz": 10,
            "opted_in": True,
            "events": [
                {"kind": "session_started", "tick": 0},
                {"kind": "first_repair", "tick": 3},
                {"kind": "idle_started", "tick": 4},
                {"kind": "idle_ended", "tick": 6, "value_ticks": 2},
                {"kind": "session_completed", "tick": 20},
                {"kind": "results_opened", "tick": 25},
            ],
            "dropped_events": 0,
            "outcome": "completed",
            "last_tick": 25,
        }

    def summarize(self, *raw_reports: dict) -> dict:
        return measure_report.summarize(
            [measure_report.validate(item) for item in raw_reports]
        )

    def assert_timing_held(self, result: dict) -> None:
        self.assertEqual(result["observation_gate"], "HOLD_INCOMPLETE_OBSERVATIONS")
        self.assertGreater(result["sessions_with_incomplete_observations"], 0)
        for key in (
            "session_duration_median_ticks",
            "completed_elapsed_median_ticks",
            "completed_elapsed_p95_ticks",
            "first_repair_median_ticks",
            "visible_to_completed_median_ticks",
            "idle_total_ticks",
        ):
            with self.subTest(key=key):
                self.assertIsNone(result[key])

    def test_MEASURE32_clean_observations_keep_original_descriptives(self) -> None:
        result = self.summarize(self.complete())
        self.assertEqual(
            result["observation_gate"],
            "STRUCTURAL_OBSERVATIONS_ONLY_REQUIRES_HUMAN_REVIEW",
        )
        self.assertEqual(result["sessions_with_incomplete_observations"], 0)
        self.assertEqual(result["session_duration_median_ticks"], 25)
        self.assertEqual(result["completed_elapsed_median_ticks"], 20)
        self.assertEqual(result["first_repair_median_ticks"], 3)
        self.assertEqual(result["idle_total_ticks"], 2)
        self.assertEqual(result["release_gate"], "NOT_EVALUATED")
        self.assertEqual(result["retention_duplicate_review"], "NOT_PERFORMED_USE_MEASURE_REVIEW")

    def test_MEASURE32_dropped_events_with_terminal_hold_direct_output(self) -> None:
        report = self.complete()
        report["dropped_events"] = 1
        result = self.summarize(report)
        self.assert_timing_held(result)
        self.assertEqual(result["completed_sessions"], 1)
        self.assertEqual(result["completed_elapsed_sample_count"], 1)
        self.assertEqual(result["observed_completed_terminals"], 1)
        self.assertEqual(result["data_completeness"], "EVENTS_DROPPED")
        self.assertEqual(result["completed_elapsed_p95_gate"], "INCOMPLETE_OBSERVATIONS")

    def test_MEASURE32_missing_terminal_with_drops_holds_direct_output(self) -> None:
        report = self.complete()
        report["dropped_events"] = 2
        report["events"] = report["events"][:2]
        result = self.summarize(report)
        self.assert_timing_held(result)
        self.assertEqual(result["completed_sessions"], 1)
        self.assertEqual(result["observed_completed_terminals"], 0)
        self.assertEqual(result["completed_elapsed_sample_count"], 0)

    def test_MEASURE32_missing_debrief_holds_despite_observed_completion(self) -> None:
        report = self.complete()
        report["events"].pop()
        result = self.summarize(report)
        self.assert_timing_held(result)
        self.assertEqual(result["observed_completed_terminals"], 1)
        self.assertEqual(result["completed_elapsed_sample_count"], 1)

    def test_MEASURE32_unclosed_idle_holds_even_when_outcome_intact(self) -> None:
        report = self.complete()
        report["events"].pop(3)  # Remove matching idle_ended observation.
        result = self.summarize(report)
        self.assert_timing_held(result)
        self.assertEqual(result["dropped_events"], 0)

    def test_MEASURE32_one_bad_session_holds_entire_mixed_cohort(self) -> None:
        good = self.complete()
        poor = copy.deepcopy(good)
        poor["outcome"] = "left"
        poor["dropped_events"] = 1
        poor["events"] = [{"kind": "session_started", "tick": 0}]
        poor["last_tick"] = 200
        result = self.summarize(good, poor)
        self.assert_timing_held(result)
        self.assertEqual(result["sessions_with_incomplete_observations"], 1)
        self.assertEqual(result["sessions"], 2)
        self.assertEqual(result["completed_sessions"], 1)
        self.assertEqual(result["left_sessions"], 1)

    def test_MEASURE32_resumed_no_repair_is_not_falsely_rejected(self) -> None:
        good = self.complete()
        good["events"].pop(1)  # Existing completed checkpoint may already have repair.
        result = self.summarize(good)
        self.assertEqual(result["sessions_with_incomplete_observations"], 0)
        self.assertEqual(result["completed_elapsed_median_ticks"], 20)
        self.assertIsNone(result["first_repair_median_ticks"])

    def test_MEASURE32_clean_mixed_outcomes_keep_real_denominator(self) -> None:
        completed = self.complete()
        left = {
            **completed,
            "outcome": "left",
            "events": [
                {"kind": "session_started", "tick": 0},
                {"kind": "session_left", "tick": 10},
            ],
            "last_tick": 10,
        }
        result = self.summarize(completed, left)
        self.assertEqual(result["sessions_with_incomplete_observations"], 0)
        self.assertEqual(result["observed_completed_terminals"], 1)
        self.assertEqual(result["observed_left_terminals"], 1)
        self.assertEqual(result["session_duration_median_ticks"], 17.5)

    def test_MEASURE32_cli_fail_closed_and_redacted(self) -> None:
        incomplete = self.complete()
        incomplete["dropped_events"] = 1
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "c01-private-local.json"
            path.write_text(json.dumps(incomplete), encoding="utf-8")
            proc = subprocess.run(
                [sys.executable, str(Path(measure_report.__file__).resolve()), str(path)],
                capture_output=True, text=True, check=False,
            )
        self.assertEqual(proc.returncode, 0, proc.stderr)
        result = json.loads(proc.stdout)
        self.assert_timing_held(result)
        self.assertNotIn(str(path), proc.stdout + proc.stderr)
        self.assertNotIn("private-local", proc.stdout + proc.stderr)
        self.assertNotIn('"events": [', proc.stdout)
        self.assertEqual(result["consent_and_playtest_proof"], "NOT_VERIFIED")


if __name__ == "__main__":
    unittest.main()
