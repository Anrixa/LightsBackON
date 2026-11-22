"""EXP014 A10.1 independent cross-system mutation and reachability probes.

Every test uses source-only snapshots. No real navigation, player, network,
GPU, physical device, production save, reward or release claim is made.
"""
from __future__ import annotations

import copy
import unittest

from tools.validate_exp014_a10 import audit, read_sources
from tools.validate_exp014_outcomes import parse_script as parse_risks


class EXP014A10SourceOracleTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.pristine = read_sources()
        cls.risk_classes, _ = parse_risks()

    def check(self, **changes: dict) -> dict:
        sources = dict(self.pristine)
        sources.update(changes)
        return audit(**sources, risk_classes=self.risk_classes)

    def test_full_25_regions_200_levels_1000_jobs_50_routes(self) -> None:
        result = self.check()
        self.assertTrue(result["ok"])
        self.assertEqual(result["regions"], 25)
        self.assertEqual(result["locations"], 200)
        self.assertEqual(result["levels"], 200)
        self.assertEqual(result["immutable_task_ids"], 1000)
        self.assertEqual(result["original_lore_ids"], 200)
        self.assertEqual(result["distinct_mechanical_source_fingerprints"], 200)
        self.assertEqual(result["distinct_unlabeled_regional_networks"], 25)
        self.assertEqual(result["distinct_investigation_source_graphs"],
                         {"forensic": 200, "field": 200})
        self.assertEqual(result["cross_system_campaign_branch_scenarios"], 50)
        self.assertEqual(result["branch_dispatch_source_visits"], 300)
        self.assertTrue(result["all_branch_scenarios_reach_finale"])
        self.assertFalse(result["physical_playability_certified"])
        self.assertFalse(result["hardware_steam_release_certified"])
        self.assertEqual(len(result["source_fingerprint_sha256"]), 64)
        for region in result["regions_evidence"]:
            self.assertEqual(len(region["branch_scenarios"]), 2)
            self.assertEqual({x["mode"] for x in region["branch_scenarios"]},
                             {"critical_first", "resilience_first"})
            for branch in region["branch_scenarios"]:
                self.assertEqual(len(branch["sites"]), 6)
                self.assertTrue(branch["finale_restored"])

    def test_deleted_or_duplicate_site_and_orphan_regional_source_fail(self) -> None:
        tampered = copy.deepcopy(self.pristine["atlas"])
        tampered["levels"].pop()
        with self.assertRaisesRegex(ValueError, "CANONICAL_COVERAGE"):
            self.check(atlas=tampered)
        tampered = copy.deepcopy(self.pristine["networks"])
        tampered["regions"][3]["source_sites"][7] = copy.deepcopy(
            tampered["regions"][3]["source_sites"][6])
        with self.assertRaisesRegex(ValueError, "DUPLICATE_REGIONAL_SITE"):
            self.check(networks=tampered)

    def test_immutable_task_join_and_forged_lore_fail(self) -> None:
        tampered = copy.deepcopy(self.pristine["investigations"])
        tampered["entries"][133]["source_task_ids"][4] = "JOB_001_5"
        with self.assertRaisesRegex(ValueError, "IMMUTABLE_TASK_CROSS_LINK"):
            self.check(investigations=tampered)
        tampered = copy.deepcopy(self.pristine["atlas"])
        tampered["levels"][155]["collectible"]["effect"] = "CREDITS_100000"
        with self.assertRaisesRegex(ValueError, "ORIGINAL_LORE_OR_REWARD_DRIFT"):
            self.check(atlas=tampered)

    def test_optional_task_cannot_be_promoted_to_required(self) -> None:
        tampered = copy.deepcopy(self.pristine["atlas"])
        tampered["levels"][44]["tasks"][3]["required"] = True
        with self.assertRaisesRegex(ValueError, "TASK_AUTHORITY_OR_OPTIONALITY"):
            self.check(atlas=tampered)

    def test_cross_system_contingency_and_risk_splice_fail(self) -> None:
        tampered = copy.deepcopy(self.pristine["contingencies"])
        tampered["entries"][144]["source_puzzle_identity"] = "fake"
        with self.assertRaisesRegex(ValueError, "MECHANICAL_SOURCE_SPLICE"):
            self.check(contingencies=tampered)
        tampered = copy.deepcopy(self.pristine["investigations"])
        tampered["entries"][24]["risk_class"] = "weather"
        with self.assertRaisesRegex(ValueError, "SITE_RISK_OR_FAMILY_SPLICE"):
            self.check(investigations=tampered)

    def test_first_and_second_or_join_cannot_become_and_gate(self) -> None:
        tampered = copy.deepcopy(self.pristine["campaign"])
        tampered["nodes"][3]["requires_any"] = ["LV_002"]
        with self.assertRaisesRegex(ValueError, "OR_JOIN_REGRESSION"):
            self.check(campaign=tampered)
        tampered = copy.deepcopy(self.pristine["campaign"])
        tampered["nodes"][6]["requires_any"] = ["LV_005"]
        with self.assertRaisesRegex(ValueError, "OR_JOIN_REGRESSION"):
            self.check(campaign=tampered)

    def test_cyclic_forensic_graph_and_unnecessary_evidence_fail(self) -> None:
        tampered = copy.deepcopy(self.pristine["investigations"])
        tampered["entries"][19]["branches"]["forensic"]["nodes"][0][
            "requires"] = ["P5"]
        with self.assertRaisesRegex(ValueError,
                                    "INVESTIGATION_CYCLE_OR_MISSING_PROOF"):
            self.check(investigations=tampered)
        tampered = copy.deepcopy(self.pristine["investigations"])
        tampered["entries"][0]["branches"]["field"]["nodes"][-1][
            "requires"] = ["P0"]
        with self.assertRaisesRegex(ValueError, "INVESTIGATION_DECORATIVE_PROOF"):
            self.check(investigations=tampered)

    def test_independent_branch_proof_is_required(self) -> None:
        tampered = copy.deepcopy(self.pristine["networks"])
        tampered["regions"][8]["strategies"]["critical_first"][
            "requires_receipt_site"] = tampered["regions"][8][
                "source_sites"][1]["site_id"]
        with self.assertRaisesRegex(ValueError, "STRATEGY_PROOF_UNREACHABLE"):
            self.check(networks=tampered)

    def test_cosmetic_text_and_dwell_cannot_fake_mechanical_diversity(self) -> None:
        tampered = copy.deepcopy(self.pristine["investigations"])
        src = tampered["entries"][0]["branches"]["forensic"]
        target = tampered["entries"][1]["branches"]["forensic"]
        target["entry"] = src["entry"]
        for before, after in zip(src["nodes"], target["nodes"]):
            for key in ("kind", "station", "requires", "guard", "cost"):
                after[key] = copy.deepcopy(before[key])
            after["dwell_ticks"] = (before["dwell_ticks"] % 3) + 2
        with self.assertRaisesRegex(ValueError,
                                    "COSMETIC_INVESTIGATION_COLLISION_FORENSIC"):
            self.check(investigations=tampered)

    def test_fingerprint_ignores_prose_titles_and_clock_ticks(self) -> None:
        before = self.check()
        tampered = copy.deepcopy(self.pristine["investigations"])
        tampered["entries"][0]["branches"]["forensic"][
            "description"] = "Different decorative text"
        tampered["entries"][0]["branches"]["forensic"][
            "nodes"][0]["dwell_ticks"] = 4
        after = self.check(investigations=tampered)
        self.assertEqual(after["source_fingerprint_sha256"],
                         before["source_fingerprint_sha256"])


if __name__ == "__main__":
    unittest.main()
