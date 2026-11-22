"""EXP016 A02 mutations: source drift, unearned DAG edges, mechanical clones."""
import copy
import unittest

from validate_exp016_casework import audit, _load


class CaseworkAuditTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.atlas = _load("atlas.json")
        cls.source = _load("site_investigations_exp014_a08.json")
        cls.cases = _load("exp016_casework_a02.json")

    def test_50_cases_and_100_routes(self):
        result = audit(self.atlas, self.source, self.cases)
        self.assertEqual(result["cases"], 50)
        self.assertEqual(result["routes"], 100)

    def test_forged_task_pin_fails(self):
        altered = copy.deepcopy(self.cases)
        altered["entries"][4]["source_task_ids"][0] = "JOB_900_1"
        with self.assertRaisesRegex(ValueError, "SOURCE_DRIFT"):
            audit(self.atlas, self.source, altered)

    def test_foreign_dependency_fails(self):
        altered = copy.deepcopy(self.cases)
        altered["entries"][4]["routes"]["forensic"]["steps"][1]["requires"] = ["BAD"]
        with self.assertRaisesRegex(ValueError, "DAG"):
            audit(self.atlas, self.source, altered)

    def test_mechanical_clone_detected(self):
        altered = copy.deepcopy(self.cases)
        altered["entries"][1]["routes"] = copy.deepcopy(altered["entries"][0]["routes"])
        with self.assertRaisesRegex(ValueError, "MECHANICAL_CLONES"):
            audit(self.atlas, self.source, altered)


if __name__ == "__main__":
    unittest.main()
