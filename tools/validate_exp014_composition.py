#!/usr/bin/env python3
"""EXP014 A01: source-only structural diversity and composition regression gate.

The pre-existing EXP013 authoring audit protects task/target/action IDs. This
second audit deliberately IGNORES action names, level IDs and timer values when
counting mechanically different route structures. A renamed operation does
not magically become a new puzzle. No collision, playability or art approval is
inferred from static source validation or proposed visual geometry.
"""
from __future__ import annotations

from collections import Counter, defaultdict
import json

if __package__:
    from tools.validate_exp012_a02_sites import read_book as read_a02
    from tools.validate_exp013_expansions import read_books
else:
    from validate_exp012_a02_sites import read_book as read_a02
    from validate_exp013_expansions import read_books

MODES = frozenset({"hold", "pulse", "sample", "handoff", "balance"})
FAILURES = frozenset({"step", "backtrack", "restart"})
QUALIFICATION = "SOURCE_HEADLESS_ONLY_HUMAN_CONTROLLER_RELEASE_HELD"
BASELINE_DISTINCT_STRUCTURES = 112
BASELINE_MAX_PATTERN_REUSE = 16
MIN_REGION_VARIETY = 5


def require(condition: bool, code: str) -> None:
    if not condition:
        raise ValueError(code)


def source_entries() -> list[dict]:
    """Read the existing immutably authored 40+4*40 source book sequence."""
    books = [read_a02(), *read_books()]
    return [entry for book in books for entry in book["entries"]]


def structural_route(entry: dict, route: str) -> tuple:
    """Exclude names/timing: keep only mechanics, station flow and failure."""
    targets = entry.get("targets", {})
    require(isinstance(targets, dict) and set(targets) == {"A", "B", "C"},
            "EXP014_BAD_TARGET_MAP")
    require(len(set(targets.values())) == 3, "EXP014_TARGETS_NOT_DISTINCT")
    reverse = {value: key for key, value in targets.items()}
    routes = entry.get("routes", {})
    steps = routes.get(route)
    require(isinstance(steps, list) and len(steps) == 4,
            "EXP014_ROUTE_LENGTH")
    result: list[tuple[str, str, str, str]] = []
    for step in steps:
        require(isinstance(step, dict), "EXP014_STEP_TYPE")
        mode = step.get("mode")
        failure = step.get("failure")
        target = reverse.get(step.get("target"))
        support = reverse.get(step.get("support_target"))
        require(mode in MODES and failure in FAILURES and
                target is not None and support is not None and
                target != support, "EXP014_INVALID_OPERATION")
        result.append((mode, support, target, failure))
    return tuple(result)


def validate(entries: list[dict]) -> dict:
    """A non-destructive audit; source payloads must never be modified here."""
    require(len(entries) == 200, "EXP014_SOURCE_COUNT")
    region_patterns: dict[str, set[tuple]] = defaultdict(set)
    structure_counts: Counter[tuple] = Counter()
    mode_counts: Counter[str] = Counter()
    seen_levels: set[str] = set()
    for index, entry in enumerate(entries, start=1):
        level = f"LV_{index:03d}"
        require(entry.get("level_id") == level and level not in seen_levels,
                "EXP014_LEVEL_IDENTITY")
        seen_levels.add(level)
        require(entry.get("qualification") == QUALIFICATION,
                "EXP014_QUALIFICATION_HOLD")
        region = f"REG_{(index - 1) // 8 + 1:02d}"
        require(entry.get("region_id") == region,
                "EXP014_REGION_IDENTITY")
        priority = structural_route(entry, "priority")
        resilience = structural_route(entry, "resilience")
        require(priority != resilience, "EXP014_IDENTICAL_ROUTE_TOPOLOGY")
        key = (priority, resilience)
        region_patterns[region].add(key)
        structure_counts[key] += 1
        mode_counts.update(operation[0] for operation in priority)
    require(len(region_patterns) == 25, "EXP014_REGION_COUNT")
    require(all(len(kinds) >= MIN_REGION_VARIETY
                for kinds in region_patterns.values()),
            "EXP014_REGION_VARIETY_REGRESSION")
    distinct = len(structure_counts)
    most_reused = max(structure_counts.values())
    require(distinct >= BASELINE_DISTINCT_STRUCTURES,
            "EXP014_STRUCTURAL_VARIETY_REGRESSION")
    require(most_reused <= BASELINE_MAX_PATTERN_REUSE,
            "EXP014_TEMPLATE_REUSE_REGRESSION")
    require(set(mode_counts) == MODES, "EXP014_MISSING_MECHANIC")
    return {
        "ok": True,
        "source_interventions": 200,
        "regions": 25,
        "route_variants": 400,
        "site_operation_steps": 1600,
        "priority_modes": dict(sorted(mode_counts.items())),
        "distinct_mechanical_route_pairs": distinct,
        "most_reused_mechanical_route_pair": most_reused,
        "regions_with_eight_unique_pairs": sum(
            len(patterns) == 8 for patterns in region_patterns.values()),
        "minimum_distinct_pairs_in_region": min(map(len, region_patterns.values())),
        "counts_ignore_action_names_and_timing": True,
        "future_content_quality_target": "Raise distinct structural pairs beyond 112",
        "qualification": QUALIFICATION,
        "physical_playability_certified": False,
        "release_certified": False,
    }


if __name__ == "__main__":
    print("EXP014 WORKSITE DIVERSITY AUDIT:",
          json.dumps(validate(source_entries()), sort_keys=True))
