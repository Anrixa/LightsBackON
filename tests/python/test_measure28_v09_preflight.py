"""MEASURE28: ten-run V09 structural preflight never asserts playtest success."""
from __future__ import annotations

import copy
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from tools import measure_v09_preflight, measure_review


class V09PreflightTests(unittest.TestCase):
    NOW = 2_000_000_000.0

    def setUp(self) -> None:
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.folder = Path(tmp.name)
        self.template = {
            "schema_version": 1, "contract": "C01", "tick_rate_hz": 10,
            "opted_in": True, "dropped_events": 0, "outcome": "completed",
            "last_tick": 20,
            "events": [
                {"kind": "session_started", "tick": 0},
                {"kind": "first_repair", "tick": 5},
                {"kind": "session_completed", "tick": 18},
                {"kind": "results_opened", "tick": 20},
            ],
        }

    def add(self, index: int, *, age_days: int = 0,
            dropped: bool = False) -> Path:
        report = copy.deepcopy(self.template)
        report["last_tick"] = 20 + index
        report["events"][-1]["tick"] = 20 + index
        if dropped:
            report["dropped_events"] = 1
        path = self.folder / f"c01-{index:03d}.json"
        path.write_text(json.dumps(report), encoding="utf-8")
        timestamp = self.NOW - age_days * measure_review.SECONDS_PER_DAY
        os.utime(path, (timestamp, timestamp))
        return path

    def run_preflight(self) -> dict:
        return measure_v09_preflight.preflight(self.folder, now_utc=self.NOW)

    def test_MEASURE28_one_valid_run_is_not_ten(self) -> None:
        self.add(0)
        result = self.run_preflight()
        self.assertEqual(result["preflight_gate"], "BELOW_TEN_RUN_TARGET")
        self.assertEqual(result["structurally_aggregatable_runs"], 1)
        self.assertEqual(result["target_run_count"], 10)

    def test_MEASURE28_nine_valid_reports_are_not_enough(self) -> None:
        for i in range(9):
            self.add(i)
        self.assertEqual(self.run_preflight()["preflight_gate"], "BELOW_TEN_RUN_TARGET")

    def test_MEASURE28_ten_reports_are_only_structural_candidate(self) -> None:
        for i in range(10):
            self.add(i)
        result = self.run_preflight()
        self.assertEqual(
            result["preflight_gate"],
            "STRUCTURAL_SAMPLE_PRESENT_REQUIRES_HUMAN_VERIFICATION",
        )
        self.assertEqual(result["claimed_completed_runs"], 10)
        self.assertEqual(result["human_playtest_gate"], "REQUIRED")
        self.assertEqual(result["four_player_evidence"],
                         "NOT_OBSERVABLE_IN_REPORT_SCHEMA")
        self.assertEqual(result["physical_build_evidence"],
                         "NOT_OBSERVABLE_IN_REPORT_SCHEMA")
        self.assertEqual(result["study_gate"], "HUMAN_PLAYTEST_REVIEW_REQUIRED")
        self.assertEqual(result["release_gate"], "NOT_EVALUATED")

    def test_MEASURE28_dropped_observation_blocks_structural_claim(self) -> None:
        for i in range(10):
            self.add(i, dropped=(i == 4))
        result = self.run_preflight()
        self.assertEqual(result["aggregate_gate"], "HOLD_INCOMPLETE_OBSERVATIONS")
        self.assertEqual(result["preflight_gate"], "INPUT_OR_OBSERVATION_HOLD")
        self.assertIsNone(result["structurally_aggregatable_runs"])
        self.assertIsNone(result["claimed_completed_runs"])

    def test_MEASURE28_retention_review_blocks_sample(self) -> None:
        for i in range(10):
            self.add(i, age_days=(31 if i == 9 else 0))
        result = self.run_preflight()
        self.assertEqual(result["aggregate_gate"], "HOLD_RETENTION_REVIEW")
        self.assertEqual(result["preflight_gate"], "INPUT_OR_OBSERVATION_HOLD")

    def test_MEASURE28_invalid_consent_fails_closed(self) -> None:
        path = self.add(0)
        report = json.loads(path.read_text(encoding="utf-8"))
        report["opted_in"] = False
        path.write_text(json.dumps(report), encoding="utf-8")
        with self.assertRaises(measure_review.measure_report.InvalidReport):
            self.run_preflight()

    def test_MEASURE28_no_path_or_identity_export_and_read_only(self) -> None:
        path = self.add(0)
        before = path.read_bytes()
        result = self.run_preflight()
        output = json.dumps(result)
        self.assertNotIn(str(path), output)
        self.assertNotIn("c01-000", output)
        self.assertEqual(path.read_bytes(), before)
        self.assertFalse(result["automatic_deletion"])
        self.assertFalse(result["network_upload"])

    def test_MEASURE28_cli_rejects_untrusted_data_without_path_leak(self) -> None:
        path = self.add(0)
        report = json.loads(path.read_text(encoding="utf-8"))
        report["unknown_test_marker"] = "NOT_FOR_STDERR"
        path.write_text(json.dumps(report), encoding="utf-8")
        run = subprocess.run(
            [sys.executable, str(Path(measure_v09_preflight.__file__).resolve()), str(path)],
            capture_output=True, text=True, check=False,
        )
        self.assertEqual(run.returncode, 2)
        self.assertIn("MEASURE28_ERROR: INVALID_ROOT_KEYS", run.stderr)
        self.assertNotIn(str(path), run.stderr + run.stdout)
        self.assertNotIn("NOT_FOR_STDERR", run.stderr + run.stdout)


if __name__ == "__main__":
    unittest.main()
