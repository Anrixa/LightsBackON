extends "res://tests/test_case.gd"
## DEBRIEF01-DEBRIEF20: host-result projection and production results UI.
## No synthetic data is written to game saves or mission authority.

const ShiftDebrief := preload("res://scripts/gameplay/shift_debrief.gd")
const UiText := preload("res://scripts/ui/ui_text.gd")

var _results: Dictionary


func before_each() -> void:
	UiText.set_locale(UiText.LOCALE_EN)
	_results = {
		"stars": 3, "required_restored": 5, "required_total": 5,
		"optional_services": [], "optional_total": 0,
		"trips": 1, "preventable_trips": 0, "crew_recoveries": 0,
		"ticks": 316, "equipment_collected": true
	}


func after_each() -> void:
	UiText.set_locale(UiText.LOCALE_EN)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _view() -> Dictionary:
	return ShiftDebrief.build(_results)


func test_DEBRIEF01_unfinished_run_has_no_scorecard() -> void:
	assert_false(ShiftDebrief.build({})["available"])


func test_DEBRIEF02_finished_results_are_available() -> void:
	assert_true(_view()["available"])


func test_DEBRIEF03_star_total_is_host_authored_not_inferred() -> void:
	_results["stars"] = 1
	assert_eq(_view()["stars"], 1)
	assert_true((_view()["awards"] as Array)[1]["earned"])


func test_DEBRIEF04_out_of_range_star_display_is_bounded() -> void:
	_results["stars"] = 99
	assert_eq(_view()["stars"], 3)
	_results["stars"] = -2
	assert_eq(_view()["stars"], 0)


func test_DEBRIEF05_required_services_reflect_completion_receipt() -> void:
	assert_eq(_view()["required_restored"], 5)
	assert_eq(_view()["required_total"], 5)


func test_DEBRIEF06_required_count_never_exceeds_recorded_total() -> void:
	_results["required_restored"] = 8
	assert_eq(_view()["required_restored"], 5)


func test_DEBRIEF07_required_award_follows_restored_services() -> void:
	assert_true((_view()["awards"] as Array)[0]["earned"])
	_results["required_restored"] = 4
	assert_false((_view()["awards"] as Array)[0]["earned"])


func test_DEBRIEF08_no_optional_services_awards_the_contract_bonus() -> void:
	assert_eq(_view()["optional_total"], 0)
	assert_eq(_view()["optional_restored"], 0)
	assert_true((_view()["awards"] as Array)[1]["earned"])


func test_DEBRIEF09_incomplete_optional_work_does_not_award_bonus() -> void:
	_results["optional_total"] = 2
	_results["optional_services"] = ["MARKET"]
	assert_false((_view()["awards"] as Array)[1]["earned"])
	assert_eq(_view()["optional_restored"], 1)


func test_DEBRIEF10_all_optional_services_award_bonus() -> void:
	_results["optional_total"] = 2
	_results["optional_services"] = ["PUB", "MARKET"]
	assert_true((_view()["awards"] as Array)[1]["earned"])


func test_DEBRIEF11_optional_ids_are_sorted_and_deduplicated() -> void:
	_results["optional_total"] = 2
	_results["optional_services"] = ["PUB", "MARKET", "PUB"]
	assert_eq(_view()["optional_restored"], 2)
	assert_eq(_view()["optional_services"], ["MARKET", "PUB"] as Array[String])


func test_DEBRIEF12_non_identifier_optional_ids_are_not_displayed() -> void:
	_results["optional_total"] = 2
	_results["optional_services"] = ["PUB", "../secret", 17, "bad id"]
	assert_eq(_view()["optional_services"], ["PUB"] as Array[String])
	assert_false((_view()["awards"] as Array)[1]["earned"])


func test_DEBRIEF13_missing_optional_evidence_is_not_assumed_complete() -> void:
	_results.erase("optional_services")
	assert_false((_view()["awards"] as Array)[1]["earned"])


func test_DEBRIEF14_tutorial_protection_trip_keeps_safety_award() -> void:
	assert_eq(_view()["trips"], 1)
	assert_eq(_view()["preventable_trips"], 0)
	assert_true((_view()["awards"] as Array)[2]["earned"])


func test_DEBRIEF15_preventable_trip_removes_safety_award() -> void:
	_results["trips"] = 3
	_results["preventable_trips"] = 2
	assert_false((_view()["awards"] as Array)[2]["earned"])
	assert_eq(_view()["preventable_trips"], 2)


func test_DEBRIEF16_recoveries_and_equipment_match_frozen_receipt() -> void:
	_results["crew_recoveries"] = 2
	_results["equipment_collected"] = false
	assert_eq(_view()["recoveries"], 2)
	assert_false(_view()["equipment_stowed"])


func test_DEBRIEF17_exact_tenths_come_from_host_ticks() -> void:
	assert_eq(_view()["elapsed_clock"], "00:31.6")
	assert_eq(_view()["elapsed_ticks"], 316)


func test_DEBRIEF18_long_shifts_roll_minutes_without_rounding() -> void:
	assert_eq(ShiftDebrief.clock(602), "01:00.2")
	assert_eq(ShiftDebrief.clock(0), "00:00.0")


func test_DEBRIEF19_projection_is_read_only_and_localized() -> void:
	var before: String = JSON.stringify(_results)
	var report: Dictionary = _view()
	report["optional_services"].append("SIGN")
	report["awards"][0]["earned"] = false
	assert_eq(JSON.stringify(_results), before)
	for key: String in ["offline.debrief.score", "offline.debrief.duration",
			"offline.debrief.required", "offline.debrief.optional",
			"offline.debrief.award_required", "offline.debrief.award_optional",
			"offline.debrief.award_protection", "offline.debrief.award_row",
			"offline.debrief.earned", "offline.debrief.missed",
			"offline.debrief.optional_none", "offline.debrief.unknown_service",
			"offline.debrief.unavailable"]:
		assert_true(UiText.has(key), "missing localization key " + key)
	UiText.set_locale(UiText.LOCALE_PSEUDO)
	assert_ne(UiText.t("offline.debrief.award_required"), UiText.t("offline.debrief.award_optional"))


func test_DEBRIEF20_real_results_screen_preserves_controller_exit() -> void:
	var packed: PackedScene = load("res://scenes/mission/mission_root.tscn") as PackedScene
	var root: Node = packed.instantiate()
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	tree.root.add_child(root)
	assert_true(root.find_child("ResultScroll", true, false) is ScrollContainer)
	assert_true(root.find_child("ResultsTiming", true, false) is Label)
	assert_true(root.find_child("ResultsAwardRequired", true, false) is Label)
	assert_true(root.find_child("ResultsAwardOptional", true, false) is Label)
	assert_true(root.find_child("ResultsAwardSafety", true, false) is Label)
	root.call("_finish")
	var exit_button: Button = root.find_child("ReturnToMenu", true, false) as Button
	assert_true(exit_button != null)
	assert_eq(tree.root.gui_get_focus_owner(), exit_button)
	root.call("_render_debrief", _results)
	var score: Label = root.find_child("Score", true, false) as Label
	var clock: Label = root.find_child("ResultsTiming", true, false) as Label
	assert_true(score.text.contains("3"))
	assert_true(clock.text.contains("00:31.6"))
	tree.root.remove_child(root)
	root.free()
