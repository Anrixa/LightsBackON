"""RB03 (ADR-019) challenge format, solver, difficulty and pillar checks. Names follow the acceptance matrix where an ID
applies (SIM08 equality, SIM10 refused reset, SIM11 order independence, SIM12 access latch); RB03_* otherwise.
Python/GDScript byte parity is checked by tools/rb03_challenge_check.py (run_tests.sh, Godot section)."""
from __future__ import annotations

import copy
import json
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import lbo_challenge as L  # noqa: E402

RULES = L.load_rules()
DATA = L.ROOT / "tests" / "data" / "challenges"
CONTRACTS = sorted(d for d in (L.ROOT / "content" / "contracts").iterdir() if (d / "grid.json").is_file())


def fixture(name: str) -> dict:
    return json.loads((DATA / f"{name}.json").read_text(encoding="utf-8"))


def story(cid: str) -> dict:
    return L.from_contract(next(d for d in CONTRACTS if d.name.startswith(cid.lower() + "_")), RULES)


class Solved:
    """Solve each challenge once for the whole module."""
    cache: dict[str, tuple[dict, dict]] = {}

    @classmethod
    def get(cls, doc: dict) -> tuple[dict, dict]:
        key = doc["id"] + L.puzzle_hash(doc)  # tests mutate copies that keep their id
        if key not in cls.cache:
            sol = L.solve(doc, RULES)
            assert sol["status"] == "solved", (doc["id"], sol)
            cls.cache[key] = (sol, L.make_trace(doc, RULES, sol))
        return cls.cache[key]


class StoryContracts(unittest.TestCase):
    def test_RB03_solver_solves_c01_and_every_ct_contract(self) -> None:
        self.assertEqual(len(CONTRACTS), 12)
        for d in CONTRACTS:
            doc = L.from_contract(d, RULES)
            self.assertEqual(L.validate(doc), [], d.name)
            _sol, trace = Solved.get(doc)
            self.assertEqual(L.check_trace(doc, trace, RULES), [], d.name)

    def test_RB03_c01_solution_respects_the_generator_tradeoff(self) -> None:
        """Blueprint p.7: the generator runs the pump OR the pub, never both; the pub never has two energized routes."""
        doc = story("C01")
        _sol, trace = Solved.get(doc)
        routes = [s["edge"] for s in trace["steps"] if s["do"] == "route" and s["on"]]
        self.assertEqual(routes, ["E_TEMP_PUMP"])
        self.assertNotIn({"do": "switch", "id": "SW_SIGN", "value": True}, trace["steps"])
        an = L.analyse(doc, trace, RULES)
        self.assertIn(['{"do":"route","edge":"E_TEMP_PUB","id":"GEN_PORTABLE","on":true}', "OVERLOAD"],
                      [list(t) for t in an["failing_routes"]])
        self.assertTrue(an["temp_required"])
        self.assertEqual(an["pillar_failures"], [])

    def test_SIM12_c01_east_trunk_waits_for_the_latched_drain(self) -> None:
        doc = story("C01")
        run = L.Run(doc, RULES)
        self.assertEqual(run.do({"do": "repair", "id": "R_JE_TRUNK"}), "ACCESS_BLOCKED")
        for step in ({"do": "place", "id": "GEN_PORTABLE", "anchor": "PAD_PUMP"},
                     {"do": "route", "id": "GEN_PORTABLE", "edge": "E_TEMP_PUMP", "on": True},
                     {"do": "power", "id": "GEN_PORTABLE", "on": True},
                     {"do": "wait", "until": "latch", "id": "LATCH_PUMP_DRAIN"},
                     {"do": "power", "id": "GEN_PORTABLE", "on": False}):
            self.assertEqual(run.do(step), "ok", step)
        self.assertIn("PUMP_HOUSE_DRAINED", run.grants)  # latched: switching the pump off does not refill
        self.assertEqual(run.do({"do": "repair", "id": "R_JE_TRUNK"}), "ok")

    def test_RB03_c07_module_replacement_in_the_reference(self) -> None:
        doc = story("C07")
        run = L.Run(doc, RULES)
        bad = run.grid.apply({"op": "replace_module", "id": "E_GRID_JE", "capacity": 14})
        self.assertEqual(bad["code"], "MODULE_NOT_ISOLATED")
        self.assertEqual(run.do({"do": "repair", "id": "R_JE_MODULE"}), "ok")
        self.assertEqual(run.grid.edges["E_GRID_JE"]["capacity"], 14)


