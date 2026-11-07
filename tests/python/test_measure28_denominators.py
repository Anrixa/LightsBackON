"""MEASURE28: cohort funnel counts are not evidence of human participation."""
from __future__ import annotations

import copy
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from tools import measure_study_denominators as study


class StudyDenominatorTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.path = Path(self.tmp.name) / "counts.json"
        self.empty = {key: 0 for key in study.STAGES}
        self.data = {
            "schema_version": 1,
            "contract": "C01",
            "cohorts": {
                "outside_pairs": dict(self.empty),
                "solo": dict(self.empty),
            },
        }

    def write(self, data: dict | None = None) -> Path:
        self.path.write_text(json.dumps(self.data if data is None else data),
                             encoding="utf-8")
        return self.path

    def test_MEASURE28_empty_template_has_locked_targets_and_no_zero_division(self) -> None:
        out = study.analyze(self.data)
        self.assertEqual(out["planned_pair_sessions"], 6)
        self.assertEqual(out["planned_solo_sessions"], 3)
        self.assertEqual(out["planned_participant_seats"], 15)
        self.assertEqual(out["declared_total_included_sessions"], 0)
        self.assertEqual(out["declared_missing_target_sessions"], 9)
        self.assertIsNone(out["cohorts"]["outside_pairs"]["completion_fraction"])
        self.assertIsNone(out["cohorts"]["solo"]["inclusion_fraction"])

    def test_MEASURE28_full_declared_study_still_cannot_prove_human_playtest(self) -> None:
        for name, sessions in (("outside_pairs", 6), ("solo", 3)):
            self.data["cohorts"][name] = {
                stage: sessions for stage in study.STAGES
            }
        result = study.analyze(self.data)
        self.assertEqual(result["declared_total_included_sessions"], 9)
        self.assertEqual(result["declared_total_included_participant_seats"], 15)
        self.assertEqual(result["declared_missing_target_sessions"], 0)
        self.assertEqual(result["consent_gate"], "HUMAN_PARTICIPANT_CONSENT_VERIFICATION_REQUIRED")
        self.assertEqual(result["playtest_gate"], "REAL_SESSION_EVIDENCE_NOT_VERIFIED")
        self.assertEqual(result["bias_gate"], "HUMAN_RECRUITMENT_BIAS_REVIEW_REQUIRED")
        self.assertEqual(result["release_gate"], "NOT_EVALUATED")

    def test_MEASURE28_partial_funnel_keeps_exact_denominators_and_attrition(self) -> None:
        self.data["cohorts"]["outside_pairs"] = {
            "approached": 10, "eligible": 8, "consented": 7,
            "started": 6, "completed": 5, "included": 4
        }
        output = study.analyze(self.data)
        pairs = output["cohorts"]["outside_pairs"]
        self.assertEqual(pairs["declared_attrition"]["approached_not_eligible"], 2)
        self.assertEqual(pairs["declared_attrition"]["eligible_not_consented"], 1)
        self.assertEqual(pairs["completion_fraction"], {"numerator": 5, "denominator": 6})
        self.assertEqual(pairs["inclusion_fraction"], {"numerator": 4, "denominator": 5})
        self.assertEqual(output["declared_missing_target_sessions"], 5)
        self.assertEqual(output["declared_total_included_participant_seats"], 8)

    def test_MEASURE28_disallows_impossible_later_stage_counts(self) -> None:
        self.data["cohorts"]["solo"]["started"] = 1
        with self.assertRaisesRegex(study.InvalidCohort, "INCONSISTENT_FUNNEL"):
            study.analyze(self.data)

    def test_MEASURE28_rejects_unknown_identifier_fields(self) -> None:
        for scope in ("root", "cohort", "funnel"):
            variant = copy.deepcopy(self.data)
            if scope == "root":
                variant["participant_ref"] = "fixture"
            elif scope == "cohort":
                variant["cohorts"]["additional"] = {}
            else:
                variant["cohorts"]["outside_pairs"]["participant_ref"] = "fixture"
            with self.subTest(scope=scope), self.assertRaises(study.InvalidCohort):
                study.analyze(variant)

    def test_MEASURE28_disallows_negatives_bools_floats_and_huge_counts(self) -> None:
        for value in (True, -1, 1.5, 10001, "3"):
            variant = copy.deepcopy(self.data)
            variant["cohorts"]["solo"]["approached"] = value
            with self.subTest(value=value), self.assertRaisesRegex(
                study.InvalidCohort, "INVALID_FUNNEL_COUNT"
            ):
                study.analyze(variant)

    def test_MEASURE28_rejects_schema_and_contract_changes(self) -> None:
        for name, value in (("schema_version", 2), ("schema_version", True),
                            ("contract", "C02"), ("contract", 1)):
            variant = copy.deepcopy(self.data)
            variant[name] = value
            with self.subTest(name=name, value=value), self.assertRaises(study.InvalidCohort):
                study.analyze(variant)

    def test_MEASURE28_readonly_input_preserves_bytes(self) -> None:
        path = self.write()
        before = path.read_bytes()
        result = study.read_input(path)
        self.assertEqual(result["declared_total_started_sessions"], 0)
        self.assertEqual(path.read_bytes(), before)
        self.assertNotIn(str(path), json.dumps(result))

    def test_MEASURE28_symlink_and_directory_not_followed(self) -> None:
        self.write()
        with self.assertRaisesRegex(study.InvalidCohort, "UNSAFE_INPUT"):
            study.read_input(self.path.parent)
        alias = self.path.parent / "alias.json"
        try:
            alias.symlink_to(self.path)
        except (OSError, NotImplementedError):
            return
        with self.assertRaisesRegex(study.InvalidCohort, "UNSAFE_INPUT"):
            study.read_input(alias)

    def test_MEASURE28_size_limit_and_malformed_json(self) -> None:
        self.path.write_bytes(b" " * (study.MAX_BYTES + 1))
        with self.assertRaisesRegex(study.InvalidCohort, "INPUT_TOO_LARGE"):
            study.read_input(self.path)
        self.path.write_bytes(bytes((255, 254)))
        with self.assertRaisesRegex(study.InvalidCohort, "INVALID_JSON"):
            study.read_input(self.path)

    def test_MEASURE28_rejects_duplicate_keys_and_nonfinite_numbers(self) -> None:
        self.path.write_text('{"schema_version":1,"schema_version":1}', encoding="utf-8")
        with self.assertRaisesRegex(study.InvalidCohort, "DUPLICATE_JSON_KEY"):
            study.read_input(self.path)
        self.path.write_text('{"schema_version":NaN}', encoding="utf-8")
        with self.assertRaisesRegex(study.InvalidCohort, "INVALID_JSON"):
            study.read_input(self.path)

    def test_MEASURE28_cli_errors_are_redacted(self) -> None:
        self.write({"unexpected_fixture": "DO_NOT_ECHO_THIS_MARKER"})
        program = str(Path(study.__file__).resolve())
        result = subprocess.run(
            [sys.executable, program, str(self.path)], text=True,
            capture_output=True, check=False
        )
        self.assertEqual(result.returncode, 2)
        self.assertIn("MEASURE28_ERROR: INVALID_ROOT_FIELDS", result.stderr)
        self.assertNotIn("DO_NOT_ECHO_THIS_MARKER", result.stdout + result.stderr)
        self.assertNotIn(str(self.path), result.stdout + result.stderr)

    def test_MEASURE28_cli_outputs_only_unverified_aggregate_fields(self) -> None:
        self.write()
        result = subprocess.run(
            [sys.executable, str(Path(study.__file__).resolve()), str(self.path)],
            text=True, capture_output=True, check=False
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        data = json.loads(result.stdout)
        self.assertEqual(data["source_attestation"], "OPERATOR_DECLARATION_ONLY")
        self.assertFalse(data["network_upload"])
        self.assertNotIn(str(self.path), result.stdout)


if __name__ == "__main__":
    unittest.main()
