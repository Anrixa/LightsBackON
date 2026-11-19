"""EXP08 mutation gates and deterministic alternative/recovery reference replays."""
import copy
import unittest

from tools.validate_exp08_faults import load_inputs, validate, replay_reference


class EXP08FaultTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.atlas, cls.graphs, cls.book = load_inputs()

    def test_200_source_scenarios_two_routes_and_unique_keys(self):
        result = validate(self.atlas, self.graphs, self.book)
        self.assertEqual((result["levels"], result["fault_classes"],
                          result["sensor_targets"], result["alternate_routes"]),
                         (200, 8, 400, 400))
        for profile in self.book["entries"]:
            replay_reference(profile)

    def test_forged_graph_identity_rejected(self):
        changed = copy.deepcopy(self.book)
        changed["entries"][0]["graph_key"] = "forged"
        with self.assertRaisesRegex(ValueError, "SOURCE_DRIFT"):
            validate(self.atlas, self.graphs, changed)

    def test_duplicate_scenario_key_rejected(self):
        changed = copy.deepcopy(self.book)
        changed["entries"][1]["scenario_key"] = changed["entries"][0]["scenario_key"]
        with self.assertRaisesRegex(ValueError, "SCENARIO_KEY_INVALID"):
            validate(self.atlas, self.graphs, changed)

    def test_inflated_relays_and_unbounded_hold_rejected(self):
        changed = copy.deepcopy(self.book)
        changed["entries"][0]["spare_relays"] = 500
        with self.assertRaisesRegex(ValueError, "COUNTER_BOUNDS"):
            validate(self.atlas, self.graphs, changed)
        changed = copy.deepcopy(self.book)
        changed["entries"][0]["hold_ticks"] = 0
        with self.assertRaisesRegex(ValueError, "COUNTER_BOUNDS"):
            validate(self.atlas, self.graphs, changed)

    def test_foreign_fault_class_and_forged_sensor_rejected(self):
        changed = copy.deepcopy(self.book)
        changed["entries"][0]["fault_class"] = "free_points"
        with self.assertRaisesRegex(ValueError, "FAULT_CLASS_INVALID"):
            validate(self.atlas, self.graphs, changed)
        changed = copy.deepcopy(self.book)
        changed["entries"][0]["console"] = "SW_EAST"
        with self.assertRaisesRegex(ValueError, "TARGET_INVALID"):
            validate(self.atlas, self.graphs, changed)


if __name__ == "__main__":
    unittest.main()
