#!/usr/bin/env python3
"""Isolate Godot headless lifetime warnings without suppressing engine diagnostics.

QA #51 / QA52 / QA53 / QA54 / QA55: A passing test suite does not imply its exit-time RID/ObjectDB warnings
are harmless. Run a no-fixture baseline and small, reproducible fixture groups
as separate Godot processes so teardown costs can be compared on both CI OSes.
This is diagnostic evidence, not a physical GPU memory benchmark.
"""
from __future__ import annotations

import argparse
from collections import Counter
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import platform
import re
import subprocess
import sys
import tempfile

CASES = {
    "empty": ["--dir=res://tests/qa51_empty_no_scripts"],
    "pure": ["--filter=SIM08"],
    "power_scene": ["--filter=DS04"],
    "tablet_menu_only": ["--filter=DS05_menu"],
    "tablet_bounds_only": ["--filter=DS05_accessibility"],
    "tablet_objectives_only": ["--filter=DS05_tablet"],
    "tablet_footer_only": ["--filter=DS05_network"],
    "tablet_scene": ["--filter=DS05"],
    # QA52: isolate residual teardown warnings by independently running the
    # individual legacy UI/world fixture families after the orphaned map fix.
    # Filter by exact file token or test-method token, not an ad-hoc scene guess.
    "menu_reflow": ["--filter=DS01"],
    "menu_geometry_only": ["--filter=DS01_menu_reflows"],
    "menu_focus_only": ["--filter=DS01_primary"],
    "offline_ownership": ["--filter=QA52_lifetime"],
    "v07_unit": ["--filter=V07_ui"],
    "v07_hud_layout": ["--filter=V07_hud_fits"],
    "v07_tablet_layout": ["--filter=V07_tablet_fits"],
    "v07_focus": ["--filter=V07_directional_focus"],
    "v07_live": ["--filter=V07_live"],
    "a04_live": ["--filter=A04_live"],
    "v01_offline": ["--filter=V01_offline"],
    # QA53: distinguish a font/theme cache from a real control ownership leak.
    "font_theme": ["--dir=res://tests/diagnostics", "--filter=QA53_theme"],
    "font_menu_single": ["--dir=res://tests/diagnostics", "--filter=QA53_single"],
    "font_menu_repeated": ["--dir=res://tests/diagnostics", "--filter=QA53_multiple"],
    "font_ui_lifetime": ["--dir=res://tests/diagnostics", "--filter=QA53"],
    "plain_label_lifetime": ["--dir=res://tests/diagnostics", "--filter=QA53_plain_labels"],
    "project_label_lifetime": ["--dir=res://tests/diagnostics", "--filter=QA53_themed_labels"],
    "dialog_lifetime": ["--dir=res://tests/diagnostics", "--filter=QA53_unused_confirmation"],
    "plain_shaped_labels": ["--dir=res://tests/diagnostics", "--filter=QA53_explicitly_shaped_plain"],
    "project_shaped_labels": ["--dir=res://tests/diagnostics", "--filter=QA53_explicitly_shaped_project"],
    "menu_reflow_frame_settled": ["--filter=DS01", "--settle-frames=30"],
    "font_menu_frame_settled": ["--dir=res://tests/diagnostics", "--filter=QA53_multiple", "--settle-frames=30"],
    # QA54 synthetic bisection of the menu's smallest independently-built
    # groups. Keep limits observational until two-OS baseline proves a bound.
    "qa54_structure": ["--dir=res://tests/diagnostics", "--filter=QA54_structure_only"],
    "qa54_text": ["--dir=res://tests/diagnostics", "--filter=QA54_structured_text"],
    "qa54_buttons": ["--dir=res://tests/diagnostics", "--filter=QA54_buttons"],
    "qa54_dialog": ["--dir=res://tests/diagnostics", "--filter=QA54_dialog"],
    "qa54_reflow": ["--dir=res://tests/diagnostics", "--filter=QA54_reflow"],
    "qa54_signals": ["--dir=res://tests/diagnostics", "--filter=QA54_signals_and_focus"],
    # Real PackedScene/script variation locates the boundary between a
    # generic UI tree and the production MainMenu._ready() lifecycle.
    "qa54_packed_unentered": ["--dir=res://tests/diagnostics", "--filter=QA54_packed_scene_not_entered"],
    "qa54_packed_scriptless": ["--dir=res://tests/diagnostics", "--filter=QA54_packed_scene_without_script"],
    "qa54_real_no_reflow": ["--dir=res://tests/diagnostics", "--filter=QA54_actual_menu_without_reflow"],
    # QA55 production regression exercises the actual button owner and reads
    # the source to detect any reintroduced unparented double-allocation.
    "qa55_menu_lifetime": ["--filter=QA55"],
}
# Measured on both hosted OSes after eliminating unparented Objectives maps.
# These cases must never recreate detached UI trees with leaked canvas/texture RIDs.
RID_LIMITS = {
    "tablet_objectives_only": {"CanvasItem": 0, "DummyTexture": 0},
    "tablet_footer_only": {"CanvasItem": 0, "DummyTexture": 0},
    "tablet_scene": {"CanvasItem": 0, "DummyTexture": 0},
    # QA52 recovered a real RefCounted cycle in the production offline host
    # adapter. Both hosted OSes now release these headless fixture graphs
    # completely. Keep a strict zero ceiling to catch accidental regressions.
    "offline_ownership": {"ObjectDB": 0, "CanvasItem": 0, "DummyTexture": 0},
    "power_scene": {"ObjectDB": 0, "CanvasItem": 0, "DummyTexture": 0},
    "v07_live": {"ObjectDB": 0, "CanvasItem": 0, "DummyTexture": 0},
    "a04_live": {"ObjectDB": 0, "CanvasItem": 0, "DummyTexture": 0},
    # QA53: independent controls and font resources showed zero warnings.
    # QA55 also removed the actual menu ownership defect: all menu isolates
    # have now shown zero exit-time warnings on both hosted OSes.
    "font_theme": {"CanvasItem": 0, "ObjectDB": 0, "ShapedText": 0, "FontRID": 0},
    "plain_label_lifetime": {"CanvasItem": 0, "ObjectDB": 0, "ShapedText": 0, "FontRID": 0},
    "project_label_lifetime": {"CanvasItem": 0, "ObjectDB": 0, "ShapedText": 0, "FontRID": 0},
    "plain_shaped_labels": {"CanvasItem": 0, "ObjectDB": 0, "ShapedText": 0, "FontRID": 0},
    "project_shaped_labels": {"CanvasItem": 0, "ObjectDB": 0, "ShapedText": 0, "FontRID": 0},
    "dialog_lifetime": {"CanvasItem": 0, "ObjectDB": 0, "ShapedText": 0, "FontRID": 0},
    "font_menu_single": {"CanvasItem": 0, "ObjectDB": 0, "ShapedText": 0, "FontRID": 0, "DummyTexture": 0},
    "font_menu_repeated": {"CanvasItem": 0, "ObjectDB": 0, "ShapedText": 0, "FontRID": 0, "DummyTexture": 0},
    "font_menu_frame_settled": {"CanvasItem": 0, "ObjectDB": 0, "ShapedText": 0, "FontRID": 0, "DummyTexture": 0},
    "menu_reflow": {"CanvasItem": 0, "ObjectDB": 0, "ShapedText": 0, "FontRID": 0, "DummyTexture": 0},
    "menu_reflow_frame_settled": {"CanvasItem": 0, "ObjectDB": 0, "ShapedText": 0, "FontRID": 0, "DummyTexture": 0},
    # QA55: after removing the duplicate, never-parented StartButton,
    # previously leaking production menu/reflow/text cases are zero on
    # independently hosted 4.7.2 Linux and Windows.
    "menu_geometry_only": {"CanvasItem": 0, "ObjectDB": 0, "ShapedText": 0, "FontRID": 0, "DummyTexture": 0},
    "menu_focus_only": {"CanvasItem": 0, "ObjectDB": 0, "ShapedText": 0, "FontRID": 0, "DummyTexture": 0},
    "v01_offline": {"CanvasItem": 0, "ObjectDB": 0, "ShapedText": 0, "FontRID": 0, "DummyTexture": 0},
    "font_ui_lifetime": {"CanvasItem": 0, "ObjectDB": 0, "ShapedText": 0, "FontRID": 0, "DummyTexture": 0},
    "qa55_menu_lifetime": {"CanvasItem": 0, "ObjectDB": 0, "ShapedText": 0, "FontRID": 0, "DummyTexture": 0},
    # QA54 diagnostics now also run clean. Keeping them protects against
    # reintroducing teardown warnings during future UI refactors.
    "qa54_structure": {"CanvasItem": 0, "ObjectDB": 0, "ShapedText": 0, "FontRID": 0},
    "qa54_text": {"CanvasItem": 0, "ObjectDB": 0, "ShapedText": 0, "FontRID": 0},
    "qa54_buttons": {"CanvasItem": 0, "ObjectDB": 0, "ShapedText": 0, "FontRID": 0},
    "qa54_dialog": {"CanvasItem": 0, "ObjectDB": 0, "ShapedText": 0, "FontRID": 0},
    "qa54_reflow": {"CanvasItem": 0, "ObjectDB": 0, "ShapedText": 0, "FontRID": 0},
    "qa54_signals": {"CanvasItem": 0, "ObjectDB": 0, "ShapedText": 0, "FontRID": 0},
    "qa54_packed_unentered": {"CanvasItem": 0, "ObjectDB": 0, "ShapedText": 0, "FontRID": 0},
    "qa54_packed_scriptless": {"CanvasItem": 0, "ObjectDB": 0, "ShapedText": 0, "FontRID": 0},
    "qa54_real_no_reflow": {"CanvasItem": 0, "ObjectDB": 0, "ShapedText": 0, "FontRID": 0, "DummyTexture": 0},
}

