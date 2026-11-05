"""QA56 offline regression checks for non-fabricated performance evidence."""
import csv
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest

from tools.qa56_analyze import analyze, percentile, read_csv


def frame_rows(count=8000, interval=16.7):
    return [
        {"elapsed_ms": str(i * interval), "frame_ms": str(interval),
         "scene": "MainMenu" if i < count // 2 else "MissionRoot",
         "segment": "0" if i < count // 2 else "1"}
        for i in range(1, count + 1)
    ]


def memory_rows(count=65, gpu="104857600"):
    return [
        {"elapsed_s": str(i * 2), "working_set_bytes": str(200 * 1048576 + i),
         "private_bytes": str(150 * 1048576 + i),
         "gpu_dedicated_bytes": gpu}
        for i in range(count)
    ]


class QA56AnalyzerTests(unittest.TestCase):
    def test_p95_uses_nearest_rank_not_average(self):
        self.assertEqual(percentile([10.0] * 95 + [100.0] * 5, .95), 10.0)
        self.assertEqual(percentile([10.0] * 95 + [100.0] * 5, .99), 100.0)

    def test_observed_complete_never_claims_release_approved(self):
        report = analyze(frame_rows(), memory_rows())
        self.assertEqual(report["capture_completeness"], "COMPLETE_FOR_REVIEW")
        self.assertEqual(report["release_gate"], "PENDING_PHYSICAL_REVIEW")
        self.assertEqual(report["frame_p95_ms"], 16.7)
        self.assertEqual(report["gpu_dedicated"]["peak_mib"], 100.0)
        self.assertIn("MainMenu", report["scenes"])
        self.assertIn("MissionRoot", report["scenes"])

    def test_missing_gpu_is_unknown_not_zero(self):
        report = analyze(frame_rows(), memory_rows(gpu=""))
        self.assertEqual(report["capture_completeness"], "INCOMPLETE")
        self.assertEqual(report["gpu_dedicated"]["available"], False)
        self.assertIsNone(report["gpu_dedicated"]["peak_mib"])

    def test_warmup_is_explicitly_excluded(self):
        rows = frame_rows()
        rows[0]["frame_ms"] = "200"
        report = analyze(rows, memory_rows())
        self.assertEqual(report["frame_p95_ms"], 16.7)
        self.assertEqual(report["frame_max_ms"], 16.7)

    def test_invalid_or_reordered_samples_fail_closed(self):
        rows = frame_rows(700)
        rows[2]["elapsed_ms"] = rows[1]["elapsed_ms"]
        with self.assertRaisesRegex(ValueError, "strictly increasing"):
            analyze(rows, memory_rows())
        bad = memory_rows()
        bad[1]["gpu_dedicated_bytes"] = "nan"
        with self.assertRaisesRegex(ValueError, "nonfinite"):
            analyze(frame_rows(), bad)

    def test_short_capture_fails_completeness_not_metrics(self):
        report = analyze(frame_rows(count=1000), memory_rows(count=8))
        self.assertEqual(report["capture_completeness"], "INCOMPLETE")
        self.assertGreater(report["frame_count_post_warmup"], 0)

    def test_required_csv_fields_are_checked(self):
        with TemporaryDirectory() as folder:
            path = Path(folder) / "missing.csv"
            with path.open("w", newline="", encoding="utf-8") as stream:
                writer = csv.DictWriter(stream, fieldnames=["frame_ms"])
                writer.writeheader()
                writer.writerow({"frame_ms": 16.7})
            with self.assertRaisesRegex(ValueError, "missing required"):
                read_csv(path, {"elapsed_ms", "frame_ms"})


if __name__ == "__main__":
    unittest.main()
