#!/usr/bin/env python3
"""Prepare or structurally verify redacted F02 two-PC Steam test evidence.

This tool cannot establish that a Steam lobby, distinct account, or independent
network was real. It enforces a complete, locally backed record so the human
qualification review can identify missing or inconsistent evidence.
No Steamworks access, network traffic, external packages, or game-state changes.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path
from typing import Any

CASE_IDS: tuple[str, ...] = (
    "PRIVATE_LOBBY_CREATED",
    "SECOND_ACCOUNT_JOINED",
    "RELIABLE_HOST_TO_GUEST",
    "RELIABLE_GUEST_TO_HOST",
    "GUEST_LEAVE_REJOIN",
    "GUEST_NETWORK_INTERRUPTION",
    "HOST_EXIT_NOTICE",
)
NETWORK_FIELDS: tuple[str, ...] = (
    "two_distinct_pcs",
    "two_distinct_licensed_accounts",
    "accounts_are_friends",
    "steam_running_on_both_pcs",
    "friends_only_lobby",
    "independent_networks",
    "different_public_egress",
)
HEX_SHA256 = re.compile(r"^[a-fA-F0-9]{64}$")
STEAM_ID = re.compile(r"(?<!\d)\d{17}(?!\d)")
IPV4_ADDRESS = re.compile(r"(?<![\d.])(?:\d{1,3}\.){3}\d{1,3}(?![\d.])")


def template() -> dict[str, Any]:
    """An incomplete record. Never prepopulate the outcome of a real test."""
    return {
        "schema_version": 1,
        "task": "F02",
        "candidate": "A",
        "tuple": {
            "godot_version": "4.7.2.stable",
            "godot_binary_sha256": "",
            "export_templates_sha256": "",
            "steam_peer_class": "",
            "steamworks_runtime_version": "",
            "extensions": [
                {
                    "name": "",
                    "source_revision": "",
                    "license": "",
                    "binary_sha256": "",
                }
            ],
        },
        "build": {
            "build_id": "",
            "windows_exe_sha256": "",
            "windows_pck_sha256": "",
        },
        "network": dict.fromkeys(NETWORK_FIELDS, False),
        "cases": [
            {"id": case, "status": "NOT_RUN", "evidence_path": "", "evidence_sha256": ""}
            for case in CASE_IDS
        ],
        "review": {
            "human_checked_real_networks": False,
            "human_checked_log_redaction": False,
            "reviewer_note": "",
        },
    }


def _object(value: Any, path: str, errors: list[str]) -> dict[str, Any]:
    if not isinstance(value, dict):
        errors.append(f"{path}: expected an object")
        return {}
    return value


def _text(obj: dict[str, Any], field: str, path: str, errors: list[str]) -> str:
    value = obj.get(field)
    if not isinstance(value, str) or not value.strip():
        errors.append(f"{path}.{field}: non-empty text required")
        return ""
    return value.strip()


def _hash(obj: dict[str, Any], field: str, path: str, errors: list[str]) -> str:
    value = _text(obj, field, path, errors)
    if value and HEX_SHA256.fullmatch(value) is None:
        errors.append(f"{path}.{field}: expected a complete 64-character SHA-256 hex digest")
        return ""
    return value.lower()


def _true(obj: dict[str, Any], field: str, path: str, errors: list[str]) -> None:
    if obj.get(field) is not True:
        errors.append(f"{path}.{field}: must be explicitly true; unverified is not PASS")


def _evidence_path(raw: str, root: Path, path: str, errors: list[str]) -> Path | None:
    # Require portable relative paths. Never follow an attachment outside this record's folder.
    if "\\" in raw or ":" in raw or raw.startswith("/"):
        errors.append(f"{path}: evidence path must be a relative forward-slash path")
        return None
    parts = raw.split("/")
    if any(part in ("", ".", "..") for part in parts):
        errors.append(f"{path}: unsafe or non-normalized evidence path")
        return None
    local = (root / raw).resolve()
    if not local.is_relative_to(root.resolve()):
        errors.append(f"{path}: evidence path escapes the record folder")
        return None
    return local


def validate(record: Any, record_path: Path) -> list[str]:
    """Verify structure, redaction and file hashes; never assert network authenticity."""
    errors: list[str] = []
    doc = _object(record, "root", errors)
    if type(doc.get("schema_version")) is not int or doc["schema_version"] != 1:
        errors.append("schema_version: expected exactly 1")
    if doc.get("task") != "F02":
        errors.append("task: expected F02")
    if doc.get("candidate") not in ("A", "B", "C"):
        errors.append("candidate: expected A, B or C from the approved test sequence")

    tuple_data = _object(doc.get("tuple"), "tuple", errors)
    for key in ("godot_version", "steam_peer_class", "steamworks_runtime_version"):
        _text(tuple_data, key, "tuple", errors)
    for key in ("godot_binary_sha256", "export_templates_sha256"):
        _hash(tuple_data, key, "tuple", errors)
    extensions = tuple_data.get("extensions")
    if not isinstance(extensions, list) or not extensions:
        errors.append("tuple.extensions: at least one approved and version-pinned extension required")
    else:
        for index, value in enumerate(extensions):
            path = f"tuple.extensions[{index}]"
            extension = _object(value, path, errors)
            for key in ("name", "source_revision", "license"):
                _text(extension, key, path, errors)
            _hash(extension, "binary_sha256", path, errors)

    build = _object(doc.get("build"), "build", errors)
    _text(build, "build_id", "build", errors)
    for key in ("windows_exe_sha256", "windows_pck_sha256"):
        _hash(build, key, "build", errors)

    network = _object(doc.get("network"), "network", errors)
    for field in NETWORK_FIELDS:
        _true(network, field, "network", errors)

    review = _object(doc.get("review"), "review", errors)
    for field in ("human_checked_real_networks", "human_checked_log_redaction"):
        _true(review, field, "review", errors)
    _text(review, "reviewer_note", "review", errors)

    cases = doc.get("cases")
    if not isinstance(cases, list):
        errors.append("cases: expected an array of observations")
        return errors

    observed: set[str] = set()
    for index, value in enumerate(cases):
        path = f"cases[{index}]"
        case = _object(value, path, errors)
        identifier = _text(case, "id", path, errors)
        if identifier:
            if identifier in observed:
                errors.append(f"{path}: duplicate case {identifier}")
            observed.add(identifier)
            if identifier not in CASE_IDS:
                errors.append(f"{path}: unknown case {identifier}")
        if case.get("status") != "PASS":
            errors.append(f"{path}.status: expected PASS from an observed real-network test")
        relative = _text(case, "evidence_path", path, errors)
        digest = _hash(case, "evidence_sha256", path, errors)
        if not relative:
            continue
        local = _evidence_path(relative, record_path.parent, f"{path}.evidence_path", errors)
        if local is None:
            continue
        if not local.is_file():
            errors.append(f"{path}: missing evidence file {relative}")
            continue
        data = local.read_bytes()
        if not data:
            errors.append(f"{path}: empty evidence file {relative}")
            continue
        if digest and hashlib.sha256(data).hexdigest() != digest:
            errors.append(f"{path}: evidence SHA-256 does not match file {relative}")
        # Keep account identifiers and network addresses out of committed logs.
        text = data.decode("utf-8", errors="replace")
        if STEAM_ID.search(text):
            errors.append(f"{path}: evidence may contain an unredacted 17-digit Steam ID")
        if IPV4_ADDRESS.search(text):
            errors.append(f"{path}: evidence may contain an unredacted IPv4 address")
        if "-----BEGIN PRIVATE KEY-----" in text or "Bearer " in text:
            errors.append(f"{path}: evidence may contain a credential")
    missing = sorted(set(CASE_IDS) - observed)
    if missing:
        errors.append("cases: missing required observations: " + ", ".join(missing))
    return errors


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    init = commands.add_parser("init", help="Create an incomplete evidence record without overwriting")
    init.add_argument("path", type=Path)
    verify = commands.add_parser("verify", help="Check record completeness and redacted evidence hashes")
    verify.add_argument("path", type=Path)
    args = parser.parse_args(argv)

    if args.command == "init":
        try:
            args.path.parent.mkdir(parents=True, exist_ok=True)
            with args.path.open("x", encoding="utf-8", newline="\n") as stream:
                json.dump(template(), stream, indent=2)
                stream.write("\n")
        except FileExistsError:
            print(f"F02_INIT_REFUSED: existing record not overwritten: {args.path}", file=sys.stderr)
            return 2
        except OSError as exc:
            print(f"F02_INIT_FAILED: {exc}", file=sys.stderr)
            return 2
        print(f"F02_RECORD_CREATED: {args.path} (NOT_RUN; no qualification claimed)")
        return 0

    try:
        with args.path.open(encoding="utf-8") as stream:
            doc = json.load(stream)
        errors = validate(doc, args.path)
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        print(f"F02_READ_FAILED: {exc}", file=sys.stderr)
        return 2
    if errors:
        for error in errors:
            print(f"F02_PRECHECK_FAIL: {error}", file=sys.stderr)
        return 1
    print("F02_RECORD_STRUCTURALLY_COMPLETE: hashes, redaction and required observations checked.")
    print("NOT STEAM QUALIFICATION: original logs, distinct real networks and accounts need human review.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
