"""EXP014 A05: independent source and noncosmetic-mechanics mutation gates."""
from __future__ import annotations

import copy
import json
import unittest

from tools.validate_exp014_approach import (
    ATLAS, CONTINGENCIES, SCRIPT, load_profiles, validate,
)
from tools.validate_exp014_feedback import load_profiles as load_a04


class EXP014ApproachTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.atlas = json.loads(ATLAS.read_text(encoding="utf-8"))
        cls.cases = json.loads(CONTINGENCIES.read_text(encoding="utf-8"))
        cls.profiles = load_profiles()
        cls.apparatus = load_a04()

    def test_25_behavioral_signatures_200_sites_1000_tasks(self) -> None:
        report = validate(self.atlas, self.cases, self.profiles, self.apparatus)
        self.assertTrue(report["ok"])
        self.assertEqual(report["regional_behavioral_signatures"], 25)
        self.assertEqual(report["evidence_protocol_families"], 5)
        self.assertEqual(report["host_fact_guards"], 4)
        self.assertEqual(report["source_pinned_sites"], 200)
        self.assertEqual(report["source_pinned_original_tasks"], 1000)
        self.assertEqual(report["host_route_replay_cases"], 400)
        self.assertFalse(report["physical_playability_certified"])

    def test_signage_and_timer_free_duplicate_structure_rejected(self) -> None:
        tampered = copy.deepcopy(self.profiles)
        # Even with a different clock, this duplicates the actual behavior.
        tampered["REG_25"] = {**tampered["REG_01"], "window": 16}
        with self.assertRaisesRegex(ValueError, "MECHANICAL_SIGNATURE_REUSED"):
            validate(self.atlas, self.cases, tampered, self.apparatus)

    def test_hazard_domain_or_witness_branch_splice_rejected(self) -> None:
        tampered = copy.deepcopy(self.profiles)
        tampered["REG_01"]["guard"] = "faults_solved"
        with self.assertRaisesRegex(ValueError, "HAZARD_PROOF_MISMATCH"):
            validate(self.atlas, self.cases, tampered, self.apparatus)
        tampered = copy.deepcopy(self.profiles)
        tampered["REG_18"]["first"] = tampered["REG_18"]["second"]
        with self.assertRaisesRegex(ValueError, "STATION_ROLE"):
            validate(self.atlas, self.cases, tampered, self.apparatus)

    def test_source_risk_task_and_station_splices_rejected(self) -> None:
        tampered = copy.deepcopy(self.cases)
        tampered["entries"][100]["source_risk"] = "invented water hazard"
        with self.assertRaisesRegex(ValueError, "CROSS_SOURCE_DRIFT"):
            validate(self.atlas, tampered, self.profiles, self.apparatus)
        tampered = copy.deepcopy(self.cases)
        tampered["entries"][199]["source_task_ids"][0] = "JOB_001_1"
        with self.assertRaisesRegex(ValueError, "TASK_DRIFT"):
            validate(self.atlas, tampered, self.profiles, self.apparatus)
        tampered = copy.deepcopy(self.cases)
        tampered["entries"][14]["targets"]["B"] = "SC_014_B"
        with self.assertRaisesRegex(ValueError, "TARGET_DRIFT"):
            validate(self.atlas, tampered, self.profiles, self.apparatus)

    def test_source_literal_parser_rejects_removed_region(self) -> None:
        script = SCRIPT.read_text(encoding="utf-8")
        line = next(x for x in script.splitlines()
                    if x.strip().startswith('"REG_24":'))
        with self.assertRaisesRegex(ValueError, "PROFILE_COUNT"):
            load_profiles(script.replace(line + "\n", ""))

    def test_legacy_atlas_tasks_must_remain_immutable(self) -> None:
        tampered = copy.deepcopy(self.atlas)
        tampered["levels"][40]["tasks"][2]["id"] = "JOB_001_3"
        with self.assertRaisesRegex(ValueError, "TASK_DRIFT"):
            validate(tampered, self.cases, self.profiles, self.apparatus)


if __name__ == "__main__":
    unittest.main()
