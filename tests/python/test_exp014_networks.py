"""EXP014 A09.1 negative and structural oracles for regional source book.

These tests cannot certify host operations, physical reachability, multiplayer,
save changes, GPU behavior or game release. Those remain explicitly held.
"""
from __future__ import annotations

import copy
import json
import unittest

from tools.validate_exp014_networks import (
    ATLAS, BOOK, CAMPAIGN, PUZZLES, unlabeled_tree_signature, validate,
)


class RegionalNetworkSourceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.atlas = json.loads(ATLAS.read_text(encoding="utf-8"))
        cls.campaign = json.loads(CAMPAIGN.read_text(encoding="utf-8"))
        cls.puzzles = json.loads(PUZZLES.read_text(encoding="utf-8"))
        cls.book = json.loads(BOOK.read_text(encoding="utf-8"))

    def check(self, **changed: dict) -> dict:
        values = {
            "atlas": self.atlas, "campaign": self.campaign,
            "puzzles": self.puzzles, "book": self.book,
        }
        values.update(changed)
        return validate(**values)

    def test_25_nonisomorphic_trees_200_sites_and_1000_original_jobs(self) -> None:
        report = self.check()
        self.assertEqual(report["regions"], 25)
        self.assertEqual(report["unique_unlabeled_rooted_primary_topologies"], 25)
        self.assertEqual(report["source_sites"], 200)
        self.assertEqual(report["immutable_job_ids"], 1000)
        self.assertEqual(report["primary_feeders"], 175)
        self.assertEqual(report["normally_open_standby_ties"], 50)
        self.assertFalse(report["host_runtime_enabled"])
        self.assertFalse(report["human_controller_certified"])

    def test_signature_independent_of_node_names_and_child_order(self) -> None:
        self.assertEqual(
            unlabeled_tree_signature([0, 0, 1, 1, 1, 2, 2]),
            unlabeled_tree_signature([0, 0, 2, 2, 1, 1, 1]),
        )

    def test_cloned_primary_topology_rejected_despite_different_names_and_pu(self) -> None:
        book = copy.deepcopy(self.book)
        first = book["regions"][0]
        other = book["regions"][1]
        source_nodes = [site["site_id"] for site in first["source_sites"]]
        target_nodes = [site["site_id"] for site in other["source_sites"]]
        # A relabeled source graph with independently varied capacities
        # cannot be presented as a twenty-fifth distinct regional topology.
        for a, b in zip(first["primary_feeders"], other["primary_feeders"]):
            b["from"] = target_nodes[source_nodes.index(a["from"])]
            b["capacity_pu"] = 32
        with self.assertRaisesRegex(ValueError, "NONCOSMETIC_DUPLICATE_TOPOLOGY"):
            self.check(book=book)

    def test_original_job_id_mutation_rejected(self) -> None:
        book = copy.deepcopy(self.book)
        book["regions"][12]["source_sites"][3]["source_task_ids"][4] = "JOB_104_5"
        with self.assertRaisesRegex(ValueError, "IMMUTABLE_TASK_SPLICE"):
            self.check(book=book)

    def test_risk_and_location_source_splice_rejected(self) -> None:
        book = copy.deepcopy(self.book)
        book["regions"][7]["risk_class"] = "weather"
        with self.assertRaisesRegex(ValueError, "RISK_SOURCE_SPLICE"):
            self.check(book=book)
        book = copy.deepcopy(self.book)
        book["regions"][7]["source_sites"][2]["location_id"] = "LOC_003"
        with self.assertRaisesRegex(ValueError, "SITE_SOURCE_SPLICE"):
            self.check(book=book)

    def test_cycle_or_multiple_enabled_incoming_routes_fail_closed(self) -> None:
        book = copy.deepcopy(self.book)
        edge = book["regions"][3]["primary_feeders"][3]
        edge["from"] = edge["to"]
        with self.assertRaisesRegex(ValueError, "PRIMARY_TREE_OR_PROTECTION"):
            self.check(book=book)
        book = copy.deepcopy(self.book)
        book["regions"][3]["standby_ties"][0]["normally_closed"] = True
        with self.assertRaisesRegex(ValueError, "UNSAFE_STANDBY_TIE"):
            self.check(book=book)

    def test_duplicate_primary_and_spliced_standby_tie_rejected(self) -> None:
        book = copy.deepcopy(self.book)
        book["regions"][5]["primary_feeders"][1]["edge_id"] = (
            book["regions"][5]["primary_feeders"][0]["edge_id"]
        )
        with self.assertRaisesRegex(ValueError, "PRIMARY_TREE_OR_PROTECTION"):
            self.check(book=book)
        book = copy.deepcopy(self.book)
        book["regions"][5]["standby_ties"][1]["to"] = (
            book["regions"][5]["source_sites"][1]["site_id"]
        )
        with self.assertRaisesRegex(ValueError, "CYCLE_OR_PARALLEL_TIE"):
            self.check(book=book)

    def test_or_join_branch_semantics_are_unchanged(self) -> None:
        campaign = copy.deepcopy(self.campaign)
        campaign["nodes"][3]["requires_any"] = ["LV_002"]
        with self.assertRaisesRegex(ValueError, "EXISTING_OR_JOIN_DRIFT"):
            self.check(campaign=campaign)

    def test_strategy_requirements_are_source_bound(self) -> None:
        book = copy.deepcopy(self.book)
        book["regions"][10]["strategies"]["critical_first"]["requires_receipt_site"] = "LV_001"
        with self.assertRaisesRegex(ValueError, "STRATEGY_SOURCE_OR_TRADEOFF"):
            self.check(book=book)

    def test_missing_region_and_unsupported_runtime_promotion_rejected(self) -> None:
        book = copy.deepcopy(self.book)
        book["regions"].pop()
        with self.assertRaisesRegex(ValueError, "CANONICAL_COVERAGE"):
            self.check(book=book)
        book = copy.deepcopy(self.book)
        book["host_runtime_enabled"] = True
        with self.assertRaisesRegex(ValueError, "HEADER_OR_UNAUTHORIZED_RUNTIME_CLAIM"):
            self.check(book=book)

    def test_python_booleans_do_not_masquerade_as_capacity(self) -> None:
        book = copy.deepcopy(self.book)
        book["regions"][0]["primary_feeders"][0]["capacity_pu"] = True
        with self.assertRaisesRegex(ValueError, "PRIMARY_TREE_OR_PROTECTION"):
            self.check(book=book)


if __name__ == "__main__":
    unittest.main()
