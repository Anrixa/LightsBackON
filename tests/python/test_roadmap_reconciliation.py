"""Regression tests for the immutable original roadmap evidence overlay."""
from __future__ import annotations

import copy
import json
import unittest
from pathlib import Path

from tools.roadmap_reconciliation import (
    DEFAULT_AUDIT,
    DEFAULT_BACKLOG,
    REPOSITORY_ROOT,
    validate,
)


class RoadmapReconciliationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.backlog = json.loads(DEFAULT_BACKLOG.read_text(encoding="utf-8"))
        cls.audit = json.loads(DEFAULT_AUDIT.read_text(encoding="utf-8"))

    def validate_copy(self, mutate=None):
        audit = copy.deepcopy(self.audit)
        backlog = copy.deepcopy(self.backlog)
        if mutate is not None:
            mutate(audit, backlog)
        return validate(audit, backlog, REPOSITORY_ROOT)

    def test_full_original_matrix_and_three_scorecards(self) -> None:
        result = self.validate_copy()
        self.assertEqual(result["original_backlog"]["DONE"], 5)
        self.assertEqual(result["original_backlog"]["CLOUD_VERIFIED"], 15)
        self.assertEqual(result["reconciled_evidence_classes"]["SOURCE_OVERLAP"], 21)
        self.assertEqual(result["engineering_coverage"]["qualifying_evidence_tasks"], 40)
        self.assertEqual(result["engineering_coverage"]["original_pre_beta_tasks"], 54)
        self.assertAlmostEqual(result["engineering_coverage"]["percent"], 74.1)
        self.assertEqual(result["playable_alpha"]["qualified_gates"], 6)
        self.assertEqual(result["commercial_release"]["qualified_gates"], 2)
        self.assertEqual(result["playable_alpha"]["acceptance"], "HOLD")
        self.assertEqual(result["commercial_release"]["acceptance"], "HOLD")

    def test_rejects_unsafe_promotion_from_source_overlap(self) -> None:
        def mutate(audit, _):
            next(t for t in audit["tasks"] if t["id"] == "CT03")["backlog_status"] = "DONE"
        with self.assertRaisesRegex(ValueError, "acceptance status was rewritten"):
            self.validate_copy(mutate)

    def test_rejects_missing_source_evidence(self) -> None:
        def mutate(audit, _):
            next(t for t in audit["tasks"] if t["id"] == "D05")["evidence_paths"] = [
                "docs/evidence/DOES-NOT-EXIST.md"
            ]
        with self.assertRaisesRegex(ValueError, "evidence not found"):
            self.validate_copy(mutate)

    def test_rejects_false_alpha_certification(self) -> None:
        def mutate(audit, _):
            next(g for g in audit["alpha_gates"] if g["id"] == "AL12")["status"] = "PASS"
        with self.assertRaisesRegex(ValueError, "hold cannot be lifted"):
            self.validate_copy(mutate)

    def test_rejects_false_release_certification(self) -> None:
        def mutate(audit, _):
            next(g for g in audit["release_gates"] if g["id"] == "RL10")["status"] = "PASS"
        with self.assertRaisesRegex(ValueError, "hold cannot be lifted"):
            self.validate_copy(mutate)

    def test_rejects_duplicate_task_ids(self) -> None:
        def mutate(audit, _):
            audit["tasks"][4]["id"] = audit["tasks"][3]["id"]
        with self.assertRaisesRegex(ValueError, "Duplicate task IDs"):
            self.validate_copy(mutate)

    def test_rejects_absolute_and_parent_evidence_paths(self) -> None:
        for invalid_path in ("/tmp/private.txt", "../../private.txt"):
            with self.subTest(invalid_path=invalid_path):
                def mutate(audit, _, invalid_path=invalid_path):
                    next(t for t in audit["tasks"] if t["id"] == "D03")[
                        "evidence_paths"
                    ] = [invalid_path]
                with self.assertRaisesRegex(ValueError, "unsafe evidence path"):
                    self.validate_copy(mutate)


if __name__ == "__main__":
    unittest.main()
