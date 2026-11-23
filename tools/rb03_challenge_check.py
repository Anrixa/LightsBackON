#!/usr/bin/env python3
"""RB03 (ADR-019): solve, score, pillar-check and cross-check challenges.

    python tools/rb03_challenge_check.py [--godot PATH] [--python-only] [--report build/rb03/report.json]

1. Builds the challenge-format view of every story contract (content/contracts/c*) and loads the challenge fixtures in
   tests/data/challenges/ (and any shipped challenges under content/challenges/<location>/).
2. Validates each, solves it with the Python reference solver (reference/lbo_challenge.py), hardens the trace for crews
   of 1-4 and checks it replays at every crew size.
3. Measures difficulty (steps, tradeoffs, failing routes, meter readings, time pressure -> score -> tier 1-5), runs the
   pillar checks and the duplicate hashes.
4. Unless --python-only: writes each challenge and trace to build/rb03/, replays them in Godot through
   tools/godot/validate_solution.gd (scripts/simulation/challenge_runner.gd) and compares every step record and the
   final canonical string with the Python replay, byte for byte. Probe traces in tests/data/challenges/probes/ (refusals,
   trips, timeouts, malformed steps; must_solve false) are replayed the same way.

Expectations it enforces (exit 1 otherwise):
- every story contract and fixture is valid, solved, and replays at crews 1-4;
- fixtures named *_marker_only fail exactly MARKER_ONLY, *_no_tradeoff exactly NO_TRADEOFF, every other fixture and
  every shipped challenge passes all pillars; shipped challenges carry par_ticks equal to the measured ones;
- no two shipped challenges share a puzzle or near-duplicate hash;
- Python and Godot agree on every record.
Story contracts are tutorials and are pinned by their own content; their pillar results are reported, not enforced.
Exit 0 = all good, 1 = a check failed, 2 = could not run.
"""
from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "reference"))

import lbo_challenge as L  # noqa: E402

FIXTURES = ROOT / "tests" / "data" / "challenges"
SHIPPED = ROOT / "content" / "challenges"
OUT = ROOT / "build" / "rb03"


def collect(rules: dict) -> list[tuple[str, dict]]:
    """[(kind, challenge)] with kind story | fixture | shipped, in a stable order."""
    out: list[tuple[str, dict]] = []
    for d in sorted((ROOT / "content" / "contracts").iterdir()):
        if (d / "grid.json").is_file():
            out.append(("story", L.from_contract(d, rules)))
    for p in sorted(FIXTURES.glob("*.json")):
        out.append(("fixture", json.loads(p.read_text(encoding="utf-8"))))
    for p in sorted(SHIPPED.glob("*/*.json")):
        if not p.name.endswith(".trace.json"):
            out.append(("shipped", json.loads(p.read_text(encoding="utf-8"))))
    return out


def python_records(doc: dict, trace: dict, rules: dict) -> list[list[str]]:
    recs: list[list[str]] = []
    for crew in L.CREWS:
        run, steps = L.replay(doc, trace, rules, crew)
        recs += [["STEP", doc["id"], crew] + r for r in steps]
        recs.append(["FINAL", doc["id"], crew, str(run.solved_tick), run.canonical_hash(), run.canonical_string()])
    return recs


