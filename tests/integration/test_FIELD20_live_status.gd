extends "res://tests/test_case.gd"
## FIELD01-FIELD20: compact real-time C01 objective / timer awareness in
## the actual field HUD. The host remains the sole source of progress data.

const ShiftOperations := preload("res://scripts/gameplay/shift_operations.gd")
const OfflineSession := preload("res://scripts/gameplay/offline_c01_session.gd")
const FieldHud := preload("res://scripts/ui/field_hud.gd")
const UiText := preload("res://scripts/ui/ui_text.gd")

var _contract: Dictionary
var _mission: Dictionary
var _objectives: Array[Dictionary]


func before_each() -> void:
	UiText.set_locale(UiText.LOCALE_EN)
	_contract = JSON.parse_string(FileAccess.get_file_as_string(
		"res://content/contracts/c01_alder_street/mission.json"))
	_mission = {"latched": {}, "latch_ticks": {"LATCH_PUMP_DRAIN": 0},
		"verify_ticks": 0, "countdown_left": -1, "trips": 0, "recoveries": 0}
	_objectives = [
		{"text_key": "objective.c01.restore_west", "status": "active", "visible": true},
		{"text_key": "objective.c01.drain_basement", "status": "pending", "visible": false},
		{"text_key": "objective.c01.restore_east", "status": "pending", "visible": false},
		{"text_key": "objective.c01.verify_supply", "status": "pending", "visible": false},
		{"text_key": "objective.c01.stow_equipment", "status": "pending", "visible": false},
		{"text_key": "objective.c01.extract", "status": "pending", "visible": false}
	]


func after_each() -> void:
	UiText.set_locale(UiText.LOCALE_EN)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _active(text_key: String) -> void:
	for row: Dictionary in _objectives:
		var selected: bool = str(row["text_key"]) == text_key
		row["status"] = "active" if selected else "pending"
		row["visible"] = selected


func _view(stowed: bool = false, at_van: bool = false, results: Dictionary = {}) -> Dictionary:
	return ShiftOperations.field_view(ShiftOperations.build(
		_objectives, _mission, _contract, stowed, at_van, results))


func _verified() -> void:
	_mission["verify_ticks"] = int(_contract["final_verification_ticks"])


func test_FIELD01_real_contract_objective_fraction_is_available_in_field() -> void:
	var view: Dictionary = _view()
	assert_eq(view["objectives_done"], 0)
	assert_eq(view["objectives_total"], 6)


func test_FIELD02_field_awareness_visible_during_live_shift() -> void:
	assert_true(_view()["visible"])


func test_FIELD03_restoring_phase_has_localization_key_not_baked_text() -> void:
	var key: String = str(_view()["phase_key"])
	assert_eq(key, "offline.briefing.phase_restoring")
	assert_true(UiText.has(key))


func test_FIELD04_future_unknown_activity_does_not_show_hidden_timer() -> void:
	_mission["latch_ticks"]["LATCH_PUMP_DRAIN"] = 70
	_mission["verify_ticks"] = 30
	assert_eq(_view()["progress_key"], "")
	assert_false(_view()["countdown"])


func test_FIELD05_active_drain_exposes_a_zero_based_meter() -> void:
	_active("objective.c01.drain_basement")
	assert_eq(_view()["progress_key"], "offline.field.pump")
	assert_eq(_view()["progress_percent"], 0)


func test_FIELD06_drain_meter_reads_actual_host_ticks() -> void:
	_active("objective.c01.drain_basement")
	# Multiple actual objectives can be visible together; the drain cannot
	# disappear merely because a different active objective is listed first.
	_objectives[0]["status"] = "active"
	_objectives[0]["visible"] = true
	_mission["latch_ticks"]["LATCH_PUMP_DRAIN"] = 60
	assert_eq(_view()["progress_percent"], 50)


func test_FIELD07_drain_meter_never_exceeds_one_hundred() -> void:
	_active("objective.c01.drain_basement")
	_mission["latch_ticks"]["LATCH_PUMP_DRAIN"] = 10000
	assert_eq(_view()["progress_percent"], 100)


func test_FIELD08_latched_drain_does_not_restart_a_stale_meter() -> void:
	_active("objective.c01.drain_basement")
	_mission["latched"] = {"LATCH_PUMP_DRAIN": 120}
	assert_eq(_view()["progress_key"], "")


func test_FIELD09_active_grid_verification_starts_at_zero() -> void:
	_active("objective.c01.verify_supply")
	assert_eq(_view()["progress_key"], "offline.field.verification")
	assert_eq(_view()["progress_percent"], 0)


func test_FIELD10_grid_verification_uses_authoritative_elapsed_ticks() -> void:
	_active("objective.c01.verify_supply")
	_mission["verify_ticks"] = 40
	assert_eq(_view()["progress_percent"], 40)


func test_FIELD11_supply_loss_rewinds_verification_visibility() -> void:
	_active("objective.c01.verify_supply")
	_mission["verify_ticks"] = 60
	assert_eq(_view()["progress_percent"], 60)
	_mission["verify_ticks"] = 0
	assert_eq(_view()["progress_percent"], 0)