class Replay(unittest.TestCase):
    def test_RB03_golden_storm_trace_replays_at_every_crew_size(self) -> None:
        doc = fixture("rb03_storm_shift")
        trace = json.loads((DATA / "traces" / "rb03_storm_shift.trace.json").read_text(encoding="utf-8"))
        self.assertEqual(L.check_trace(doc, trace, RULES), [])
        for crew in L.CREWS:
            run, _ = L.replay(doc, trace, RULES, crew)
            self.assertEqual(run.canonical_hash(), trace["final_hash"][crew], crew)
        solo = trace["solved_ticks"]
        self.assertTrue(solo["1"] >= solo["2"] >= solo["3"] >= solo["4"])  # more hands, never slower, same answer

    def test_SIM10_probe_refusals_and_refused_reset(self) -> None:
        doc = fixture("rb03_storm_shift")
        probe = json.loads((DATA / "probes" / "rb03_storm_shift.probe.json").read_text(encoding="utf-8"))
        self.assertEqual(L.check_trace(doc, probe, RULES), [])
        codes = {s.get("expect", "ok") for s in probe["steps"]}
        self.assertTrue({"RESET_OVERLOADED", "WAIT_TIMEOUT", "ROUTE_NOT_AT_ANCHOR", "ACCESS_BLOCKED", "BAD_STEP"} <= codes)

    def test_SIM11_reversed_record_order_gives_identical_hashes(self) -> None:
        doc = fixture("rb03_storm_shift")
        trace = json.loads((DATA / "traces" / "rb03_storm_shift.trace.json").read_text(encoding="utf-8"))
        rev = copy.deepcopy(doc)
        for key in ("nodes", "edges", "protections"):
            rev["grid"][key].reverse()
        for key in ("faults", "switches", "latches", "access_routes", "flood_areas", "storm_events", "temporary_supply"):
            rev[key].reverse()
        for t in rev["temporary_supply"]:
            t["anchors"].reverse()
        for crew in L.CREWS:
            self.assertEqual(L.replay(doc, trace, RULES, crew)[1], L.replay(rev, trace, RULES, crew)[1], crew)

    def test_SIM08_generator_at_exact_capacity_is_not_a_trap(self) -> None:
        """C11: the 6 PU generator on a 6 PU load is allowed (equality is not overload)."""
        doc = copy.deepcopy(fixture("rb03_storm_shift"))
        for n in doc["grid"]["nodes"]:
            if n["id"] == "PUMP":
                n["demand"] = 6
        for e in doc["grid"]["edges"]:
            if e["id"] == "E_TEMP_PUMP":
                e["capacity"] = 6
        run = L.Run(doc, RULES)
        for step in ({"do": "place", "id": "GEN_PORTABLE", "anchor": "PAD_YARD"},
                     {"do": "route", "id": "GEN_PORTABLE", "edge": "E_TEMP_PUMP", "on": True},
                     {"do": "power", "id": "GEN_PORTABLE", "on": True}, {"do": "wait", "ticks": 30}):
            self.assertEqual(run.do(step), "ok")
        self.assertFalse(run.overloaded_any())
        self.assertFalse(run.grid.nodes["TEMP"]["tripped"])


class Pillars(unittest.TestCase):
    def analyse(self, doc: dict) -> dict:
        _sol, trace = Solved.get(doc)
        return L.analyse(doc, trace, RULES)

    def test_RB03_pillar_rejects_a_marker_only_challenge(self) -> None:
        doc = fixture("rb03_marker_only")
        self.assertTrue(L.marker_policy_solves(doc, RULES))
        self.assertEqual(self.analyse(doc)["pillar_failures"], ["MARKER_ONLY"])

    def test_RB03_pillar_rejects_a_challenge_without_a_tradeoff(self) -> None:
        doc = fixture("rb03_no_tradeoff")
        an = self.analyse(doc)
        self.assertTrue(an["temp_required"])
        self.assertEqual(an["pillar_failures"], ["NO_TRADEOFF"])

    def test_RB03_pillar_rejects_a_challenge_that_needs_no_generator(self) -> None:
        doc = story("C04")  # the generator never matters: solvable without temporary supply
        self.assertIn("NO_TRADEOFF", self.analyse(doc)["pillar_failures"])

    def test_RB03_pillar_rejects_a_challenge_that_starts_lit(self) -> None:
        doc = copy.deepcopy(fixture("rb03_marker_only"))
        doc["faults"] = []
        for n in doc["grid"]["nodes"]:
            if n["kind"] == "junction":
                n["failed"] = n["tripped"] = False
        self.assertIn("NO_VISIBLE_RECOVERY", self.analyse(doc)["pillar_failures"])

    def test_RB03_storm_fixture_passes_every_pillar(self) -> None:
        self.assertEqual(self.analyse(fixture("rb03_storm_shift"))["pillar_failures"], [])


