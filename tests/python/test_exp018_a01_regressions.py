"""Mutation and regression source qualification for EXP018 A01."""
import copy
import unittest

from tools import qualify_exp015_integration as a15
from tools import qualify_exp018_a01 as exp


class EXP018A01Tests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.atlas, cls.networks = a15.load_sources()

    def test_exact_regression_methods_and_ordered_hash_baseline(self):
        self.assertEqual(exp.verify_regressions()["source_assertions"], "PASS")

    def test_regional_tree_validates_without_side_effects(self):
        atlas = copy.deepcopy(self.atlas)
        networks = copy.deepcopy(self.networks)
        before = copy.deepcopy((atlas, networks))
        result = a15.audit_original_regions(atlas, networks)
        self.assertEqual(result["source_task_ids"], 1000)
        self.assertEqual((atlas, networks), before)

    def test_mismatched_original_tasks_fail_closed(self):
        regions = copy.deepcopy(self.networks)
        regions["regions"][0]["source_sites"][0]["source_task_ids"][0] = "UNTRUSTED_TASK"
        with self.assertRaisesRegex(ValueError, "SOURCE_TASK_DRIFT"):
            a15.audit_original_regions(self.atlas, regions)

    def test_standby_interlock_fails_closed(self):
        regions = copy.deepcopy(self.networks)
        regions["regions"][0]["standby_ties"][0]["normally_closed"] = True
        with self.assertRaisesRegex(ValueError, "UNSAFE_STANDBY_DEFAULT"):
            a15.audit_original_regions(self.atlas, regions)

    def test_qualifier_never_claims_ci_or_release(self):
        result = exp.qualify()
        self.assertFalse(result["ready_for_merge"])
        self.assertFalse(result["ready_for_release"])
        self.assertEqual(result["linux_windows_ci"], "EXACT_HEAD_EXTERNAL_RESULTS_REQUIRED")


if __name__ == "__main__":
    unittest.main()
