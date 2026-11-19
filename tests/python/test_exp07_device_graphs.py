"""EXP07 source-graph mutation, reachability and export regression tests."""
from __future__ import annotations

import copy
import unittest
from pathlib import Path

from tools.validate_exp07_device_graphs import load_inputs, validate, replay_reference, ROOT


class ExpeditionDeviceGraphTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.atlas, cls.encounters, cls.book = load_inputs()

    def test_200_source_pinned_graphs_1100_devices_and_reference_replays(self) -> None:
        outcome = validate(self.atlas, self.encounters, self.book)
        self.assertTrue(outcome["ok"])
        self.assertEqual(outcome["levels"], 200)
        self.assertEqual(outcome["devices"], 1100)
        self.assertEqual(outcome["five_node_graphs"], 100)
        self.assertEqual(outcome["six_node_graphs"], 100)
        self.assertGreaterEqual(outcome["operations"], 20)

    def test_each_level_has_unique_actual_device_graph_and_valid_recovery(self) -> None:
        keys = set()
        for entry in self.book["entries"]:
            self.assertNotIn(entry["graph_key"], keys)
            keys.add(entry["graph_key"])
            self.assertEqual(len([n for n in entry["nodes"] if n["jam_on_early"]]), 1)
            replay_reference(entry)

    def test_foreign_source_identity_is_rejected(self) -> None:
        altered = copy.deepcopy(self.book)
        altered["entries"][0]["source_puzzle_identity"] = "forged-other-level"
        with self.assertRaisesRegex(ValueError, "SOURCE_DRIFT"):
            validate(self.atlas, self.encounters, altered)

    def test_cyclic_graph_and_missing_predecessor_are_rejected(self) -> None:
        altered = copy.deepcopy(self.book)
        altered["entries"][0]["nodes"][1]["depends_on"] = ["DV_001_E"]
        with self.assertRaisesRegex(ValueError, "CYCLIC_OR_MISSING_PREDECESSOR"):
            validate(self.atlas, self.encounters, altered)

    def test_invalid_recovery_and_missing_host_evidence_are_rejected(self) -> None:
        altered = copy.deepcopy(self.book)
        altered["entries"][0]["nodes"][2]["recovery_after"] = "DV_001_E"
        with self.assertRaisesRegex(ValueError, "BROKEN_RECOVERY"):
            validate(self.atlas, self.encounters, altered)
        altered = copy.deepcopy(self.book)
        altered["entries"][0]["nodes"][-1]["requires"] = "none"
        with self.assertRaisesRegex(ValueError, "HOST_EVIDENCE_GUARD_MISSING"):
            validate(self.atlas, self.encounters, altered)

    def test_duplicate_device_ids_and_forged_action_denied(self) -> None:
        altered = copy.deepcopy(self.book)
        altered["entries"][0]["nodes"][1]["id"] = "DV_001_A"
        with self.assertRaisesRegex(ValueError, "INVALID_NODE_PROPERTIES"):
            validate(self.atlas, self.encounters, altered)
        altered = copy.deepcopy(self.book)
        altered["entries"][0]["nodes"][0]["action"] = "grant_points"
        with self.assertRaisesRegex(ValueError, "INVALID_NODE_PROPERTIES"):
            validate(self.atlas, self.encounters, altered)

    def test_both_windows_exports_include_exp06_and_exp07_json(self) -> None:
        export = (ROOT / "export_presets.cfg").read_text(encoding="utf-8")
        for filename in ("bespoke_encounters.json", "bespoke_device_graphs.json"):
            self.assertEqual(export.count("scenes/expeditions/" + filename), 2)
        self.assertEqual(export.count("scenes/expeditions/atlas.json"), 2)

    def test_original_content_and_credits_not_modified_in_exp07_source(self) -> None:
        script = (ROOT / "scripts/gameplay/expedition_device_graph.gd").read_text(encoding="utf-8")
        self.assertNotIn("reward_service.gd", script)
        self.assertNotIn("save_service.gd", script)
        self.assertNotIn("grid.apply(", script)


if __name__ == "__main__":
    unittest.main()
