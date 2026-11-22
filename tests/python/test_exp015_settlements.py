"""EXP015 A10 authority, source mutation and financial conservation tests."""
from __future__ import annotations
import copy
import unittest
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))
from validate_exp015_settlements import audit, load  # noqa: E402


class SettlementOracleTests(unittest.TestCase):
    def setUp(self) -> None:
        self.networks, self.assurances, self.book = load()

    def test_all_25_original_finales_and_conservation(self) -> None:
        result = audit(self.networks, self.assurances, self.book)
        self.assertTrue(result["ok"])
        self.assertEqual(result["original_finales"], 25)
        self.assertEqual(result["conditional_source_scenarios"]["finite_settlement"], 25)
        self.assertTrue(result["no_energization_claim"])

    def test_forged_reserve_anchor_rejected(self) -> None:
        altered = copy.deepcopy(self.book)
        altered["entries"][7]["reserve_anchor_site_id"] = "FAKE_ANCHOR"
        with self.assertRaisesRegex(ValueError, "ORIGINAL_FINALE_SOURCE_MISMATCH"):
            audit(self.networks, self.assurances, altered)

    def test_forged_task_and_proof_rejected(self) -> None:
        for key, value in (
            ("original_finale_task_ids", ["UNAUTHORIZED_REWARD"]),
            ("audit_proof", "settle_fake_electricity"),
            ("initial_reserve_pu", 1000000),
        ):
            with self.subTest(field=key):
                altered = copy.deepcopy(self.book)
                altered["entries"][4][key] = value
                with self.assertRaisesRegex(ValueError, "ORIGINAL_FINALE_SOURCE_MISMATCH"):
                    audit(self.networks, self.assurances, altered)

    def test_legacy_qualification_cannot_be_promoted(self) -> None:
        changed = copy.deepcopy(self.book)
        changed["qualification"] = "PRODUCTION_READY"
        with self.assertRaisesRegex(ValueError, "SOURCE_BOOK_AUTHORITY"):
            audit(self.networks, self.assurances, changed)


if __name__ == "__main__":
    unittest.main()