LEAK_PATTERNS = (
    ("CanvasItem", re.compile(r'(\d+) RIDs of type "CanvasItem" were leaked')),
    ("ObjectDB", re.compile(r"(\d+) ObjectDB instances were leaked")),
    ("DummyTexture", re.compile(r"(\d+) RID allocations of type '[^']*DummyTexture[^']*' were leaked")),
    ("ShapedText", re.compile(r"(\d+) RID allocations of type '[^']*ShapedText[^']*' were leaked")),
    ("FontRID", re.compile(r"(\d+) RID allocations of type '[^']*FontAdvanced[^']*' were leaked")),
)
TEST_SUMMARY = re.compile(r"tests: (\d+) passed, (\d+) failed, (\d+) assertions")
LEAK_DETAIL = re.compile(r"(?im)^.*(?:leaked instance|orphaned|RID allocations|ObjectDB instances|RIDs of type).*?$")
LEAKED_CLASS = re.compile(r"(?m)^Leaked instance: ([A-Za-z0-9_]+):\d+ - Reference count:")


def parse_log(log: str) -> dict[str, object]:
    """Parse Godot's diagnostic output; missing warning classes count as zero."""
    counts: dict[str, int] = {}
    for label, pattern in LEAK_PATTERNS:
        matches = pattern.findall(log)
        counts[label] = sum(int(value) for value in matches)
    summary = TEST_SUMMARY.search(log)
    owners: Counter[str] = Counter(LEAKED_CLASS.findall(log))
    return {
        "leaked_object_classes": dict(sorted(owners.items(), key=lambda kv: (-kv[1], kv[0]))),
        "counts": counts,
        "passed": int(summary.group(1)) if summary else None,
        "failed": int(summary.group(2)) if summary else None,
        "assertions": int(summary.group(3)) if summary else None,
        "script_error": bool(re.search(r"(?m)^(?:SCRIPT ERROR:|Parse Error:)", log)),
        "warning_excerpt": LEAK_DETAIL.findall(log)[:30],
    }


