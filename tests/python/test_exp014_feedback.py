"""EXP014 A04: independently reject source, task and evidence-map drift."""
from __future__ import annotations

import copy
import json
import unittest

from tools.validate_exp014_feedback import (
    ATLAS, CONTINGENCIES, load_profiles, validate,
)


class EXP014EnvironmentalEvidenceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.atlas = json.loads(ATLAS.read_text(encoding="utf-8"))
        cls.contingencies = json.loads(
            CONTINGENCIES.read_text(encoding="utf-8"))
        cls.profiles = load_profiles()

    def test_25_authored_sequences_all_200_sites_1000_tasks(self) -> None:
        summary = validate(self.atlas, self.contingencies, self.profiles)
        self.assertTrue(summary["ok"])
        self.assertEqual(summary["authored_regions"], 25)
        self.assertEqual(summary["environmental_evidence_signals"], 75)
        self.assertEqual(summary["apparatus_families"], 5)
        self.assertEqual(summary["source_pinned_sites"], 200)
        self.assertEqual(summary["original_task_ids_preserved"], 1000)
        self.assertFalse(summary["host_authority_changed"])
        self.assertFalse(summary["physical_playability_certified"])

    def test_duplicate_regional_sequence_and_reused_clue_rejected(self) -> None:
        changed = copy.deepcopy(self.profiles)
        changed["REG_25"] = copy.deepcopy(changed["REG_24"])
        with self.assertRaisesRegex(ValueError, "REUSED_REGIONAL_CLUE"):
            validate(self.atlas, self.contingencies, changed)

    def test_bad_apparatus_and_missing_profile_rejected(self) -> None:
        changed = copy.deepcopy(self.profiles)
        changed["REG_03"]["apparatus"] = "made_up_sensor"
        with self.assertRaisesRegex(ValueError, "UNKNOWN_EVIDENCE_APPARATUS"):
            validate(self.atlas, self.contingencies, changed)
        changed = copy.deepcopy(self.profiles)
        changed.pop("REG_17")
        with self.assertRaisesRegex(ValueError, "REGION_COVERAGE"):
            validate(self.atlas, self.contingencies, changed)

    def test_cross_site_source_and_task_splice_rejected(self) -> None:
        changed = copy.deepcopy(self.contingencies)
        changed["entries"][81]["source_risk"] = "invented flood"
        with self.assertRaisesRegex(ValueError, "CROSS_SOURCE_SPLICE"):
            validate(self.atlas, changed, self.profiles)
        changed = copy.deepcopy(self.contingencies)
        changed["entries"][199]["source_task_ids"][0] = "JOB_001_1"
        with self.assertRaisesRegex(ValueError, "CASE_TASK_DRIFT"):
            validate(self.atlas, changed, self.profiles)

    def test_legacy_atlas_must_remain_immutable(self) -> None:
        changed = copy.deepcopy(self.atlas)
        changed["levels"][79]["tasks"][0]["id"] = "JOB_001_1"
        with self.assertRaisesRegex(ValueError, "ATLAS_TASK_DRIFT"):
            validate(changed, self.contingencies, self.profiles)


if __name__ == "__main__":
    unittest.main()
