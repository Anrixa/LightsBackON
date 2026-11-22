extends "res://tests/test_case.gd"
## EXP017 A03 actual ExpeditionHost -> canonical grid -> visual projection.
const Atlas := preload("res://scripts/world/dispatch_atlas.gd")
const Plan := preload("res://scripts/world/expedition_layout_plan.gd")
const Graybox := preload("res://scripts/world/expedition_graybox.gd")
const Presentation := preload("res://scripts/world/exp017_restoration_feedback.gd")
const Runtime := preload("res://scripts/gameplay/expedition_host_session.gd")


func _host_position(_id: String) -> Vector3:
	return Vector3(20, 0.9, 20)


func _no_collider(node: Node) -> bool:
	if node is CollisionObject3D or node is CollisionShape3D:
		return false
	for child: Node in node.get_children():
		if not _no_collider(child):
			return false
	return true


func test_EXP017_A03_all_200_location_source_bindings() -> void:
	var atlas: Dictionary = Atlas.load_catalog()
	var unique: Dictionary = {}
	for i: int in range(200):
		var plan: Dictionary = Plan.make_plan(atlas["levels"][i], atlas["locations"][i])
		var source: Dictionary = Presentation.inspect(plan)
		assert_true(source.get("ok", false), "unbound LV_%03d" % (i + 1))
		if source.get("ok", false):
			assert_eq((source["task_ids"] as Array).size(), 5)
			unique[str(source["signature"])] = true
	assert_eq(unique.size(), 200)


func test_EXP017_A03_real_host_dark_supply_and_forgery_rejection() -> void:
	var atlas: Dictionary = Atlas.load_catalog()
	for n: int in [1, 48, 97, 160, 200]:
		var level: String = "LV_%03d" % n
		var plan: Dictionary = Plan.make_plan(atlas["levels"][n - 1], atlas["locations"][n - 1])
		var world: Node3D = Graybox.build(plan)
		assert_true(world != null)
		if world == null:
			continue
		var view: Node3D = Presentation.build(plan, world)
		assert_true(view != null)
		if view == null:
			world.free()
			continue
		world.add_child(view)
		assert_true(_no_collider(view))
		var host: Runtime = Runtime.new()
		var started: Dictionary = host.start(level, Callable(self, "_host_position"))
		assert_true(started.get("ok", false), str(started))
		if not started.get("ok", false):
			world.free()
			continue
		var board: Dictionary = host.task_board()
		var grid: Dictionary = host.grid.canonical_state()
		var original_board: Dictionary = board.duplicate(true)
		var original_grid: Dictionary = grid.duplicate(true)
		var result: Dictionary = Presentation.reflect(view, board, grid)
		assert_true(result.get("ok", false), str(result))
		if result.get("ok", false):
			for load: String in Presentation.LOADS:
				var lamp: Node3D = view.get_node("HostSupplyLights/Supply_" + load)
				var actual: bool = bool(grid["nodes"][load]["supplied"])
				assert_eq(str(lamp.get_meta("visual_supply")), "grid" if actual else "dark")
				var light: OmniLight3D = lamp.get_node("HostPoweredLamp") as OmniLight3D
				assert_eq(light.light_energy > 0.0, actual)
			var expected_verified: bool = bool(board["mission_verified"]) and \
				bool(grid["nodes"]["LOAD_A"]["supplied"]) and \
				bool(grid["nodes"]["LOAD_B"]["supplied"]) and \
				bool(grid["nodes"]["LOAD_C"]["supplied"])
			assert_eq(result["verified"], expected_verified)
		assert_eq(board, original_board, "Presenter must not mutate host board")
		assert_eq(grid, original_grid, "Presenter must not mutate canonical grid")
		var foreign: Dictionary = board.duplicate(true)
		foreign["level_id"] = "LV_000"
		assert_false(Presentation.reflect(view, foreign, grid).get("ok", false))
		var forged: Dictionary = board.duplicate(true)
		forged["tasks"][0]["id"] = "JOB_999_1"
		assert_false(Presentation.reflect(view, forged, grid).get("ok", false))
		var fake_power: Dictionary = grid.duplicate(true)
		fake_power["nodes"]["GRID"]["online"] = false
		fake_power["nodes"]["LOAD_A"]["supplied"] = true
		assert_false(Presentation.reflect(view, board, fake_power).get("ok", false))
		var stale: Dictionary = board.duplicate(true)
		stale["host_revision"] = -2
		assert_false(Presentation.reflect(view, stale, grid).get("ok", false))
		world.free()


func test_EXP017_A03_host_supplied_state_is_reversible_not_a_reward() -> void:
	var atlas: Dictionary = Atlas.load_catalog()
	var plan: Dictionary = Plan.make_plan(atlas["levels"][0], atlas["locations"][0])
	var world: Node3D = Graybox.build(plan)
	var view: Node3D = Presentation.build(plan, world)
	world.add_child(view)
	var host: Runtime = Runtime.new()
	assert_true(host.start("LV_001", Callable(self, "_host_position")).get("ok", false))
	var board: Dictionary = host.task_board()
	var grid: Dictionary = host.grid.canonical_state()
	# A canonical-shaped host fixture checks rendering only, NOT authenticated
	# switching or physical load-flow: real source host snapshots are above.
	var future: Dictionary = grid.duplicate(true)
	future["tick"] = int(grid["tick"]) + 1
	for id: String in ["LOAD_A", "LOAD_B", "LOAD_C", "SIGN"]:
		future["nodes"][id]["supplied"] = true
	var future_board: Dictionary = board.duplicate(true)
	future_board["host_revision"] = int(board["host_revision"]) + 1
	future_board["mission_verified"] = true
	var lit: Dictionary = Presentation.reflect(view, future_board, future)
	assert_true(lit.get("ok", false))
	assert_eq(lit.get("supplied"), 4)
	assert_true((view.get_node("VerifiedRestorationGlow") as OmniLight3D).light_energy > 0.0)
	var dark: Dictionary = future.duplicate(true)
	dark["tick"] = int(future["tick"]) + 1
	dark["nodes"]["LOAD_A"]["supplied"] = false
	var receded: Dictionary = Presentation.reflect(view, future_board, dark)
	assert_true(receded.get("ok", false))
	assert_false(receded.get("verified", true))
	assert_eq((view.get_node("VerifiedRestorationGlow") as OmniLight3D).light_energy, 0.0)
	assert_eq(future_board["mission_verified"], true, "visual cannot revoke host verification")
	world.free()
