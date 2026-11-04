"""DS02 regression checks for source sample integrity and honest evidence limits."""
from __future__ import annotations

import copy
import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
from validate_ds02 import LOG_PATH, validate  # noqa: E402


class DS02SourceLogTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.valid_log = json.loads(LOG_PATH.read_text(encoding="utf-8"))

    def mutated(self) -> dict:
        return copy.deepcopy(self.valid_log)

    def test_DS02_source_log_has_28_distinct_primary_sources(self) -> None:
        self.assertEqual(validate(self.valid_log), [])
        ids = {row["steam_app_id"] for row in self.valid_log["records"]}
        self.assertEqual(len(ids), 28)
        self.assertEqual(self.valid_log["sample_size"]["metadata_screened"], 28)
        self.assertEqual(self.valid_log["sample_size"]["deep_scored"], 28)
        self.assertFalse(self.valid_log["sample_size"]["attempted_1000_candidate_crawl"])

    def test_DS02_rejects_inflated_1000_sample_and_duplicate_games(self) -> None:
        log = self.mutated()
        log["sample_size"]["metadata_screened"] = 1000
        self.assertTrue(any("sample_size" in error for error in validate(log)))
        log = self.mutated()
        log["records"][1]["steam_app_id"] = log["records"][0]["steam_app_id"]
        self.assertTrue(any("duplicate" in error for error in validate(log)))

    def test_DS02_rejects_source_spoofing_and_unbounded_review_metrics(self) -> None:
        log = self.mutated()
        log["records"][0]["source_url"] = "https://elsewhere.example/app/1290000"
        self.assertTrue(any("primary store URL" in error for error in validate(log)))
        log = self.mutated()
        log["records"][0]["review_metric"]["positive_percent"] = 200
        self.assertTrue(any("review count" in error for error in validate(log)))
        log = self.mutated()
        log["records"][0]["review_metric"]["scope"] = "unit sales"
        self.assertTrue(any("review count" in error for error in validate(log)))

    def test_DS02_unmeasured_accessibility_performance_stay_unknown(self) -> None:
        self.assertTrue(all(
            row["rubric"]["accessibility_quality"] is None
            and row["rubric"]["hardware_performance"] is None
            for row in self.valid_log["records"]
        ))
        log = self.mutated()
        log["records"][0]["rubric"]["hardware_performance"] = 4
        self.assertTrue(any("unverified" in error for error in validate(log)))
        log = self.mutated()
        log["records"][0]["rubric"]["task_pattern"] = 5
        self.assertTrue(any("score must be" in error for error in validate(log)))

    def test_DS02_every_title_has_provenance_transfer_and_confidence(self) -> None:
        for row in self.valid_log["records"]:
            with self.subTest(title=row["title"]):
                self.assertIn(row["confidence"], ("low", "medium", "high"))
                self.assertGreater(len(row["storefront_observation"]), 25)
                self.assertGreater(len(row["transfer_hypothesis"]), 25)
                self.assertEqual(row["review_snapshot_utc"], "2026-11-05")


if __name__ == "__main__":
    unittest.main()
