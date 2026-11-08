"""QA140 summary: percentiles per segment, warm-up exclusion, unknown GPU counters stay unknown."""
import json
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest

from tools.qa140_summarize import rank, summarize_run


def write_run(root: Path, gpu_column: str) -> Path:
    run = root / "nv_gl_1080"
    run.mkdir()
    run.joinpath("done.json").write_text(json.dumps({"exit_code": 0, "timed_out": False, "error": ""}), encoding="utf-8")
    lines = ["elapsed_ms,frame_ms,scene,segment,viewport_w,viewport_h"]
    # 0-5 s warm-up holds one huge stall that must not count.
    lines.append("100.0,900.0,MainMenu,0,1920,1080")
    for i in range(1, 101):
        lines.append(f"{5000.0 + i * 10.0},{float(i)},MissionRoot,1,1920,1080")
    run.joinpath("frames.csv").write_text("\n".join(lines) + "\n", encoding="utf-8")
    run.joinpath("resources.csv").write_text(
        '"elapsed_s","working_set_bytes","private_bytes","gpu_dedicated_bytes","gpu_shared_bytes"\n'
        f'"0.1","1048576","1048576","{gpu_column}",""\n"2.1","2097152","1048576","{gpu_column}",""\n', encoding="utf-8")
    return run


class QA140SummaryTest(unittest.TestCase):
    def test_QA140_nearest_rank_percentiles(self):
        values = [float(v) for v in range(1, 101)]
        self.assertEqual(rank(values, 0.95), 95.0)
        self.assertEqual(rank(values, 0.50), 50.0)

    def test_QA140_warmup_excluded_and_segment_stats(self):
        with TemporaryDirectory() as tmp:
            run = summarize_run(write_run(Path(tmp), "1048576"))
        self.assertEqual(run["frames_overall"]["count"], 100)
        self.assertEqual(run["frames_overall"]["max_ms"], 100.0)
        self.assertEqual(run["frames_by_segment"]["1"]["p95_ms"], 95.0)
        self.assertEqual(run["working_set_peak_mib"], 2.0)
        self.assertEqual(run["gpu_dedicated_peak_mib"], 1.0)

    def test_QA140_missing_gpu_counter_is_unknown_not_zero(self):
        with TemporaryDirectory() as tmp:
            run = summarize_run(write_run(Path(tmp), ""))
        self.assertIsNone(run["gpu_dedicated_peak_mib"])
        self.assertIsNone(run["gpu_shared_peak_mib"])


if __name__ == "__main__":
    unittest.main()
