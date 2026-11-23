extends "res://tests/test_case.gd"
const Atlas := preload("res://scripts/world/dispatch_atlas.gd")
const Plan := preload("res://scripts/world/expedition_layout_plan.gd")
const Contingency := preload("res://scripts/world/exp019_environment_physics.gd")
const Runtime := preload("res://scripts/gameplay/expedition_host_session.gd")
const Stage := preload("res://scenes/expeditions/mission_stage.tscn")


func test_EXP019_A04_200_source_specific_risk_access_profiles() -> void:
	var atlas: Dictionary = Atlas.load_catalog()
	var seen: Dictionary = {}
	for i: int in range(200):
		var plan: Dictionary = Plan.make_plan(atlas["levels"][i], atlas["locations"][i])
		var result: Dictionary = Contingency.inspect(plan)
		assert_true(result.get("ok", false), "LV_%03d: %s" % [i + 1, result.get("code", "")])
		if not result.get("ok", false):
			continue
		var risk_class: String = str(result["risk_class"])
		seen[risk_class] = true
		var required_lanes: Array = Contingency.CLASS_LANES[risk_class]
		var closures: Array = result["closures"]
		assert_eq(closures.size(), required_lanes.size(), "region-specific closure count")
		var visited_lanes: Dictionary = {}
		for closure: Dictionary in closures:
			var lane: int = int(closure["lane"])
			assert_true(required_lanes.has(lane), "source policy lane")
			assert_false(visited_lanes.has(lane), "no duplicate obstruction")
			visited_lanes[lane] = true
			assert_true((closure["position"] as Vector3).is_finite(), "finite physical geometry")
		assert_true(visited_lanes.size() < 4, "one independent elevated route survives")
	assert_eq(seen.size(), 5)


func test_EXP019_A04_live_host_hazard_changes_real_collision() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var holder: Node3D = Node3D.new()
	tree.root.add_child(holder)
	var scene: Node3D = Stage.instantiate()
	scene.set("level_id", "LV_001")
	holder.add_child(scene)
	var session: Runtime = scene.get("runtime") as Runtime
	var display: Node3D = scene.get_node_or_null("ExpeditionWorld/EXP019_A04_HostContingencies") as Node3D
	assert_true(session != null)
	assert_true(display != null)
	if session != null and display != null:
		var host: Dictionary = session.task_board()
		var grid: Dictionary = session.grid.canonical_state()
		assert_true(Contingency.reflect(display, host, grid).get("ok", false))
		var barrier: Node3D = display.get_node("ControlledAccessBarriers/Hazard00") as Node3D
		assert_true(bool(barrier.get_meta("closed_by_host")))
		var tampered: Dictionary = host.duplicate(true)
		tampered["worksite"]["site_hazards"]["risk_class"] = "wrong"
		assert_false(Contingency.reflect(display, tampered, grid).get("ok", false))
		assert_true(bool(barrier.get_meta("closed_by_host")))
		var healed: Dictionary = host.duplicate(true)
		healed["worksite"]["site_hazards"]["solved"] = true
		healed["worksite"]["site_hazards"]["fault"] = ""
		assert_true(Contingency.reflect(display, healed, grid).get("ok", false))
		assert_false(bool(barrier.get_meta("closed_by_host")))
		# set_deferred will reach the physics server on the next engine frame;
		# do not yield this test, because unawaited coroutines leak live worlds.
		assert_true(barrier.get_node_or_null("Collision") is CollisionShape3D)
		assert_false((barrier.get_node("Barrier") as MeshInstance3D).visible)
		# A stale grid revision and foreign host identity must be rejected before
		# any collision/visual or revision metadata can change.
		var stale_grid: Dictionary = grid.duplicate(true)
		stale_grid["tick"] = -10
		var revision_before: int = int(display.get_meta("last_host_revision"))
		assert_false(Contingency.reflect(display, healed, stale_grid).get("ok", false))
		assert_eq(int(display.get_meta("last_host_revision")), revision_before)
		var foreign_board: Dictionary = healed.duplicate(true)
		foreign_board["level_id"] = "LV_200"
		assert_false(Contingency.reflect(display, foreign_board, grid).get("ok", false))
		assert_false(bool(barrier.get_meta("closed_by_host")))
	holder.remove_child(scene)
	scene.free()
	holder.get_parent().remove_child(holder)
	holder.free()
