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


func test_MEASURE06_first_visible_objective_records_only_ordinal() -> void:
	assert_true(meter.begin(true, POLICY))
	var rows: Array[Dictionary] = [{"status": "active", "visible": true, "text_key": "a.private.string"}]
	meter.observe_tick(1, rows)
	var event: Dictionary = (meter.snapshot()["events"] as Array)[1]
	assert_eq(event["kind"], "objective_visible")
	assert_eq(event["objective_index"], 0)
	assert_false(event.has("text_key"))


func test_MEASURE07_objective_completion_is_transition_only() -> void:
	assert_true(meter.begin(true, POLICY))
	var rows: Array[Dictionary] = [{"status": "active", "visible": true}]
	meter.observe_tick(1, rows)
	rows[0]["status"] = "done"
	meter.observe_tick(2, rows)
	meter.observe_tick(3, rows)
	var events: Array = meter.snapshot()["events"]
	assert_eq(events.size(), 3)
	assert_eq(events[2]["kind"], "objective_completed")


func test_MEASURE08_resumed_completed_rows_are_not_retroactive_events() -> void:
	assert_true(meter.begin(true, POLICY))
	var rows: Array[Dictionary] = [{"status": "done", "visible": false}]
	meter.observe_tick(1, rows)
	assert_eq((meter.snapshot()["events"] as Array).size(), 1)


func test_MEASURE09_idle_threshold_uses_host_ticks_only() -> void:
	assert_true(meter.begin(true, POLICY))
	var rows: Array[Dictionary] = []
	meter.observe_tick(29, rows)
	assert_eq((meter.snapshot()["events"] as Array).size(), 1)
	meter.observe_tick(30, rows)
	meter.observe_tick(60, rows)
	var events: Array = meter.snapshot()["events"]
	assert_eq(events.size(), 2)
	assert_eq(events[1]["kind"], "idle_started")
	assert_eq(events[1]["tick"], 30)


func test_MEASURE10_activity_closes_idle_with_bounded_duration() -> void:
	assert_true(meter.begin(true, POLICY))
	var rows: Array[Dictionary] = []
	meter.observe_tick(30, rows)
	meter.mark_activity(42)
	var events: Array = meter.snapshot()["events"]
	assert_eq(events[2]["kind"], "idle_ended")
	assert_eq(events[2]["value_ticks"], 12)
	meter.observe_tick(65, rows)
	assert_eq((meter.snapshot()["events"] as Array).size(), 3)


func test_MEASURE11_only_first_accepted_repair_is_recorded_once() -> void:
	assert_true(meter.begin(true, POLICY))
	meter.note_first_repair(4)
	meter.note_first_repair(8)
	var events: Array = meter.snapshot()["events"]
	assert_eq(events.size(), 2)
	assert_eq(events[1]["kind"], "first_repair")
	assert_eq(events[1]["tick"], 4)


func test_MEASURE12_host_event_flags_never_expose_grid_entity_ids() -> void:
	assert_true(meter.begin(true, POLICY))
	assert_true(meter.note("protection_trip", 3))
	assert_true(meter.note("supply_verified", 7))
	var report: Dictionary = meter.snapshot()
	var serialized: String = JSON.stringify(report)
	assert_false(serialized.contains("GRID"))
	assert_false(serialized.contains("player_id"))
	assert_eq((report["events"] as Array)[2]["kind"], "supply_verified")


func test_MEASURE13_hint_event_is_integer_clocked_and_user_requested() -> void:
	assert_true(meter.begin(true, POLICY))
	meter.mark_activity(3)
	assert_true(meter.note("hint_requested", 3))
	assert_eq((meter.snapshot()["events"] as Array)[1]["kind"], "hint_requested")


func test_MEASURE14_solo_exit_does_not_masquerade_as_disconnect() -> void:
	assert_true(meter.begin(true, POLICY))
	assert_true(meter.note("session_left", 3))
	var events: Array = meter.snapshot()["events"]
	assert_eq(events[1]["kind"], "session_left")
	meter.note_disconnect(4)
	assert_eq((meter.snapshot()["events"] as Array)[2]["kind"], "connection_lost")


