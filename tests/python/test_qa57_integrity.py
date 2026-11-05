"""QA57 strict capture-integrity checks, with entirely synthetic observations.

Passing these tests means the evidence validator rejects incoherent packages,
not that any physical device was profiled.
"""
import copy
import unittest

from tools.qa57_integrity import assess


def samples():
    # Five marked segments at 60 Hz; exceeds each QA57 minimum after warmup.
    scenes = ("MainMenu", "MissionRoot", "MissionRoot", "MissionRoot", "MainMenu")
    durations = (42, 75, 45, 45, 28)
    frames = []
    t = 0.0
    for index, (scene, duration) in enumerate(zip(scenes, durations)):
        for _ in range(duration * 60):
            t += 1000.0 / 60.0
            frames.append({
                "elapsed_ms": f"{t:.4f}", "frame_ms": "16.667",
                "scene": scene, "segment": str(index),
            })
    resources = [
        {"elapsed_s": str(i * 2), "working_set_bytes": "209715200",
         "private_bytes": "157286400", "gpu_dedicated_bytes": "104857600"}
        for i in range((sum(durations) // 2) + 1)
    ]
    meta = {
        "session_id": "0123456789abcdef" * 2, "git_commit": "b" * 40,
        "build_id": "20261105T120000Z-bbbbbbbbbb", "git_dirty": False,
        "engine_version": "4.7.2.stable.official.abcdef012",
        "executable_sha256": "a" * 64, "pack_sha256": "b" * 64,
        "build_manifest_sha256": "c" * 64,
        "frame_csv_sha256": "d" * 64,
        "resource_csv_sha256": "e" * 64,
        "process_samples": len(resources), "sample_seconds": 2,
        "exited_naturally": True, "process_exit_code": 0,
        "capture_timed_out": False,
    }
    summary = {"capture_completeness": "COMPLETE_FOR_REVIEW",
               "release_gate": "PENDING_PHYSICAL_REVIEW"}
    return [meta, frames, resources, summary]


def check(data):
    m, f, r, s = data
    return assess(m, f, r, s, frame_sha256="d" * 64,
                  resource_sha256="e" * 64)


class CaptureIntegrityTests(unittest.TestCase):
    def setUp(self):
        self.data = samples()

    def test_complete_synthetic_package_is_review_only(self):
        result = check(self.data)
        self.assertEqual(result["failures"], [])
        self.assertEqual(result["status"], "COMPLETE_FOR_PHYSICAL_REVIEW")
        self.assertEqual(result["release_gate"], "PENDING_PHYSICAL_REVIEW")
        self.assertEqual(list(result["stage_coverage"]), ["0", "1", "2", "3", "4"])

    def test_copying_frames_from_another_session_is_rejected(self):
        self.data[0]["frame_csv_sha256"] = "f" * 64
        result = check(self.data)
        self.assertIn("frame CSV checksum mismatch", result["failures"])
        self.assertEqual(result["status"], "INCOMPLETE")

    def test_missing_exit_or_bad_source_pins_rejected(self):
        self.data[0]["exited_naturally"] = False
        self.data[0]["git_commit"] = "none"
        self.data[0]["git_dirty"] = True
        result = check(self.data)
        self.assertTrue(any("did not exit" in x for x in result["failures"]))
        self.assertTrue(any("git_commit" in x for x in result["failures"]))
        self.assertTrue(any("clean source" in x for x in result["failures"]))

    def test_omitted_tablet_workflow_stage_is_rejected(self):
        self.data[1][:] = [x for x in self.data[1] if x["segment"] != "2"]
        result = check(self.data)
        self.assertTrue(any(x.startswith("scenario 2") for x in result["failures"]))

    def test_wrong_scene_in_middle_stage_is_rejected(self):
        for row in self.data[1]:
            if row["segment"] == "3":
                row["scene"] = "MainMenu"
        result = check(self.data)
        self.assertTrue(any("scenario 3 has insufficient" in x for x in result["failures"]))

    def test_out_of_order_f9_marker_is_rejected(self):
        self.data[1][-1]["segment"] = "1"
        result = check(self.data)
        self.assertTrue(any("nonmonotonic" in x for x in result["failures"]))

    def test_short_final_menu_is_rejected(self):
        self.data[1][:] = [
            x for x in self.data[1]
            if x["segment"] != "4" or float(x["elapsed_ms"]) < 214000
        ]
        result = check(self.data)
        self.assertTrue(any("scenario 4 lacks required" in x for x in result["failures"]))

    def test_stale_memory_csv_is_rejected(self):
        self.data[2] = self.data[2][:30]
        self.data[0]["process_samples"] = len(self.data[2])
        result = check(self.data)
        self.assertIn("frame/process timelines diverge", result["failures"])

    def test_missing_gpu_is_not_a_zero_measurement(self):
        for row in self.data[2]:
            row["gpu_dedicated_bytes"] = ""
        result = check(self.data)
        self.assertIn("insufficient dedicated GPU counter samples", result["failures"])

    def test_mismatched_frame_interval_fails_integrity(self):
        # The engine writes both fields from the same monotonic time source.
        self.data[1][180]["frame_ms"] = "1.0"
        result = check(self.data)
        self.assertTrue(any("frame clock continuity" in x for x in result["failures"]))

    def test_unsupported_sample_period_fails_closed(self):
        self.data[0]["sample_seconds"] = 999
        result = check(self.data)
        self.assertTrue(any("sample_seconds must be in 1..10" in x for x in result["failures"]))

    def test_too_few_gpu_samples_is_insufficient(self):
        for row in self.data[2][10:]:
            row["gpu_dedicated_bytes"] = ""
        result = check(self.data)
        self.assertIn("insufficient dedicated GPU counter samples", result["failures"])

    def test_fake_base_release_claim_rejected(self):
        self.data[3]["release_gate"] = "APPROVED"
        self.data[3]["capture_completeness"] = "INCOMPLETE"
        result = check(self.data)
        self.assertTrue(any("must not assert release" in x for x in result["failures"]))
        self.assertEqual(result["status"], "INCOMPLETE")

    def test_nonfinite_timeline_and_sample_mismatch_fail_closed(self):
        self.data[1][-1]["elapsed_ms"] = "nan"
        self.data[0]["process_samples"] += 1
        result = check(self.data)
        self.assertTrue(any("invalid capture timeline" in x for x in result["failures"]))
        self.assertTrue(any("sample count differs" in x for x in result["failures"]))


if __name__ == "__main__":
    unittest.main()
