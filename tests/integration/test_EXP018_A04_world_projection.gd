extends "res://tests/test_case.gd"
## EXP018 A04: 200 actual source-authenticated host presentations, no graphics certification.

const Atlas := preload("res://scripts/world/dispatch_atlas.gd")
const Plan := preload("res://scripts/world/expedition_layout_plan.gd")
const Graybox := preload("res://scripts/world/expedition_graybox.gd")
const Presentation := preload("res://scripts/world/exp017_restoration_feedback.gd")
const Bridge := preload("res://scripts/world/exp018_host_presentation.gd")
const Runtime := preload("res://scripts/gameplay/expedition_host_session.gd")


func _position(_player: String) -> Vector3:
	return Vector3(20, 0.9, 20)


func _no_collider(node: Node) -> bool:
	if node is CollisionObject3D or node is CollisionShape3D:
		return false
	for child: Node in node.get_children():
		if not _no_collider(child):
			return false
	return true


func test_EXP018_A04_all_200_host_source_bindings_and_non_authoritative_visuals() -> void:
	var atlas: Dictionary = Atlas.load_catalog()
	var layout_signatures: Dictionary = {}
	var passed: int = 0
	for i: int in range(200):
		var level: Dictionary = atlas["levels"][i]
		var location: Dictionary = atlas["locations"][i]
		var plan: Dictionary = Plan.make_plan(level, location)
		var world: Node3D = Graybox.build(plan)
		assert_true(world != null, "world LV_%03d missing" % (i + 1))
		if world == null:
			continue
		var view: Node3D = Presentation.build(plan, world)
		assert_true(view != null, "presenter LV_%03d missing" % (i + 1))
		if view == null:
			world.free()
			continue
		world.add_child(view)
		assert_true(_no_collider(view))
		layout_signatures[str(view.get_meta("source_layout_signature"))] = true
		var host: Runtime = Runtime.new()
		var start: Dictionary = host.start_exp016_source_qualification(
			str(level["id"]), Callable(self, "_position"))
		assert_true(bool(start.get("ok", false)), str(start))
		if not bool(start.get("ok", false)):
			world.free()
			continue
		var original_board: Dictionary = host.task_board().duplicate(true)
		var original_grid: Dictionary = host.grid.canonical_state().duplicate(true)
		var response: Dictionary = Bridge.reflect(view, host, true)
		assert_true(bool(response.get("ok", false)), str(response))
		if bool(response.get("ok", false)):
			assert_eq(str(response["level_id"]), str(level["id"]))
		assert_eq(str(response["authority"]), "READ_ONLY_HOST_PROJECTION")
			assert_eq((host.task_board()["tasks"] as Array).size(), 5)
			for load: String in Presentation.LOADS:
				var lamp: Node3D = view.get_node("HostSupplyLights/Supply_" + load)
				var power: bool = bool(original_grid["nodes"][load]["supplied"])
				assert_eq(str(lamp.get_meta("visual_supply")), "grid" if power else "dark")
		assert_eq(host.task_board(), original_board, "Visual projection rewrote host tasks")
		assert_eq(host.grid.canonical_state(), original_grid, "Visual projection rewrote grid")
		world.free()
		passed += 1
	assert_eq(passed, 200)
	assert_eq(layout_signatures.size(), 200)


func test_EXP018_A04_wrong_visual_source_rejected_without_host_mutation() -> void:
	var atlas: Dictionary = Atlas.load_catalog()
	var plan: Dictionary = Plan.make_plan(atlas["levels"][0], atlas["locations"][0])
	var world: Node3D = Graybox.build(plan)
	var view: Node3D = Presentation.build(plan, world)
	assert_true(view != null)
	if view == null:
		world.free()
		return
	world.add_child(view)
	var host: Runtime = Runtime.new()
	assert_true(host.start_exp016_source_qualification(
		"LV_001", Callable(self, "_position")).get("ok", false))
	var before: Dictionary = host.authoritative_state()
	view.set_meta("source_level_id", "LV_200")
	var invalid: Dictionary = Bridge.reflect(view, host, true)
	assert_eq(str(invalid.get("code", "")), "EXP018_A04_SOURCE_LEVEL_MISMATCH")
	assert_eq(host.authoritative_state(), before)
	world.free()