func test_MEASURE15_real_C01_scene_wires_host_events_without_identity_fields() -> void:
	var packed: PackedScene = load("res://scenes/mission/mission_root.tscn") as PackedScene
	var root: Node = packed.instantiate()
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	tree.root.add_child(root)
	var recorder: RefCounted = root.get("_measurements")
	assert_true(recorder != null)
	assert_true(recorder.call("begin", true, POLICY))
	root.call("_on_mission_event", {"type": "trip", "tick": 1, "peer_id": "SENSITIVE"})
	var report: Dictionary = recorder.call("snapshot")
	assert_eq((report["events"] as Array)[1]["kind"], "protection_trip")
	assert_false(JSON.stringify(report).contains("SENSITIVE"))
	tree.root.remove_child(root)
	root.free()


func test_MEASURE16_no_opt_in_cannot_create_local_file() -> void:
	assert_true(meter.begin(false, POLICY))
	var result: Dictionary = meter.finish_and_export(2, false, Measurements.TEST_REPORT_DIR)
	assert_eq(result["code"], "OPT_IN_REQUIRED")


func test_MEASURE17_export_cannot_escape_app_private_directory() -> void:
	assert_true(meter.begin(true, POLICY))
	assert_eq(meter.finish_and_export(2, false, "user://../private")["code"], "BAD_DIRECTORY")
	assert_eq(meter.finish_and_export(2, false, "res://")["code"], "BAD_DIRECTORY")


func test_MEASURE18_atomic_local_report_contains_only_allowlisted_data() -> void:
	assert_true(meter.begin(true, POLICY))
	assert_true(meter.note("hint_requested", 3))
	var result: Dictionary = meter.finish_and_export(4, false, Measurements.TEST_REPORT_DIR)
	assert_true(result.get("ok", false))
	if not bool(result.get("ok", false)):
		return
	var text_data: String = FileAccess.get_file_as_string(str(result["path"]))
	var report: Variant = JSON.parse_string(text_data)
	assert_true(report is Dictionary)
	if report is Dictionary:
		assert_eq(report["outcome"], "left")
		assert_eq(int(report["schema_version"]), 1)
		assert_eq((report["events"] as Array)[2]["kind"], "session_left")
	assert_false(text_data.contains("account_key"))
	assert_false(text_data.contains("peer_id"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(str(result["path"])))


func test_MEASURE19_closed_report_cannot_be_written_twice() -> void:
	assert_true(meter.begin(true, POLICY))
	var result: Dictionary = meter.finish_and_export(3, true, Measurements.TEST_REPORT_DIR)
	assert_true(result.get("ok", false))
	assert_eq(meter.finish_and_export(4, true, Measurements.TEST_REPORT_DIR)["code"], "ALREADY_CLOSED")
	if bool(result.get("ok", false)):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(str(result["path"])))


func test_MEASURE20_complete_report_keeps_host_events_and_cleans_staging() -> void:
	assert_true(meter.begin(true, POLICY))
	var rows: Array[Dictionary] = [{"status": "active", "visible": true}]
	meter.observe_tick(1, rows)
	meter.note_first_repair(2)
	rows[0]["status"] = "done"
	meter.observe_tick(3, rows)
	assert_true(meter.note("session_completed", 4))
	assert_true(meter.note("results_opened", 4))
	var result: Dictionary = meter.finish_and_export(4, true, Measurements.TEST_REPORT_DIR)
	assert_true(result.get("ok", false))
	if not bool(result.get("ok", false)):
		return
	var payload: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(str(result["path"])))
	assert_eq(payload["outcome"], "completed")
	assert_eq((payload["events"] as Array).size(), 6)
	assert_false(FileAccess.file_exists(str(result["path"]) + ".tmp"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(str(result["path"])))