def godot_records(godot: str, pairs: list[dict]) -> tuple[int, list[list[str]], str]:
    manifest = OUT / "manifest.json"
    manifest.write_text(json.dumps(pairs, indent=1), encoding="utf-8")
    script = str(ROOT / "tools" / "godot" / "validate_solution.gd")
    p = subprocess.run([godot, "--headless", "--path", str(ROOT), "-s", script, "--", f"--manifest={manifest.as_posix()}"],
                       capture_output=True, text=True, encoding="utf-8", errors="replace")
    recs = [line.split("\t") for line in p.stdout.splitlines() if line.split("\t")[0] in ("STEP", "FINAL")]
    return p.returncode, recs, p.stdout + p.stderr


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--godot", default=os.environ.get("GODOT_BIN") or shutil.which("godot"))
    ap.add_argument("--python-only", action="store_true")
    ap.add_argument("--report", default=str(OUT / "report.json"))
    a = ap.parse_args()
    rules = L.load_rules()
    OUT.mkdir(parents=True, exist_ok=True)
    failures: list[str] = []
    report: dict = {"challenges": {}}
    pairs: list[dict] = []
    py: list[list[str]] = []
    shipped: dict[str, dict] = {}
    for kind, doc in collect(rules):
        cid = doc.get("id", "?")
        errs = L.validate(doc)
        if errs:
            failures.append(f"{cid}: invalid: {errs}")
            continue
        sol = L.solve(doc, rules)
        if sol["status"] != "solved":
            failures.append(f"{cid}: solver {sol['status']} after {sol['states']} states")
            continue
        trace = L.make_trace(doc, rules, sol)
        mism = L.check_trace(doc, trace, rules)
        failures += [f"{cid}: {m}" for m in mism]
        an = L.analyse(doc, trace, rules)
        par = L.par_ticks(trace, rules)
        pillars = an["pillar_failures"]
        if kind == "fixture" and cid.endswith("_MARKER_ONLY") and pillars != ["MARKER_ONLY"]:
            failures.append(f"{cid}: expected pillar failures ['MARKER_ONLY'], got {pillars}")
        elif kind == "fixture" and cid.endswith("_NO_TRADEOFF") and pillars != ["NO_TRADEOFF"]:
            failures.append(f"{cid}: expected pillar failures ['NO_TRADEOFF'], got {pillars}")
        elif kind in ("fixture", "shipped") and not cid.endswith(("_MARKER_ONLY", "_NO_TRADEOFF")) and pillars:
            failures.append(f"{cid}: fails pillars {pillars}")
        if kind == "shipped":
            shipped[cid] = an
            if doc.get("par_ticks") != par:
                failures.append(f"{cid}: par_ticks {doc.get('par_ticks')} differ from measured {par}")
        report["challenges"][cid] = {"kind": kind, "solved_ticks": trace["solved_ticks"], "par_ticks": par,
                                     "search_states": sol["states"], "steps": trace["steps"], **an}
        cpath, tpath = OUT / f"{cid}.challenge.json", OUT / f"{cid}.trace.json"
        cpath.write_text(json.dumps(doc, indent=1), encoding="utf-8")
        tpath.write_text(json.dumps(trace, indent=1), encoding="utf-8")
        pairs.append({"challenge": cpath.as_posix(), "trace": tpath.as_posix()})
        py += python_records(doc, trace, rules)
        m = an["metrics"]
        print(f"{cid:22} {kind:8} ticks {trace['solved_ticks']['1']:>4}/{trace['solved_ticks']['4']:>4} "
              f"steps {m['steps']:>2} trade {m['tradeoffs']} fail {m['failing_routes']} meter {m['meter_readings']} "
              f"time {m['time_pressure']} score {an['score']:>3} tier {an['tier']} pillars {','.join(pillars) or 'pass'}")
    docs = {doc.get("id"): doc for _k, doc in collect(rules)}
    for p in sorted((FIXTURES / "probes").glob("*.probe.json")):
        probe = json.loads(p.read_text(encoding="utf-8"))
        doc = docs.get(probe.get("challenge_id"))
        if doc is None:
            failures.append(f"{p.name}: unknown challenge {probe.get('challenge_id')}")
            continue
        failures += [f"{p.name}: {m}" for m in L.check_trace(doc, probe, rules)]
        pairs.append({"challenge": (OUT / f"{doc['id']}.challenge.json").as_posix(), "trace": p.as_posix()})
        py += python_records(doc, probe, rules)
        print(f"{p.name:38} probe    {len(probe['steps'])} steps, expected outcomes checked at crews 1-4")
    for kept, rejected, why in L.near_duplicates(shipped):
        failures.append(f"{rejected}: {why} duplicates {kept}")
    report["near_duplicates_among_shipped"] = L.near_duplicates(shipped)
    if not a.python_only:
        if not a.godot:
            print("cannot run: no Godot binary (set GODOT_BIN, pass --godot, or use --python-only)", file=sys.stderr)
            return 2
        code, gd, log = godot_records(a.godot, pairs)
        if code == 2 or not gd:
            print(log, file=sys.stderr)
            return 2
        if code != 0:
            failures.append(f"godot replay exit {code}")
        if len(py) != len(gd):
            failures.append(f"python emitted {len(py)} records, godot {len(gd)}")
        for i, (x, y) in enumerate(zip(py, gd)):
            if x != y:
                failures.append(f"MISMATCH at record {i}:\n  python: {x}\n  godot:  {y}")
                break
        else:
            if len(py) == len(gd):
                finals = sum(1 for r in py if r[0] == "FINAL")
                print(f"MATCH: {len(py) - finals} step hashes and {finals} final canonical strings identical in Python and Godot "
                      f"({len(pairs)} challenges x crews 1-4)")
        report["parity_records"] = len(py)
    Path(a.report).parent.mkdir(parents=True, exist_ok=True)
    Path(a.report).write_text(json.dumps(report, indent=1), encoding="utf-8")
    for f in failures:
        print("FAIL " + f)
    print(f"RB03 challenge check: {len(report['challenges'])} challenges, {len(failures)} failures")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
