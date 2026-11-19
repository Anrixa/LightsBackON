"""EXP06 independent data gates and mutation-denial regressions."""

from __future__ import annotations

import copy
import json
import unittest

from tools.validate_exp06_encounters import (
    ATLAS_PATH,
    ENCOUNTER_PATH,
    validate,
)


class ExpeditionBespokeSourceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.atlas = json.loads(ATLAS_PATH.read_text(encoding="utf-8"))
        cls.book = json.loads(ENCOUNTER_PATH.read_text(encoding="utf-8"))

    def test_all_200_source_bound_encounters_cover_eight_families_each(self) -> None:
        report = validate(self.atlas, self.book)
        self.assertEqual(report["levels"], 200)
        self.assertEqual(report["unique_encounters"], 200)
        self.assertEqual(len(report["puzzle_families"]), 8)
        self.assertEqual(len(report["hazard_families"]), 8)
        self.assertFalse(report["physical_playability_certified"])

    def test_source_identity_forgery_is_denied(self) -> None:
        book = copy.deepcopy(self.book)
        book["entries"][0]["source_puzzle_identity"] = "invented circuit"
        with self.assertRaisesRegex(ValueError, "UNPINNED_ENCOUNTER"):
            validate(self.atlas, book)

    def test_duplicate_encounter_key_is_denied(self) -> None:
        book = copy.deepcopy(self.book)
        book["entries"][0]["encounter_key"] = book["entries"][1]["encounter_key"]
        with self.assertRaisesRegex(ValueError, "DUPLICATE_OR_INVALID_KEY"):
            validate(self.atlas, book)

    def test_source_incoherent_but_supported_families_are_denied(self) -> None:
        book = copy.deepcopy(self.book)
        book["entries"][0]["puzzle"]["family"] = "fault_trace"
        with self.assertRaisesRegex(ValueError, "UNPINNED_SOURCE_MECHANIC"):
            validate(self.atlas, book)
        book = copy.deepcopy(self.book)
        book["entries"][0]["hazard"]["kind"] = "thermal_spike"
        with self.assertRaisesRegex(ValueError, "UNPINNED_SOURCE_MECHANIC"):
            validate(self.atlas, book)

    def test_unsafe_no_window_schedule_is_denied(self) -> None:
        book = copy.deepcopy(self.book)
        book["entries"][0]["hazard"]["active_ticks"] = book["entries"][0]["hazard"]["period_ticks"]
        with self.assertRaisesRegex(ValueError, "INVALID_PARAMETERS|NO_SAFE_WINDOW"):
            validate(self.atlas, book)

    def test_booleans_and_fractional_ticks_are_denied(self) -> None:
        for bad in (True, 1.5, "25", -1):
            with self.subTest(bad=bad):
                book = copy.deepcopy(self.book)
                book["entries"][0]["puzzle"]["min_gap_ticks"] = bad
                with self.assertRaisesRegex(ValueError, "INVALID_PARAMETERS"):
                    validate(self.atlas, book)

    def test_authoritative_reward_or_health_side_effect_cannot_be_declared_in_book(self) -> None:
        book = copy.deepcopy(self.book)
        book["entries"][0]["reward"] = {"credits": 1000000}
        with self.assertRaisesRegex(ValueError, "UNAUTHORIZED_SIDE_EFFECT"):
            validate(self.atlas, book)


if __name__ == "__main__":
    unittest.main()
