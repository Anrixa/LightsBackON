"""EXP013 A02-A04 mutation and source-bound coverage gates; no physical testing."""
from __future__ import annotations

import copy
import unittest

from tools.validate_exp012_worksites import load_inputs
from tools.validate_exp013_expansions import read_books, validate


class EXP013ExpansionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.atlas, _, cls.orders = load_inputs()
        cls.books = read_books()

    def test_all_loaded_contiguous_extension_ranges_are_audited(self):
        result = validate(self.atlas, self.orders, self.books)
        self.assertEqual(result["exp013_sources"], len(self.books))
        self.assertEqual(result["total_individually_scripted"], 40 + 40 * len(self.books))
        self.assertEqual(result["remaining_uncovered"], 160 - 40 * len(self.books))

    def test_each_site_has_separately_authored_operational_actions(self):
        actions = [action
                   for book in self.books
                   for item in book["entries"]
                   for action in (step["action"] for step in item["routes"]["priority"])]
        self.assertEqual(len(actions), len(set(actions)))
        for book in self.books[1:]:
            for item in book["entries"]:
                self.assertEqual(len(item["routes"]["priority"]), 4)
                self.assertEqual(len(item["routes"]["resilience"]), 4)

    def _deny(self, mutate, expected):
        modified = copy.deepcopy(self.books)
        mutate(modified[1]["entries"][0])
        with self.assertRaisesRegex(ValueError, expected):
            validate(self.atlas, self.orders, modified)

    def test_rejects_source_splice_and_renumbered_tasks(self):
        for key, value in (("level_id", "LV_001"),
                           ("source_puzzle_identity", "FAKE"),
                           ("worksite_encounter_key", "UNSIGNED"),
                           ("source_task_ids", ["JOB_FAKE"])):
            with self.subTest(key=key):
                self._deny(lambda e: e.__setitem__(key, value),
                           "EXP013_EXTENSION_SOURCE_DRIFT_" + key)

    def test_rejects_target_forgery_and_duplicates(self):
        self._deny(lambda e: e["targets"].__setitem__("A", "FOREIGN"),
                   "EXP013_EXTENSION_TARGET_DRIFT")
        self._deny(lambda e: e["station_offsets_cm"].__setitem__("A", [0, 0]),
                   "EXP013_EXTENSION_STATIONS_INVALID")

    def test_rejects_untrusted_clock_and_mechanics(self):
        for key, value, code in (
            ("dwell_ticks", True, "EXP013_EXTENSION_TIMER_INVALID"),
            ("window_ticks", 1.5, "EXP013_EXTENSION_TIMER_INVALID"),
            ("mode", "remote", "EXP013_EXTENSION_MECHANIC_INVALID"),
            ("action", "FORGE NOW", "EXP013_EXTENSION_ACTION_INVALID"),
            ("target", "SC_041_A", "EXP013_EXTENSION_MECHANIC_INVALID"),
        ):
            with self.subTest(key=key):
                self._deny(lambda e: e["routes"]["priority"][0].__setitem__(key, value),
                           code)

    def test_rejects_cosmetic_only_route(self):
        def downgrade(e):
            e["routes"]["resilience"] = [
                {**s, "action": s["action"] + "_reserve"}
                for s in e["routes"]["priority"]]
        self._deny(downgrade, "EXP013_EXTENSION_COSMETIC_STRATEGY")

    def test_both_windows_export_memberships_required(self):
        # Preserve the parent A01 export membership. Remove only the A02
        # extension to exercise the extension-specific fail-closed gate.
        from tools.validate_exp013_expansions import ROOT
        presets = (ROOT / "export_presets.cfg").read_text(encoding="utf-8")
        missing_extension = presets.replace(
            "scenes/expeditions/site_interventions_exp013_a02.json", ""
        )
        self.assertNotEqual(missing_extension, presets)
        with self.assertRaisesRegex(ValueError, "EXP013_EXTENSION_EXPORT_MISSING"):
            validate(self.atlas, self.orders, self.books, presets=missing_extension)


if __name__ == "__main__":
    unittest.main()
