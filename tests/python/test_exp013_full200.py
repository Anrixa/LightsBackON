"""Final EXP013 source identity gate: exactly 200 locations and 1000 tasks."""
from __future__ import annotations

import copy
import unittest

from tools.validate_exp012_worksites import load_inputs
from tools.validate_exp012_a02_sites import read_book as read_original_a02
from tools.validate_exp013_expansions import read_books
from tools.validate_exp013_completion import validate


class EXP013FullCatalogTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.atlas, _, cls.orders = load_inputs()
        cls.original = read_original_a02()
        cls.books = read_books()

    def test_all_200_source_bound_sites_1000_tasks_and_400_routes(self):
        report = validate(self.atlas, self.orders, self.original, self.books)
        self.assertEqual(report["source_bound_locations"], 200)
        self.assertEqual(report["regions"], 25)
        self.assertEqual(report["original_mission_task_ids"], 1000)
        self.assertEqual(report["site_control_targets"], 600)
        self.assertEqual(report["distinct_priority_actions"], 800)
        self.assertEqual(report["routes"], 400)
        self.assertEqual(report["steps"], 1600)
        self.assertFalse(report["physical_playability_certified"])
        self.assertFalse(report["release_certified"])

    def test_missing_final_book_is_a_hard_hold(self):
        with self.assertRaisesRegex(ValueError, "EXP013_FINAL_MISSING_TRANCHE"):
            validate(self.atlas, self.orders, self.original, self.books[:-1])

    def test_original_task_binding_cannot_be_forged(self):
        forged = copy.deepcopy(self.books)
        forged[3]["entries"][39]["source_task_ids"] = ["JOB_200_1"]
        with self.assertRaisesRegex(ValueError, "EXP013_EXTENSION_SOURCE_DRIFT"):
            validate(self.atlas, self.orders, self.original, forged)

    def test_final_location_and_target_cannot_be_duplicated(self):
        forged = copy.deepcopy(self.books)
        forged[3]["entries"][39]["targets"] = forged[3]["entries"][38]["targets"]
        with self.assertRaisesRegex(ValueError, "EXP013_EXTENSION_TARGET_DRIFT"):
            validate(self.atlas, self.orders, self.original, forged)


if __name__ == "__main__":
    unittest.main()
