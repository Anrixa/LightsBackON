"""Fail-closed falsification tests for C09–C12 original Hill Road source gate."""
from __future__ import annotations

import json
import shutil
import tempfile
import unittest
from pathlib import Path

from tools.check_ct_l3_gate import ROOT, C09, C10, C11, C12, TRACK, CONTRACTS, audit


class CTL3Gate(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="lbo-ctl3-closeout-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        members = [TRACK]
        for directory in CONTRACTS.values():
            members.extend(directory / f"{name}.json"
                           for name in ("grid", "mission", "repairs", "solution"))
        for path in members:
            destination = self.root / path
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT / path, destination)

    def mutate(self, path: Path, op):
        target = self.root / path
        data = json.loads(target.read_text(encoding="utf-8"))
        op(data)
        target.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")

    def rejects(self, expected: str):
        defects = audit(self.root)
        self.assertTrue(any(expected in msg for msg in defects), defects)

    def update_node(self, contract: Path, name: str, **fields):
        self.mutate(contract / "grid.json", lambda d:
                    next(n for n in d["nodes"] if n["id"] == name).update(fields))

    def update_edge(self, contract: Path, name: str, **fields):
        self.mutate(contract / "grid.json", lambda d:
                    next(e for e in d["edges"] if e["id"] == name).update(fields))

    def test_exact_source_accepted(self):
        self.assertEqual([], audit(self.root))

    def test_reject_C10_wrong_GRID(self):
        self.update_node(C10, "GRID", capacity=24)
        self.rejects("C10.grid.GRID.capacity")

    def test_reject_C10_uninstalled_spur_silently_enabled(self):
        self.update_edge(C10, "E_GRID_STAGE", enabled=True)
        self.rejects("C10.edges.E_GRID_STAGE.enabled")

    def test_reject_C10_spur_capacity_under_rated(self):
        self.update_edge(C10, "E_GRID_STAGE", capacity=3)
        self.rejects("C10.edges.E_GRID_STAGE.capacity")

    def test_reject_unsafe_west_stage_initially_connected(self):
        self.update_node(C10, "WEST_STAGE", isolated=False)
        self.rejects("C10.WEST_STAGE.isolated")

    def test_reject_stage_event_time_changed(self):
        self.mutate(C10 / "mission.json", lambda d:
                    d["optional_timed_latch"].update(deadline_ticks=1800))
        self.rejects("C10.optional_timed_latch.deadline_ticks")

    def test_reject_stage_latch_shortcut(self):
        self.mutate(C10 / "mission.json", lambda d:
                    d["access_latches"][0].update(supplied_ticks=80))
        self.rejects("C10.access_latches")

    def test_reject_fake_spur_install(self):
        self.mutate(C10 / "repairs.json", lambda d:
                    next(x for x in d["repairs"] if x["id"] == "R_STAGE_SPUR")
                    ["fix"].update(id="E_GRID_WEST"))
        self.rejects("C10.stage_install.fix.id")

    def test_reject_original_C09_wind_drift(self):
        self.mutate(C09 / "mission.json", lambda d:
                    d["wind_routes"].update(close_start_ticks=800))
        self.rejects("C09.wind_routes.close_start_ticks")

    def test_reject_C11_false_implementation(self):
        self.mutate(TRACK, lambda d:
                    next(x for x in d["episodes"] if x["contract_id"] == "C11")
                    .update(status="CLOUD_VERIFIED"))
        self.rejects("C11.tracker.status")

    def test_reject_physical_claim(self):
        self.mutate(TRACK, lambda d:
                    next(x for x in d["episodes"] if x["contract_id"] == "C10")
                    .update(physical_release_status="DONE"))
        self.rejects("C10.physical_release_status")

    def test_missing_content_fails_closed(self):
        (self.root / C10 / "mission.json").unlink()
        self.rejects("cannot load original-source data")

    def test_reject_C11_generator_overload_authority(self):
        self.update_node(C11, "GEN", capacity=8)
        self.rejects("C11.grid.GEN.capacity")

    def test_reject_C11_unsafe_west_telecom_initial_route(self):
        self.update_edge(C11, "E_WEST_TELECOM", enabled=True)
        self.rejects("C11.edges.E_WEST_TELECOM.enabled")

    def test_reject_C11_different_50_tick_bonus(self):
        self.mutate(C11 / "mission.json", lambda d:
                    d["optional_max_consecutive_outage"].update(max_outage_ticks=51))
        self.rejects("C11.optional_max_consecutive_outage.max_outage_ticks")

    def test_reject_C11_telecom_to_wrong_source(self):
        self.update_edge(C11, "E_TEMP_TELECOM", to="BAKERY")
        self.rejects("C11.edges.E_TEMP_TELECOM.to")

    def test_reject_C11_premature_east_access(self):
        self.mutate(C11 / "repairs.json", lambda d:
                    next(x for x in d["repairs"] if x["id"] == "R_EAST_TRUNK")
                    .update(access="NONE"))
        self.rejects("C11.east_repair.access")

    def test_reject_C12_wrong_drain_duration(self):
        self.mutate(C12 / "mission.json", lambda d:
                    d["access_latches"][0].update(supplied_ticks=100))
        self.rejects("C12.access_latches")

    def test_reject_C12_uninstalled_beacon_connected(self):
        self.update_edge(C12, "E_GRID_BEACON", enabled=True)
        self.rejects("C12.edges.E_GRID_BEACON.enabled")

    def test_reject_C12_wrong_beacon_spur_capacity(self):
        self.update_edge(C12, "E_GRID_BEACON", capacity=3)
        self.rejects("C12.edges.E_GRID_BEACON.capacity")

    def test_reject_C12_west_beacon_unisolated(self):
        self.update_node(C12, "WEST_BEACON", isolated=False)
        self.rejects("C12.WEST_BEACON.isolated")

    def test_reject_C12_event_stagger_forgery(self):
        self.mutate(C12 / "mission.json", lambda d:
                    d["finale"].update(stagger_ticks=21))
        self.rejects("C12.finale.stagger_ticks")

    def test_reject_C12_endless_game_instead_of_replay(self):
        self.mutate(C12 / "mission.json", lambda d:
                    d["finale"].update(results_actions=["endless_game"]))
        self.rejects("C12.finale.results_actions")

    def test_reject_C12_false_drain_access(self):
        self.mutate(C12 / "repairs.json", lambda d:
                    next(x for x in d["repairs"] if x["id"] == "R_EAST_TRUNK")
                    .update(access="NONE"))
        self.rejects("C12.east_repair.access")

    def test_reject_C12_wrong_beacon_install(self):
        self.mutate(C12 / "repairs.json", lambda d:
                    next(x for x in d["repairs"] if x["id"] == "R_BEACON_SPUR")
                    ["fix"].update(id="E_GRID_WEST"))
        self.rejects("C12.beacon_install.fix.id")

    def test_reject_missing_C12_solution(self):
        (self.root / C12 / "solution.json").unlink()
        self.rejects("cannot load original-source data")

    def test_reject_duplicate_C12_node(self):
        self.mutate(C12 / "grid.json", lambda d:
                    d["nodes"].append(dict(d["nodes"][0])))
        self.rejects("C12.nodes: duplicate ID")

    def test_reject_duplicate_tracker_episode(self):
        self.mutate(TRACK, lambda d:
                    d["episodes"].append(dict(d["episodes"][0])))
        self.rejects("CT-L3.episodes: duplicate ID")


if __name__ == "__main__":
    unittest.main()
