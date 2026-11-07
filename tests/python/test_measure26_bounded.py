"""MEASURE26: bounded descriptor semantics for local report analysis."""
from __future__ import annotations

import json
import os
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from tools import measure_report, measure_review


class BoundedDescriptorTests(unittest.TestCase):
    def setUp(self) -> None:
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.file = Path(temp.name) / "c01-a.json"
        self.sample = {
            "schema_version": 1, "contract": "C01",
            "tick_rate_hz": 10, "opted_in": True,
            "outcome": "left", "dropped_events": 0, "last_tick": 10,
            "events": [
                {"kind": "session_started", "tick": 0},
                {"kind": "session_left", "tick": 10},
            ],
        }
        self.file.write_text(json.dumps(self.sample), encoding="utf-8")

    def test_MEASURE26_preserves_public_reader_compatibility(self) -> None:
        report = measure_report.read_report(self.file)
        self.assertEqual(report["outcome"], "left")
        self.assertEqual(report["counts"]["session_left"], 1)

    def test_MEASURE26_metadata_and_digest_do_not_leave_aggregate(self) -> None:
        os.utime(self.file, (1_900_000_000, 1_900_000_000))
        report = measure_report.read_report(self.file)
        self.assertAlmostEqual(report["_internal_file_mtime"], 1_900_000_000, delta=1)
        reviewed = measure_review.review_input(self.file, now_utc=1_900_000_001)
        serialized = json.dumps(reviewed)
        self.assertEqual(reviewed["retention"]["gate"], "WITHIN_REVIEW_WINDOW")
        self.assertNotIn("_internal_fingerprint", serialized)
        self.assertNotIn("_internal_file_mtime", serialized)

    def test_MEASURE26_exact_maximum_file_bytes_is_allowed(self) -> None:
        raw = self.file.read_bytes()
        self.file.write_bytes(raw + b" " * (measure_report.MAX_FILE_BYTES - len(raw)))
        self.assertEqual(measure_report.read_report(self.file)["last_tick"], 10)

    def test_MEASURE26_oversize_file_is_rejected(self) -> None:
        self.file.write_bytes(b" " * (measure_report.MAX_FILE_BYTES + 1))
        with self.assertRaisesRegex(measure_report.InvalidReport, "REPORT_TOO_LARGE"):
            measure_report.read_report(self.file)

    def test_MEASURE26_directory_and_symlink_are_rejected(self) -> None:
        with self.assertRaisesRegex(measure_report.InvalidReport, "UNSAFE_REPORT_FILE"):
            measure_report.read_report(self.file.parent)
        symlink = self.file.parent / "c01-link.json"
        try:
            symlink.symlink_to(self.file)
        except (OSError, NotImplementedError):
            return
        with self.assertRaisesRegex(measure_report.InvalidReport, "UNSAFE_REPORT_FILE"):
            measure_report.read_report(symlink)

    def test_MEASURE26_inode_replacement_between_check_and_open(self) -> None:
        original_open = os.open
        old_file = self.file.with_suffix(".old")
        def swap_on_open(path: str | os.PathLike[str], flags: int) -> int:
            self.file.replace(old_file)
            self.file.write_text(json.dumps(self.sample), encoding="utf-8")
            return original_open(path, flags)
        with mock.patch.object(measure_report.os, "open", side_effect=swap_on_open):
            with self.assertRaisesRegex(measure_report.InvalidReport, "UNSAFE_REPORT_FILE"):
                measure_report.read_report(self.file)

    def test_MEASURE26_size_growth_before_open_is_rejected(self) -> None:
        original_open = os.open
        def grow_on_open(path: str | os.PathLike[str], flags: int) -> int:
            with self.file.open("ab") as sink:
                sink.write(b" " * (measure_report.MAX_FILE_BYTES + 1))
            return original_open(path, flags)
        with mock.patch.object(measure_report.os, "open", side_effect=grow_on_open):
            with self.assertRaisesRegex(measure_report.InvalidReport, "REPORT_TOO_LARGE"):
                measure_report.read_report(self.file)

    def test_MEASURE26_invalid_utf8_has_stable_error(self) -> None:
        self.file.write_bytes(bytes((255, 254)))
        with self.assertRaisesRegex(measure_report.InvalidReport, "INVALID_JSON"):
            measure_report.read_report(self.file)


if __name__ == "__main__":
    unittest.main()
