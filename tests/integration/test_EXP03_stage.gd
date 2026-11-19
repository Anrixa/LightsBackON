extends "res://tests/test_case.gd"
## EXP03 end-to-end scene wiring, without a walked route or GPU/controller
## playability claim. The atlas remains inert until its opt-in launch event.

const AtlasPanel := preload("res://scripts/ui/dispatch_atlas_panel.gd")
const Runtime := preload("res://scripts/gameplay/expedition_host_session.gd")
const Scene := preload("res://scenes/expeditions/mission_stage.tscn")

var _holder: Node3D


func before_each() -> void:
	_holder = Node3D.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(_holder)


func after_each() -> void:
	_holder.get_parent().remove_child(_holder)
	_holder.free()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func test_EXP03_atlas_launch_requires_explicit_selection_and_emits_source_id_only() -> void:
	var panel: Control = AtlasPanel.new()
	_holder.add_child(panel)
	var button: Button = panel.find_child("LaunchExperimentalMission", true, false) as Button
	assert_true(button != null)
	assert_false(button.disabled)
	assert_true(panel.find_children("*", "CharacterBody3D", true, false).is_empty(),
		"design browsing never starts a gameplay actor")
	var chosen: Array[String] = []
	panel.mission_requested.connect(func(id: String) -> void: chosen.append(id))
	var list: ItemList = panel.find_child("LevelList", true, false) as ItemList
	list.select(12)
	button.pressed.emit()
	assert_eq(chosen, ["LV_013"] as Array[String])
	var search: LineEdit = panel.find_child("DispatchSearch", true, false) as LineEdit
	search.text = "impossible-level-xyzz"
	search.text_changed.emit(search.text)
	assert_true(button.disabled)
	button.pressed.emit()
	assert_eq(chosen.size(), 1, "a filtered-out level cannot be launched")


func test_EXP03_godot_stage_instantiates_actual_character_and_source_host() -> void:
	var stage: Node3D = Scene.instantiate()
	stage.set("level_id", "LV_001")
	_holder.add_child(stage)
	assert_true(stage.get_node_or_null("ExpeditionWorld/CandidateGround/FoundationCollision") != null)
	assert_true(stage.get_node_or_null("Player/BodyCollision") != null)
	assert_true(stage.get_node_or_null("Player/Eyes") != null)
	assert_true(stage.find_child("TaskStatuses", true, false) != null)
	var session: Runtime = stage.get("runtime") as Runtime
	assert_true(session != null)
	assert_eq(session.session_id(), "S_EXP03_LV_001")
	assert_eq(int(session.task_board()["required_total"]), 4)
	assert_true(session.authoritative_state().has("mission"))
	assert_false(session.completed())
	assert_eq(str(session.definition_snapshot()["not_certified"]),
		"NO_WALKED_ROUTE_CONTROLLER_GPU_STEAM_OR_RELEASE")
	assert_true(stage.find_children("*", "OfflinePersistence", true, false).is_empty())


func test_EXP03_staged_host_position_is_not_claimed_as_completed_gameplay() -> void:
	var stage: Node3D = Scene.instantiate()
	stage.set("level_id", "LV_124")
	_holder.add_child(stage)
	var session: Runtime = stage.get("runtime") as Runtime
	assert_true(session != null)
	assert_eq(int(session.task_board()["required_completed"]), 0)
	assert_false(bool(session.task_board()["optional_completed"]))
	assert_false(bool(session.mission.verified()))
	assert_eq(str(session.task_board()["not_certified"]),
		"NO_PHYSICAL_PLAYABILITY_OR_REWARD_PROMOTION")
	assert_true(stage.get_node_or_null("ExpeditionWorld/Stations/Station01") != null)
	assert_true(stage.get_node_or_null("ExpeditionWorld/Stations/Station05") != null)


func test_EXP03_dispatch_atlas_is_included_in_both_windows_export_presets() -> void:
	var source: String = FileAccess.get_file_as_string("res://export_presets.cfg")
	assert_eq(source.count("scenes/expeditions/atlas.json"), 2,
		"the dispatcher must remain available in both shipped and internal builds")


func test_EXP03_live_3d_stage_sends_real_host_inspection_and_denies_distant_player() -> void:
	var stage: Node3D = Scene.instantiate()
	stage.set("level_id", "LV_055")
	_holder.add_child(stage)
	var session: Runtime = stage.get("runtime") as Runtime
	var player: CharacterBody3D = stage.get_node("Player") as CharacterBody3D
	var panel: Vector3 = session.definition_snapshot()["positions"]["PANEL_WEST"]
	player.global_position = Vector3(2.0, 0.90, 2.0)
	var before: String = session.state_hash()
	var denied: Dictionary = stage.call("_send", "inspect", "PANEL_WEST", {})
	assert_false(bool(denied.get("ok", true)))
	assert_eq(str(denied.get("code", "")), "NOT_IN_RANGE")
	assert_eq(session.state_hash(), before)
	player.global_position = Vector3(panel.x, 0.90, panel.z + 1.40)
	var accepted: Dictionary = stage.call("_send", "inspect", "PANEL_WEST", {})
	assert_true(bool(accepted.get("ok", false)), str(accepted))
	assert_eq(int(session.task_board()["required_completed"]), 1)
	assert_true((stage.find_child("TaskStatuses", true, false) as Label).text.contains("DONE"))
	assert_true(stage.get_node_or_null("ExpeditionWorld/HostTargets/PANEL_WEST") != null)
