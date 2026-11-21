"""EXP015 A02 independently mutated second-OR-join cascading fault source."""
from __future__ import annotations

import copy
import unittest

from tools.validate_exp015_cascades import audit, load


class Exp015A02CascadeSourceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.original = load()

    def mutated(self, code: str, change) -> None:
        network, cases = copy.deepcopy(self.original)
        change(network, cases)
        with self.assertRaisesRegex(ValueError, code):
            audit(network, cases)

    def test_source_has_25_distinct_cascades_and_live_backfeed(self) -> None:
        result = audit(*self.original)
        self.assertTrue(result["ok"])
        self.assertEqual(result["second_or_join_cascades"], 25)
        self.assertEqual(result["distinct_mechanical_fault_graphs"], 25)
        self.assertEqual(result["risk_specific_recovery_protocols"], 5)
        self.assertGreaterEqual(
            result["original_critical_first_live_backfeed_paths"], 5)
        self.assertEqual(result["original_managed_recovery_fallbacks"], 25)
        self.assertFalse(result["physical_steam_release_certified"])
        self.assertFalse(result["host_runtime_certified_by_source_only"])

    def test_missing_duplicate_or_reordered_junction_rejected(self) -> None:
        self.mutated("SOURCE_REGION_COVERAGE",
                     lambda n, c: c["entries"].pop())
        self.mutated("JUNCTION_IDENTITY",
                     lambda n, c: c["entries"][18].update(
                         junction_site_id=c["entries"][17]["junction_site_id"]))

    def test_source_swapped_second_tie_and_normal_feeder_rejected(self) -> None:
        self.mutated("SECOND_TIE_SOURCE_MISMATCH",
                     lambda n, c: c["entries"][2].update(
                         backfeed_tie_id=n["regions"][2]["standby_ties"][0]["edge_id"]))
        self.mutated("ORIGINAL_NORMAL_FEEDER_MISMATCH",
                     lambda n, c: c["entries"][8].update(
                         normal_feeder_id="FAKE_FEEDER"))

    def test_fault_signature_and_recovery_procedure_immutable(self) -> None:
        self.mutated("ORIGINAL_FAULT_PROOF_MISMATCH",
                     lambda n, c: c["entries"][13].update(
                         original_fault_signature="client_generated"))
        self.mutated("ORIGINAL_FAULT_PROOF_MISMATCH",
                     lambda n, c: c["entries"][21].update(
                         original_recovery_procedure="FAKE_RECOVERY"))

    def test_risk_protocol_and_service_pressure_bounded(self) -> None:
        self.mutated("RISK_RESPONSE_MISMATCH",
                     lambda n, c: c["entries"][0].update(
                         managed_service_pressure=-500))
        self.mutated("RISK_RESPONSE_MISMATCH",
                     lambda n, c: c["entries"][9].update(
                         risk_protocol="DECORATIVE_ONLY"))

    def test_unsafe_cyclic_regional_feeder_is_rejected(self) -> None:
        def cycle(n, c):
            r = n["regions"][15]
            r["primary_feeders"][0]["from"] = r["source_sites"][1]["site_id"]
        self.mutated("CYCLIC_FEEDER", cycle)

    def test_no_authority_or_legacy_promotion(self) -> None:
        self.mutated("CASCADE_AUTHORITY",
                     lambda n, c: c.update(
                         legacy_campaign_contracts_unchanged=False))
        self.mutated("CASCADE_AUTHORITY",
                     lambda n, c: c.update(
                         qualification="RELEASE_CERTIFIED"))


if __name__ == "__main__":
    unittest.main()
