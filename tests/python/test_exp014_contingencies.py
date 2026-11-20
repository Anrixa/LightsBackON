"""EXP014 A02: full-source, mutation, noncosmetic and host-timer checks."""
from __future__ import annotations

import copy
import unittest

from tools.validate_exp012_worksites import load_inputs
from tools.validate_exp014_composition import source_entries
from tools.validate_exp014_contingencies import (
    read_book, validate, mechanic_signature, replay_oracle,
    next_recovery_index,
)


class EXP014ContingencySourceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.atlas, _, _ = load_inputs()
        cls.original = source_entries()
        cls.book = read_book()

    def test_complete_200_level_source_and_noncosmetic_gate(self) -> None:
        result = validate(self.atlas, self.original, self.book)
        self.assertTrue(result["ok"])
        self.assertEqual(result["routes"], 400)
        self.assertEqual(result["contingency_steps"], 1200)
        self.assertEqual(result["minimal_operate_actions"], 4800)
        self.assertGreaterEqual(result["distinct_mechanical_route_pairs"], 150)
        self.assertLessEqual(result["maximum_reused_structure"], 8)
        self.assertFalse(result["physical_playability_certified"])

    def test_all_routes_have_finite_host_only_positive_replays(self) -> None:
        for entry in self.book["entries"]:
            for route in ("priority", "resilience"):
                with self.subTest(entry=entry["level_id"], route=route):
                    done = replay_oracle(entry, route)
                    self.assertTrue(done["complete"])
                    self.assertEqual(done["steps"], 3)
                    self.assertEqual(done["actions"], 12)
                    self.assertGreaterEqual(done["host_ticks"], 30)

    def test_action_renaming_and_timer_tweaks_cannot_mint_new_mechanics(self) -> None:
        entry = copy.deepcopy(self.book["entries"][25])
        before = tuple(mechanic_signature(entry, route)
                       for route in ("priority", "resilience"))
        for route in ("priority", "resilience"):
            for step in entry["routes"][route]:
                step["action"] += "_cosmetic"
                step["dwell_ticks"] += 1
                step["window_ticks"] += 1
        after = tuple(mechanic_signature(entry, route)
                      for route in ("priority", "resilience"))
        self.assertEqual(before, after)

    def test_source_task_splice_and_cross_site_station_rejected(self) -> None:
        tampered = copy.deepcopy(self.book)
        tampered["entries"][50]["source_task_ids"][0] = "FORGED_TASK"
        with self.assertRaisesRegex(ValueError, "SOURCE_DRIFT|TASK_ID_DRIFT"):
            validate(self.atlas, self.original, tampered)
        tampered = copy.deepcopy(self.book)
        tampered["entries"][75]["routes"]["priority"][0]["target"] = "SC_999_A"
        with self.assertRaisesRegex(ValueError, "FORGED_STATION"):
            validate(self.atlas, self.original, tampered)

    def test_type_confusion_and_unbounded_clock_rejected(self) -> None:
        for value in (True, "10", -2, 100000, 2.5):
            with self.subTest(value=value):
                tampered = copy.deepcopy(self.book)
                tampered["entries"][0]["routes"]["priority"][0]["dwell_ticks"] = value
                with self.assertRaisesRegex(ValueError, "UNSAFE_CLOCK"):
                    validate(self.atlas, self.original, tampered)

    def test_no_purely_cosmetic_200_level_claim(self) -> None:
        # A renamed action cannot mask a mechanically repeated shared graph.
        tampered = copy.deepcopy(self.book)
        reference = tampered["entries"][0]["routes"]
        for entry in tampered["entries"]:
            for route in ("priority", "resilience"):
                for idx, step in enumerate(entry["routes"][route]):
                    original = reference[route][idx]
                    step["mode"] = original["mode"]
                    step["failure"] = original["failure"]
                    step["guard"] = original["guard"]
                    for key in ("target", "support", "witness"):
                        step[key] = entry["targets"][original[key][-1]]
        with self.assertRaisesRegex(ValueError, "NONCOSMETIC_DIVERSITY_GATE"):
            validate(self.atlas, self.original, tampered)

    def test_recovery_backtrack_step_and_restart_are_bounded(self) -> None:
        for index in range(3):
            self.assertEqual(next_recovery_index("step", index), index)
            self.assertEqual(next_recovery_index("backtrack", index), max(0, index - 1))
            self.assertEqual(next_recovery_index("restart", index), 0)
        with self.assertRaisesRegex(ValueError, "RECOVERY_SCOPE"):
            next_recovery_index("forged_scope", 2)


if __name__ == "__main__":
    unittest.main()
