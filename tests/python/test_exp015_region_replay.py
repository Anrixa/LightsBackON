"""EXP015 A06: inherited original-book mutation and route/source coverage."""
from __future__ import annotations

import copy
import unittest

from tools.qualify_exp015_region_replay import audit, load


class FullRegionReplaySourceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.baseline = load()

    def mutate(self, expected: str, edit) -> None:
        cloned = copy.deepcopy(self.baseline)
        edit(*cloned)
        with self.assertRaisesRegex(ValueError, expected):
            audit(*cloned)

    def test_exact_25_regions_75_original_junctions_and_50_routes(self) -> None:
        result = audit(*self.baseline)
        self.assertTrue(result["ok"])
        self.assertEqual(result["original_regions"], 25)
        self.assertEqual(result["original_unique_stages"], 75)
        self.assertEqual(result["original_source_mechanical_signatures"], 25)
        self.assertEqual(result["authenticated_3_dispatch_scenarios_required"], 50)
        self.assertFalse(result["physical_controller_steam_release_certified"])

    def test_cross_phase_wrong_authored_site_never_passes(self) -> None:
        self.mutate("EXP015_A01_|EXP015_A06_", lambda n, a, b, c, d, e:
                    a["entries"][0].update(incident_site_id="LV_001"))
        self.mutate("EXP015_A02_|EXP015_A06_", lambda n, a, b, c, d, e:
                    b["entries"][1].update(junction_site_id="LV_008"))
        self.mutate("EXP015_A05_|EXP015_A06_", lambda n, a, b, c, d, e:
                    e["entries"][2].update(finale_site_id="LV_008"))

    def test_protected_feeder_tie_and_risk_falsification_is_rejected(self) -> None:
        self.mutate("EXP015_A01_|EXP015_A06_", lambda n, a, b, c, d, e:
                    a["entries"][7].update(standby_tie_id="FORGED"))
        self.mutate("EXP015_A02_|EXP015_A06_", lambda n, a, b, c, d, e:
                    b["entries"][13].update(backfeed_tie_id="FORGED"))
        self.mutate("EXP015_A05_|EXP015_A06_", lambda n, a, b, c, d, e:
                    e["entries"][24].update(critical_feeder_id="FORGED"))
        self.mutate("EXP015_A05_|EXP015_A06_", lambda n, a, b, c, d, e:
                    e["entries"][9].update(source_qualification="PRODUCTION"))

    def test_original_receipt_invariant_survives_every_region(self) -> None:
        result = audit(*self.baseline)
        self.assertEqual(result["original_branch_effects"]["critical_first"],
                         {"critical_live": 25, "recharge_ready": 3})
        self.assertEqual(result["original_branch_effects"]["resilience_first"],
                         {"critical_live": 0, "recharge_ready": 0})
        self.assertTrue(result["original_saves_rewards_levels_tasks_unchanged"])


if __name__ == "__main__":
    unittest.main()
