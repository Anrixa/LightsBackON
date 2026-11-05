"""QA59: scenario-level review is synthetic engineering, not real GPU/UX evidence."""
from __future__ import annotations

import csv
import json
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest

from tools.qa56_analyze import analyze
from tools.qa57_integrity import assess, sha256_file
from tools.qa59_scenario_review import (
    compare_scenarios,
    load_scenario_capture,
    main,
    scenario_frames,
)


SCENES = ("MainMenu", "MissionRoot", "MissionRoot", "MissionRoot", "MainMenu")
DURATIONS = (42, 75, 45, 45, 28)
BASIC_IDENTITY = {
    "build_id": "qa59-synthetic",
    "git_commit": "b" * 40,
    "executable_sha256": "c" * 64,
    "pack_sha256": "d" * 64,
    "build_manifest_sha256": "e" * 64,
    "windows_version": "10.0",
    "video_controller_names": ["TEST SYNTHETIC GPU"],
    "video_controller_driver_versions": ["TEST DRIVER"],
}


def synthetic_rows(resolution: tuple[int, int] = (1280, 720)):
    """F9 markers mirror the QA57 stage contract, with complete warm-up."""
    frames = []
    elapsed_ms = 0.0
    for stage, (scene, seconds) in enumerate(zip(SCENES, DURATIONS)):
        for _ in range(seconds * 60):
            elapsed_ms += 1000.0 / 60.0
            frames.append({
                "elapsed_ms": f"{elapsed_ms:.3f}",
                "frame_ms": "16.667",
                "scene": scene,
                "segment": str(stage),
                "viewport_w": str(resolution[0]),
                "viewport_h": str(resolution[1]),
            })
    resources = [
        {
            "elapsed_s": str(t),
            "working_set_bytes": str(220 * 1048576),
            "private_bytes": str(190 * 1048576),
            "gpu_dedicated_bytes": str(115 * 1048576),
        }
        for t in range(0, sum(DURATIONS) + 1, 2)
    ]
    return frames, resources


def write_rows(path: Path, rows: list[dict[str, str]]) -> None:
    with path.open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def write_capture(folder: Path, resolution=(1280, 720)) -> None:
    frames, resources = synthetic_rows(resolution)
    write_rows(folder / "frames.csv", frames)
    write_rows(folder / "resources.csv", resources)
    log = "Lights Back On boot | engine 4.7.2.stable.official | build qa59-synthetic\n"
    (folder / "godot.log").write_text(log, encoding="utf-8")
    metadata = {
        "session_id": "a" * 32, **BASIC_IDENTITY,
        "engine_version": "4.7.2.stable.official",
        "git_dirty": False,
        "frame_csv_sha256": sha256_file(folder / "frames.csv"),
        "resource_csv_sha256": sha256_file(folder / "resources.csv"),
        "runtime_log_sha256": sha256_file(folder / "godot.log"),
        "runtime_boot_manifest_verified": True,
        "process_samples": len(resources),
        "sample_seconds": 2,
        "exited_naturally": True,
        "process_exit_code": 0,
        "capture_timed_out": False,
    }
    report = analyze(frames, resources)
    integrity = assess(
        metadata, frames, resources, report,
        frame_sha256=metadata["frame_csv_sha256"],
        resource_sha256=metadata["resource_csv_sha256"],
        boot_log_sha256=metadata["runtime_log_sha256"],
        boot_log_text=log,
    )
    assert report["capture_completeness"] == "COMPLETE_FOR_REVIEW", report
    assert integrity["status"] == "COMPLETE_FOR_PHYSICAL_REVIEW", integrity
    for filename, data in (
        ("metadata.json", metadata), ("report.json", report),
        ("integrity.json", integrity),
    ):
        (folder / filename).write_text(
            json.dumps(data, indent=2, sort_keys=True) + "\n", encoding="utf-8"
        )


def fake_capture(resolution: str, session: str):
    def series():
        return {"available": True, "peak_mib": 200.0, "first_last_delta_mib": 2.0}

    dims = (1280, 720) if resolution == "720p" else (1920, 1080)
    frames, _ = synthetic_rows(dims)
    return {
        "resolution": resolution,
        "dimension_coverage": 1.0,
        "session_id": session,
        "identity": dict(BASIC_IDENTITY),
        "stats": {
            "frame_p95_ms": 16.667,
            "frame_p99_ms": 16.667,
            "frame_max_ms": 16.667,
            "ram_working_set": series(),
            "ram_private": series(),
            "gpu_dedicated": series(),
        },
        "stage_metrics": scenario_frames(frames, resolution),
    }


def four_runs():
    return [
        fake_capture("720p", "a" * 32),
        fake_capture("1080p", "b" * 32),
        fake_capture("720p", "c" * 32),
        fake_capture("1080p", "d" * 32),
    ]


