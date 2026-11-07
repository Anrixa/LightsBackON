"""MEASURE31: truthful C01 terminal timestamps and bounded tail descriptives."""
from __future__ import annotations

import copy
import json
import unittest

from tools import measure_report


class CompletionTimingTests(unittest.TestCase):
    @staticmethod
    def completed(completed_at: int, finalized_at: int | None = None,
                  *, dropped: int = 0, with_results: bool = True,
                  with_repair: bool = True, open_idle: bool = False) -> dict:
        end = finalized_at if finalized_at is not None else completed_at + 2
        events = [{"kind": "session_started", "tick": 0}]
        if open_idle:
            events.append({"kind": "idle_started", "tick": 1})
        if with_repair:
            events.append({"kind": "first_repair", "tick": 2})
        events.append({"kind": "session_completed", "tick": completed_at})
        if with_results:
            events.append({"kind": "results_opened", "tick": end})
        report = {
            "schema_version": 1, "contract": "C01", "tick_rate_hz": 10,
            "opted_in": True, "outcome": "completed",
            "dropped_events": dropped, "last_tick": end, "events": events,
        }
        return measure_report.validate(report)

    @staticmethod
    def left(last_tick: int) -> dict:
        return measure_report.validate({
            "schema_version": 1, "contract": "C01", "tick_rate_hz": 10,
            "opted_in": True, "outcome": "left",
            "dropped_events": 0, "last_tick": last_tick,
            "events": [
                {"kind": "session_started", "tick": 0},
                {"kind": "session_left", "tick": last_tick},
            ],
        })

    def test_MEASURE31_real_completion_tick_precedes_debrief(self) -> None:
        item = self.completed(10, 900)
        self.assertEqual(item["completion_observed_tick"], 10)
        summary = measure_report.summarize([item])
        self.assertEqual(summary["completed_elapsed_median_ticks"], 10)
        self.assertEqual(summary["session_duration_median_ticks"], 900)
        self.assertEqual(summary["completed_elapsed_sample_count"], 1)

    def test_MEASURE31_zero_completion_for_left_is_missing_not_fabricated(self) -> None:
        data = self.left(400)
        self.assertIsNone(data["completion_observed_tick"])
        summary = measure_report.summarize([data])
        self.assertIsNone(summary["completed_elapsed_median_ticks"])
        self.assertEqual(summary["completed_elapsed_sample_count"], 0)

    def test_MEASURE31_p95_requires_ten_observed_completions(self) -> None:
        summaries = [self.completed(10 + i) for i in range(9)]
        result = measure_report.summarize(summaries)
        self.assertEqual(result["completed_elapsed_p95_gate"], "BELOW_TEN_OBSERVED_COMPLETIONS")
        self.assertIsNone(result["completed_elapsed_p95_ticks"])
        summaries.append(self.completed(19))
        full = measure_report.summarize(summaries)
        self.assertEqual(full["completed_elapsed_p95_ticks"], 19)
        self.assertEqual(
            full["completed_elapsed_p95_gate"],
            "STRUCTURAL_P95_ONLY_REQUIRES_HUMAN_REVIEW",
        )
        self.assertEqual(full["completed_elapsed_median_ticks"], 14.5)

    def test_MEASURE31_p95_uses_nearest_rank_not_interpolation(self) -> None:
        values = [100 + i * 10 for i in range(20)]
        report = measure_report.summarize([self.completed(n) for n in values])
        self.assertEqual(report["completed_elapsed_p95_ticks"], values[18])

    def test_MEASURE31_left_sessions_do_not_shortcut_ten_completion_floor(self) -> None:
        data = [self.completed(20 + i) for i in range(9)] + [self.left(30)]
        report = measure_report.summarize(data)
        self.assertEqual(report["sessions"], 10)
        self.assertEqual(report["completed_elapsed_sample_count"], 9)
        self.assertIsNone(report["completed_elapsed_p95_ticks"])

    def test_MEASURE31_ten_completed_plus_left_maintains_right_sample(self) -> None:
        data = [self.completed(20 + i) for i in range(10)] + [self.left(900)]
        report = measure_report.summarize(data)
        self.assertEqual(report["completed_elapsed_p95_ticks"], 29)
        self.assertEqual(report["completed_elapsed_sample_count"], 10)
        self.assertEqual(report["completed_sessions"], 10)
        self.assertEqual(report["left_sessions"], 1)

    def test_MEASURE31_dropped_events_disable_tail_even_with_terminal(self) -> None:
        data = [self.completed(10 + i) for i in range(9)]
        data.append(self.completed(20, dropped=1))
        report = measure_report.summarize(data)
        self.assertEqual(report["completed_elapsed_p95_gate"], "INCOMPLETE_OBSERVATIONS")
        self.assertIsNone(report["completed_elapsed_p95_ticks"])

    def test_MEASURE31_no_debrief_disables_tail(self) -> None:
        data = [self.completed(20 + i) for i in range(9)]
        data.append(self.completed(40, with_results=False))
        summary = measure_report.summarize(data)
        self.assertEqual(summary["completed_elapsed_sample_count"], 10)
        self.assertIsNone(summary["completed_elapsed_p95_ticks"])
        self.assertEqual(summary["completed_elapsed_p95_gate"], "INCOMPLETE_OBSERVATIONS")

    def test_MEASURE31_open_idle_disables_tail(self) -> None:
        data = [self.completed(30 + i) for i in range(9)]
        data.append(self.completed(50, open_idle=True))
        report = measure_report.summarize(data)
        self.assertEqual(report["completed_elapsed_p95_gate"], "INCOMPLETE_OBSERVATIONS")

    def test_MEASURE31_missing_repair_from_resume_does_not_fake_timestamp(self) -> None:
        data = [self.completed(10 + i) for i in range(9)]
        data.append(self.completed(20, with_repair=False))
        result = measure_report.summarize(data)
        self.assertEqual(result["completed_elapsed_sample_count"], 10)
        self.assertEqual(result["completed_elapsed_p95_ticks"], 20)
        self.assertEqual(result["event_counts"]["first_repair"], 9)

    def test_MEASURE31_no_report_schema_or_identity_changes(self) -> None:
        raw = {
            "schema_version": 1, "contract": "C01", "tick_rate_hz": 10,
            "opted_in": True, "outcome": "completed", "dropped_events": 0,
            "last_tick": 20,
            "events": [
                {"kind": "session_started", "tick": 0},
                {"kind": "session_completed", "tick": 15},
                {"kind": "results_opened", "tick": 20},
            ],
        }
        before = json.dumps(raw, sort_keys=True)
        validated = measure_report.validate(raw)
        result = measure_report.summarize([validated])
        self.assertEqual(before, json.dumps(raw, sort_keys=True))
        self.assertNotIn("events", result)
        self.assertNotIn("player_id", json.dumps(result))
        self.assertEqual(result["completed_elapsed_timing_basis"],
                         "local_10Hz_host_ticks_pause_excluded")
        self.assertEqual(result["completed_elapsed_human_evidence"], "NOT_VERIFIED")

    def test_MEASURE31_missing_terminal_when_dropped_does_not_count_as_observed(self) -> None:
        raw = {
            "schema_version": 1, "contract": "C01", "tick_rate_hz": 10,
            "opted_in": True, "outcome": "completed", "dropped_events": 2,
            "last_tick": 20,
            "events": [{"kind": "session_started", "tick": 0}],
        }
        item = measure_report.validate(raw)
        self.assertIsNone(item["completion_observed_tick"])
        result = measure_report.summarize([item])
        self.assertEqual(result["completed_elapsed_sample_count"], 0)
        self.assertEqual(result["completed_elapsed_p95_gate"], "INCOMPLETE_OBSERVATIONS")


if __name__ == "__main__":
    unittest.main()
