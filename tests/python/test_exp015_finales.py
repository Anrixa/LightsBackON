"""EXP015 A03 source mutation and original-branch supply invariant tests."""
from __future__ import annotations

import copy
import unittest

from tools.validate_exp015_finales import audit, load, source_supplies


class RegionalFinaleSourceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.baseline = load()

    def mutate(self, expected: str, edit) -> None:
        regions, finales = copy.deepcopy(self.baseline)
        edit(regions, finales)
        with self.assertRaisesRegex(ValueError, expected):
            audit(regions, finales)

    def test_25_unique_mechanics_50_campaign_paths_and_real_supply_split(self) -> None:
        result = audit(*self.baseline)
        self.assertTrue(result["ok"])
        self.assertEqual(result["finales"], 25)
        self.assertEqual(result["distinct_id_normalized_finale_mechanics"], 25)
        self.assertEqual(result["original_campaign_routes"], 50)
        self.assertEqual(result["risk_protocols"], 5)
        self.assertEqual(
            result["regional_strategy_effects"]["critical_first"]["critical_live"], 25)
        self.assertEqual(
            result["regional_strategy_effects"]["critical_first"]["shelter_ready"], 7)
        self.assertEqual(
            result["regional_strategy_effects"]["resilience_first"]["critical_live"], 0)
        self.assertEqual(
            result["regional_strategy_effects"]["resilience_first"]["shelter_ready"], 12)
        self.assertFalse(result["human_controller_hardware_steam_release_certified"])
        self.assertTrue(result["no_new_levels_tasks_or_original_credits"])

    def test_original_critical_route_never_forges_resilience_energization(self) -> None:
        network, _ = self.baseline
        for i, region in enumerate(network["regions"]):
            with self.subTest(region=i + 1):
                critical = source_supplies(region, "critical_first")
                resilient = source_supplies(region, "resilience_first")
                self.assertTrue(critical["critical_energized"])
                self.assertFalse(resilient["critical_energized"])

    def test_remove_duplicate_or_swap_finale_cannot_be_silently_accepted(self) -> None:
        self.mutate("FINALE_CARDINALITY", lambda n, b: b["entries"].pop())
        self.mutate("ORIGINAL_FINALE_PROVENANCE", lambda n, b:
                    b["entries"][6].update(finale_site_id="LV_001"))
        self.mutate("ORIGINAL_FINALE_PROVENANCE", lambda n, b:
                    b["entries"][14].update(
                        region_id=b["entries"][13]["region_id"]))

    def test_forged_critical_or_shelter_feeder_fails(self) -> None:
        self.mutate("ORIGINAL_SERVICE_FEEDER_BINDING", lambda n, b:
                    b["entries"][3].update(critical_feeder_id="INVENTED"))
        self.mutate("ORIGINAL_SERVICE_FEEDER_BINDING", lambda n, b:
                    b["entries"][8].update(shelter_feeder_id="INVENTED"))
        self.mutate("ORIGINAL_SERVICE_FEEDER_BINDING", lambda n, b:
                    b["entries"][16].update(shelter_standby_tie_id="INVENTED"))

    def test_wrong_pressure_or_risk_protocol_fails(self) -> None:
        self.mutate("REGIONAL_RISK_PRESSURE", lambda n, b:
                    b["entries"][4].update(critical_dark_pressure_pu=-100))
        self.mutate("REGIONAL_RISK_PRESSURE", lambda n, b:
                    b["entries"][19].update(risk_closeout_protocol="renamed_only"))

    def test_cyclic_or_partial_source_feeder_graph_fails(self) -> None:
        def cycle(network, book):
            region = network["regions"][10]
            region["primary_feeders"][0]["from"] = region["source_sites"][1]["site_id"]
        self.mutate("SOURCE_CYCLIC_FEEDER", cycle)

    def test_cannot_promote_gameplay_or_contract_authority(self) -> None:
        self.mutate("FINALE_AUTHORITY", lambda n, b:
                    b.update(original_campaign_unchanged=False))
        self.mutate("FINALE_AUTHORITY", lambda n, b:
                    b.update(qualification="PHYSICAL_CERTIFIED"))
        self.mutate("FINALE_AUTHORITY", lambda n, b:
                    b.update(authority="UNVERIFIED_CLIENT_AUTHORITY"))


if __name__ == "__main__":
    unittest.main()
