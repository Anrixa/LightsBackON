extends "res://tests/test_case.gd"
const Tools := preload("res://scripts/gameplay/exp019_field_tools.gd")
const Runtime := preload("res://scripts/gameplay/expedition_host_session.gd")
const Scene := preload("res://scenes/expeditions/mission_stage.tscn")


func _facts(state: String, isolated: bool = true) -> Dictionary:
	return {"repair_state": state, "isolated": isolated,
		"west_failed": true, "inspected": true}


func test_EXP019_A03_distinct_five_tool_operations_are_host_state_guarded() -> void:
	var service: Tools = Tools.new()
	assert_true(service.configure("LV_200").get("ok", false))
	var sequence: Array[Dictionary] = [
		{"op":"measure","tool":"meter","state":"undiagnosed"},
		{"op":"secure","tool":"screwdriver","state":"opened"},
		{"op":"cut","tool":"cutter","state":"opened"},
		{"op":"extract","tool":"puller","state":"component_removed"},
		{"op":"crimp","tool":"crimper","state":"replacement_installed"},
		{"op":"verify","tool":"meter","state":"tested"}
	]
	assert_false(service.preflight_step("diagnose").get("ok", false))
	for action: Dictionary in sequence:
		service.accepted_equip(str(action["tool"]))
		var before: Dictionary = service.snapshot()
		if str(action["op"]) != "measure":
			assert_false(service.operate(str(action["op"]), _facts(str(action["state"]), false)).get("ok", false))
			assert_eq(service.snapshot(), before)
		assert_true(service.operate(str(action["op"]), _facts(str(action["state"]))).get("ok", false))
		assert_false(service.operate(str(action["op"]), _facts(str(action["state"]))).get("ok", false))
	assert_eq(int(service.snapshot()["completed_operations"]), 6)
	service.accepted_equip("puller")
	assert_true(service.preflight_step("remove").get("ok", false))
	assert_true(service.preflight_step("install").get("ok", false))
	service.accepted_equip("screwdriver")
	assert_true(service.preflight_step("close").get("ok", false))
	service.accepted_equip("meter")
	assert_true(service.preflight_step("restore").get("ok", false))


func test_EXP019_A03_stage_has_host_tool_authority_and_range_gate() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var holder: Node3D = Node3D.new()
	tree.root.add_child(holder)
	var stage: Node3D = Scene.instantiate()
	stage.set("level_id", "LV_007")
	holder.add_child(stage)
	var session: Runtime = stage.get("runtime") as Runtime
	assert_true(session != null)
	if session != null:
		assert_true(session.field_tools != null)
		assert_true(session.task_board()["worksite"].has("field_tools"))
		var denied: Dictionary = stage.call("_send", "operate_worksite", "R_WEST", {"action": "measure"})
		assert_false(bool(denied.get("ok", false)))
		assert_eq(int(session.field_tools.snapshot()["revision"]), 0)
	holder.remove_child(stage)
	stage.free()
	holder.get_parent().remove_child(holder)
	holder.free()
