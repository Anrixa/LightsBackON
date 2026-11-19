"""EXP009 independent source/tamper tests; source/headless only."""
from __future__ import annotations

import copy
import unittest

from tools.validate_exp009_consequences import load_inputs, replay_reference, validate


class EXP009ConsequenceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.atlas, cls.faults, cls.chains = load_inputs()

    def mutation(self, field: str, value, expected: str, node: bool = False) -> None:
        altered = copy.deepcopy(self.chains)
        target = altered["entries"][0]["nodes"][0] if node else altered["entries"][0]
        target[field] = value
        with self.assertRaisesRegex(ValueError, expected):
            validate(self.atlas, self.faults, altered)

    def test_all_200_propagation_chains_and_recovery_reference(self):
        audit = validate(self.atlas, self.faults, self.chains)
        self.assertEqual((audit["levels"], audit["domains"],
                          audit["linked_services"], audit["source_targets"]),
                         (200, 8, 600, 800))
        self.assertEqual(audit["topologies"], {"fork": 67, "serial": 133})
        for entry in self.chains["entries"]:
            replay_reference(entry)

    def test_scenario_tampering_rejected(self):
        self.mutation("scenario_key", "forged", "SOURCE_DRIFT")

    def test_parent_splice_and_cycle_rejected(self):
        changed = copy.deepcopy(self.chains)
        changed["entries"][0]["nodes"][1]["parent"] = changed["entries"][0]["nodes"][2]["id"]
        with self.assertRaisesRegex(ValueError, "NODE_TOPOLOGY_INVALID"):
            validate(self.atlas, self.faults, changed)

    def test_unbounded_pressure_and_forged_relay_rejected(self):
        self.mutation("threshold_ticks", 5000, "THRESHOLD", node=True)
        self.mutation("reserve", 12, "CONSOLE_OR_RESERVE")

    def test_domain_reassignment_and_foreign_target_rejected(self):
        self.mutation("site", "health", "SOURCE_DRIFT")
        self.mutation("id", "SW_EAST", "NODE_TOPOLOGY", node=True)

    def test_duplication_and_disconnected_chain_rejected(self):
        changed = copy.deepcopy(self.chains)
        changed["entries"][1] = copy.deepcopy(changed["entries"][0])
        with self.assertRaisesRegex(ValueError, "FOREIGN_OR_DUPLICATE"):
            validate(self.atlas, self.faults, changed)
        self.mutation("topology", "cycle", "TOPOLOGY_DRIFT")


if __name__ == "__main__":
    unittest.main()
