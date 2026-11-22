"""EXP017 A01 structural morphology / source pin mutation probes."""
import copy
import unittest

from tools import validate_exp017_landmarks as q


class EXP017LandmarkTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        import json
        cls.atlas = json.loads(q.ATLAS.read_text(encoding="utf-8"))
        cls.recipes = q.read_recipes()
        cls.profiles = q.parse_profiles(q.SCRIPT.read_text(encoding="utf-8"))

    def test_all_25_structures_have_independent_noncosmetic_geometry(self):
        report = q.audit(self.atlas, self.recipes, self.profiles)
        self.assertEqual(report["distinct_structural_morphologies"], 25)
        self.assertEqual(len(report["structural_families"]), 5)
        self.assertFalse(report["physical_reachability_certified"])

    def test_copied_structural_profile_rejected(self):
        clone = self.profiles.copy()
        clone["REG_02"] = clone["REG_01"]
        with self.assertRaisesRegex(ValueError, "SOURCE_RISK_DRIFT|REUSED_STRUCTURE"):
            q.audit(self.atlas, self.recipes, clone)

    def test_unauthored_hazard_cue_rejected(self):
        changed = self.profiles.copy()
        f, n, h, _ = changed["REG_01"]
        changed["REG_01"] = (f, n, h, "forged")
        with self.assertRaisesRegex(ValueError, "SOURCE_RISK_DRIFT"):
            q.audit(self.atlas, self.recipes, changed)


if __name__ == "__main__":
    unittest.main()
