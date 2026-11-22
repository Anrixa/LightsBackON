"""EXP015 A08: original route-source integrity and non-forgeable event proof."""
from __future__ import annotations

import copy
import unittest

from tools.validate_exp015_rejoins import audit, event_proof, load, network_live


class RejoinSourceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.book = load()

    def changed(self, expected: str, fn) -> None:
        n, a, b = copy.deepcopy(self.book)
        fn(n, a, b)
        with self.assertRaisesRegex(ValueError, "EXP015_A08_" + expected):
            audit(n, a, b)

    def test_50_original_rejoins_150_original_route_combinations(self) -> None:
        r = audit(*self.book)
        self.assertTrue(r["ok"])
        self.assertEqual(r["original_rejoin_sites"], 50)
        self.assertEqual(r["source_mechanical_route_scenarios"], 150)
        self.assertEqual(r["original_network_signatures"], 25)
        self.assertEqual(r["source_feasible_standby_rejoins"], {
            "first_a_second_a": 13, "first_a_second_b": 11,
            "first_b_second_a": 9, "first_b_second_b": 11,
        })
        self.assertFalse(r["new_levels_tasks_rewards_production_saves"])
        self.assertFalse(r["playability_hardware_steam_release_certified"])

    def test_forged_join_and_original_feeder_rejected(self) -> None:
        self.changed("REJOIN_ORIGINAL_FEEDER_BINDING", lambda n, a, b:
                     b["entries"][7].update(join_site_id="LV_900"))
        self.changed("REJOIN_ORIGINAL_FEEDER_BINDING", lambda n, a, b:
                     b["entries"][17].update(join_feeder_id="FAKE"))
        self.changed("REJOIN_ORIGINAL_FEEDER_BINDING", lambda n, a, b:
                     b["entries"][27].update(route_a_feeder_id="FAKE"))
        self.changed("REJOIN_ORIGINAL_FEEDER_BINDING", lambda n, a, b:
                     b["entries"][35].update(finale_standby_tie_id="FAKE"))
        self.changed("REJOIN_ORIGINAL_FEEDER_BINDING", lambda n, a, b:
                     b["entries"][41].update(original_recovery_procedure="FAKE"))

    def test_source_proof_is_not_a_merely_repeated_relay_reset(self) -> None:
        good = [{"asset": "FEED", "action": x}
                for x in ("trip_feeder", "clear_fault", "reset_feeder")]
        self.assertTrue(event_proof("FEED", True, True, good))
        self.assertFalse(event_proof("FEED", True, True, list(reversed(good))))
        self.assertFalse(event_proof("FEED", False, True, good))
        self.assertFalse(event_proof("FEED", True, False, good))
        self.assertFalse(event_proof("FEED", True, True, good + [
            {"asset": "FEED", "action": "isolate_feeder"}]))
        self.assertFalse(event_proof("OTHER", True, True, good))

    def test_no_fabricated_rights_or_managed_source_credits(self) -> None:
        self.changed("REJOIN_AUTHORITY", lambda n, a, b:
                     b.update(legacy_campaign_contracts_unchanged=False))
        self.changed("REJOIN_AUTHORITY", lambda n, a, b:
                     b.update(qualification="RELEASE_CANDIDATE"))
        self.changed("REJOIN_ORIGINAL_FEEDER_BINDING", lambda n, a, b:
                     b["entries"][22].update(managed_pressure_pu=-1))
        self.changed("REJOIN_ORIGINAL_FEEDER_BINDING", lambda n, a, b:
                     b["entries"][3].update(source_task_ids=["FAKE"]))


if __name__ == "__main__":
    unittest.main()
