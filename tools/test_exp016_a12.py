"""EXP016 A12 consolidated source gates and 200 original job IDs."""
import copy
import unittest
from qualify_exp016_a12 import qualify,read

class EXP016A12QualificationTests(unittest.TestCase):
    def test_consolidated_200_1000_400(self):
        result=qualify()
        self.assertEqual(result["levels"],200)
        self.assertEqual(result["immutable_original_job_ids"],1000)
        self.assertEqual(result["advanced_case_routes"],400)
        self.assertFalse(result["promotion_allowed"])

    def test_original_task_unique_source(self):
        atlas=read("atlas.json")
        jobs=[task["id"] for level in atlas["levels"] for task in level["tasks"]]
        self.assertEqual(len(jobs),len(set(jobs)))
        self.assertEqual(jobs[0],"JOB_001_1")
        self.assertEqual(jobs[-1],"JOB_200_5")

    def test_qualification_records_all_physical_and_release_holds(self):
        report=qualify()
        self.assertIn("release promotion",report["outstanding_holds"])
        self.assertIn("physical reachability / line of sight",report["outstanding_holds"])
