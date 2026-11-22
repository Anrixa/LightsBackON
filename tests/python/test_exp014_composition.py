"""EXP014 A01 mutation and source fidelity tests for honest 200-site diversity."""
import copy
import unittest

from tools.validate_exp014_composition import (
    source_entries, structural_route, validate,
)


class EXP014SourceCompositionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.entries = source_entries()

    def test_complete_catalog_has_measureable_noncosmetic_diversity(self) -> None:
        report = validate(self.entries)
        self.assertTrue(report["ok"])
        self.assertEqual(report["source_interventions"], 200)
        self.assertEqual(report["regions"], 25)
        self.assertGreaterEqual(report["distinct_mechanical_route_pairs"], 112)
        self.assertLessEqual(report["most_reused_mechanical_route_pair"], 16)
        self.assertFalse(report["physical_playability_certified"])

    def test_names_and_timer_shifts_do_not_invent_mechanical_diversity(self) -> None:
        sample = copy.deepcopy(self.entries[0])
        first = (structural_route(sample, "priority"),
                 structural_route(sample, "resilience"))
        for route in ("priority", "resilience"):
            for step in sample["routes"][route]:
                step["action"] = "renamed_" + step["action"]
                step["dwell_ticks"] += 1
                step["window_ticks"] += 1
        after = (structural_route(sample, "priority"),
                 structural_route(sample, "resilience"))
        self.assertEqual(first, after)

    def test_duplicate_topologies_fail_even_with_distinct_level_names(self) -> None:
        tampered = copy.deepcopy(self.entries)
        source = tampered[0]["routes"]
        for item in tampered:
            for route in ("priority", "resilience"):
                for index, old in enumerate(source[route]):
                    target_letter = old["target"][-1]
                    support_letter = old["support_target"][-1]
                    current = item["routes"][route][index]
                    current["mode"] = old["mode"]
                    current["failure"] = old["failure"]
                    current["target"] = item["targets"][target_letter]
                    current["support_target"] = item["targets"][support_letter]
        with self.assertRaisesRegex(ValueError, "VARIETY_REGRESSION|REUSE_REGRESSION"):
            validate(tampered)

    def test_source_swap_or_repeated_strategy_refused(self) -> None:
        tampered = copy.deepcopy(self.entries)
        tampered[40]["level_id"] = "LV_001"
        with self.assertRaisesRegex(ValueError, "EXP014_LEVEL_IDENTITY"):
            validate(tampered)
        tampered = copy.deepcopy(self.entries)
        tampered[5]["routes"]["resilience"] = copy.deepcopy(
            tampered[5]["routes"]["priority"])
        with self.assertRaisesRegex(ValueError, "EXP014_IDENTICAL_ROUTE_TOPOLOGY"):
            validate(tampered)

    def test_unbound_station_or_missing_mechanic_refused(self) -> None:
        source = copy.deepcopy(self.entries[0])
        source["routes"]["priority"][0]["target"] = "INJECTED_PANEL"
        with self.assertRaisesRegex(ValueError, "EXP014_INVALID_OPERATION"):
            structural_route(source, "priority")
        source = copy.deepcopy(self.entries[0])
        source["routes"]["priority"][0]["mode"] = "magic_success"
        with self.assertRaisesRegex(ValueError, "EXP014_INVALID_OPERATION"):
            structural_route(source, "priority")


if __name__ == "__main__":
    unittest.main()
