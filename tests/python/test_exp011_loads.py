"""EXP011 source corruption, conservation and recovery regression probes."""
from __future__ import annotations

import copy
import unittest

from tools.validate_exp011_loads import load_inputs, replay_reference, validate


class EXP011SourceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.atlas, cls.logistics, cls.loads = load_inputs()

    def test_all_200_source_bound_boards_and_1000_unique_targets(self) -> None:
        report = validate(self.atlas, self.logistics, self.loads)
        self.assertEqual((report["levels"], report["circuits"], report["targets"]),
                         (200, 600, 1000))
        self.assertEqual(report["modes"], ["cascade", "interlock", "triage"])

    def test_valid_completion_route_for_every_mode_and_site(self) -> None:
        for entry in self.loads["entries"]:
            with self.subTest(level=entry["level_id"]):
                replay_reference(entry)

    def test_cross_site_manifest_swap_is_rejected(self) -> None:
        altered = copy.deepcopy(self.loads)
        altered["entries"][0]["logistics_key"] = altered["entries"][1]["logistics_key"]
        with self.assertRaisesRegex(ValueError, "EXP011_SOURCE_DRIFT"):
            validate(self.atlas, self.logistics, altered)

    def test_client_or_forged_authority_cannot_admit_a_book(self) -> None:
        altered = copy.deepcopy(self.loads)
        altered["authority"] = "CLIENT_APPROVED_GRID"
        with self.assertRaisesRegex(ValueError, "EXP011_HEADER_INVALID"):
            validate(self.atlas, self.logistics, altered)

    def test_duplicate_host_target_is_rejected(self) -> None:
        altered = copy.deepcopy(self.loads)
        altered["entries"][1]["services"][0]["id"] = altered["entries"][0]["services"][0]["id"]
        with self.assertRaisesRegex(ValueError, "EXP011_SERVICE_DRIFT"):
            validate(self.atlas, self.logistics, altered)

    def test_capacity_inflation_is_rejected(self) -> None:
        altered = copy.deepcopy(self.loads)
        altered["entries"][0]["capacity_pu"] = 999
        with self.assertRaisesRegex(ValueError, "EXP011_BOARD_OR_CAPACITY_INVALID"):
            validate(self.atlas, self.logistics, altered)

    def test_dependency_bypass_is_rejected(self) -> None:
        altered = copy.deepcopy(self.loads)
        altered["entries"][0]["services"][1]["requires"] = []
        with self.assertRaisesRegex(ValueError, "EXP011_SERVICE_DRIFT"):
            validate(self.atlas, self.logistics, altered)

    def test_deadline_never_becomes_an_impossible_gate(self) -> None:
        entry = self.loads["entries"][0]
        self.assertGreater(sum(s["dwell_ticks"] for s in entry["services"]),
                           entry["services"][0]["deadline_ticks"])
        replay_reference(entry)

    def test_windows_export_membership_is_required(self) -> None:
        with self.assertRaisesRegex(ValueError, "EXP011_WINDOWS_EXPORT_MISSING"):
            validate(self.atlas, self.logistics, self.loads, presets="")


if __name__ == "__main__":
    unittest.main()
