"""EXP014 A07 independent environmental-hazard source/host mutation gates."""
from __future__ import annotations

import copy
import json
import unittest

from tools.validate_exp014_hazards import (
    ATLAS, CONTINGENCIES, HOST, SCRIPT, STAGE,
    load_a04, load_a05, parse_a06, parse_script, validate,
)


class EXP014HazardsTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.atlas = json.loads(ATLAS.read_text(encoding="utf-8"))
        cls.contingencies = json.loads(CONTINGENCIES.read_text(encoding="utf-8"))
        cls.a04 = load_a04()
        cls.a05 = load_a05()
        cls.a06_classes, cls.a06_graphs = parse_a06()
        cls.profiles = parse_script()
        cls.host = HOST.read_text(encoding="utf-8")
        cls.stage = STAGE.read_text(encoding="utf-8")
        cls.module = SCRIPT.read_text(encoding="utf-8")

    def audit(self, **kwargs: object) -> dict:
        args = dict(
            atlas=self.atlas, contingencies=self.contingencies,
            a05=self.a05, a04=self.a04, a06_classes=self.a06_classes,
            a06_graphs=self.a06_graphs, profiles=self.profiles,
            host=self.host, stage=self.stage, module=self.module,
        )
        args.update(kwargs)
        return validate(**args)

    def test_25_regions_200_sites_1000_tasks_and_400_host_routes(self) -> None:
        report = self.audit()
        self.assertTrue(report["ok"])
        self.assertEqual(report["regional_source_profiles"], 25)
        self.assertEqual(report["site_cases"], 200)
        self.assertEqual(report["unaltered_original_tasks"], 1000)
        self.assertEqual(report["hazard_mechanism_families"], 5)
        self.assertEqual(report["source_host_control_replays"], 400)
        self.assertFalse(report["physical_playability_certified"])

    def test_cosmetic_action_and_timer_changes_cannot_duplicate_risk_mechanics(self) -> None:
        forged = copy.deepcopy(self.profiles)
        forged["weather"] = copy.deepcopy(forged["depth"])
        forged["weather"]["pressure_period"] = 37
        forged["weather"]["settle"] = 6
        for entry in forged["weather"]["sequence"]:
            entry["action"] = "cosmetic_" + entry["action"]
        with self.assertRaisesRegex(ValueError, "COSMETIC_GRAPH_REUSE"):
            self.audit(profiles=forged)

    def test_invalid_station_guard_gap_and_stage_count_fail_closed(self) -> None:
        forged = copy.deepcopy(self.profiles)
        forged["structure"]["sequence"][1]["station"] = "Z"
        with self.assertRaisesRegex(ValueError, "PROOF_SOURCE_GUARD"):
            self.audit(profiles=forged)
        forged = copy.deepcopy(self.profiles)
        forged["conductivity"]["sequence"][1]["guard"] = "client_success"
        with self.assertRaisesRegex(ValueError, "PROOF_SOURCE_GUARD"):
            self.audit(profiles=forged)
        forged = copy.deepcopy(self.profiles)
        forged["mechanical"]["sequence"][1]["gap"] = 0
        with self.assertRaisesRegex(ValueError, "UNSAFE_WITNESS_GAP"):
            self.audit(profiles=forged)
        forged = copy.deepcopy(self.profiles)
        forged["weather"]["sequence"] = [forged["weather"]["sequence"][0]]
        with self.assertRaisesRegex(ValueError, "MECHANICAL_SEQUENCE"):
            self.audit(profiles=forged)

    def test_source_risk_and_immutable_original_task_pins_cannot_be_swapped(self) -> None:
        mutated = dict(self.a06_classes)
        mutated["REG_01"] = "weather"
        with self.assertRaisesRegex(ValueError, "RISK_SOURCE_MISMATCH"):
            self.audit(a06_classes=mutated)
        mutated = copy.deepcopy(self.contingencies)
        mutated["entries"][199]["source_task_ids"][1] = "JOB_001_2"
        with self.assertRaisesRegex(ValueError, "EXP014_A05_TASK_DRIFT"):
            self.audit(contingencies=mutated)

    def test_missing_authoritative_gates_and_scene_binding_are_detected(self) -> None:
        tampered = self.host.replace("EXP014_A07_ENVIRONMENT_UNVERIFIED", "BYPASS")
        with self.assertRaisesRegex(ValueError, "HOST_AUTHORITY_OR_EXTRACTION_BYPASS"):
            self.audit(host=tampered)
        tampered = self.host.replace("site_hazards.can_operate()", "true")
        with self.assertRaisesRegex(ValueError, "HOST_AUTHORITY_OR_EXTRACTION_BYPASS"):
            self.audit(host=tampered)
        tampered = self.stage.replace("_activate_hazard_target()", "_wrong_controller()")
        with self.assertRaisesRegex(ValueError, "LIVE_HAZARD_INTERFACE_MISSING"):
            self.audit(stage=tampered)

    def test_unavailable_risk_or_duplicate_profile_is_not_silently_accepted(self) -> None:
        source = self.module.replace('"weather": {', '"depth": {', 1)
        with self.assertRaisesRegex(ValueError, "PROFILE_COUNT"):
            parse_script(source)
        source = self.module.replace('"guard":"balancing_solved"', '"guard":"client_yes"', 1)
        forged = parse_script(source)
        with self.assertRaisesRegex(ValueError, "PROFILE_ROLE|PROOF_SOURCE_GUARD"):
            self.audit(profiles=forged)


if __name__ == "__main__":
    unittest.main()
