"""EXP014 A08 immutable source, nonlinear DAG and authority mutation tests."""
from __future__ import annotations

import copy
import json
import unittest

from tools.validate_exp014_puzzles import (
    ATLAS, BOOK, CONTINGENCIES, HOST, MODULE, STAGE,
    parse_a06, validate,
)


class EXP014PuzzleTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.atlas = json.loads(ATLAS.read_text(encoding="utf-8"))
        cls.contingencies = json.loads(CONTINGENCIES.read_text(encoding="utf-8"))
        cls.book = json.loads(BOOK.read_text(encoding="utf-8"))
        cls.classes, _ = parse_a06()
        cls.host = HOST.read_text(encoding="utf-8")
        cls.stage = STAGE.read_text(encoding="utf-8")
        cls.module = MODULE.read_text(encoding="utf-8")

    def check(self, **changed: object) -> dict:
        args = dict(atlas=self.atlas, contingency=self.contingencies,
                    a06_class=self.classes, book=self.book,
                    host=self.host, stage=self.stage, module=self.module)
        args.update(changed)
        return validate(**args)

    def test_all_200_source_cases_and_400_noncosmetic_paths(self) -> None:
        report = self.check()
        self.assertTrue(report["ok"])
        self.assertEqual(report["source_sites"], 200)
        self.assertEqual(report["original_task_ids"], 1000)
        self.assertEqual(report["forensic_graphs"], 200)
        self.assertEqual(report["field_graphs"], 200)
        self.assertGreaterEqual(report["noncosmetic_dependency_patterns"], 6)
        self.assertFalse(report["human_controller_certified"])

    def test_cosmetic_names_and_host_clock_changes_do_not_fake_diversity(self) -> None:
        book = copy.deepcopy(self.book)
        other = book["entries"][0]["branches"]["forensic"]
        duplicate = book["entries"][1]["branches"]["forensic"]
        duplicate["entry"] = other["entry"]
        for src, dst in zip(other["nodes"], duplicate["nodes"]):
            dst.update({key: copy.deepcopy(src[key]) for key in
                        ("kind", "station", "requires", "guard", "cost")})
            dst["dwell_ticks"] = (src["dwell_ticks"] % 3) + 2
        with self.assertRaisesRegex(ValueError, "NONCOSMETIC_DUPLICATE_FORENSIC"):
            self.check(book=book)

    def test_cycle_or_missing_dependency_rejected(self) -> None:
        book = copy.deepcopy(self.book)
        book["entries"][11]["branches"]["forensic"]["nodes"][2]["requires"] = ["P5"]
        with self.assertRaisesRegex(ValueError, "CYCLE_OR_MISSING_DEPENDENCY"):
            self.check(book=book)

    def test_zero_cost_forensic_and_drainable_field_are_forbidden(self) -> None:
        book = copy.deepcopy(self.book)
        for node in book["entries"][0]["branches"]["forensic"]["nodes"]:
            node["cost"] = 0
        with self.assertRaisesRegex(ValueError, "INVALID_BUDGET"):
            self.check(book=book)
        book = copy.deepcopy(self.book)
        book["entries"][0]["branches"]["field"]["nodes"][0]["cost"] = 1
        with self.assertRaisesRegex(ValueError, "INVALID_BUDGET"):
            self.check(book=book)

    def test_foreign_station_route_task_and_risk_splices_rejected(self) -> None:
        for key, value, diagnostic in (
            ("targets", {"A": "SC_200_A"}, "SOURCE_STATION_OR_ACTION_SPLICE"),
            ("source_task_ids", ["JOB_001_1"], "IMMUTABLE_TASK_DRIFT"),
            ("source_risk", "forged safe risk", "SOURCE_IDENTITY_DRIFT"),
            ("risk_class", "weather", "REGIONAL_RISK_DRIFT"),
        ):
            book = copy.deepcopy(self.book)
            book["entries"][0][key] = value
            with self.assertRaisesRegex(ValueError, diagnostic):
                self.check(book=book)

    def test_host_bypass_and_unauthorized_presentation_paths_rejected(self) -> None:
        for fragment in ("EXP014_A08_INVESTIGATION_INCOMPLETE",
                         "EXP014_A08_INVESTIGATION_REQUIRED",
                         "site_puzzles.operate(entity, action, _puzzle_facts())"):
            removed = self.host.replace(fragment, "BYPASS")
            with self.assertRaisesRegex(ValueError, "HOST_AUTHORITY_OR_EXTRACT_BYPASS"):
                self.check(host=removed)
        with self.assertRaisesRegex(ValueError, "PRESENTATION_DISCONNECTED"):
            self.check(stage=self.stage.replace("_activate_puzzle_target()", "wrong_action()"))

    def test_unsupported_source_action_and_decorative_nodes_rejected(self) -> None:
        book = copy.deepcopy(self.book)
        book["entries"][0]["branches"]["forensic"]["nodes"][0]["source_action"] = "FAKE_ACTION"
        with self.assertRaisesRegex(ValueError, "UNSUPPORTED_NODE"):
            self.check(book=book)
        book = copy.deepcopy(self.book)
        # A final attestation that depends only on the root would make
        # the five other site proofs decorative and disconnected.
        book["entries"][0]["branches"]["field"]["nodes"][-1]["requires"] = ["P0"]
        with self.assertRaisesRegex(ValueError, "DECORATIVE_UNCONNECTED_EVIDENCE"):
            self.check(book=book)


if __name__ == "__main__":
    unittest.main()
