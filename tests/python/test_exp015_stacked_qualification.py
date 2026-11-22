"""Mutation probes for EXP015 A12.16 inherited CI/source inventory."""
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from tools import exp015_stacked_qualification as q


class EXP015StackQualificationTests(unittest.TestCase):
    def test_original_region_and_stale_guard_tests_are_pinned(self) -> None:
        inventory = q.check_inventory(q.ROOT)
        self.assertEqual(inventory["expected_methods"], 12)
        self.assertFalse(inventory["test_execution_proved_by_inventory"])
        self.assertEqual(len(inventory["source_inventory"]), 2)

    def test_missing_method_refuses_source_qualification(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            path = root / "tests" / "integration" / "case.gd"
            path.parent.mkdir(parents=True)
            path.write_text("func test_real() -> void:\n\tpass\n", encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "MISSING_TEST_METHOD"):
                q.check_inventory(root, {"tests/integration/case.gd": ("test_missing",)})

    def test_duplicate_test_name_fails_closed(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            path = root / "tests" / "integration" / "case.gd"
            path.parent.mkdir(parents=True)
            path.write_text("func test_same() -> void:\n\tpass\n"
                            "func test_same() -> void:\n\tpass\n", encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "DUPLICATE_TEST_NAME"):
                q.check_inventory(root, {"tests/integration/case.gd": ("test_same",)})

    def test_existing_workflow_executes_python_and_godot(self) -> None:
        q.check_workflow(q.ROOT)

    def test_positive_source_qualification_never_claims_release(self) -> None:
        report = q.qualify()
        self.assertTrue(report["original_contracts_preserved"])
        self.assertFalse(report["ready_for_merge_or_release"])
        self.assertEqual(report["exact_head_linux_windows_ci"], "EXTERNAL_EVIDENCE_REQUIRED")
        self.assertTrue(all(x == "HOLD" for x in report["owner_holds"].values()))

    def test_mutating_owner_hold_blocks_qualification(self) -> None:
        with patch.dict(q.baseline.HOLDS, {"production_release": "PASS"}):
            with self.assertRaisesRegex(ValueError, "OWNER_HOLD_DRIFT"):
                q.qualify()


if __name__ == "__main__":
    unittest.main()
