#!/usr/bin/env python3
"""EXP021 A05 Windows build provenance and launch identity verifier.

Runs only after the existing Windows QA57/EXP014 manifest/export gates.
This is a source/build reproducibility check, not a GPU, Steam or alpha claim.
"""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def verify() -> dict:
    binary = ROOT / "build/windows/LightsBackOn.exe"
    pack = ROOT / "build/windows/LightsBackOn.pck"
    manifest_file = ROOT / "build_manifest.json"
    packed_manifest = ROOT / "build/windows/build_manifest.json"
    smoke = ROOT / "build/smoke.log"
    checksum_file = ROOT / "build/SHA256SUMS.txt"
    for required in (binary, pack, manifest_file, packed_manifest, smoke, checksum_file):
        if not required.is_file() or required.stat().st_size == 0:
            raise ValueError(f"EXP021_A05_MISSING_WINDOWS_ARTIFACT:{required}")
    if manifest_file.read_bytes() != packed_manifest.read_bytes():
        raise ValueError("EXP021_A05_PACKAGED_MANIFEST_BYTE_DRIFT")
    manifest = json.loads(manifest_file.read_text(encoding="utf-8"))
    head = subprocess.run(["git", "rev-parse", "HEAD"], cwd=ROOT,
                          check=True, capture_output=True, text=True).stdout.strip()
    if manifest.get("git_commit") != head:
        raise ValueError("EXP021_A05_EXPORT_COMMIT_MISMATCH")
    if manifest.get("git_dirty") is not False:
        raise ValueError("EXP021_A05_EXPORT_NOT_REPRODUCIBLE_CLEAN_TREE")
    if not str(manifest.get("engine_version", "")).startswith("4.7.2."):
        raise ValueError("EXP021_A05_WRONG_ENGINE_VERSION")
    build_id = str(manifest.get("build_id", ""))
    if not build_id or build_id == "none":
        raise ValueError("EXP021_A05_MISSING_BUILD_ID")
    boot_log = smoke.read_text(encoding="utf-8", errors="replace")
    if f"Lights Back On boot" not in boot_log or f"build {build_id}" not in boot_log:
        raise ValueError("EXP021_A05_BOOT_SOURCE_IDENTITY_MISMATCH")
    sums: dict[str, str] = {}
    for line in checksum_file.read_text(encoding="utf-8").splitlines():
        parts = line.strip().split(maxsplit=1)
        if len(parts) != 2 or not re.fullmatch(r"[a-f0-9]{64}", parts[0]):
            raise ValueError("EXP021_A05_INVALID_SHA256SUMS_RECORD")
        path = parts[1].lstrip("*").replace("\\", "/")
        if path in sums:
            raise ValueError("EXP021_A05_DUPLICATE_HASH_PATH")
        sums[path] = parts[0]
    files = [binary, pack, packed_manifest]
    records = []
    for p in files:
        rel = p.relative_to(ROOT).as_posix()
        if sums.get(rel) != sha256(p):
            raise ValueError(f"EXP021_A05_HASH_MISMATCH:{rel}")
        records.append({"path": rel, "size_bytes": p.stat().st_size,
                        "sha256": sha256(p)})
    return {
        "phase": "EXP021_A05_WINDOWS_EXPORT",
        "status": "EXACT_HEAD_BINARY_HASH_AND_BOOT_CHECK_PASSED",
        "git_commit": head, "build_id": build_id,
        "engine_version": manifest["engine_version"],
        "manifest_sha256": sha256(manifest_file),
        "boot_log_sha256": sha256(smoke),
        "files": records,
        "actual_gpu_render": "NOT_TESTED",
        "actual_full_mission_completion": "NOT_ESTABLISHED",
        "two_client_steam": "NOT_TESTED",
        "alpha_release": "HOLD"
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report", type=Path,
                        default=Path("build/exp021-a05/windows-export-gate.json"))
    args = parser.parse_args()
    try:
        outcome = verify()
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(outcome, indent=2, sort_keys=True) + "\n",
                               encoding="utf-8")
    except (ValueError, KeyError, TypeError, OSError,
            subprocess.CalledProcessError) as exc:
        print(f"[FAIL][EXP021_A05_WINDOWS_EXPORT] {exc}", file=sys.stderr, flush=True)
        return 1
    print("[PASS][EXP021_A05_WINDOWS_EXPORT] exact commit, manifest, EXE/PCK SHA256, boot source",
          flush=True)
    print("[HOLD] hardware, Steam, human/controller, release", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
