"""EXP012 A02 independent source and mutation regression gates (no playability)."""
from __future__ import annotations

import copy
import unittest

from tools.validate_exp012_worksites import load_inputs
from tools.validate_exp012_a02_sites import read_book, recovery_oracle, replay, validate


class SiteInterventionA02Tests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.atlas, _, cls.a01 = load_inputs()
        cls.book = read_book()

    def test_40_bespoke_sites_80_routes_320_scripted_steps(self) -> None:
        result = validate(self.atlas, self.a01, self.book)
        self.assertEqual(result["individually_scripted_locations"], 40)
        self.assertEqual(result["not_yet_authored"], 160)
        self.assertEqual(result["strategies"], 80)
        self.assertEqual(result["host_action_steps"], 320)
        self.assertEqual(result["source_targets"], 120)
        self.assertEqual(result["mechanic_modes"], 5)

    def test_two_complete_authorized_route_oracles_per_location(self) -> None:
        for entry in self.book["entries"]:
            for route in ("priority", "resilience"):
                with self.subTest(site=entry["level_id"], route=route):
                    result = replay(entry, route)
                    self.assertEqual(result["completed"], 4)
                    self.assertGreaterEqual(result["actions"], 8)
                    self.assertGreater(result["host_ticks"], 0)

    def test_each_fault_scope_is_recoverable_without_permanent_deadlock(self) -> None:
        for entry in self.book["entries"]:
            for route in ("priority", "resilience"):
                for i, step in enumerate(entry["routes"][route]):
                    with self.subTest(site=entry["level_id"], step=i, route=route):
                        target = recovery_oracle(step["failure"], i)
                        self.assertLessEqual(target, i)
                        self.assertGreaterEqual(target, 0)

    def _mutation(self, key: str, fake: object, code: str) -> None:
        source = copy.deepcopy(self.book)
        source["entries"][0][key] = fake
        with self.assertRaisesRegex(ValueError, code):
            validate(self.atlas, self.a01, source)

    def test_spliced_source_and_mismatched_worksite_pins_denied(self) -> None:
        for field, bogus in (
            ("location_id", "LOC_200"),
            ("source_puzzle_identity", "injected_source"),
            ("source_task_ids", ["JOB_999_1"]),
            ("worksite_encounter_key", "SPOOFED"),
            ("source_risk", "no_hazard"),
        ):
            with self.subTest(field=field):
                self._mutation(field, bogus, "EXP012A02_SOURCE_DRIFT_" + field)

    def test_fabricated_targets_and_duplicated_intervention_title_denied(self) -> None:
        self._mutation("targets", {"A": "SC_NEW_A"}, "EXP012A02_SOURCE_DRIFT_targets")
        altered = copy.deepcopy(self.book)
        altered["entries"][1]["title"] = altered["entries"][0]["title"]
        with self.assertRaisesRegex(ValueError, "EXP012A02_AUTHORSHIP_INVALID"):
            validate(self.atlas, self.a01, altered)

    def test_invalid_time_and_wired_client_data_denied(self) -> None:
        for key, value, expected in (
            ("dwell_ticks", True, "EXP012A02_TIMER_INVALID"),
            ("window_ticks", 1.5, "EXP012A02_TIMER_INVALID"),
            ("mode", "magic", "EXP012A02_MECHANIC_INVALID"),
            ("target", "FAKE_CLIENT_TARGET", "EXP012A02_MECHANIC_INVALID"),
            ("action", "SIGN NOW!", "EXP012A02_ACTION_INVALID"),
        ):
            with self.subTest(key=key):
                altered = copy.deepcopy(self.book)
                altered["entries"][0]["routes"]["priority"][0][key] = value
                with self.assertRaisesRegex(ValueError, expected):
                    validate(self.atlas, self.a01, altered)

    def test_strategy_must_really_reorder_operating_steps(self) -> None:
        altered = copy.deepcopy(self.book)
        target = altered["entries"][0]["routes"]
        target["resilience"] = [
            {**step, "action": step["action"] + "_reserve"}
            for step in target["priority"]
        ]
        with self.assertRaisesRegex(ValueError, "EXP012A02_STRATEGY_NOT_DISTINCT"):
            validate(self.atlas, self.a01, altered)

    def test_no_missing_windows_export_membership(self) -> None:
        with self.assertRaisesRegex(ValueError, "EXP012A02_EXPORT_MISSING"):
            validate(self.atlas, self.a01, self.book, presets="")


if __name__ == "__main__":
    unittest.main()
