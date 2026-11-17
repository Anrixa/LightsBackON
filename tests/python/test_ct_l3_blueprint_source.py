"""Structural negative tests for original-source Hill Road C09–C12 authoring."""
from __future__ import annotations

import json
import shutil
import tempfile
import unittest
from pathlib import Path

from tools.check_ct_l3_blueprint_source import audit, ROOT, CONTRACT, SOURCE, TRACKER


class HillRoadBlueprintSourceGate(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="lbo-hill-gate-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        for rel in (SOURCE, TRACKER, CONTRACT / "grid.json",
                    CONTRACT / "mission.json", CONTRACT / "equipment.json"):
            path = self.root / rel
            path.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT / rel, path)

    def mutate(self, rel: Path, change):
        path = self.root / rel
        value = json.loads(path.read_text(encoding="utf-8"))
        change(value)
        path.write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8")

    def rejects(self, term):
        errors = audit(self.root)
        self.assertTrue(any(term in x for x in errors), f"{term!r} not found in {errors}")

    def test_exact_blueprint_passes(self):
        self.assertEqual([], audit(self.root))

    def test_reject_wrong_grid_capacity(self):
        self.mutate(CONTRACT / "grid.json",
                    lambda x: next(n for n in x["nodes"] if n["id"] == "GRID").update(capacity=24))
        self.rejects("grid.GRID.capacity")

    def test_reject_drifted_wind_warning(self):
        self.mutate(CONTRACT / "mission.json", lambda x: x["wind_window"].update(warning_ticks=700))
        self.rejects("mission.wind_window.warning_ticks")

    def test_reject_wind_return_removed(self):
        self.mutate(CONTRACT / "mission.json",
                    lambda x: x["fixed_ladders"].pop(1))
        self.rejects("mission.fixed_ladders")

    def test_reject_bonus_power_drift(self):
        self.mutate(CONTRACT / "grid.json",
                    lambda x: next(n for n in x["nodes"] if n["id"] == "WORK_LIGHT").update(demand=3))
        self.rejects("grid.work_light.demand")

    def test_reject_double_generator_socket(self):
        self.mutate(CONTRACT / "equipment.json",
                    lambda x: next(a for a in x["anchors"] if a["id"] == "PAD_SHELTER").update(
                        routes=["E_TEMP_WORK_LIGHT", "FAKE"]))
        self.rejects("equipment.PAD_SHELTER")

    def test_reject_false_c10_implementation_claim(self):
        self.mutate(TRACKER,
                    lambda x: next(c for c in x["episodes"] if c["contract_id"] == "C10").update(
                        status="CLOUD_VERIFIED"))
        self.rejects("C10: cannot mark unimplemented")

    def test_reject_false_physical_promotion(self):
        self.mutate(TRACKER, lambda x: x["episodes"][0].update(physical_release_status="DONE"))
        self.rejects("physical/release HOLD")

    def test_reject_c11_optional_window_drift(self):
        self.mutate(SOURCE,
                    lambda x: next(c for c in x["contracts"] if c["id"] == "C11")["optional"].update(
                        max_uninterrupted_telecom_outage_ticks=100))
        self.rejects("source.C11.optional")

    def test_missing_mission_file_fails_closed(self):
        (self.root / CONTRACT / "mission.json").unlink()
        self.rejects("unreadable or malformed JSON")


if __name__ == "__main__":
    unittest.main()
