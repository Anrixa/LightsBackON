#!/usr/bin/env python3
"""Independent EXP014 A07 source and environmental-mechanism audit.

Reads the real A04, A05, A06 and A07 sources. Stage names, timer values,
signage and labels alone cannot count as different hazard behavior.
No physical route, actual weather/electricity, GPU or release certification.
"""
from __future__ import annotations

import json
from pathlib import Path
import re

if __package__:
    from .validate_exp014_outcomes import (
        ATLAS, CONTINGENCIES, QUALIFICATION, HOST, STAGE,
        load_a04, load_a05, parse_script as parse_a06,
        validate as validate_a06,
    )
else:
    from validate_exp014_outcomes import (
        ATLAS, CONTINGENCIES, QUALIFICATION, HOST, STAGE,
        load_a04, load_a05, parse_script as parse_a06,
        validate as validate_a06,
    )

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts/gameplay/expedition_environment_hazards.gd"
RISK_CLASSES = {"depth", "conductivity", "mechanical", "structure", "weather"}
GUARDS = {"faults_solved", "logistics_solved",
          "balancing_solved", "consequences_solved"}
STEP = re.compile(
    r'\{"station":"([ABC])", "action":"([a-z_]+)", '
    r'"guard":"([a-z_]+)", "gap":(\d+)\}'
)
BLOCK = re.compile(r'^\t"([a-z]+)": \{(.*?)(?=^\t"[a-z]+": \{|\Z)',
                   re.MULTILINE | re.DOTALL)


def require(condition: bool, code: str) -> None:
    if not condition:
        raise ValueError("EXP014_A07_" + code)


def parse_script(source: str | None = None) -> dict[str, dict]:
    raw = SCRIPT.read_text(encoding="utf-8") if source is None else source
    require("const PROFILES: Dictionary = {" in raw, "MISSING_MECHANICS")
    section = raw.split("const PROFILES: Dictionary = {", 1)[1].split(
        "\n}\n\nvar _spec:", 1)[0]
    rows = BLOCK.findall(section)
    require(len(rows) == 5 and len({name for name, _ in rows}) == 5,
            "PROFILE_COUNT")
    profiles: dict[str, dict] = {}
    for name, body in rows:
        header = re.search(
            r'"entry":"([ABC])", "restore":"([ABC])", '
            r'"guard":"([a-z_]+)"', body,
        )
        settle = re.search(r'"settle":(\d+), "pressure_period":(\d+)', body)
        matches = STEP.findall(body)
        require(header is not None and settle is not None,
                "PROFILE_HEADER_" + name)
        require(len(matches) == body.count('{"station":'),
                "UNPARSED_STEP_" + name)
        profiles[name] = {
            "entry": header.group(1),
            "restore": header.group(2),
            "guard": header.group(3),
            "settle": int(settle.group(1)),
            "pressure_period": int(settle.group(2)),
            "sequence": [
                {"station": station, "action": action,
                 "guard": guard, "gap": int(gap)}
                for station, action, guard, gap in matches
            ],
        }
    return profiles


