"""EXP014 A06: source, risk mechanism and host authority regression gates."""
from __future__ import annotations

import copy
import json
import unittest

from tools.validate_exp014_outcomes import (
    ATLAS, CONTINGENCIES, SCRIPT, HOST, STAGE,
    load_a04, load_a05, parse_script, validate,
)


class EXP014OutcomesTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.atlas = json.loads(ATLAS.read_text(encoding="utf-8"))
        cls.cases = json.loads(CONTINGENCIES.read_text(encoding="utf-8"))
        cls.a04 = load_a04()
        cls.a05 = load_a05()
        cls.classes, cls.graphs = parse_script()
        cls.host = HOST.read_text(encoding="utf-8")
        cls.stage = STAGE.read_text(encoding="utf-8")

    def check(self, **updates: object) -> dict:
        values = {
            "atlas": self.atlas, "contingencies": self.cases,
            "a05": self.a05, "a04": self.a04, "classes": self.classes,
            "graphs": self.graphs, "host": self.host, "stage": self.stage,
        }
        values.update(updates)
        return validate(**values)

    def test_all_25_regions_200_sites_1000_original_tasks_400_plans(self) -> None:
        result = self.check()
        self.assertTrue(result["ok"])
        self.assertEqual(result["regions"], 25)
        self.assertEqual(result["risk_graph_families"], 5)
        self.assertEqual(result["noncosmetic_evidence_graphs"], 5)
        self.assertEqual(result["source_pinned_sites"], 200)
        self.assertEqual(result["immutable_original_tasks"], 1000)
        self.assertEqual(result["planned_branch_replays"], 400)
        self.assertFalse(result["physical_playability_certified"])
        self.assertFalse(result["production_rewards_approved"])

    def test_risk_class_cannot_be_recolored_into_wrong_region(self) -> None:
        tampered = dict(self.classes)
        tampered["REG_01"] = "weather"
        with self.assertRaisesRegex(ValueError, "RISK_ARTIFACT_DRIFT"):
            self.check(classes=tampered)

    def test_names_and_timers_do_not_count_as_distinct_host_mechanics(self) -> None:
        tampered = copy.deepcopy(self.graphs)
        tampered["weather"] = copy.deepcopy(tampered["depth"])
        for step in tampered["weather"]:
            step["action"] = "decorative_" + step["action"]
            step["gap"] = 2 if step["gap"] else 0
        with self.assertRaisesRegex(ValueError, "MECHANICAL_GRAPH_COLLISION"):
            self.check(graphs=tampered)

    def test_fake_station_unsafe_guard_or_clock_are_rejected(self) -> None:
        broken = copy.deepcopy(self.graphs)
        broken["mechanical"][1]["station"] = "X"
        with self.assertRaisesRegex(ValueError, "AUDIT_ROLE_OR_GUARD"):
            self.check(graphs=broken)
        broken = copy.deepcopy(self.graphs)
        broken["depth"][1]["guard"] = "client_claimed_success"
        with self.assertRaisesRegex(ValueError, "AUDIT_ROLE_OR_GUARD"):
            self.check(graphs=broken)
        broken = copy.deepcopy(self.graphs)
        broken["weather"][2]["gap"] = 0
        with self.assertRaisesRegex(ValueError, "AUDIT_GAP"):
            self.check(graphs=broken)

    def test_authoritative_extraction_and_contingency_bridge_are_required(self) -> None:
        missing_gate = self.host.replace("EXP014_A06_OUTCOMES_INCOMPLETE", "BYPASS", 1)
        with self.assertRaisesRegex(ValueError, "HOST_AUTHORITY_OR_EXTRACTION_BYPASS"):
            self.check(host=missing_gate)
        missing_bridge = self.host.replace(
            "site_outcomes.operate(entity, action, _outcome_facts())", "{}", 1)
        with self.assertRaisesRegex(ValueError, "HOST_AUTHORITY_OR_EXTRACTION_BYPASS"):
            self.check(host=missing_bridge)

    def test_source_task_and_target_mutations_fail_closed(self) -> None:
        tampered = copy.deepcopy(self.cases)
        tampered["entries"][199]["source_task_ids"][0] = "JOB_001_1"
        with self.assertRaisesRegex(ValueError, "EXP014_A05_TASK_DRIFT"):
            self.check(contingencies=tampered)
        tampered = copy.deepcopy(self.cases)
        tampered["entries"][10]["targets"]["A"] = "SC_010_A"
        with self.assertRaisesRegex(ValueError, "EXP014_A05_TARGET_DRIFT"):
            self.check(contingencies=tampered)

    def test_duplicate_region_source_parse_rejected(self) -> None:
        source = SCRIPT.read_text(encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "REGIONAL_CLASS_COUNT"):
            parse_script(source.replace('"REG_25":"depth"', '"REG_01":"depth"'))


if __name__ == "__main__":
    unittest.main()
