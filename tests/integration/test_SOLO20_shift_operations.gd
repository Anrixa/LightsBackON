extends "res://tests/test_case.gd"
## SOLO01-SOLO20: production shift-status projection and live pause/results.
## All numbers are obtained from the canonical C01 contract and host state.

const ShiftOperations := preload("res://scripts/gameplay/shift_operations.gd")
const OfflineSession := preload("res://scripts/gameplay/offline_c01_session.gd")
const UiText := preload("res://scripts/ui/ui_text.gd")

var _contract: Dictionary
var _mission: Dictionary
var _objectives: Array[Dictionary]


func before_each() -> void:
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


func _view(stowed: bool = false, at_van: bool = false, results: Dictionary = {}) -> Dictionary:
	return ShiftOperations.build(_objectives, _mission, _contract, stowed, at_van, results)


func _verified() -> void:
	_mission["verify_ticks"] = int(_contract["final_verification_ticks"])


func test_SOLO01_six_contract_objectives_are_counted() -> void:
	assert_eq(_view()["objectives_total"], 6)
	assert_eq(_view()["objectives_done"], 0)


func test_SOLO02_first_actionable_objective_is_exposed() -> void:
	assert_eq(_view()["active_key"], "objective.c01.restore_west")


func test_SOLO03_hidden_pending_tasks_are_not_promoted_to_active() -> void:
	_objectives[0]["visible"] = false
	assert_eq(_view()["active_key"], "")


func test_SOLO04_completed_objective_moves_the_progress_counter() -> void:
	_objectives[0]["status"] = "done"
	_objectives[1]["status"] = "active"
	_objectives[1]["visible"] = true
	assert_eq(_view()["objectives_done"], 1)
	assert_eq(_view()["active_key"], "objective.c01.drain_basement")


func test_SOLO05_drain_timer_starts_empty_with_authored_duration() -> void:
	var view: Dictionary = _view()
	assert_eq(view["pump_ticks"], 0)
	assert_eq(view["pump_total"], 120)


func test_SOLO06_running_pump_has_visible_halfway_progress() -> void:
	_mission["latch_ticks"]["LATCH_PUMP_DRAIN"] = 60
	assert_eq(_view()["pump_percent"], 50)


func test_SOLO07_latched_drain_stays_complete_even_after_supply_changes() -> void:
	_mission["latched"] = {"LATCH_PUMP_DRAIN": 120}
	_mission["latch_ticks"]["LATCH_PUMP_DRAIN"] = 0
	assert_true(_view()["pump_latched"])
	assert_eq(_view()["pump_percent"], 100)


func test_SOLO08_verification_uses_the_authored_ten_seconds() -> void:
	_mission["verify_ticks"] = 40
	assert_eq(_view()["verify_total"], 100)
	assert_eq(_view()["verify_percent"], 40)


func test_SOLO09_verification_loss_returns_to_zero_progress() -> void:
	_mission["verify_ticks"] = 0
	assert_false(_view()["verified"])
	assert_eq(_view()["verify_percent"], 0)


func test_SOLO10_full_grid_verification_changes_phase_to_stow() -> void:
	_verified()
	assert_true(_view()["verified"])
	assert_eq(_view()["phase_key"], "offline.briefing.phase_stow")


func test_SOLO11_stowed_equipment_before_verification_does_not_unlock_exit() -> void:
	assert_false(_view(true, true)["ready"])
	assert_eq(_view(true, true)["phase_key"], "offline.briefing.phase_restoring")


func test_SOLO12_stowing_after_verification_requires_return_to_van() -> void:
	_verified()
	assert_eq(_view(true, false)["phase_key"], "offline.briefing.phase_return")


func test_SOLO13_crew_and_stowed_equipment_ready_the_departure() -> void:
	_verified()
	assert_true(_view(true, true)["ready"])
	assert_eq(_view(true, true)["phase_key"], "offline.briefing.phase_ready")


func test_SOLO14_departure_countdown_uses_host_ticks() -> void:
	_verified()
	_mission["countdown_left"] = 30
	var view: Dictionary = _view(true, true)
	assert_true(view["departing"])
	assert_eq(view["departure_total"], 50)
	assert_eq(view["departure_percent"], 40)
	assert_eq(view["phase_key"], "offline.briefing.phase_departing")


func test_SOLO15_cancelled_departure_does_not_show_stale_countdown() -> void:
	_verified()
	_mission["countdown_left"] = -1
	var view: Dictionary = _view(true, true)
	assert_false(view["departing"])
	assert_eq(view["departure_percent"], 0)


func test_SOLO16_completed_mission_cannot_show_ready_or_departing() -> void:
	_verified()
	_mission["countdown_left"] = 1
	var view: Dictionary = _view(true, true, {"stars": 3})
	assert_true(view["finished"])
	assert_false(view["ready"])
	assert_eq(view["phase_key"], "offline.briefing.phase_complete")


func test_SOLO17_trip_count_comes_from_host_mission_only() -> void:
	_mission["trips"] = 3
	assert_eq(_view()["trips"], 3)


func test_SOLO18_recovery_count_comes_from_host_mission_only() -> void:
	_mission["recoveries"] = 2
	assert_eq(_view()["recoveries"], 2)


func test_SOLO19_projection_does_not_mutate_objectives_or_durable_state() -> void:
	var before_mission: String = JSON.stringify(_mission)
	var before_objectives: String = JSON.stringify(_objectives)
	var view: Dictionary = _view()
	view["objectives"].clear()
	assert_eq(JSON.stringify(_mission), before_mission)
	assert_eq(JSON.stringify(_objectives), before_objectives)


func test_SOLO20_offline_session_and_real_scene_expose_nonspoiling_briefing() -> void:
	var session: RefCounted = OfflineSession.new()
	var failures: Array[Dictionary] = session.setup(
		func(_player: String, _target: String) -> bool: return true,
		func(_player: String) -> Vector3i: return Vector3i(450, 100, 1500))
	assert_eq(failures, [] as Array[Dictionary])
	var view: Dictionary = session.shift_operations_view()
	assert_eq(view["objectives_total"], 6)
	assert_false(view.has("grid") or view.has("findings") or view.has("fault"))
	assert_true(UiText.has(str(view["phase_key"])))
	var scene: PackedScene = load("res://scenes/mission/mission_root.tscn") as PackedScene
	var root: Node = scene.instantiate()
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	tree.root.add_child(root)
	assert_true(root.find_child("ShiftOverview", true, false) is VBoxContainer)
	assert_true(root.find_child("BriefingStatus", true, false) is Label)
	assert_true(root.find_child("PumpProgress", true, false) is ProgressBar)
	assert_true(root.find_child("CompletionMetrics", true, false) is Label)
	tree.root.remove_child(root)
	root.free()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
