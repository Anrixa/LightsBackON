"""EXP015 A04 mutation tests for source-pinned feeder stress and real standby."""
from __future__ import annotations

import copy
import unittest

from tools.validate_exp015_aftercare import audit, load, route


class AftercareAuditTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.baseline = load()

    def reject(self, code: str, change) -> None:
        network, finales, aftercare = copy.deepcopy(self.baseline)
        change(network, finales, aftercare)
        with self.assertRaisesRegex(ValueError, "EXP015_A04_" + code):
            audit(network, finales, aftercare)

    def test_25_original_50_branches_with_actual_transfer_tradeoffs(self) -> None:
        verdict = audit(*self.baseline)
        self.assertTrue(verdict["ok"])
        self.assertEqual(verdict["region_count"], 25)
        self.assertEqual(verdict["original_branch_scenarios"], 50)
        self.assertEqual(verdict["unique_source_topologies"], 25)
        self.assertEqual(verdict["real_standby_feasibility"]["critical_first"],
                         {"standby_viable": 11, "managed_required": 14})
        self.assertEqual(verdict["real_standby_feasibility"]["resilience_first"],
                         {"standby_viable": 17, "managed_required": 8})
        self.assertFalse(verdict["physical_hardware_steam_release_qualified"])

    def test_standby_never_invents_energized_shelter_or_overdrafts_reserve(self) -> None:
        regions, _, _ = self.baseline
        for r in regions["regions"]:
            for mode in ("critical_first", "resilience_first"):
                with self.subTest(region=r["region_id"], mode=mode):
                    facts = route(r, mode)
                    self.assertFalse(facts["shelter_site_restored"])
                    self.assertGreaterEqual(facts["reserve_after_a03_pu"], 0)
                    if facts["standby_transfer_feasible"]:
                        self.assertGreaterEqual(
                            facts["standby_reserve_after_transfer_pu"], 0)

    def test_source_book_authority_is_immutable(self) -> None:
        self.reject("BOOK_AUTHORITY", lambda n, f, a:
                    a.update(original_campaign_unchanged=False))
        self.reject("BOOK_AUTHORITY", lambda n, f, a:
                    a.update(qualification="RELEASE_CERTIFIED"))
        self.reject("BOOK_CARDINALITY", lambda n, f, a: a["entries"].pop())

    def test_original_fault_and_recovery_proof_cannot_be_spoofed(self) -> None:
        self.reject("ORIGINAL_FEEDER_RECOVERY_BINDING", lambda n, f, a:
                    a["entries"][0].update(fault_signature="FAKE"))
        self.reject("ORIGINAL_FEEDER_RECOVERY_BINDING", lambda n, f, a:
                    a["entries"][7].update(recovery_procedure="BYPASS"))
        self.reject("ORIGINAL_FEEDER_RECOVERY_BINDING", lambda n, f, a:
                    a["entries"][13].update(recovery_feeder_id="OTHER"))
        self.reject("ORIGINAL_FEEDER_RECOVERY_BINDING", lambda n, f, a:
                    a["entries"][24].update(standby_tie_id="OTHER"))

    def test_duplicate_site_or_false_retest_pressure_fails(self) -> None:
        self.reject("ORIGINAL_FEEDER_RECOVERY_BINDING", lambda n, f, a:
                    a["entries"][2].update(finale_site_id="LV_001"))
        self.reject("ORIGINAL_FEEDER_RECOVERY_BINDING", lambda n, f, a:
                    a["entries"][5].update(retest_protocol="label_only"))
        self.reject("ORIGINAL_FEEDER_RECOVERY_BINDING", lambda n, f, a:
                    a["entries"][10].update(managed_dark_pressure_pu=-12))


if __name__ == "__main__":
    unittest.main()
