"""Negative source-mutation and evidence-certification tests for EXP015 A15."""
import copy
import unittest

from tools import qualify_exp015_integration as q


class EXP015IntegrationCloseoutTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.atlas, cls.networks = q.load_sources()

    def test_complete_original_graph_and_job_join(self) -> None:
        audited = q.audit_original_regions(self.atlas, self.networks)
        self.assertEqual(audited["regions"], 25)
        self.assertEqual(audited["authored_levels"], 200)
        self.assertEqual(audited["source_task_ids"], 1000)
        self.assertEqual(audited["original_primary_feeders"], 175)
        self.assertEqual(audited["strategy_cases"], 50)

    def test_duplicate_original_task_id_is_refused(self) -> None:
        book = copy.deepcopy(self.networks)
        book["regions"][0]["source_sites"][1]["source_task_ids"][0] = (
            book["regions"][0]["source_sites"][0]["source_task_ids"][0])
        with self.assertRaisesRegex(ValueError, "SOURCE_TASK_DRIFT"):
            q.audit_original_regions(self.atlas, book)

    def test_broken_break_before_make_interlock_is_refused(self) -> None:
        book = copy.deepcopy(self.networks)
        book["regions"][0]["standby_ties"][0]["normally_closed"] = True
        with self.assertRaisesRegex(ValueError, "UNSAFE_STANDBY_DEFAULT"):
            q.audit_original_regions(self.atlas, book)

    def test_primary_feeder_cycle_or_multiple_incoming_is_refused(self) -> None:
        book = copy.deepcopy(self.networks)
        book["regions"][0]["primary_feeders"][0]["to"] = (
            book["regions"][0]["primary_feeders"][1]["to"])
        with self.assertRaisesRegex(ValueError, "MULTIPLE_PRIMARY_FEEDERS"):
            q.audit_original_regions(self.atlas, book)

    def test_foreign_region_site_reference_is_refused(self) -> None:
        book = copy.deepcopy(self.networks)
        book["regions"][0]["strategies"]["critical_first"]["target_site"] = "LV_200"
        with self.assertRaisesRegex(ValueError, "STRATEGY_REFERENCES_FOREIGN_SITE"):
            q.audit_original_regions(self.atlas, book)

    def test_closeout_report_keeps_all_unverified_holds(self) -> None:
        result = q.qualify()
        self.assertFalse(result["ready_for_merge"])
        self.assertFalse(result["ready_for_release"])
        self.assertEqual(result["ci_execution"], "EXACT_HEAD_LINUX_AND_WINDOWS_EXTERNAL")
        self.assertEqual(result["independent_integration_review"], "PENDING")
        self.assertTrue(all(v == "HOLD" for v in result["owner_holds"].values()))


if __name__ == "__main__":
    unittest.main()
