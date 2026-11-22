extends "res://tests/test_case.gd"
const Atlas := preload("res://scripts/world/dispatch_atlas.gd")
const Plan := preload("res://scripts/world/expedition_layout_plan.gd")
const Graybox := preload("res://scripts/world/expedition_graybox.gd")
const Physical := preload("res://scripts/world/exp019_physical_worksite.gd")


func test_EXP019_A01_all_200_routes_are_sourced_bounded_and_distinct() -> void:
	var atlas: Dictionary = Atlas.load_catalog()
	var signatures: Dictionary = {}
	for i: int in range(200):
		var plan: Dictionary = Plan.make_plan(atlas["levels"][i], atlas["locations"][i])
		var route: Dictionary = Physical.inspect(plan)
		assert_true(route.get("ok", false), "LV_%03d: %s" % [i + 1, route.get("code", "")])
		if not route.get("ok", false):
			continue
		assert_eq((route["routes"] as Array).size(), 4)
		for lane: Dictionary in route["routes"]:
			assert_true(float(lane["slope_ratio"]) <= Physical.MAX_RISE_RATIO)
			assert_true(Vector2(lane["start"].x - lane["finish"].x,
				lane["start"].z - lane["finish"].z).length() >= 7.0)
			assert_true(lane["detour"].distance_to(lane["barrier"]) >= 2.99)
		signatures[str(route["signature"])] = true
	assert_eq(signatures.size(), 200)


func test_EXP019_A01_physical_colliders_and_elevated_ray_intersections() -> void:
	var atlas: Dictionary = Atlas.load_catalog()
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	for index: int in [0, 27, 89, 141, 199]:
		var plan: Dictionary = Plan.make_plan(atlas["levels"][index], atlas["locations"][index])
		var world: Node3D = Graybox.build(plan)
		assert_true(world != null)
		if world == null:
			continue
		tree.root.add_child(world)
		var geometry: Node3D = Physical.build(plan, world)
		assert_true(geometry != null)
		if geometry != null:
			world.add_child(geometry)
			var colliders: Array[Node] = geometry.find_children("*", "CollisionShape3D", true, false)
			assert_eq(colliders.size(), 4 * (3 + 2 + 1 + 7))
			await tree.physics_frame
			var audit: Dictionary = Physical.inspect(plan)
			for lane: Dictionary in audit["routes"]:
				var center: Vector3 = (lane["rise"] + lane["crest"]) * 0.5
				var ray: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
					Vector3(center.x, 5.0, center.z), Vector3(center.x, -1.0, center.z), 1)
				var hit: Dictionary = tree.root.get_world_3d().direct_space_state.intersect_ray(ray)
				assert_true(not hit.is_empty(), "elevated deck has a physics surface")
				if not hit.is_empty():
					assert_true((hit["position"] as Vector3).y > 0.70,
						"ray must hit the real raised deck, not just the base floor")
		tree.root.remove_child(world)
		world.free()


func test_EXP019_A01_foreign_site_or_invalid_geometry_fails_closed() -> void:
	var atlas: Dictionary = Atlas.load_catalog()
	var plan: Dictionary = Plan.make_plan(atlas["levels"][0], atlas["locations"][0])
	var wrong: Dictionary = plan.duplicate(true)
	wrong["location_id"] = "LOC_200"
	assert_false(Physical.inspect(wrong).get("ok", false))
	var world: Node3D = Graybox.build(plan)
	assert_true(Physical.build(wrong, world) == null)
	world.free()
