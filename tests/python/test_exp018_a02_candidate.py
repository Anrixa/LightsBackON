"""EXP018 A02 — cross-track source ancestry and opt-in behavior."""
import unittest
from tools import qualify_exp018_a02 as q

class EXP018A02CandidateTests(unittest.TestCase):
    def test_all_three_tracks_present_and_identity_preserved(self):
        result=q.qualify()
        self.assertEqual((result["region_count"],result["level_count"],result["task_count"]),(25,200,1000))
        self.assertEqual(result["exp016_runtime_modules"],7)
        self.assertEqual(result["exp017_world_modules"],3)
        self.assertFalse(result["ready_for_merge"])
        self.assertFalse(result["ready_for_release"])
        self.assertEqual(result["composite_runtime_state"],"NOT_YET_QUALIFIED_A03_A04")

if __name__=="__main__":
    unittest.main()
