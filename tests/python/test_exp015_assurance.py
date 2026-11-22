"""EXP015 A05 source/authority negative mutation qualification."""
from __future__ import annotations

import copy
import unittest

from tools.validate_exp015_assurance import audit, load, original_supply


class CriticalAssuranceAuditTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.baseline = load()

    def mutate(self, code: str, fn) -> None:
        n, f, after, assurance = copy.deepcopy(self.baseline)
        fn(n, f, after, assurance)
        with self.assertRaisesRegex(ValueError, "EXP015_A05_" + code):
            audit(n, f, after, assurance)

    def test_25_source_graphs_and_50_true_restore_paths(self) -> None:
        result = audit(*self.baseline)
        self.assertTrue(result["ok"])
        self.assertEqual(result["regions"], 25)
        self.assertEqual(result["original_branch_scenarios"], 50)
        self.assertEqual(result["distinct_original_mechanics"], 25)
        self.assertEqual(result["original_source_effects"]["critical_first"],
                         {"critical_live": 25, "recharge_source_eligible": 3})
        self.assertEqual(result["original_source_effects"]["resilience_first"],
                         {"critical_live": 0, "recharge_source_eligible": 0})
        self.assertFalse(result["physical_steam_hardware_release_certified"])

    def test_never_forges_power_by_choosing_a_priority_label(self) -> None:
        networks, _, _, _ = self.baseline
        for region in networks["regions"]:
            for route in ("critical_first", "resilience_first"):
                with self.subTest(region=region["region_id"], route=route):
                    state = original_supply(region, route)
                    self.assertFalse(state["finale_restored"])
                    self.assertGreaterEqual(state["reserve_before_recharge"], 0)
                    self.assertEqual(state["critical_live"],
                                     route == "critical_first")

    def test_untrusted_book_authority_cannot_promote_release(self) -> None:
        self.mutate("SOURCE_AUTHORITY", lambda n, f, a, b:
                    b.update(original_campaign_unchanged=False))
        self.mutate("SOURCE_AUTHORITY", lambda n, f, a, b:
                    b.update(qualification="HARDWARE_CERTIFIED"))
        self.mutate("SOURCE_CARDINALITY", lambda n, f, a, b:
                    b["entries"].pop())

    def test_original_critical_and_reserve_bindings_are_immutable(self) -> None:
        self.mutate("CRITICAL_ORIGINAL_BINDING", lambda n, f, a, b:
                    b["entries"][1].update(critical_feeder_id="FAKED"))
        self.mutate("CRITICAL_ORIGINAL_BINDING", lambda n, f, a, b:
                    b["entries"][4].update(reserve_anchor_site="FAKED"))
        self.mutate("CRITICAL_ORIGINAL_BINDING", lambda n, f, a, b:
                    b["entries"][9].update(shelter_feeder_id="FAKED"))
        self.mutate("CRITICAL_ORIGINAL_BINDING", lambda n, f, a, b:
                    b["entries"][14].update(fault_signature="FAKED"))
        self.mutate("CRITICAL_ORIGINAL_BINDING", lambda n, f, a, b:
                    b["entries"][18].update(recovery_procedure="FAKED"))

    def test_risk_pressure_and_duplicate_finales_fail(self) -> None:
        self.mutate("CRITICAL_ORIGINAL_BINDING", lambda n, f, a, b:
                    b["entries"][24].update(finale_site_id="LV_008"))
        self.mutate("CRITICAL_ORIGINAL_BINDING", lambda n, f, a, b:
                    b["entries"][7].update(critical_retest_protocol="COSMETIC"))
        self.mutate("CRITICAL_ORIGINAL_BINDING", lambda n, f, a, b:
                    b["entries"][6].update(managed_pressure_pu=-5))


if __name__ == "__main__":
    unittest.main()
