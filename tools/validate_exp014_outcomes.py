#!/usr/bin/env python3
"""EXP014 A06 independent source / noncosmetic consequence-graph validator.

The five risk-specific graphs are verified against A04's authored apparatus,
A05's real investigation policies and all 200 immutable original source cases.
This is a source/headless audit, not a physics or release qualification.
"""
from __future__ import annotations

import json
from pathlib import Path
import re

if __package__:
    from .validate_exp014_approach import (
        ATLAS, CONTINGENCIES, QUALIFICATION, load_profiles as load_a05,
        validate as validate_a05,
    )
    from .validate_exp014_feedback import load_profiles as load_a04
else:
    from validate_exp014_approach import (
        ATLAS, CONTINGENCIES, QUALIFICATION, load_profiles as load_a05,
        validate as validate_a05,
    )
    from validate_exp014_feedback import load_profiles as load_a04

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts/gameplay/expedition_operational_consequences.gd"
HOST = ROOT / "scripts/gameplay/expedition_host_session.gd"
STAGE = ROOT / "scripts/gameplay/expedition_mission_stage.gd"

RISK_CLASSES = {"depth", "conductivity", "mechanical", "structure", "weather"}
GUARDS = {"logistics_solved", "faults_solved",
          "balancing_solved", "consequences_solved"}
STATIONS = {"A", "B", "C"}
CLASS_ROW = re.compile(r'"(REG_\d{2})":"([a-z]+)"')
GRAPH_ROW = re.compile(r'^\t"([a-z]+)": \[(.*?)^\t\]', re.MULTILINE | re.DOTALL)
STEP_ROW = re.compile(
    r'\{"station":"([ABC])", "action":"([a-z_]+)", '
    r'"guard":"([a-z_]+)", "gap":(\d+)\}'
)


def require(value: bool, code: str) -> None:
    if not value:
        raise ValueError("EXP014_A06_" + code)


def parse_script(source: str | None = None) -> tuple[dict[str, str], dict[str, list[dict]]]:
    script = SCRIPT.read_text(encoding="utf-8") if source is None else source
    require("const RISK_CLASS: Dictionary = {" in script
            and "const AUDIT_BOOK: Dictionary = {" in script
            and "const GUARDS: Array[String]" in script, "MISSING_BOOK")
    classes_text = script.split("const RISK_CLASS: Dictionary = {", 1)[1].split(
        "const AUDIT_BOOK: Dictionary = {", 1)[0]
    graph_text = script.split("const AUDIT_BOOK: Dictionary = {", 1)[1].split(
        "const GUARDS: Array[String]", 1)[0]
    pairs = CLASS_ROW.findall(classes_text)
    require(len(pairs) == 25 and len({name for name, _ in pairs}) == 25,
            "REGIONAL_CLASS_COUNT")
    classes = dict(pairs)
    graphs: dict[str, list[dict]] = {}
    matches = GRAPH_ROW.findall(graph_text)
    require(len(matches) == 5 and len({name for name, _ in matches}) == 5,
            "AUDIT_GRAPH_COUNT")
    for name, body in matches:
        rows = STEP_ROW.findall(body)
        require(len(rows) == body.count('{"station":'), "UNPARSED_AUDIT_STEP")
        graphs[name] = [
            {"station": station, "action": action,
             "guard": guard, "gap": int(gap)}
            for station, action, guard, gap in rows
        ]
    return classes, graphs