def regression_violations(case: str, counts: dict[str, int]) -> list[str]:
    """Bound the specific detached-control regression without hiding other leaks."""
    return [
        f"{kind}={counts[kind]} exceeds {ceiling}"
        for kind, ceiling in RID_LIMITS.get(case, {}).items()
        if counts[kind] > ceiling
    ]


def isolated_env(root: str, base: dict[str, str] | None = None) -> dict[str, str]:
    """SAVE22: point Godot's user:// (APPDATA on Windows, XDG_DATA_HOME on Linux) at an empty directory.

    tests/run_tests.gd refuses to start unless user:// resolves inside LBO_TEST_USER_ROOT, so a stale
    checkpoint in the PC's real user dir can never fail (or be overwritten by) a probe run.
    """
    env = dict(os.environ if base is None else base)
    path = Path(root).resolve().as_posix()
    env.update({"LBO_TEST_USER_ROOT": path, "APPDATA": path, "XDG_DATA_HOME": path})
    return env


def run_case(godot: str, case: str, out_dir: Path, timeout: int) -> dict[str, object]:
    args = [godot, "--headless", "--verbose", "--path", ".", "-s",
            "res://tests/run_tests.gd", "--", *CASES[case]]
    try:
        with tempfile.TemporaryDirectory(prefix="lbo_test_user.") as user_root:
            run = subprocess.run(args, capture_output=True, text=True, encoding="utf-8",
                                 errors="replace", timeout=timeout, check=False,
                                 env=isolated_env(user_root))
        log = run.stdout + "\n" + run.stderr
        returncode: int | None = run.returncode
        timed_out = False
    except subprocess.TimeoutExpired as exc:
        stdout = exc.stdout or b""
        stderr = exc.stderr or b""
        log = (stdout.decode("utf-8", "replace") if isinstance(stdout, bytes) else stdout)
        log += "\n" + (stderr.decode("utf-8", "replace") if isinstance(stderr, bytes) else stderr)
        returncode = None
        timed_out = True
    (out_dir / f"{case}.log").write_text(log, encoding="utf-8")
    parsed = parse_log(log)
    # No tests found is intentional only for the empty baseline.
    summary_ok = (parsed["passed"] == 0 if case == "empty" else
                  isinstance(parsed["passed"], int) and parsed["passed"] > 0)
    violations = regression_violations(case, parsed["counts"])
    passed = (not timed_out and returncode == 0 and
              parsed["failed"] in (None, 0) and
              not parsed["script_error"] and summary_ok and not violations)
    return {
        "regression_violations": violations,
        "case": case,
        "runner_args": CASES[case],
        "exit_code": returncode,
        "timed_out": timed_out,
        "probe_passed": passed,
        **parsed,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default=os.environ.get("GODOT_BIN"),
                        help="Pinned Godot executable (or GODOT_BIN)")
    parser.add_argument("--out-dir", type=Path, default=Path("build/qa-resources"))
    parser.add_argument("--timeout", type=int, default=150)
    args = parser.parse_args()
    if not args.godot:
        parser.error("set --godot or GODOT_BIN")
    args.out_dir.mkdir(parents=True, exist_ok=True)
    result = {
        "purpose": "QA51 diagnostic only; not exported-game memory validation",
        "godot": "Godot 4.7.2 (pin enforced by project setup)",
        "platform": platform.system(),
        "recorded_at_utc": datetime.now(timezone.utc).isoformat(),
        "cases": [run_case(args.godot, name, args.out_dir, args.timeout) for name in CASES],
    }
    baseline = result["cases"][0]["counts"]
    for case in result["cases"]:
        case["delta_from_empty"] = {
            kind: count - baseline[kind] for kind, count in case["counts"].items()
        }
        print(f"QA51 {case['case']}: exit={case['exit_code']} "
              f"tests={case['passed']} failures={case['failed']} "
              f"leaks={case['counts']} delta={case['delta_from_empty']} "
              f"probe={'PASS' if case['probe_passed'] else 'FAIL'}")
        if case["counts"]["CanvasItem"] or case["counts"]["ObjectDB"]:
            print("  QA52_OBJECT_CLASSES " + json.dumps(
                dict(list(case["leaked_object_classes"].items())[:12]), sort_keys=True))
            for line in case["warning_excerpt"][:5]:
                print("  QA51_OWNER " + line[:260])
    (args.out_dir / "summary.json").write_text(
        json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    # Existing engine leak messages are deliberately recorded, not silenced
    # or unilaterally turned into a release gate before their cause is known.
    return 0 if all(case["probe_passed"] for case in result["cases"]) else 1


if __name__ == "__main__":
    sys.exit(main())
