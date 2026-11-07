"""MEASURE25: terminal provenance is necessary for credible C01 cohort counts."""
from __future__ import annotations

import copy
import unittest

from tools import measure_report


class TerminalProvenanceTests(unittest.TestCase):
    def setUp(self) -> None:
        self.report = {
            "schema_version": 1, "contract": "C01",
            "tick_rate_hz": 10, "opted_in": True,
            "dropped_events": 0, "outcome": "completed", "last_tick": 10,
            "events": [
                {"kind": "session_started", "tick": 0},
                {"kind": "first_repair", "tick": 3},
                {"kind": "session_completed", "tick": 9},
                {"kind": "objective_completed", "tick": 9, "objective_index": 0},
                {"kind": "results_opened", "tick": 10},
            ],
        }

    def check_rejected(self, events: list[dict], reason: str) -> None:
        sample = copy.deepcopy(self.report)
        sample["events"] = events
        with self.assertRaisesRegex(measure_report.InvalidReport, "^" + reason + "$"):
            measure_report.validate(sample)

    def test_MEASURE25_valid_live_completion_allows_final_objective_snapshot(self) -> None:
        result = measure_report.validate(self.report)
        self.assertEqual(result["counts"]["session_completed"], 1)
        self.assertEqual(result["counts"]["results_opened"], 1)

    def test_MEASURE25_repeat_completion_does_not_double_count(self) -> None:
        events = copy.deepcopy(self.report["events"])
        events.insert(3, {"kind": "session_completed", "tick": 9})
        self.check_rejected(events, "REPEATED_TERMINAL_EVENT")

    def test_MEASURE25_conflicting_terminals_cannot_be_aggregated(self) -> None:
        events = copy.deepcopy(self.report["events"])
        events.insert(3, {"kind": "session_left", "tick": 9})
        self.check_rejected(events, "CONFLICTING_OUTCOME")

    def test_MEASURE25_first_successful_repair_only_once(self) -> None:
        events = copy.deepcopy(self.report["events"])
        events.insert(2, {"kind": "first_repair", "tick": 8})
        self.check_rejected(events, "REPEATED_FIRST_REPAIR")

    def test_MEASURE25_debrief_never_precedes_completion(self) -> None:
        events = copy.deepcopy(self.report["events"])
        events.insert(2, {"kind": "results_opened", "tick": 8})
        events.pop()
        self.check_rejected(events, "RESULTS_WITHOUT_PRIOR_COMPLETION")

    def test_MEASURE25_debrief_is_final_observation(self) -> None:
        events = copy.deepcopy(self.report["events"])
        events.append({"kind": "hint_requested", "tick": 10})
        self.check_rejected(events, "EVENT_AFTER_RESULTS")

    def test_MEASURE25_no_duplicate_results(self) -> None:
        events = copy.deepcopy(self.report["events"])
        events.insert(4, {"kind": "results_opened", "tick": 10})
        self.check_rejected(events, "REPEATED_RESULTS_OPEN")

    def test_MEASURE25_left_run_has_no_post_exit_events(self) -> None:
        sample = copy.deepcopy(self.report)
        sample["outcome"] = "left"
        sample["events"] = [
            {"kind": "session_started", "tick": 0},
            {"kind": "session_left", "tick": 9},
            {"kind": "hint_requested", "tick": 10},
        ]
        with self.assertRaisesRegex(measure_report.InvalidReport, "EVENT_AFTER_SESSION_LEFT"):
            measure_report.validate(sample)

    def test_MEASURE25_dropped_terminal_is_not_fabricated(self) -> None:
        sample = copy.deepcopy(self.report)
        sample["dropped_events"] = 3
        sample["events"] = sample["events"][:2]
        result = measure_report.validate(sample)
        self.assertEqual(result["counts"]["session_completed"], 0)
        self.assertEqual(result["dropped_events"], 3)

    def test_MEASURE25_completion_without_debrief_is_reviewable(self) -> None:
        sample = copy.deepcopy(self.report)
        sample["events"].pop()
        result = measure_report.validate(sample)
        self.assertEqual(result["counts"]["results_opened"], 0)
        self.assertEqual(result["outcome"], "completed")

    def test_MEASURE25_forged_results_without_terminal_even_if_dropped(self) -> None:
        sample = copy.deepcopy(self.report)
        sample["dropped_events"] = 2
        sample["events"] = [
            {"kind": "session_started", "tick": 0},
            {"kind": "results_opened", "tick": 9},
        ]
        with self.assertRaisesRegex(measure_report.InvalidReport, "RESULTS_WITHOUT_PRIOR_COMPLETION"):
            measure_report.validate(sample)


if __name__ == "__main__":
    unittest.main()
