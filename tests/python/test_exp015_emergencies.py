"""EXP015 A01 source-identity and mechanism mutation tests (CPU only)."""
from __future__ import annotations

import copy
import unittest

from tools.validate_exp015_emergencies import audit, load


class RegionalEmergencySourceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.networks, cls.incidents = load()

    def test_original_25_incidents_and_source_live_branch_coverage(self) -> None:
        result = audit(self.networks, self.incidents)
        self.assertTrue(result["ok"])
        self.assertEqual(result["source_pinned_incident_sites"], 25)
        self.assertEqual(result["distinct_electrical_recovery_chains"], 25)
        self.assertEqual(result["source_managed_outage_fallbacks"], 25)
        self.assertEqual(result["five_different_hazard_protocols"], 5)
        self.assertGreaterEqual(
            result["source_live_critical_first_standby_opportunities"], 5)
        self.assertFalse(result["original_campaign_or_rewards_edited"])
        self.assertFalse(result["physical_controller_steam_release_certified"])

    def check_mutation(self, fragment: str, mutate) -> None:
        network = copy.deepcopy(self.networks)
        incidents = copy.deepcopy(self.incidents)
        mutate(network, incidents)
        with self.assertRaisesRegex(ValueError, fragment):
            audit(network, incidents)

    def test_missing_incident_or_duplicate_rejoin_is_rejected(self) -> None:
        self.check_mutation("REGIONAL_INCIDENT_CARDINALITY",
                            lambda n, c: c["entries"].pop())
        self.check_mutation("SOURCE_SITE_IDENTITY",
                            lambda n, c: c["entries"][9].update(
                                incident_site_id=c["entries"][8]["incident_site_id"]))

    def test_forged_standby_and_normal_feeders_are_rejected(self) -> None:
        self.check_mutation("STANDBY_TOPOLOGY_PIN",
                            lambda n, c: c["entries"][9].update(
                                standby_tie_id="NET_999_T99"))
        self.check_mutation("NORMAL_FEEDER_SOURCE_PIN",
                            lambda n, c: c["entries"][21].update(
                                normal_feeder_id="NET_999_F99"))

    def test_mutated_hazard_protocol_and_pressure_rejected(self) -> None:
        self.check_mutation("HAZARD_SPECIFIC_RECOVERY_PROTOCOL",
                            lambda n, c: c["entries"][13].update(
                                managed_unserved_pressure_pu=999))
        self.check_mutation("HAZARD_SPECIFIC_RECOVERY_PROTOCOL",
                            lambda n, c: c["entries"][4].update(
                                preparation_protocol="cosmetic_label"))

    def test_source_topology_cycles_and_cross_region_splices_rejected(self) -> None:
        self.check_mutation("SOURCE_FEEDER_GRAPH_NOT_TREE",
                            lambda n, c: n["regions"][5]["primary_feeders"][0].update(
                                **{"from": n["regions"][5]["source_sites"][1]["site_id"]}))
        self.check_mutation("STANDBY_TOPOLOGY_PIN",
                            lambda n, c: c["entries"][22].update(
                                standby_source_site=c["entries"][21]["standby_source_site"]))

    def test_source_scoring_and_campaign_flags_are_locked(self) -> None:
        self.check_mutation("INCIDENT_SOURCE_AUTHORITY",
                            lambda n, c: c.update(
                                legacy_campaign_contracts_unchanged=False))
        self.check_mutation("INCIDENT_SOURCE_AUTHORITY",
                            lambda n, c: c.update(
                                authority="UNAUTHORIZED_CLIENT_SOURCE"))


if __name__ == "__main__":
    unittest.main()
