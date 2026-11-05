"""QA58 regressions: synthetic capture consistency is not real GPU evidence."""
import csv
import json
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest

from tools.qa56_analyze import analyze
from tools.qa57_integrity import assess, sha256_file
from tools.qa58_compare import compare, load_capture, resolution_from_frames


def fake_run(resolution: str, session: str, *, build: str = "same"):
    def series():
        return {"available": True, "peak_mib": 200.0, "first_last_delta_mib": 4.0}
    return {
        "resolution": resolution, "dimension_coverage": 1.0, "session_id": session,
        "identity": {"build_id": build, "git_commit": "b" * 40,
                     "video_controller_names": ["NVIDIA GTX1650"],
                     "video_controller_driver_versions": ["example-driver"]},
        "stats": {"frame_p95_ms": 16.7, "frame_p99_ms": 16.7, "frame_max_ms": 16.7,
                  "ram_working_set": series(), "ram_private": series(),
                  "gpu_dedicated": series()},
    }


def four_runs():
    return [
        fake_run("720p", "a" * 32), fake_run("720p", "b" * 32),
        fake_run("1080p", "c" * 32), fake_run("1080p", "d" * 32),
    ]


def make_synthetic_capture(folder: Path) -> None:
    scenes = ("MainMenu", "MissionRoot", "MissionRoot", "MissionRoot", "MainMenu")
    durations = (42, 75, 45, 45, 28)
    frames = []
    elapsed = 0.0
    for index, (scene, seconds) in enumerate(zip(scenes, durations)):
        for _ in range(seconds * 60):
            elapsed += 1000 / 60
            frames.append({
                "elapsed_ms": f"{elapsed:.3f}", "frame_ms": "16.667",
                "scene": scene, "segment": str(index),
                "viewport_w": "1280", "viewport_h": "720",
            })
    resources = [
        {"elapsed_s": str(t), "working_set_bytes": str(200 * 1048576),
         "private_bytes": str(180 * 1048576),
         "gpu_dedicated_bytes": str(110 * 1048576)}
        for t in range(0, sum(durations) + 1, 2)
    ]
    for filename, rows in (("frames.csv", frames), ("resources.csv", resources)):
        with (folder / filename).open("w", newline="", encoding="utf-8") as stream:
            writer = csv.DictWriter(stream, fieldnames=list(rows[0]))
            writer.writeheader()
            writer.writerows(rows)
    boot = "Lights Back On boot | engine 4.7.2.stable.official | build pin-01\n"
    (folder / "godot.log").write_text(boot, encoding="utf-8")
    metadata = {
        "session_id": "a" * 32, "git_commit": "b" * 40, "build_id": "pin-01",
        "git_dirty": False, "engine_version": "4.7.2.stable.official.sample",
        "executable_sha256": "a" * 64, "pack_sha256": "b" * 64,
        "build_manifest_sha256": "c" * 64,
        "frame_csv_sha256": sha256_file(folder / "frames.csv"),
        "resource_csv_sha256": sha256_file(folder / "resources.csv"),
        "runtime_log_sha256": sha256_file(folder / "godot.log"),
        "runtime_boot_manifest_verified": True, "process_samples": len(resources),
        "sample_seconds": 2, "exited_naturally": True, "process_exit_code": 0,
        "capture_timed_out": False, "windows_version": "10.0",
        "video_controller_names": ["NVIDIA GTX1650"],
        "video_controller_driver_versions": ["example-driver"],
    }
    report = analyze(frames, resources)
    integrity = assess(
        metadata, frames, resources, report,
        frame_sha256=metadata["frame_csv_sha256"],
        resource_sha256=metadata["resource_csv_sha256"],
        boot_log_sha256=metadata["runtime_log_sha256"],
        boot_log_text=boot,
    )
    assert integrity["status"] == "COMPLETE_FOR_PHYSICAL_REVIEW", integrity
    for filename, object_ in (
        ("metadata.json", metadata), ("report.json", report),
        ("integrity.json", integrity),
    ):
        (folder / filename).write_text(
            json.dumps(object_, indent=2, sort_keys=True), encoding="utf-8"
        )


class QA58Tests(unittest.TestCase):
    def test_four_synthetic_runs_are_manual_review_only(self):
        result = compare(four_runs())
        self.assertEqual(result["status"], "COMPLETE_FOR_MANUAL_REVIEW")
        self.assertEqual(result["failures"], [])
        self.assertEqual(set(result["comparisons"]), {"720p", "1080p"})
        self.assertEqual(result["release_gate"], "PENDING_PHYSICAL_AND_HUMAN_REVIEW")

    def test_insufficient_resolution_repeats(self):
        result = compare([fake_run("720p", str(i)) for i in range(4)])
        self.assertEqual(result["status"], "INCOMPLETE")
        self.assertTrue(any("1080p" in message for message in result["failures"]))

    def test_duplicate_session_and_mismatched_export_rejected(self):
        runs = four_runs()
        runs[1]["session_id"] = runs[0]["session_id"]
        runs[3]["identity"]["build_id"] = "wrong"
        problems = compare(runs)["failures"]
        self.assertTrue(any("distinct" in message for message in problems))
        self.assertTrue(any("identity" in message for message in problems))

    def test_absent_gpu_samples_prevent_complete_comparison(self):
        runs = four_runs()
        runs[0]["stats"]["gpu_dedicated"]["available"] = False
        self.assertEqual(compare(runs)["status"], "INCOMPLETE")

    def test_frame_and_memory_anomalies_only_trigger_manual_review(self):
        runs = four_runs()
        runs[-1]["stats"]["frame_p95_ms"] = 39.0
        runs[1]["stats"]["gpu_dedicated"]["peak_mib"] = 500.0
        result = compare(runs)
        self.assertEqual(result["status"], "COMPLETE_FOR_MANUAL_REVIEW")
        self.assertEqual(len(result["review_triggers"]), 2)
        self.assertEqual(result["release_gate"], "PENDING_PHYSICAL_AND_HUMAN_REVIEW")

    def test_observed_viewport_rejects_resize_and_malformed_fields(self):
        rows = [{"elapsed_ms": str(i + 6000), "viewport_w": "1280",
                 "viewport_h": "720"} for i in range(200)]
        self.assertEqual(resolution_from_frames(rows), ("720p", 1.0))
        for row in rows[:20]:
            row["viewport_w"], row["viewport_h"] = "1920", "1080"
        with self.assertRaisesRegex(ValueError, "expected fixed"):
            resolution_from_frames(rows)
        rows[0].pop("viewport_w")
        with self.assertRaisesRegex(ValueError, "missing or invalid"):
            resolution_from_frames(rows)

    def test_synthetic_raw_files_recompute_and_tampering_rejected(self):
        with TemporaryDirectory() as temporary:
            folder = Path(temporary)
            make_synthetic_capture(folder)
            observed = load_capture(folder)
            self.assertEqual(observed["resolution"], "720p")
            self.assertEqual(observed["stats"]["frame_p95_ms"], 16.667)
            (folder / "frames.csv").write_text("corrupted", encoding="utf-8")
            with self.assertRaises((ValueError, KeyError)):
                load_capture(folder)

    def test_forged_p95_json_is_rejected(self):
        with TemporaryDirectory() as temporary:
            folder = Path(temporary)
            make_synthetic_capture(folder)
            path = folder / "report.json"
            altered = json.loads(path.read_text(encoding="utf-8"))
            altered["frame_p95_ms"] = 1.0
            path.write_text(json.dumps(altered), encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "recalculated raw metrics"):
                load_capture(folder)


if __name__ == "__main__":
    unittest.main()
