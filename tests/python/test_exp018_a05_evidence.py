"""EXP018 A05: independent original identities and evidence rejection."""
import copy
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
from tools import qualify_exp018_a05 as a05
from tools import qualify_exp015_integration as source

class EXP018A05QualificationTests(unittest.TestCase):
    def test_source_counts_and_non_release_policy(self):
        evidence=a05.sources()
        self.assertEqual((evidence["original_regions"], evidence["original_levels"],
                          evidence["original_task_ids"]),(25,200,1000))
        self.assertFalse(evidence["ready_for_release"])
        self.assertEqual(evidence["actual_all_200_mission_completion"],"NOT_ESTABLISHED")

    def test_missing_host_replay_evidence_fails_closed(self):
        with tempfile.TemporaryDirectory() as directory:
            with patch.object(a05,"EVIDENCE",Path(directory)/"absent.json"):
                with self.assertRaisesRegex(ValueError,"EVIDENCE_MISSING"):
                    a05.post_run()

    def test_forged_replay_counts_do_not_qualify(self):
        with tempfile.TemporaryDirectory() as directory:
            path=Path(directory)/"forged.json"
            path.write_text(json.dumps({"phase":"EXP018_A05","status":"PASS",
                "level_count":200,"source_task_id_count":999}),encoding="utf-8")
            with patch.object(a05,"EVIDENCE",path):
                with self.assertRaisesRegex(ValueError,"CARDINALITY_DRIFT"):
                    a05.post_run()

if __name__=="__main__":
    unittest.main()
