#!/usr/bin/env python3
"""Reject content JSON that breaks ADR-003: any non-integer number (Godot's JSON parser turns every number into
a float, so 12.0 would load there; it must never reach content/). Also loads every contract grid with the
reference model when reference/ is present.

    python3 tools/validate_content.py
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


class FloatInContent(ValueError):
    pass


def no_float(token: str) -> float:
    raise FloatInContent(token)


def check_save_compat(base: Path) -> list[str]:
    """ADR-018: the presentation-only list must name real files, once each, with a reason, and never rules files."""
    rel_base = base.name
    own = f"{rel_base}/save_compat.json"
    path = base / "save_compat.json"
    if not path.is_file():
        return [f"{own}: missing (ADR-018); without it every content edit strands offline checkpoints"]
    try:
        entries = json.loads(path.read_text(encoding="utf-8")).get("presentation_only")
    except (ValueError, AttributeError) as e:
        return [f"{own}: unreadable: {e}"]
    if not isinstance(entries, list) or not entries:
        return [f"{own}: presentation_only must be a non-empty list"]
    errs: list[str] = []
    seen: set[str] = set()
    for i, entry in enumerate(entries):
        where = f"{own} presentation_only[{i}]"
        if not isinstance(entry, dict) or not isinstance(entry.get("path"), str):
            errs.append(f"{where}: needs a string path")
            continue
        rel = entry["path"]
        if not (isinstance(entry.get("reason"), str) and entry["reason"].strip()):
            errs.append(f"{where}: {rel} needs a reason")
        if rel in seen:
            errs.append(f"{where}: {rel} is listed twice")
        seen.add(rel)
        if any(ch in rel for ch in "*?[") or "\\" in rel or ".." in rel.split("/"):
            errs.append(f"{where}: {rel} must be an exact relative path (no globs, backslashes or ..)")
        elif rel in (own, f"{rel_base}/versions.json") or rel.startswith(f"{rel_base}/contracts/"):
            errs.append(f"{where}: {rel} defines rules or versions and cannot be presentation-only")
        elif not rel.startswith(f"{rel_base}/") or not (base.parent / rel).is_file():
            errs.append(f"{where}: {rel} names no file under {rel_base}/")
    return errs


def main() -> int:
    errs: list[str] = []
    files = sorted((ROOT / "content").rglob("*.json"))
    for p in files:
        rel = p.relative_to(ROOT).as_posix()
        try:
            json.loads(p.read_text(encoding="utf-8"), parse_float=no_float)
        except FloatInContent as e:
            errs.append(f"{rel}: non-integer number {e} (PU and ticks are integers, ADR-003)")
        except json.JSONDecodeError as e:
            errs.append(f"{rel}: invalid JSON: {e}")
    if (ROOT / "reference" / "lbo_grid.py").is_file():
        sys.path.insert(0, str(ROOT / "reference"))
        from lbo_grid import Grid, GridError  # noqa: E402
        for p in sorted((ROOT / "content" / "contracts").glob("*/grid.json")):
            try:
                Grid.load(json.loads(p.read_text(encoding="utf-8")))
            except GridError as e:
                errs.append(f"{p.relative_to(ROOT).as_posix()}: " + "; ".join(d["message"] for d in e.diagnostics))
    errs.extend(check_save_compat(ROOT / "content"))
    for e in errs:
        print("CONTENT ERROR:", e)
    print(f"content: {len(files)} JSON files, {len(errs)} errors")
    return 1 if errs else 0


if __name__ == "__main__":
    sys.exit(main())
