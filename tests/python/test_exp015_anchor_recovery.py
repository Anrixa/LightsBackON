"""A12.3 rejects false managed source claims and mutated original feeder trees."""
from __future__ import annotations

import copy
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))
from validate_exp015_anchor_recovery import audit  # noqa: E402
from validate_exp015_anchor_routes import source_book  # noqa: E402


class AdversarialSourceTests(unittest.TestCase):
    def setUp(self) -> None:
        self.book = source_book()

    def test_real_original_25_region_feeders(self) -> None:
        result = audit(self.book)
        self.assertEqual(result["source_regions"], 25)
        self.assertGreaterEqual(result["repairable_path_feeder_cases"], 25)
        self.assertEqual(result["missing_receipt_regions"], [11, 25])
        self.assertTrue(result["no_fabricated_electrical_power"])

    def test_forged_primary_path_is_rejected(self) -> None:
        corrupt = copy.deepcopy(self.book)
        corrupt["regions"][4]["primary_feeders"][0]["from"] = "INVENTED_ROOT"
        with self.assertRaisesRegex(ValueError, "EXP015_A12_"):
            audit(corrupt)

    def test_original_risk_proof_cannot_disappear(self) -> None:
        corrupt = copy.deepcopy(self.book)
        corrupt["regions"][0]["recovery_procedure"] = ""
        with self.assertRaisesRegex(ValueError, "REAL_SOURCE_RECOVERY_IDENTITY"):
            audit(corrupt)

    def test_release_promotion_fails(self) -> None:
        corrupt = copy.deepcopy(self.book)
        corrupt["qualification"] = "PRODUCTION_APPROVED"
        with self.assertRaisesRegex(ValueError, "SOURCE_AUTHORITY"):
            audit(corrupt)


if __name__ == "__main__":
    unittest.main()
