"""Falsification tests for the Hill Road blueprint source gate."""
from __future__ import annotations

import json
import shutil
import tempfile
import unittest
from pathlib import Path

from tools.check_ct_l3_gate import ROOT, C09, C10, TRACK, audit


class CTL3Gate(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="lbo-ctl3-gate-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        for path in (TRACK, C09 / "grid.json", C09 / "mission.json",
                     C10 / "grid.json", C10 / "mission.json", C10 / "repairs.json"):
            dest = self.root / path
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT / path, dest)

    def mutate(self, path: Path, operation):
        target = self.root / path
        data = json.loads(target.read_text(encoding="utf-8"))
        operation(data)
        target.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")

    def rejects(self, text: str):
        defects = audit(self.root)
        self.assertTrue(any(text in row for row in defects), defects)

    def test_exact_source_accepted(self):
        self.assertEqual([], audit(self.root))

    def test_reject_C10_wrong_GRID(self):
        self.mutate(C10 / "grid.json", lambda j: next(n for n in j["nodes"] if n["id"] == "GRID").update(capacity=24))
        self.rejects("C10.grid.GRID.capacity")

    def test_reject_C10_uninstalled_spur_silently_enabled(self):
        self.mutate(C10 / "grid.json", lambda j: next(e for e in j["edges"] if e["id"] == "E_GRID_STAGE").update(enabled=True))
        self.rejects("C10.edges.E_GRID_STAGE.enabled")

    def test_reject_C10_spur_capacity_under_rated(self):
        self.mutate(C10 / "grid.json", lambda j: next(e for e in j["edges"] if e["id"] == "E_GRID_STAGE").update(capacity=3))
        self.rejects("C10.edges.E_GRID_STAGE.capacity")

    def test_reject_unsafe_west_stage_initially_connected(self):
        self.mutate(C10 / "grid.json", lambda j: next(n for n in j["nodes"] if n["id"] == "WEST_STAGE").update(isolated=False))
        self.rejects("C10.WEST_STAGE.isolated")

    def test_reject_stage_event_time_changed(self):
        self.mutate(C10 / "mission.json", lambda j: j["optional_timed_latch"].update(deadline_ticks=1800))
        self.rejects("C10.optional_timed_latch.deadline_ticks")

    def test_reject_stage_latch_shortcut(self):
        self.mutate(C10 / "mission.json", lambda j: j["access_latches"][0].update(supplied_ticks=80))
        self.rejects("C10.access_latches")

    def test_reject_fake_spur_install(self):
        self.mutate(C10 / "repairs.json", lambda j: next(x for x in j["repairs"] if x["id"] == "R_STAGE_SPUR")["fix"].update(id="E_GRID_WEST"))
        self.rejects("C10.stage_install.fix.id")

    def test_reject_original_C09_wind_drift(self):
        self.mutate(C09 / "mission.json", lambda j: j["wind_routes"].update(close_start_ticks=800))
        self.rejects("C09.wind_routes.close_start_ticks")

    def test_reject_C11_false_implementation(self):
        self.mutate(TRACK, lambda j: next(x for x in j["episodes"] if x["contract_id"] == "C11").update(status="CLOUD_VERIFIED"))
        self.rejects("C11: cannot claim")

    def test_reject_physical_claim(self):
        self.mutate(TRACK, lambda j: next(x for x in j["episodes"] if x["contract_id"] == "C10").update(physical_release_status="DONE"))
        self.rejects("C10.physical_release_status")

    def test_missing_content_fails_closed(self):
        (self.root / C10 / "mission.json").unlink()
        self.rejects("cannot load original-source data")


if __name__ == "__main__":
    unittest.main()
