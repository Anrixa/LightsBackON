"""EXP012 independent source/mutation/replay qualification, not playability."""
from __future__ import annotations

import copy
import unittest

from tools.validate_exp012_worksites import load_inputs, route_replay, validate


class EXP012WorksiteTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.atlas, cls.loads, cls.book = load_inputs()

    def test_complete_source_coverage_and_eight_families(self) -> None:
        result = validate(self.atlas, self.loads, self.book)
        self.assertEqual(
            (result["levels"], result["task_bindings"], result["targets"],
             result["site_families"], result["alternative_routes"]),
            (200, 1000, 1400, 8, 400))

    def test_both_routes_solve_all_sites_without_consumables(self) -> None:
        for entry in self.book["entries"]:
            with self.subTest(level=entry["level_id"]):
                a = route_replay(entry, "priority")
                b = route_replay(entry, "resilience")
                self.assertEqual(len(a["order"]), 3)
                self.assertEqual(len(b["order"]), 3)
                self.assertEqual(a["cells_left"], entry["cell_budget"])
                self.assertEqual(b["cells_left"], entry["cell_budget"])

    def test_rapid_uses_finite_cells_and_remains_solvable(self) -> None:
        for entry in self.book["entries"]:
            with self.subTest(level=entry["level_id"]):
                for route in ("priority", "resilience"):
                    rapid = route_replay(entry, route, True)
                    self.assertEqual(
                        rapid["cells_left"], max(0, entry["cell_budget"] - 3))

    def test_missing_task_binding_is_denied(self) -> None:
        altered = copy.deepcopy(self.book)
        altered["entries"][0]["task_ids"][3] = "FAKE_OPTIONAL"
        with self.assertRaisesRegex(ValueError, "EXP012_SOURCE_DRIFT_task_ids"):
            validate(self.atlas, self.loads, altered)

    def test_source_splice_is_denied(self) -> None:
        altered = copy.deepcopy(self.book)
        altered["entries"][0]["load_key"] = altered["entries"][1]["load_key"]
        with self.assertRaisesRegex(ValueError, "EXP012_SOURCE_DRIFT_load_key"):
            validate(self.atlas, self.loads, altered)

    def test_made_up_target_is_denied(self) -> None:
        altered = copy.deepcopy(self.book)
        altered["entries"][0]["checkpoints"][0]["id"] = "WO_FORGED_A"
        with self.assertRaisesRegex(ValueError, "EXP012_CHECKPOINT_DRIFT"):
            validate(self.atlas, self.loads, altered)

    def test_cyclic_dependency_is_denied(self) -> None:
        altered = copy.deepcopy(self.book)
        entry = altered["entries"][0]
        entry["routes"]["priority"][0] = [entry["checkpoints"][2]["id"]]
        with self.assertRaisesRegex(ValueError, "EXP012_ROUTES_INVALID"):
            validate(self.atlas, self.loads, altered)

    def test_capacity_inflation_is_denied(self) -> None:
        altered = copy.deepcopy(self.book)
        altered["entries"][0]["crew_capacity"] = 99
        with self.assertRaisesRegex(ValueError, "EXP012_SOURCE_DRIFT_crew_capacity"):
            validate(self.atlas, self.loads, altered)

    def test_float_or_boolean_budget_is_denied(self) -> None:
        for bogus in (True, 2.0):
            altered = copy.deepcopy(self.book)
            altered["entries"][0]["cell_budget"] = bogus
            with self.assertRaisesRegex(ValueError, "EXP012_RESOURCE_TYPE_INVALID"):
                validate(self.atlas, self.loads, altered)

    def test_export_source_must_be_present_in_both_presets(self) -> None:
        with self.assertRaisesRegex(ValueError, "EXP012_WINDOWS_EXPORT_MISSING"):
            validate(self.atlas, self.loads, self.book, presets="")


if __name__ == "__main__":
    unittest.main()