func test_FIELD12_verified_supply_advances_to_stow_not_a_stale_bar() -> void:
	_verified()
	var view: Dictionary = _view()
	assert_eq(view["phase_key"], "offline.briefing.phase_stow")
	assert_eq(view["progress_key"], "")


func test_FIELD13_stowed_equipment_without_van_presence_still_needs_return() -> void:
	_verified()
	var view: Dictionary = _view(true, false)
	assert_eq(view["phase_key"], "offline.briefing.phase_return")
	assert_false(view["countdown"])


func test_FIELD14_van_presence_does_not_skip_stow_requirement() -> void:
	_verified()
	assert_eq(_view(false, true)["phase_key"], "offline.briefing.phase_stow")


func test_FIELD15_all_prerequisites_produce_ready_not_departing() -> void:
	_verified()
	var view: Dictionary = _view(true, true)
	assert_eq(view["phase_key"], "offline.briefing.phase_ready")
	assert_eq(view["progress_key"], "")


func test_FIELD16_departure_countdown_uses_host_ticks_without_frame_clock() -> void:
	_verified()
	_mission["countdown_left"] = 21
	var view: Dictionary = _view(true, true)
	assert_eq(view["phase_key"], "offline.briefing.phase_departing")
	assert_true(view["countdown"])
	assert_eq(view["remaining_seconds"], 3)


func test_FIELD17_departure_bar_uses_host_progress_fraction() -> void:
	_verified()
	_mission["countdown_left"] = 30
	var view: Dictionary = _view(true, true)
	assert_eq(view["progress_key"], "offline.field.departure")
	assert_eq(view["progress_percent"], 40)


func test_FIELD18_cancelled_departure_hides_old_countdown() -> void:
	_verified()
	_mission["countdown_left"] = 20
	assert_true(_view(true, true)["countdown"])
	_mission["countdown_left"] = -1
	var view: Dictionary = _view(true, true)
	assert_false(view["countdown"])
	assert_eq(view["progress_key"], "")
	assert_eq(view["phase_key"], "offline.briefing.phase_ready")


func test_FIELD19_completed_shift_hides_field_status_without_mutations() -> void:
	_verified()
	var before: String = JSON.stringify(_mission)
	var view: Dictionary = _view(true, true, {"stars": 3})
	assert_false(view["visible"])
	assert_eq(view["progress_key"], "")
	assert_eq(JSON.stringify(_mission), before)


func test_FIELD20_production_session_and_hud_render_on_real_scene() -> void:
	var session: RefCounted = OfflineSession.new()
	var failures: Array[Dictionary] = session.setup(
		func(_player: String, _target: String) -> bool: return true,
		func(_player: String) -> Vector3i: return Vector3i(450, 100, 1500))
	assert_eq(failures, [] as Array[Dictionary])
	var field: Dictionary = session.hud_view(1, "", "meter")["field_shift"]
	assert_eq(field["objectives_total"], 6)
	assert_false(field.has("grid") or field.has("findings") or field.has("fault"))
	assert_true(UiText.has("offline.field.status"))
	assert_true(UiText.has("offline.field.progress"))
	assert_true(UiText.has("offline.field.countdown"))
	assert_true(UiText.has("offline.field.pump"))
	assert_true(UiText.has("offline.field.verification"))
	assert_true(UiText.has("offline.field.departure"))

	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var scene: PackedScene = load("res://scenes/mission/mission_root.tscn") as PackedScene
	var root: Node = scene.instantiate()
	tree.root.add_child(root)
	var hud: Container = root.get("hud") as Container
	assert_true(hud != null, "production scene constructs a field HUD")
	assert_true(hud.find_child("FieldShiftStatus", true, false) is Label, "initial scene shift status exists")
	assert_true(hud.find_child("FieldShiftProgress", true, false) == null, "future meter is initially hidden")
	# A non-event mission tick must update the real production HUD in place.
	# Transition into progress mode creates the bar once; subsequent ticks
	# update only text/value, without discarding the focused scene/UI controls.
	var live: Dictionary = field.duplicate(true)
	live["progress_key"] = "offline.field.pump"
	live["progress_percent"] = 25
	hud.call("set_field_shift", live)
	var bar: ProgressBar = hud.find_child("FieldShiftProgress", true, false) as ProgressBar
	assert_true(bar != null, "entering active pump stage creates meter")
	if bar != null:
		assert_eq(bar.value, 25.0)
		live = live.duplicate(true)
		live["progress_percent"] = 65
		hud.call("set_field_shift", live)
		assert_true(hud.find_child("FieldShiftProgress", true, false) == bar,
			"timer ticks must not rebuild the whole HUD")
		assert_eq(bar.value, 65.0)
	# UI-only model changes never take world input focus and obey the existing
	# viewport and accessibility-scale reflow path.
	UiText.set_locale(UiText.LOCALE_PSEUDO)
	hud.call("set_ui_scale", 150)
	var status: Label = hud.find_child("FieldShiftStatus", true, false) as Label
	assert_true(status != null and status.text != "", "status remains visible with pseudo locale at 150 percent")
	assert_eq(status.focus_mode, Control.FOCUS_NONE)
	assert_eq(status.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	tree.root.remove_child(root)
	root.free()
