"""EXP015 A12.1 — source-independent graph mutations and fixture hold tests."""
from __future__ import annotations

import copy
import importlib.util
import unittest
from pathlib import Path

MODULE = Path(__file__).resolve().parents[2] / "tools" / "validate_exp015_anchor_routes.py"
SPEC = importlib.util.spec_from_file_location("anchor_a12_oracle", MODULE)
assert SPEC and SPEC.loader
ORACLE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(ORACLE)


class OriginalAnchorSourceTests(unittest.TestCase):
    def setUp(self) -> None:
        self.book = ORACLE.source_book()

    def test_all_25_original_anchor_routes_and_two_dark_source_cases(self) -> None:
        report = ORACLE.audit(self.book)
        self.assertTrue(report["ok"])
        self.assertEqual(report["rooted_original_paths"], 25)
        self.assertEqual(report["baseline_dark_region_numbers"], [11, 25])
        self.assertFalse(report["host_recovery_implemented"])

    def test_duplicate_inbound_provenance_rejected(self) -> None:
        mutated = copy.deepcopy(self.book)
        source = mutated["regions"][0]["primary_feeders"]
        source[1]["to"] = source[0]["to"]
        with self.assertRaisesRegex(ValueError, "NONORIGINAL_TREE_EDGE"):
            ORACLE.audit(mutated)

    def test_missing_original_reserve_anchor_rejected(self) -> None:
        mutated = copy.deepcopy(self.book)
        mutated["regions"][0]["reserve_anchor_site"] = "FORGED"
        with self.assertRaisesRegex(ValueError, "ORIGINAL_SITES"):
            ORACLE.audit(mutated)

    def test_forged_feeder_root_and_cycle_rejected(self) -> None:
        mutated = copy.deepcopy(self.book)
        mutated["regions"][0]["primary_feeders"][0]["from"] = "LV_008"
        with self.assertRaisesRegex(ValueError, "CYCLE_OR_DISCONNECTED_ORIGINAL_TREE"):
            ORACLE.audit(mutated)

    def test_source_authority_and_region_coverage_rejected(self) -> None:
        mutated = copy.deepcopy(self.book)
        mutated["qualification"] = "RELEASED"
        with self.assertRaisesRegex(ValueError, "SOURCE_AUTHORITY"):
            ORACLE.audit(mutated)
        mutated = copy.deepcopy(self.book)
        mutated["regions"].pop()
        with self.assertRaisesRegex(ValueError, "SOURCE_AUTHORITY"):
            ORACLE.audit(mutated)


if __name__ == "__main__":
    unittest.main()