class Difficulty(unittest.TestCase):
    def test_RB03_score_and_tier_come_from_the_solution(self) -> None:
        storm, c01 = fixture("rb03_storm_shift"), story("C01")
        a = L.analyse(storm, Solved.get(storm)[1], RULES)
        b = L.analyse(c01, Solved.get(c01)[1], RULES)
        self.assertEqual(a["metrics"]["time_pressure"], 3)  # three storm events before the finish
        w = RULES["score_weights"]
        self.assertEqual(a["score"], sum(w[k] * a["metrics"][k] for k in w))
        self.assertGreater(a["tier"], b["tier"])
        lows = RULES["tier_min_scores"]
        self.assertEqual(lows, sorted(lows))
        self.assertEqual(len(lows), 5)

    def test_RB03_duplicate_and_near_duplicate_hashes(self) -> None:
        base = fixture("rb03_storm_shift")
        renamed = copy.deepcopy(base)
        renamed["id"] = "RB03_STORM_SHIFT_COPY"
        retuned = copy.deepcopy(base)
        retuned["id"] = "RB03_STORM_SHIFT_RETUNED"
        for n in retuned["grid"]["nodes"]:
            if n["id"] == "GRID":
                n["capacity"] = 32  # a different number, the same puzzle
        other = fixture("rb03_no_tradeoff")
        an = {d["id"]: L.analyse(d, Solved.get(d)[1], RULES) for d in (base, renamed, retuned, other)}
        self.assertEqual(an[base["id"]]["puzzle_hash"], an[renamed["id"]]["puzzle_hash"])
        self.assertNotEqual(an[base["id"]]["puzzle_hash"], an[retuned["id"]]["puzzle_hash"])
        self.assertEqual(an[base["id"]]["near_duplicate_hash"], an[retuned["id"]]["near_duplicate_hash"])
        dups = L.near_duplicates(an)
        self.assertEqual(sorted(r for _k, r, _w in dups), ["RB03_STORM_SHIFT_COPY", "RB03_STORM_SHIFT_RETUNED"])
        self.assertNotIn(other["id"], [r for _k, r, _w in dups])


class Schema(unittest.TestCase):
    def codes(self, doc: dict) -> set[str]:
        return {d["code"] for d in L.validate(doc)}

    def test_RB03_schema_accepts_fixtures_and_story_contracts(self) -> None:
        for name in ("rb03_marker_only", "rb03_no_tradeoff", "rb03_storm_shift"):
            self.assertEqual(L.validate(fixture(name)), [], name)

    def test_RB03_schema_rejects_bad_records(self) -> None:
        base = fixture("rb03_storm_shift")
        cases = {
            "BAD_SCHEMA": lambda d: d.update(schema=2),
            "INVALID_ID": lambda d: d.update(location_id="alder street"),
            "BAD_VALUE": lambda d: d.update(verification_ticks=0),
            "BAD_FAULT": lambda d: d["faults"][0]["fix"].update(field="capacity"),
            "BAD_SWITCH": lambda d: d["switches"].append({"id": "SW_X", "target": "GRID", "field": "online"}),
            "BAD_TEMPORARY_SUPPLY": lambda d: d["temporary_supply"][0].update(start_anchor="PAD_YARD"),
            "BAD_STORM_EVENT": lambda d: d["storm_events"][2]["cmd"].update(value=True),
            "BAD_CREW": lambda d: d["crew_scaling"].update({"4": 120}),
            "BAD_LATCH": lambda d: d["latches"][0].update(supplied_ticks=0),
            "DUPLICATE_ID": lambda d: d["switches"].append({"id": "R_JW_FUSE", "target": "SIGN", "field": "enabled"}),
            "CYCLE": lambda d: d["grid"]["edges"].append({"id": "E_LOOP", "from": "JE", "to": "JW", "capacity": 1,
                                                          "enabled": False, "healthy": True})
                                 or d["grid"]["edges"].append({"id": "E_LOOP2", "from": "JW", "to": "JE", "capacity": 1,
                                                               "enabled": False, "healthy": True}),
        }
        for code, mutate in cases.items():
            doc = copy.deepcopy(base)
            mutate(doc)
            self.assertIn(code, self.codes(doc), code)

    def test_RB03_floats_are_not_pu(self) -> None:
        doc = copy.deepcopy(fixture("rb03_storm_shift"))
        doc["grid"]["nodes"][0]["capacity"] = 30.0
        self.assertIn("BAD_VALUE", self.codes(doc))


class Solver(unittest.TestCase):
    def test_RB03_a_capped_search_is_never_read_as_unsolvable(self) -> None:
        rules = copy.deepcopy(RULES)
        rules["solver"]["max_states"] = 3
        self.assertEqual(L.solve(story("C01"), rules)["status"], "limit")
        self.assertEqual(L.solve(story("C01"), RULES, with_temp=False)["status"], "unsolvable")


if __name__ == "__main__":
    unittest.main()
