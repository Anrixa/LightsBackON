"""Regression tests for F02 evidence preflight; no Steam network is simulated."""

from __future__ import annotations

import hashlib
import json
import tempfile
import unittest
from pathlib import Path

from tools import f02_evidence


class F02EvidenceTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.record_path = self.root / "F02-record.json"
        self.record = f02_evidence.template()
        self.record["tuple"].update(
            godot_binary_sha256="a" * 64,
            export_templates_sha256="b" * 64,
            steam_peer_class="VerifiedPeerClass",
            steamworks_runtime_version="captured-build-1",
        )
        self.record["tuple"]["extensions"] = [
            {
                "name": "approved-extension",
                "source_revision": "pinned-test-revision",
                "license": "MIT",
                "binary_sha256": "c" * 64,
            }
        ]
        self.record["build"].update(
            build_id="windows-test-build",
            windows_exe_sha256="d" * 64,
            windows_pck_sha256="e" * 64,
        )
        for field in f02_evidence.NETWORK_FIELDS:
            self.record["network"][field] = True
        self.record["review"] = {
            "human_checked_real_networks": True,
            "human_checked_log_redaction": True,
            "reviewer_note": "Synthetic fixture for validator testing only, not a network result.",
        }
        logs = self.root / "logs"
        logs.mkdir()
        for case in self.record["cases"]:
            name = case["id"] + ".txt"
            content = ("Redacted synthetic fixture for " + case["id"] + "\n") * 3
            evidence = logs / name
            evidence.write_text(content, encoding="utf-8")
            case["status"] = "PASS"
            case["evidence_path"] = "logs/" + name
            case["evidence_sha256"] = hashlib.sha256(evidence.read_bytes()).hexdigest()

    def check(self) -> list[str]:
        return f02_evidence.validate(self.record, self.record_path)

    def test_complete_synthetic_fixture_is_structurally_valid_not_qualified(self) -> None:
        self.assertEqual(self.check(), [])
        # Passing this synthetic check never proves a real Steam connection.

    def test_blank_template_fails_closed(self) -> None:
        errors = f02_evidence.validate(f02_evidence.template(), self.record_path)
        self.assertTrue(any("NOT_RUN" in error for error in errors))
        self.assertTrue(any("network.two_distinct_pcs" in error for error in errors))

    def test_two_distinct_accounts_required(self) -> None:
        self.record["network"]["two_distinct_licensed_accounts"] = False
        self.assertTrue(any("two_distinct_licensed_accounts" in error for error in self.check()))

    def test_independent_networks_required(self) -> None:
        self.record["network"]["independent_networks"] = False
        self.assertTrue(any("independent_networks" in error for error in self.check()))

    def test_missing_case_is_rejected(self) -> None:
        self.record["cases"].pop()
        self.assertTrue(any("missing required observations" in error for error in self.check()))

    def test_duplicate_case_is_rejected(self) -> None:
        self.record["cases"].append(dict(self.record["cases"][0]))
        self.assertTrue(any("duplicate case" in error for error in self.check()))

    def test_incomplete_hash_is_rejected(self) -> None:
        self.record["tuple"]["godot_binary_sha256"] = "abcd"
        self.assertTrue(any("64-character SHA-256" in error for error in self.check()))

    def test_modified_log_is_rejected(self) -> None:
        evidence = self.root / self.record["cases"][0]["evidence_path"]
        evidence.write_text("Changed after digest was recorded.", encoding="utf-8")
        self.assertTrue(any("does not match file" in error for error in self.check()))

    def test_path_traversal_is_rejected(self) -> None:
        self.record["cases"][0]["evidence_path"] = "../outside.log"
        self.assertTrue(any("unsafe or non-normalized" in error for error in self.check()))

    def test_absolute_path_is_rejected(self) -> None:
        self.record["cases"][0]["evidence_path"] = "C:\\secrets\\steam.log"
        self.assertTrue(any("relative forward-slash path" in error for error in self.check()))

    def test_unredacted_steam_id_is_rejected(self) -> None:
        evidence = self.root / self.record["cases"][0]["evidence_path"]
        evidence.write_text("Unredacted account number 76561198012345678\n", encoding="utf-8")
        self.record["cases"][0]["evidence_sha256"] = hashlib.sha256(evidence.read_bytes()).hexdigest()
        self.assertTrue(any("Steam ID" in error for error in self.check()))

    def test_unredacted_ip_is_rejected(self) -> None:
        evidence = self.root / self.record["cases"][0]["evidence_path"]
        evidence.write_text("WAN egress address 203.0.113.42\n", encoding="utf-8")
        self.record["cases"][0]["evidence_sha256"] = hashlib.sha256(evidence.read_bytes()).hexdigest()
        self.assertTrue(any("IPv4" in error for error in self.check()))

    def test_human_review_cannot_be_omitted(self) -> None:
        self.record["review"]["human_checked_real_networks"] = False
        self.assertTrue(any("human_checked_real_networks" in error for error in self.check()))

    def test_init_refuses_to_overwrite_a_record(self) -> None:
        self.record_path.write_text('{"existing":"preserve"}', encoding="utf-8")
        self.assertEqual(f02_evidence.main(["init", str(self.record_path)]), 2)
        self.assertEqual(json.loads(self.record_path.read_text(encoding="utf-8")), {"existing": "preserve"})

    def test_missing_evidence_file_is_rejected(self) -> None:
        (self.root / self.record["cases"][1]["evidence_path"]).unlink()
        self.assertTrue(any("missing evidence file" in error for error in self.check()))


if __name__ == "__main__":
    unittest.main()