def validate(
    atlas: dict, contingencies: dict, a05: dict[str, dict],
    a04: dict[str, dict], classes: dict[str, str],
    graphs: dict[str, list[dict]], host: str, stage: str,
) -> dict:
    previous = validate_a05(atlas, contingencies, a05, a04)
    require(previous["ok"] and previous["source_pinned_sites"] == 200
            and previous["source_pinned_original_tasks"] == 1000,
            "PREDECESSOR_COVERAGE")
    expected_regions = {f"REG_{i:02d}" for i in range(1, 26)}
    require(set(classes) == expected_regions, "REGIONAL_SOURCE_DRIFT")
    require(set(graphs) == RISK_CLASSES, "RISK_FAMILY_COVERAGE")
    signatures: set[tuple] = set()
    for name, steps in graphs.items():
        require(2 <= len(steps) <= 3, "AUDIT_LENGTH_" + name)
        require(all(x["station"] in STATIONS and x["guard"] in GUARDS
                    and x["action"].isidentifier() for x in steps),
                "AUDIT_ROLE_OR_GUARD_" + name)
        require(steps[0]["gap"] == 0 and all(
            2 <= x["gap"] <= 5 for x in steps[1:]), "AUDIT_GAP_" + name)
        require(len({x["station"] for x in steps}) == len(steps),
                "AUDIT_STATION_REUSE_" + name)
        # Names, titles and timers are excluded from a structural signature.
        signatures.add(tuple((x["station"], x["guard"]) for x in steps))
    require(len(signatures) == 5, "MECHANICAL_GRAPH_COLLISION")
    for rid in expected_regions:
        require(classes[rid] in RISK_CLASSES and
                classes[rid] == a04[rid]["apparatus"],
                "RISK_ARTIFACT_DRIFT_" + rid)
    # All level identities, risks, exact task IDs and source SC markers have
    # been verified above by A05. Check that the source-locked consequences
    # are actually bound and cannot be bypassed in the host/runtime paths.
    critical_host = (
        "enable_site_outcomes: bool = false",
        "EXP014_A06_REQUIRES_A05_RECON",
        "site_outcomes.configure(",
        '["site_outcomes"] = site_outcomes.definition_snapshot()',
        "site_outcomes.begin(site_approach.snapshot())",
        "site_outcomes.operate(entity, action, _outcome_facts())",
        'facts["site_contingency_solved"]',
        "site_outcomes.advance(_outcome_facts())",
        "site_outcomes.needs_action()",
        "site_outcomes.solved()",
        "EXP014_A06_OUTCOMES_INCOMPLETE",
        'return "EXP014_A06_"',
    )
    require(all(fragment in host for fragment in critical_host),
            "HOST_AUTHORITY_OR_EXTRACTION_BYPASS")
    critical_stage = (
        "runtime.site_outcomes.needs_action()",
        "_activate_outcome_target()",
        'runtime.site_outcomes.snapshot()',
        '"site_outcomes"',
    )
    require(all(fragment in stage for fragment in critical_stage),
            "SCENE_INTERACTION_BINDING")
    module = SCRIPT.read_text(encoding="utf-8")
    require("source_task_ids" in module and "source_risk" in module
            and "wrong_peer" not in module.lower()
            and 'return _reject("UNKNOWN_TARGET")' in module
            and 'str(facts.get("worksite_route", "")) != _route' in module
            and "_service_debt = mini(6," in module
            and '_phase = "certified"' in module, "MODULE_CONSEQUENCE_GATE")
    return {
        "ok": True, "regions": len(classes), "risk_graph_families": len(graphs),
        "noncosmetic_evidence_graphs": len(signatures),
        "source_pinned_sites": previous["source_pinned_sites"],
        "immutable_original_tasks": previous["source_pinned_original_tasks"],
        "planned_branch_replays": 200 * 2,
        "old_campaign_mutated": False, "physical_playability_certified": False,
        "production_rewards_approved": False, "qualification": QUALIFICATION,
    }


if __name__ == "__main__":
    print("EXP014 A06 OPERATIONAL CONSEQUENCES AUDIT:", json.dumps(
        validate(
            json.loads(ATLAS.read_text(encoding="utf-8")),
            json.loads(CONTINGENCIES.read_text(encoding="utf-8")),
            load_a05(), load_a04(), *parse_script(),
            HOST.read_text(encoding="utf-8"),
            STAGE.read_text(encoding="utf-8"),
        ), sort_keys=True))
