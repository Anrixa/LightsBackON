"""EXP013: exact-source, mutation, dual-route and recovery audit."""
from __future__ import annotations

import copy
import unittest

from tools.validate_exp012_worksites import load_inputs
from tools.validate_exp012_a02_sites import replay, recovery_oracle
from tools.validate_exp013_sites import read_book, validate


class EXP013SourceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.atlas, _, cls.orders = load_inputs()
        cls.book = read_book()

    def test_40_new_sites_and_80_authorized_operating_routes(self) -> None:
        report = validate(self.atlas, self.orders, self.book)
        self.assertEqual(report["new_individually_scripted"], 40)
        self.assertEqual(report["cumulative_individually_scripted"], 80)
        self.assertEqual(report["remaining"], 120)
        self.assertEqual(report["new_steps"], 320)

    def test_exact_source_book_and_both_workable_strategies(self) -> None:
        for entry in self.book["entries"]:
            for route in ("priority", "resilience"):
                with self.subTest(level=entry["level_id"], route=route):
                    self.assertEqual(replay(entry, route)["completed"], 4)
                    self.assertGreater(replay(entry, route)["actions"], 7)
                    for i, step in enumerate(entry["routes"][route]):
                        self.assertLessEqual(recovery_oracle(step["failure"], i), i)

    def test_rejects_spliced_worksite_and_atlas_identity(self) -> None:
        for field, replacement in (
            ("source_task_ids", ["JOB_FORGED"]),
            ("worksite_encounter_key", "STALE_SOURCE"),
            ("source_puzzle_identity", "REPLACED"),
            ("source_risk", "NO_RISK"),
        ):
            with self.subTest(field=field):
                forged = copy.deepcopy(self.book)
                forged["entries"][4][field] = replacement
                with self.assertRaisesRegex(ValueError, "EXP013_SOURCE_DRIFT_" + field):
                    validate(self.atlas, self.orders, forged)

    def test_rejects_forged_locations_geometry_and_stages(self) -> None:
        for field, replacement, code in (
            ("targets", {"A": "EXPLOIT"}, "EXP013_TARGET_INVALID"),
            ("station_offsets_cm", {"A": [0, 0]}, "EXP013_POSITION_INVALID"),
            ("title", self.book["entries"][1]["title"], "EXP013_AUTHORSHIP_INVALID"),
        ):
            forged = copy.deepcopy(self.book)
            forged["entries"][0][field] = replacement
            with self.subTest(field=field), self.assertRaisesRegex(ValueError, code):
                validate(self.atlas, self.orders, forged)
        for field, replacement, code in (
            ("action", "cheat now", "EXP013_ACTION_INVALID"),
            ("target", "SC_001_A", "EXP013_STEP_INVALID"),
            ("dwell_ticks", True, "EXP013_TIMER_INVALID"),
            ("window_ticks", 3.5, "EXP013_TIMER_INVALID"),
            ("mode", "teleport", "EXP013_STEP_INVALID"),
        ):
            forged = copy.deepcopy(self.book)
            forged["entries"][0]["routes"]["priority"][0][field] = replacement
            with self.subTest(field=field), self.assertRaisesRegex(ValueError, code):
                validate(self.atlas, self.orders, forged)

    def test_rejects_cosmetic_only_strategy_and_duplicate_placement(self) -> None:
        forged = copy.deepcopy(self.book)
        forged["entries"][0]["routes"]["resilience"] = [
            {**step, "action": step["action"] + "_reserve"}
            for step in forged["entries"][0]["routes"]["priority"]
        ]
        with self.assertRaisesRegex(ValueError, "EXP013_STRATEGY_NOT_DISTINCT"):
            validate(self.atlas, self.orders, forged)
        forged = copy.deepcopy(self.book)
        forged["entries"][1]["station_offsets_cm"] = forged["entries"][0]["station_offsets_cm"]
        with self.assertRaisesRegex(ValueError, "EXP013_REUSED_STATION_PLAN"):
            validate(self.atlas, self.orders, forged)

    def test_windows_export_membership_is_mandatory(self) -> None:
        with self.assertRaisesRegex(ValueError, "EXP013_EXPORT_MISSING"):
            validate(self.atlas, self.orders, self.book, presets="")


if __name__ == "__main__":
    unittest.main()
