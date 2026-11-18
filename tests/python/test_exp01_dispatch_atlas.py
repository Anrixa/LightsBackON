"""Negative gates for the 200-location / 1000-task expansion catalogue."""
from __future__ import annotations

import copy
import json
import unittest
from pathlib import Path

from tools.build_dispatch_atlas import create_atlas, encoded
from tools.validate_dispatch_atlas import ATLAS, SEEDS, audit


class TestExp01DispatchAtlas(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.seeds = json.loads(SEEDS.read_text(encoding="utf-8"))
        cls.data = json.loads(ATLAS.read_text(encoding="utf-8"))

    def test_200_locations_200_levels_1000_unique_tasks(self) -> None:
        summary = audit(self.data, self.seeds)
        self.assertEqual(summary["locations"], 200)
        self.assertEqual(summary["levels"], 200)
        self.assertEqual(summary["tasks"], 1000)
        self.assertEqual(summary["unique_puzzle_signatures"], 200)

    def test_seeded_generator_reproduces_checked_in_catalog(self) -> None:
        self.assertEqual(encoded(create_atlas(self.seeds)), ATLAS.read_bytes())

    def test_reject_duplicate_task_id(self) -> None:
        forged = copy.deepcopy(self.data)
        forged["levels"][1]["tasks"][0]["id"] = forged["levels"][0]["tasks"][0]["id"]
        with self.assertRaisesRegex(ValueError, "unique task IDs"):
            audit(forged)

    def test_reject_counterfeit_playable_status(self) -> None:
        forged = copy.deepcopy(self.data)
        forged["levels"][0]["runtime_status"] = "PLAYABLE"
        with self.assertRaisesRegex(ValueError, "not host-enabled"):
            audit(forged)

    def test_reject_credit_bearing_collectible(self) -> None:
        forged = copy.deepcopy(self.data)
        forged["levels"][0]["collectible"]["effect"] = "CREDITS_100"
        with self.assertRaisesRegex(ValueError, "forbidden gameplay reward"):
            audit(forged)

    def test_reject_optional_task_becoming_required(self) -> None:
        forged = copy.deepcopy(self.data)
        forged["levels"][0]["tasks"][3]["required"] = True
        with self.assertRaisesRegex(ValueError, "optional task improperly gates"):
            audit(forged)


if __name__ == "__main__":
    unittest.main()
