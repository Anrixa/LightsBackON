"""SAVE22 / ADR-018: rules revision (Python mirror) and the save_compat.json content check."""
from __future__ import annotations

import json
import shutil
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
from build_manifest import content_revision, presentation_paths, rules_revision  # noqa: E402
from validate_content import check_save_compat  # noqa: E402


class RulesRevisionTests(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory(prefix="save22_")
        self.base = Path(self._tmp.name) / "content"
        shutil.copytree(ROOT / "content", self.base)

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def _append(self, rel: str) -> None:
        path = self.base.parent / rel
        path.write_bytes(path.read_bytes() + b"\n")

    def _write_compat(self, entries: object) -> None:
        (self.base / "save_compat.json").write_text(json.dumps({"presentation_only": entries}), encoding="utf-8")

    def test_SAVE22_copy_hashes_like_the_repo(self) -> None:
        self.assertEqual(content_revision(self.base), content_revision())
        self.assertEqual(rules_revision(self.base), rules_revision())
        self.assertNotEqual(rules_revision(), "")
        self.assertNotEqual(rules_revision(), content_revision())

    def test_SAVE22_presentation_edit_keeps_the_rules_revision(self) -> None:
        full, rules = content_revision(self.base), rules_revision(self.base)
        for rel in sorted(presentation_paths(self.base)):
            self._append(rel)
        self.assertNotEqual(content_revision(self.base), full, "joins still see every byte")
        self.assertEqual(rules_revision(self.base), rules)

    def test_SAVE22_rules_and_unlisted_edits_change_both(self) -> None:
        for rel in ["content/contracts/c01_alder_street/grid.json", "content/world/alder_street.json",
                    "content/offline_solo.json", "content/save_compat.json"]:
            full, rules = content_revision(self.base), rules_revision(self.base)
            self._append(rel)
            self.assertNotEqual(content_revision(self.base), full, rel)
            self.assertNotEqual(rules_revision(self.base), rules, rel)

    def test_SAVE22_a_new_unclassified_file_counts_as_rules(self) -> None:
        rules = rules_revision(self.base)
        (self.base / "world" / "look_new.json").write_text("{}\n", encoding="utf-8")
        self.assertNotEqual(rules_revision(self.base), rules)

    def test_SAVE22_broken_list_gives_no_rules_revision(self) -> None:
        for entries in ["not a list", [{"path": "content/ui/missing.json", "reason": "x"}],
                        [{"path": "content/save_compat.json", "reason": "x"}], [{"reason": "no path"}], []]:
            self._write_compat(entries)
            self.assertEqual(rules_revision(self.base), "", repr(entries))
        (self.base / "save_compat.json").write_text("{broken", encoding="utf-8")
        self.assertEqual(rules_revision(self.base), "")
        (self.base / "save_compat.json").unlink()
        self.assertEqual(rules_revision(self.base), "")

    def test_SAVE22_content_check_accepts_the_shipped_list(self) -> None:
        self.assertEqual(check_save_compat(ROOT / "content"), [])

    def test_SAVE22_content_check_refuses_bad_entries(self) -> None:
        cases = {
            "names no file": [{"path": "content/ui/nope.json", "reason": "x"}],
            "needs a reason": [{"path": "content/ui/tokens.json"}],
            "listed twice": [{"path": "content/ui/tokens.json", "reason": "x"}] * 2,
            "no globs": [{"path": "content/ui/*.json", "reason": "x"}],
            "defines rules": [{"path": "content/contracts/c01_alder_street/grid.json", "reason": "x"}],
            "cannot be presentation-only": [{"path": "content/versions.json", "reason": "x"}],
        }
        for expected, entries in cases.items():
            self._write_compat(entries)
            errs = check_save_compat(self.base)
            self.assertTrue(any(expected in e for e in errs), f"{expected}: {errs}")
        (self.base / "save_compat.json").unlink()
        self.assertTrue(any("missing" in e for e in check_save_compat(self.base)))


if __name__ == "__main__":
    unittest.main()
