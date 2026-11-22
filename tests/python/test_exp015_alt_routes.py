"""EXP015 A07 original route risk, network, capacity and tie mutations."""
from __future__ import annotations

import copy
import unittest

from tools.validate_exp015_alt_routes import audit, load, upstream_energized


class OriginalRouteSourceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.source = load()

    def mutate(self, expected: str, fn) -> None:
        networks, book = copy.deepcopy(self.source)
        fn(networks, book)
        with self.assertRaisesRegex(ValueError, "EXP015_A07_" + expected):
            audit(networks, book)

    def test_all_100_original_routes_and_actual_mechanical_branch_counts(self) -> None:
        result = audit(*self.source)
        self.assertEqual(result["original_route_sites"], 100)
        self.assertEqual(result["branch_route_scenarios"], 125)
        self.assertEqual(result["unique_original_networks"], 25)
        self.assertEqual(result["role_counts"],
                         dict.fromkeys(("first_route_a", "first_route_b",
                                        "second_route_a", "second_route_b"), 25))
        self.assertEqual(result["source_derived_mechanics"], {
            "first_route_a_rapid_eligible": 20,
            "first_route_b_upstream_priority_ready": 25,
            "second_route_a_original_buffer_possible": 25,
            "second_route_b_original_tie_a_ready": 12,
            "second_route_b_original_tie_b_ready": 17,
        })
        self.assertFalse(result["hardware_steam_2peer_playability_release_certified"])

    def test_no_forged_site_or_second_route_tie(self) -> None:
        self.mutate("ORIGINAL_ALT_ASSET_PROOF", lambda n, b:
                    b["entries"][0].update(route_site_id="LV_004"))
        self.mutate("ORIGINAL_ALT_ASSET_PROOF", lambda n, b:
                    b["entries"][3].update(standby_tie_id="FICTIONAL_TIE"))
        self.mutate("ORIGINAL_ALT_ASSET_PROOF", lambda n, b:
                    b["entries"][7].update(standby_source_site="LV_999"))

    def test_no_swapped_protection_proof_capacity_or_risk(self) -> None:
        self.mutate("ORIGINAL_ALT_ASSET_PROOF", lambda n, b:
                    b["entries"][12].update(capacity_pu=999))
        self.mutate("ORIGINAL_ALT_ASSET_PROOF", lambda n, b:
                    b["entries"][25].update(original_fault_signature="FAKE"))
        self.mutate("ORIGINAL_ALT_ASSET_PROOF", lambda n, b:
                    b["entries"][48].update(original_recovery_procedure="FAKE"))
        self.mutate("ORIGINAL_ALT_ASSET_PROOF", lambda n, b:
                    b["entries"][92].update(risk_containment_protocol="COSMETIC"))

    def test_no_early_service_or_fake_receipts(self) -> None:
        self.mutate("ORIGINAL_ALT_ASSET_PROOF", lambda n, b:
                    b["entries"][58].update(task_ids=["FAKE"] * 5))
        self.mutate("ORIGINAL_ALT_ASSET_PROOF", lambda n, b:
                    b["entries"][55].update(managed_outage_pressure_pu=0))
        self.mutate("SOURCE_AUTHORITY", lambda n, b:
                    b.update(qualification="RELEASE_APPROVED"))
        self.mutate("SOURCE_AUTHORITY", lambda n, b:
                    b["entries"].pop())

    def test_normal_supply_ignores_unrestored_route_sites(self) -> None:
        for reg in self.source[0]["regions"]:
            sites = [s["site_id"] for s in reg["source_sites"]]
            restored = {sites[0], sites[1], sites[3]}
            self.assertNotIn(sites[5], upstream_energized(reg, restored))
            self.assertNotIn(sites[7], upstream_energized(reg, restored))


if __name__ == "__main__":
    unittest.main()