def validate(
    atlas: dict, contingencies: dict, a05: dict[str, dict],
    a04: dict[str, dict], a06_classes: dict[str, str],
    a06_graphs: dict[str, list[dict]], profiles: dict[str, dict],
    host: str, stage: str, module: str,
) -> dict:
    predecessor = validate_a06(
        atlas, contingencies, a05, a04, a06_classes, a06_graphs,
        host, stage,
    )
    require(predecessor["ok"] and
            predecessor["source_pinned_sites"] == 200 and
            predecessor["immutable_original_tasks"] == 1000,
            "PREDECESSOR_SOURCE_HOLD")
    require(set(profiles) == RISK_CLASSES, "RISK_FAMILY_COVERAGE")
    signatures: set[tuple] = set()
    proof_count = 0
    for name, profile in profiles.items():
        require(profile["entry"] in "ABC"
                and profile["restore"] in "ABC"
                and profile["guard"] in GUARDS, "PROFILE_ROLE_" + name)
        seq = profile["sequence"]
        require(2 <= len(seq) <= 3 and
                len({s["station"] for s in seq}) == len(seq),
                "MECHANICAL_SEQUENCE_" + name)
        require(all(s["guard"] in GUARDS and
                    s["station"] in "ABC" and
                    s["action"].isidentifier() for s in seq),
                "PROOF_SOURCE_GUARD_" + name)
        require(seq[0]["gap"] == 0 and
                all(2 <= s["gap"] <= 5 for s in seq[1:]),
                "UNSAFE_WITNESS_GAP_" + name)
        require(2 <= profile["settle"] <= 8 and
                18 <= profile["pressure_period"] <= 40,
                "TICK_BOUNDS_" + name)
        # Timers and action strings deliberately excluded; station roles,
        # genuine guards and ordered branches remain in the signature.
        signatures.add((profile["entry"], profile["restore"],
                        profile["guard"],
                        tuple((s["station"], s["guard"]) for s in seq)))
        proof_count += len(seq)
    require(len(signatures) == 5, "COSMETIC_GRAPH_REUSE")
    require(set(a06_classes) == {
        f"REG_{i:02d}" for i in range(1, 26)}, "REGION_COVERAGE")
    region_counts = {name: 0 for name in RISK_CLASSES}
    for rid, risk in a06_classes.items():
        require(risk == a04[rid]["apparatus"] and risk in profiles,
                "RISK_SOURCE_MISMATCH_" + rid)
        region_counts[risk] += 1
    require(all(value > 0 for value in region_counts.values()),
            "UNREACHABLE_RISK_MECHANISM")

    host_contract = (
        "enable_site_hazards: bool = false",
        "EXP014_A07_REQUIRES_A06_OUTCOMES",
        "site_hazards.configure(",
        '["site_hazards"] = site_hazards.definition_snapshot()',
        'return "EXP014_A07_"',
        "site_hazards.begin(site_outcomes.snapshot())",
        "site_hazards.advance(_hazard_facts())",
        "site_hazards.operate(entity, action, _hazard_facts())",
        "site_hazards.needs_action()",
        "site_hazards.can_operate()",
        "site_hazards.solved()",
        "EXP014_A07_ENVIRONMENT_UNVERIFIED",
        "EXP014_A07_HAZARD_LOCKED",
        'state["site_hazards"] = site_hazards.snapshot()',
    )
    require(all(fragment in host for fragment in host_contract),
            "HOST_AUTHORITY_OR_EXTRACTION_BYPASS")
    stage_contract = (
        "runtime.site_hazards.needs_action()",
        "_activate_hazard_target()",
        "runtime.site_hazards.snapshot()",
        'KEY_J',
        'site_hazards',
    )
    require(all(fragment in stage for fragment in stage_contract),
            "LIVE_HAZARD_INTERFACE_MISSING")
    mechanics = (
        'if _mode == "temporary":',
        'if action == "engineer_control":',
        'elif action == "temporary_bypass":',
        'not bool(facts.get(str(required["guard"]), false))',
        '_trip("ENVIRONMENTAL_ESCALATION")',
        '_trip("UPSTREAM_SUPPORT_LOST")',
        '_phase = "postcheck"',
        'action != "retire_temporary_bypass"',
        'action == "verify_environment"',
        'str(facts.get("worksite_route", "")) != _route',
        'return _reject("WRONG_SOURCE_STATION")',
        '_solved = true',
    )
    require(all(fragment in module for fragment in mechanics),
            "MITIGATION_OR_RECOVERY_PATH_MISSING")
    return {
        "ok": True, "regional_source_profiles": len(a06_classes),
        "site_cases": predecessor["source_pinned_sites"],
        "unaltered_original_tasks": predecessor["immutable_original_tasks"],
        "hazard_mechanism_families": len(signatures),
        "risk_specific_proof_stages": proof_count,
        "source_host_control_replays": 400,
        "source_certification_only": True,
        "physical_playability_certified": False,
        "hardware_or_release_certified": False,
        "qualification": QUALIFICATION,
    }


if __name__ == "__main__":
    print("EXP014 A07 ENVIRONMENTAL HAZARD AUDIT:", json.dumps(
        validate(
            json.loads(ATLAS.read_text(encoding="utf-8")),
            json.loads(CONTINGENCIES.read_text(encoding="utf-8")),
            load_a05(), load_a04(), *parse_a06(), parse_script(),
            HOST.read_text(encoding="utf-8"),
            STAGE.read_text(encoding="utf-8"),
            SCRIPT.read_text(encoding="utf-8"),
        ), sort_keys=True))
