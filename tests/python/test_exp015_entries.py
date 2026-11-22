"""EXP015 A09 original root source mutation and reserve bookkeeping tests."""
from __future__ import annotations

import copy
import unittest

from tools.validate_exp015_entries import audit, load


class OriginalEntryAudits(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.sources = load()

    def mutate(self, expected: str, mutator) -> None:
        networks, entries = copy.deepcopy(self.sources)
        mutator(networks, entries)
        with self.assertRaisesRegex(ValueError, "EXP015_A09_" + expected):
            audit(networks, entries)

    def test_25_root_sites_100_four_branch_and_reserve_scenarios(self) -> None:
        report = audit(*self.sources)
        self.assertTrue(report["ok"])
        self.assertEqual(report["original_entry_sites"], 25)
        self.assertEqual(report["original_first_feeders"], 50)
        self.assertEqual(report["source_bound_campaign_tasks"], 125)
        self.assertEqual(report["original_100_commissioning_scenarios"], 100)
        self.assertEqual(report["reserve_and_debt_paths"], {
            "finite_buffer": 50, "managed_debt": 50,
        })
        self.assertEqual(len(report["original_risk_classes"]), 5)
        self.assertFalse(report["fake_restoration_or_revenue"])
        self.assertFalse(report["physical_steam_two_peer_hardware_release_certified"])

    def test_no_forged_root_receipt_or_source_feeder(self) -> None:
        self.mutate("ORIGINAL_ENTRY_BINDING", lambda n, b:
                    b["entries"][0].update(entry_site_id="LV_999"))
        self.mutate("ORIGINAL_ENTRY_BINDING", lambda n, b:
                    b["entries"][1].update(critical_feeder_id="FAKE"))
        self.mutate("ORIGINAL_ENTRY_BINDING", lambda n, b:
                    b["entries"][6].update(transport_feeder_id="FAKE"))
        self.mutate("ORIGINAL_ENTRY_BINDING", lambda n, b:
                    b["entries"][15].update(original_task_ids=["FAKE"] * 5))

    def test_no_cosmetic_prep_or_invented_reserve(self) -> None:
        self.mutate("ORIGINAL_ENTRY_BINDING", lambda n, b:
                    b["entries"][10].update(entry_risk_proof="COSMETIC"))
        self.mutate("ORIGINAL_ENTRY_BINDING", lambda n, b:
                    b["entries"][12].update(initial_reserve_pu=999))
        self.mutate("ORIGINAL_ENTRY_BINDING", lambda n, b:
                    b["entries"][24].update(managed_pressure_pu=-1))
        self.mutate("SOURCE_AUTHORITY", lambda n, b:
                    b.update(qualification="RELEASE_APPROVED"))
        self.mutate("SOURCE_AUTHORITY", lambda n, b:
                    b["entries"].pop())


if __name__ == "__main__":
    unittest.main()