class QA59ScenarioTests(unittest.TestCase):
    def test_each_scenario_reports_frames_and_scene_p99(self):
        frames, _ = synthetic_rows()
        stages = scenario_frames(frames, "720p")
        self.assertEqual(set(stages), {"0", "1", "2", "3", "4"})
        self.assertEqual(stages["0"]["scenario"], "initial_menu")
        self.assertEqual(stages["1"]["scenario"], "first_repair")
        self.assertGreater(stages["1"]["frame_count"], 60)
        self.assertEqual(stages["2"]["frame_p95_ms"], 16.667)
        self.assertEqual(stages["3"]["scenes"]["MissionRoot"]["frame_p99_ms"], 16.667)
        self.assertGreaterEqual(stages["4"]["observed_span_s"], 20)

    def test_strict_fixed_resolution_rejects_one_post_warmup_resize(self):
        frames, _ = synthetic_rows()
        frames[400]["viewport_w"] = "1920"
        frames[400]["viewport_h"] = "1080"
        with self.assertRaisesRegex(ValueError, "viewport changed"):
            scenario_frames(frames, "720p")

    def test_wrong_resolution_and_missing_size_fail(self):
        frames, _ = synthetic_rows()
        with self.assertRaisesRegex(ValueError, "viewport changed"):
            scenario_frames(frames, "1080p")
        del frames[400]["viewport_w"]
        with self.assertRaisesRegex(ValueError, "missing viewport"):
            scenario_frames(frames, "720p")

    def test_absent_scenario_and_nonmonotonic_markers_fail(self):
        frames, _ = synthetic_rows()
        short = [row for row in frames if row["segment"] != "3"]
        with self.assertRaisesRegex(ValueError, "scenario 3"):
            scenario_frames(short, "720p")
        frames[-1]["segment"] = "1"
        with self.assertRaisesRegex(ValueError, "markers regress"):
            scenario_frames(frames, "720p")

    def test_nonfinite_or_reordered_frame_time_fail(self):
        frames, _ = synthetic_rows()
        frames[400]["frame_ms"] = "NaN"
        with self.assertRaisesRegex(ValueError, "invalid frame interval"):
            scenario_frames(frames, "720p")
        frames[400]["frame_ms"] = "16.667"
        frames[400]["elapsed_ms"] = frames[399]["elapsed_ms"]
        with self.assertRaisesRegex(ValueError, "not increasing"):
            scenario_frames(frames, "720p")

    def test_report_is_manual_review_only_for_coherent_four_runs(self):
        result = compare_scenarios(four_runs())
        self.assertEqual(result["status"], "COMPLETE_FOR_MANUAL_REVIEW")
        self.assertEqual(result["qa58_status"], "COMPLETE_FOR_MANUAL_REVIEW")
        self.assertEqual(result["release_gate"], "PENDING_PHYSICAL_AND_HUMAN_REVIEW")
        self.assertEqual(result["failures"], [])
        self.assertEqual(len(result["resolution_pairs"]["720p"]["scenarios"]), 5)
        self.assertEqual(result["resolution_pairs"]["1080p"]["scenarios"]["4"][
            "run_2_minus_run_1_p95_ms"
        ], 0.0)

    def test_stage_performance_anomaly_only_triggers_review(self):
        runs = four_runs()
        runs[-1]["stage_metrics"]["1"]["frame_p95_ms"] = 55.0
        result = compare_scenarios(runs)
        self.assertEqual(result["status"], "COMPLETE_FOR_MANUAL_REVIEW")
        self.assertTrue(any("scenario 1" in s for s in result["review_triggers"]))
        self.assertEqual(result["release_gate"], "PENDING_PHYSICAL_AND_HUMAN_REVIEW")

    def test_source_identity_or_duplicate_session_rejected(self):
        runs = four_runs()
        runs[3]["identity"]["build_id"] = "different"
        runs[1]["session_id"] = runs[0]["session_id"]
        result = compare_scenarios(runs)
        self.assertEqual(result["status"], "INCOMPLETE")
        self.assertTrue(any("identity" in s for s in result["failures"]))
        self.assertTrue(any("distinct" in s for s in result["failures"]))

    def test_missing_stage_metrics_rejected(self):
        runs = four_runs()
        del runs[0]["stage_metrics"]["0"]
        self.assertEqual(compare_scenarios(runs)["status"], "INCOMPLETE")

    def test_raw_capture_revalidated_before_scenario_metrics(self):
        with TemporaryDirectory() as temporary:
            folder = Path(temporary)
            write_capture(folder)
            capture = load_scenario_capture(folder)
            self.assertEqual(capture["resolution"], "720p")
            self.assertEqual(capture["stage_metrics"]["2"]["frame_p99_ms"], 16.667)
            (folder / "frames.csv").write_text("tampered", encoding="utf-8")
            with self.assertRaises((ValueError, KeyError)):
                load_scenario_capture(folder)


if __name__ == "__main__":
    unittest.main()
