"""EXP015 A11: independent 25-region source-identity mutation suite."""
from __future__ import annotations

import copy
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))
from qualify_exp015_debt_handoff import audit, load  # noqa: E402


class SourceReplay(unittest.TestCase):
    def setUp(self) -> None:
        self.source, self.entries, self.settlements = load()

    def test_all_100_original_routes(self) -> None:
        result = audit(self.source, self.entries, self.settlements)
        self.assertEqual(result["original_root_to_finale_paths"], 100)
        self.assertTrue(result["ok"])
        self.assertFalse(result["recovery_claim"])

    def test_fake_anchor_or_entry_denied(self) -> None:
        for kind, field in (("finale", "reserve_anchor_site_id"),
                            ("entry", "transport_feeder_id")):
            with self.subTest(kind=kind):
                original = copy.deepcopy(
                    self.settlements if kind == "finale" else self.entries)
                original["entries"][5][field] = "FORGED"
                with self.assertRaisesRegex(ValueError, "ORIGINAL_SOURCE_HANDOFF_DRIFT"):
                    if kind == "finale":
                        audit(self.source, self.entries, original)
                    else:
                        audit(self.source, original, self.settlements)

    def test_forged_reserve_and_release_promotion_denied(self) -> None:
        forged = copy.deepcopy(self.entries)
        forged["entries"][8]["initial_reserve_pu"] = -1
        with self.assertRaisesRegex(ValueError, "ORIGINAL_SOURCE_HANDOFF_DRIFT"):
            audit(self.source, forged, self.settlements)
        changed = copy.deepcopy(self.settlements)
        changed["qualification"] = "RELEASE_READY"
        with self.assertRaisesRegex(ValueError, "SOURCE_RELEASE_HOLD"):
            audit(self.source, self.entries, changed)


if __name__ == "__main__":
    unittest.main()
