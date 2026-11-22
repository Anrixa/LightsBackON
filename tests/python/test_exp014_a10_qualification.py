"""EXP014 A10.4 qualification-gate mutation and exported-smoke tests.

No remote repository, player, GPU, Steam, production profile or real exported
executable is required; export cases use clearly synthetic local fixture bytes.
"""
from __future__ import annotations

import copy
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from tools import qualify_exp014_a10 as q


class QualificationSourceTests(unittest.TestCase):
    def test_green_source_contains_pinned_protected_contracts(self) -> None:
        audited = q.protected_git_audit()
        self.assertEqual(len(audited["protected_objects"]), 9)
        self.assertTrue(audited["protected_worktree_clean"])
        self.assertEqual(
            audited["original_contract_tree_object"],
            q.PROTECTED_GIT_OBJECTS["content/contracts"],
        )

    def test_exact_post_baseline_host_revision_is_pinned_not_certified(self) -> None:
        audited = q.protected_git_audit()
        host_path = "scripts/network/session_host.gd"
        host_oid = audited["protected_objects"][host_path]
        allowed = {q.PROTECTED_GIT_OBJECTS[host_path],
                   *q.PINNED_SESSION_HOST_EVOLUTIONS.values()}
        self.assertIn(host_oid, allowed)
        self.assertFalse(audited["source_host_evolution_independently_reviewed"])
        if host_oid != q.PROTECTED_GIT_OBJECTS[host_path]:
            self.assertEqual(audited["source_host_evolution"],
                             "EXP015_A12_11_HOST_TICK_FENCE")

    def test_unlisted_host_revision_is_rejected_fail_closed(self) -> None:
        with patch.dict(q.PINNED_SESSION_HOST_EVOLUTIONS,
                        {"EXP015_A12_11_HOST_TICK_FENCE": "f" * 40}):
            with self.assertRaisesRegex(q.QualificationError,
                                        "PROTECTED_SOURCE_DRIFT"):
                q.protected_git_audit()

    def test_original_contract_tree_drift_is_rejected(self) -> None:
        with patch.dict(q.PROTECTED_GIT_OBJECTS,
                        {"content/contracts": "0" * 40}):
            with self.assertRaisesRegex(q.QualificationError,
                                        "PROTECTED_SOURCE_DRIFT"):
                q.protected_git_audit()

    def test_exp04_ledger_and_legacy_credits_drift_is_rejected(self) -> None:
        for path in (
            "scripts/progression/reward_service.gd",
            "scripts/progression/expedition_ledger.gd",
            "scripts/persistence/save_service.gd",
        ):
            with self.subTest(path=path):
                with patch.dict(q.PROTECTED_GIT_OBJECTS, {path: "1" * 40}):
                    with self.assertRaisesRegex(q.QualificationError,
                                                "PROTECTED_SOURCE_DRIFT"):
                        q.protected_git_audit()

    def test_full_source_parity_counts_and_fingerprint(self) -> None:
        result = q.source_audit()
        self.assertTrue(result["source_coverage_checked"])
        self.assertEqual(result["expected"]["levels"], 200)
        self.assertEqual(result["expected"]["immutable_task_ids"], 1000)
        self.assertEqual(result["expected"]["cross_system_campaign_branch_scenarios"], 50)
        self.assertEqual(result["investigation_graphs"],
                         {"forensic": 200, "field": 200})
        self.assertEqual(len(result["mechanical_fingerprint_sha256"]), 64)

    def test_id_normalized_mechanical_uniqueness_is_independent(self) -> None:
        books = q.read_sources()
        result = q.id_normalized_mechanical_audit(
            books["contingencies"], books["investigations"])
        self.assertEqual(result["site_count"], 200)
        self.assertEqual(result["unique_mechanics_without_ids"], 200)
        self.assertEqual(len(result["normalized_signature_set_sha256"]), 64)

    def test_renamed_targets_and_timers_cannot_mint_new_mechanics(self) -> None:
        books = q.read_sources()
        case = copy.deepcopy(books["contingencies"]["entries"][0])
        inquiry = copy.deepcopy(books["investigations"]["entries"][0])
        before = q.mechanical_structure(case, inquiry)
        old_targets = dict(case["targets"])
        remap = {target: "TEST_TARGET_" + role
                 for role, target in old_targets.items()}
        case["targets"] = {role: remap[target]
                           for role, target in old_targets.items()}
        for route in case["routes"].values():
            for step in route:
                for field in ("target", "support", "witness"):
                    step[field] = remap[step[field]]
                step["dwell_ticks"] = 999
                step["action"] = "NEW_COSMETIC_LABEL"
        for branch in inquiry["branches"].values():
            for node in branch["nodes"]:
                node["dwell_ticks"] = 12345
                node["source_action"] = "RENAMED_ACTION"
        self.assertEqual(q.mechanical_structure(case, inquiry), before)
        self.assertEqual(
            q.canonical_sha(q.mechanical_structure(case, inquiry)),
            q.canonical_sha(before),
        )

    def test_relabelled_mechanical_copy_is_rejected_as_duplicate(self) -> None:
        books = q.read_sources()
        old = books["contingencies"]["entries"]
        inquiries = books["investigations"]["entries"]
        first = old[0]
        second = old[1]
        inverse_first = {val: key for key, val in first["targets"].items()}
        second["routes"] = copy.deepcopy(first["routes"])
        for route in second["routes"].values():
            for step in route:
                for field in ("target", "support", "witness"):
                    role = inverse_first[step[field]]
                    step[field] = second["targets"][role]
        inquiries[1]["branches"] = copy.deepcopy(inquiries[0]["branches"])
        inquiries[1]["risk_class"] = inquiries[0]["risk_class"]
        with self.assertRaisesRegex(q.QualificationError,
                                    "RENAMED_SITE_MECHANICAL_COLLISION"):
            q.id_normalized_mechanical_audit(
                books["contingencies"], books["investigations"])

    def test_godot_test_inventory_exists_but_does_not_pretend_execution(self) -> None:
        item = q.host_test_inventory()
        self.assertEqual(item["expected_test_methods"], 9)
        self.assertEqual(item["discovered_test_methods"], 9)
        self.assertFalse(item["execution_proved_by_this_check"])
        self.assertTrue(item["execution_requires_exact_head_linux_windows_ci"])

    def test_removed_host_test_detected_independently(self) -> None:
        key = "tests/integration/test_EXP014_A10_3_adversarial_invariants.gd"
        with patch.dict(q.REQUIRED_GODOT_TESTS,
                        {key: (*q.REQUIRED_GODOT_TESTS[key],
                               "test_EXP014_A10_3_fabricated_proof")}):
            with self.assertRaisesRegex(q.QualificationError,
                                        "MISSING_GODOT_TESTS"):
                q.host_test_inventory()

    def test_duplicate_test_names_rejected_without_code_execution(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "test_case.gd"
            path.write_text(
                "func test_EXP014_A10_2_a() -> void:\n"
                "\tpass\n"
                "func test_EXP014_A10_2_a() -> void:\n"
                "\tpass\n",
                encoding="utf-8",
            )
            with self.assertRaisesRegex(q.QualificationError,
                                        "DUPLICATE_HOST_TEST"):
                q.discover_host_tests(path)

    def test_positive_source_gate_still_preserves_release_holds(self) -> None:
        result = q.qualify()
        self.assertTrue(result["ok"])
        self.assertFalse(result["ready_for_merge_or_release"])
        self.assertFalse(result["windows_export_verified"])
        self.assertIsNone(result["windows_export"])
        self.assertEqual(result["current_exact_head_ci_status"],
                         "EXTERNAL_EVIDENCE_NOT_INFERRED")
        self.assertEqual(result["all_owner_release_holds"]["production_release"],
                         "HOLD")
        self.assertEqual(result["independent_review_status"], "PENDING")


class WindowsExportEvidenceTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tempdir = tempfile.TemporaryDirectory()
        self.addCleanup(self.tempdir.cleanup)
        self.root = Path(self.tempdir.name)
        self.export = self.root / "windows"
        self.export.mkdir()
        self.manifest = self.root / "build_manifest.json"
        self.smoke = self.root / "smoke.log"
        self.head = "b" * 40
        self.build_id = "20261122T080000Z-" + self.head[:10]
        self.metadata = {
            "git_commit": self.head, "git_dirty": False,
            "build_id": self.build_id, "content_revision": "c" * 64,
            "rules_revision": "d" * 64,
        }
        self.refresh_manifest()
        (self.export / "LightsBackOn.exe").write_bytes(b"E" * 8192)
        (self.export / "LightsBackOn.pck").write_bytes(b"P" * 8192)
        self.smoke.write_text(
            f"Lights Back On boot | engine 4.7.2.stable | build {self.build_id}\n",
            encoding="utf-8",
        )

    def refresh_manifest(self) -> None:
        content = json.dumps(self.metadata, sort_keys=True) + "\n"
        self.manifest.write_text(content, encoding="utf-8")
        (self.export / "build_manifest.json").write_text(content, encoding="utf-8")

    def inspect(self) -> dict:
        return q.exported_windows_evidence(
            self.export, self.manifest, self.smoke, self.head
        )

    def test_synthetic_correct_export_is_qualified_headless_only(self) -> None:
        result = self.inspect()
        self.assertEqual(result["status"],
                         "WINDOWS_HEADLESS_EXPORTED_BOOT_EVIDENCE_ONLY")
        self.assertFalse(result["physical_and_multiplayer_certified"])
        self.assertEqual(result["build_id"], self.build_id)
        self.assertEqual(len(result["artifacts"]["LightsBackOn.exe"]["sha256"]), 64)

    def test_bogus_head_or_dirty_manifest_is_rejected(self) -> None:
        for data in ({"git_commit": "a" * 40}, {"git_dirty": True}):
            with self.subTest(change=data):
                old = self.metadata.copy()
                self.metadata.update(data)
                self.refresh_manifest()
                with self.assertRaisesRegex(
                        q.QualificationError, "WINDOWS_EXPORT_SOURCE_NOT_PINN"):
                    self.inspect()
                self.metadata = old

    def test_mismatched_packaged_manifest_is_rejected(self) -> None:
        (self.export / "build_manifest.json").write_text(
            '{"build_id":"foreign"}\n', encoding="utf-8")
        with self.assertRaisesRegex(q.QualificationError,
                                    "WINDOWS_PACKAGED_MANIFEST_MISMATCH"):
            self.inspect()

    def test_wrong_boot_identity_is_rejected(self) -> None:
        self.smoke.write_text(
            "Lights Back On boot | engine 4.7.2.stable | build DIFFERENT\n",
            encoding="utf-8")
        with self.assertRaisesRegex(q.QualificationError,
                                    "WINDOWS_BOOT_SOURCE_MISMATCH"):
            self.inspect()

    def test_missing_or_empty_export_is_rejected(self) -> None:
        (self.export / "LightsBackOn.pck").write_bytes(b"")
        with self.assertRaisesRegex(q.QualificationError,
                                    "WINDOWS_EXPORTED_BINARY_MISSING"):
            self.inspect()

    def test_incomplete_export_arguments_fail_closed(self) -> None:
        with patch.object(q, "protected_git_audit", return_value={"head_commit": self.head}), \
             patch.object(q, "source_audit", return_value={}), \
             patch.object(q, "host_test_inventory", return_value={}):
            with self.assertRaisesRegex(q.QualificationError,
                                        "PARTIAL_WINDOWS_EVIDENCE_ARGUMENTS"):
                q.qualify(windows_export_dir=self.export)


if __name__ == "__main__":
    unittest.main()
