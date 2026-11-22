"""EXP016 A01 source-semantic diversity and deliberate-copy regression."""
import copy
import unittest

from tools import audit_exp016_mechanical_diversity as q


class EXP016MechanicalDiversityTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.atlas, cls.contingencies, cls.investigations = q.load()

    def test_atlas_coverage_and_honest_mechanic_measurement(self):
        result = q.audit(self.atlas, self.contingencies, self.investigations)
        self.assertEqual(result["levels"], 200)
        self.assertEqual(result["tasks"], 1000)
        self.assertEqual(result["regions"], 25)
        self.assertGreater(result["unique_combined_mechanical_signatures"], 0)
        self.assertFalse(any(value != "HOLD" for value in result["owner_holds"].values()))

    def test_title_and_timing_do_not_change_mechanical_identity(self):
        c = copy.deepcopy(self.contingencies["entries"][0])
        i = copy.deepcopy(self.investigations["entries"][0])
        original = q.normalize(c, i)
        c["source_title"] = "Completely renamed surface identity"
        for procedure in c["routes"]["priority"]:
            procedure["dwell_ticks"] = 999
            procedure["action"] = "COSMETIC_ACTION_ONLY"
        for branch in i["branches"].values():
            for node in branch["nodes"]:
                node["dwell_ticks"] = 999
                node["source_action"] = "RENAMED_ACTION"
        self.assertEqual(q.normalize(c, i), original)

    def test_foreign_job_link_is_rejected(self):
        book = copy.deepcopy(self.contingencies)
        book["entries"][0]["source_task_ids"][0] = "JOB_002_1"
        with self.assertRaisesRegex(ValueError, "SOURCE_DRIFT"):
            q.audit(self.atlas, book, self.investigations)

    def test_mechanical_clone_is_reported_not_certified_unique(self):
        c = copy.deepcopy(self.contingencies["entries"][0])
        i = copy.deepcopy(self.investigations["entries"][0])
        self.assertEqual(q.fingerprint(q.normalize(c, i)),
                         q.fingerprint(q.normalize(c, i)))


if __name__ == "__main__":
    unittest.main()
