extends "res://tests/test_case.gd"
## MEASURE01-MEASURE20: opt-in C01 events, never a Steam/Windows acceptance.

const Measurements := preload("res://scripts/diagnostics/shift_measurements.gd")
const POLICY: Dictionary = {"max_events": 16, "idle_threshold_ticks": 30, "max_objectives": 8}

var meter: RefCounted


func before_each() -> void:
	meter = Measurements.new()


func test_MEASURE01_disabled_by_default_even_with_valid_policy() -> void:
	assert_true(meter.begin(false, POLICY))
	assert_false(meter.enabled())
	assert_false(meter.note("hint_requested", 1))
	assert_eq((meter.snapshot()["events"] as Array).size(), 0)


func test_MEASURE02_schema_contains_no_account_or_transport_identifiers() -> void:
	assert_true(meter.begin(true, POLICY))
	var report: Dictionary = meter.snapshot()
	assert_eq(report["schema_version"], 1)
	assert_eq(report["contract"], "C01")
	assert_eq(report["tick_rate_hz"], 10)
	assert_false(report.has("account_key"))
	assert_false(report.has("peer_id"))
	assert_false(report.has("steam_id"))
	assert_eq((report["events"] as Array)[0]["kind"], "session_started")


func test_MEASURE03_unknown_events_and_identity_values_are_refused() -> void:
	assert_true(meter.begin(true, POLICY))
	assert_false(meter.note("account_identifier", 1))
	assert_false(meter.note("objective_completed", 2, -1))
	assert_false(meter.note("hint_requested", 3, 2))
	assert_false(meter.note("objective_visible", 4, 32))
	assert_eq((meter.snapshot()["events"] as Array).size(), 1)


func test_MEASURE04_event_budget_drops_excess_without_growth() -> void:
	assert_true(meter.begin(true, POLICY))
	for i: int in range(30):
		meter.note("hint_requested", i + 1)
	var report: Dictionary = meter.snapshot()
	assert_eq((report["events"] as Array).size(), 16)
	assert_eq(report["dropped_events"], 15)


func test_MEASURE05_host_ticks_are_monotonic_and_report_is_immutable() -> void:
	assert_true(meter.begin(true, POLICY))
	assert_true(meter.note("hint_requested", 8))
	assert_false(meter.note("hint_requested", 7))
	assert_true(meter.note("hint_requested", 8))
	var report: Dictionary = meter.snapshot()
	(report["events"] as Array).clear()
	assert_eq((meter.snapshot()["events"] as Array).size(), 3)
