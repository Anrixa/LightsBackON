"""Negative and positive checks for the C02-C06 source-fidelity drift guard."""
from __future__ import annotations

import json
import shutil
import tempfile
import unittest
from pathlib import Path

from tools.check_ct_blueprint_gate import CONTRACT_DIRS, ROOT, audit


class BlueprintSourceGateTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory(prefix="lbo-ct-bp-gate-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        files = [
            "docs/design/CT-BP-SOURCE-GATE.json",
            "docs/design/CT-BLUEPRINT-CORRECTIONS.json",
        ]
        for folder in CONTRACT_DIRS.values():
            files.extend([
                f"content/contracts/{folder}/grid.json",
                f"content/contracts/{folder}/mission.json",
            ])
        for relative in files:
            dest = self.root / relative
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT / relative, dest)

    def change(self, relative: str, mutate) -> None:
        path = self.root / relative
        data = json.loads(path.read_text(encoding="utf-8"))
        mutate(data)
        path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")

    def assert_rejected(self, expected_fragment: str) -> None:
        self.assertTrue(any(expected_fragment in e for e in audit(self.root)),
                        f"Expected failure mentioning {expected_fragment!r}")

    def test_source_and_receipts_pass(self) -> None:
        self.assertEqual([], audit(self.root))

    def test_reject_generator_capacity_regression(self) -> None:
        self.change("content/contracts/c06_cold_chain/grid.json",
                    lambda d: next(n for n in d["nodes"] if n["id"] == "GEN").update(capacity=6))
        self.assert_rejected("C06.nodes.GEN.capacity")

    def test_reject_cumulative_outage_replaced_with_deadline(self) -> None:
        self.change("content/contracts/c06_cold_chain/mission.json",
                    lambda d: d.pop("optional_cumulative_outage"))
        self.assert_rejected("C06.mission.optional_cumulative_outage")

    def test_reject_wrong_c02_venue_pair(self) -> None:
        self.change("content/contracts/c02_dinner_rush/mission.json",
                    lambda d: d["opening_venues"].update(consumers=["MARKET"]))
        self.assert_rejected("C02.mission.opening_venues.consumers")

    def test_reject_false_physical_certification(self) -> None:
        self.change("docs/design/CT-BLUEPRINT-CORRECTIONS.json",
                    lambda d: d["contracts"][4].update(full_original_blueprint_certification="DONE"))
        self.assert_rejected("physical original-blueprint certification")

    def test_reject_disconnected_ci_evidence(self) -> None:
        self.change("docs/design/CT-BLUEPRINT-CORRECTIONS.json",
                    lambda d: d["contracts"][3].update(post_merge_ci_run="https://example.invalid/ci"))
        self.assert_rejected("C05.tracker.post_merge_ci_run")

    def test_reject_duplicate_feeder_id(self) -> None:
        self.change("content/contracts/c05_canal_pump_access/grid.json",
                    lambda d: d["edges"].append(dict(d["edges"][0])))
        self.assert_rejected("C05.edges: duplicate ID")

    def test_missing_file_fails_closed(self) -> None:
        (self.root / "content/contracts/c04_whole_block/mission.json").unlink()
        self.assert_rejected("cannot load JSON")


if __name__ == "__main__":
    unittest.main()
