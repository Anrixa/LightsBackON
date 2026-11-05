#!/usr/bin/env python3
"""Isolate Godot headless lifetime warnings without suppressing engine diagnostics.

QA #51: A passing test suite does not imply its exit-time RID/ObjectDB warnings
are harmless. Run a no-fixture baseline and small, reproducible fixture groups
as separate Godot processes so teardown costs can be compared on both CI OSes.
This is diagnostic evidence, not a physical GPU memory benchmark.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import platform
import re
import subprocess
import sys

CASES = {
    "empty": ["--dir=res://tests/qa51_empty_no_scripts"],
    "pure": ["--filter=SIM08"],
    "power_scene": ["--filter=DS04"],
    "tablet_menu_only": ["--filter=DS05_menu"],
    "tablet_bounds_only": ["--filter=DS05_accessibility"],
    "tablet_objectives_only": ["--filter=DS05_tablet"],
    "tablet_footer_only": ["--filter=DS05_network"],
    "tablet_scene": ["--filter=DS05"],
}
# Measured on both hosted OSes after eliminating unparented Objectives maps.
# These cases must never recreate detached UI trees with leaked canvas/texture RIDs.
RID_LIMITS = {
    "tablet_objectives_only": {"CanvasItem": 0, "DummyTexture": 0},
    "tablet_footer_only": {"CanvasItem": 0, "DummyTexture": 0},
    "tablet_scene": {"CanvasItem": 0, "DummyTexture": 0},
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


def parse_log(log: str) -> dict[str, object]:
    """Parse Godot's diagnostic output; missing warning classes count as zero."""
    counts: dict[str, int] = {}
    for label, pattern in LEAK_PATTERNS:
        matches = pattern.findall(log)
        counts[label] = sum(int(value) for value in matches)
    summary = TEST_SUMMARY.search(log)
    return {
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


def run_case(godot: str, case: str, out_dir: Path, timeout: int) -> dict[str, object]:
    args = [godot, "--headless", "--verbose", "--path", ".", "-s",
            "res://tests/run_tests.gd", "--", *CASES[case]]
    try:
        run = subprocess.run(args, capture_output=True, text=True, encoding="utf-8",
                             errors="replace", timeout=timeout, check=False)
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
            for line in case["warning_excerpt"][:8]:
                print("  QA51_OWNER " + line[:260])
    (args.out_dir / "summary.json").write_text(
        json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    # Existing engine leak messages are deliberately recorded, not silenced
    # or unilaterally turned into a release gate before their cause is known.
    return 0 if all(case["probe_passed"] for case in result["cases"]) else 1


if __name__ == "__main__":
    sys.exit(main())
