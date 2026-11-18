extends "res://tests/test_case.gd"
## EXP02: source-built geometry and numerical candidate checks; never a playtest.

const Atlas := preload("res://scripts/world/dispatch_atlas.gd")
const Plan := preload("res://scripts/world/expedition_layout_plan.gd")
const Graybox := preload("res://scripts/world/expedition_graybox.gd")


func test_EXP02_all_200_levels_generate_distinct_bounded_five_station_layouts() -> void:
	var data: Dictionary = Atlas.load_catalog()
	var signatures: Dictionary = {}
	for level: Dictionary in data["levels"]:
		var site: Dictionary = Atlas.find_location(data, str(level["location_id"]))
		var plan: Dictionary = Plan.make_plan(level, site)
		assert_true(bool(plan["ok"]), str(plan))
		assert_eq(str(plan["not_certified"]), "NO_PHYSICAL_PLAYABILITY")
		assert_eq(str(plan["code"]), "VISUAL_CANDIDATE_ONLY")
		assert_eq((plan["stations"] as Array).size(), 5)
		var signature: String = str(plan["layout_signature"])
		assert_false(signatures.has(signature), "duplicate 3D level plan: " + str(level["id"]))
		signatures[signature] = true
		for station: Dictionary in plan["stations"]:
			var position: Vector3 = station["position"]
			assert_true(position.x >= 4.0 and position.x <= 48.0)
			assert_true(position.z >= 4.0 and position.z <= 48.0)
			assert_eq(str(station["target_authority"]), "NONE_PREVIEW_ONLY")
	assert_eq(signatures.size(), 200)
	print("EXP02_LEVEL_PLANS PASS levels=200 stations=1000 unique_layouts=%d" % signatures.size())


func test_EXP02_safe_numeric_optional_route_and_deliberately_overloaded_shortcut() -> void:
	var data: Dictionary = Atlas.load_catalog()
	for level: Dictionary in data["levels"]:
		var site: Dictionary = Atlas.find_location(data, str(level["location_id"]))
		var plan: Dictionary = Plan.make_plan(level, site)
		var puzzle: Dictionary = plan["puzzle"]
		var loads: Array = puzzle["required_pu"]
		assert_eq(loads.size(), 3)
		var required: int = int(loads[0]) + int(loads[1]) + int(loads[2])
		assert_eq(int(puzzle["required_total_pu"]), required)
		assert_true(required + int(puzzle["optional_pu"]) <= int(puzzle["source_capacity_pu"]))
		assert_true(int(loads[0]) + int(loads[1]) <= int(puzzle["west_capacity_pu"]))
		assert_true(int(loads[2]) <= int(puzzle["east_capacity_pu"]))
		assert_true(int(puzzle["optional_pu"]) <= int(puzzle["dedicated_spur_capacity_pu"]))
		assert_true(required - int(loads[2]) + int(puzzle["optional_pu"]) >
			int(puzzle["west_capacity_pu"]), "unsafe west route must overload")
		assert_eq(str(puzzle["status"]), "PLANNED_NOT_HOST_ENABLED")


func test_EXP02_all_200_cold_world_builds_have_real_ground_and_noninteractive_task_pads() -> void:
	var data: Dictionary = Atlas.load_catalog()
	var n: int = 0
	for level: Dictionary in data["levels"]:
		var site: Dictionary = Atlas.find_location(data, str(level["location_id"]))
		var plan: Dictionary = Plan.make_plan(level, site)
		var world: Node3D = Graybox.build(plan)
		assert_true(world != null)
		assert_eq(str(world.get_meta("qualification")), "SCHEMATIC_NOT_PLAYABLE")
		assert_true(world.get_node_or_null("CandidateGround/FoundationCollision") != null)
		assert_eq((world.get_node("Stations") as Node3D).get_child_count(), 5)
		assert_true((world.get_node("Landmarks") as Node3D).get_child_count() >= 5)
		assert_eq(world.find_children("*", "CharacterBody3D", true, false).size(), 0)
		for i: int in range(5):
			var station: Marker3D = world.get_node("Stations/Station%02d" % (i + 1)) as Marker3D
			assert_eq(str(station.get_meta("task_id")), str((level["tasks"] as Array)[i]["id"]))
			assert_eq(str(station.get_meta("authority")), "NONE_PREVIEW_ONLY")
		world.free()
		n += 1
	assert_eq(n, 200)
	print("EXP02_GRAYBOX_BUILD PASS distinct_level_worlds=200 planned_stage_pads=1000")


func test_EXP02_foreign_location_and_fake_live_status_fail_closed() -> void:
	var data: Dictionary = Atlas.load_catalog()
	var level: Dictionary = (data["levels"] as Array)[0]
	var wrong_site: Dictionary = (data["locations"] as Array)[1]
	assert_eq(str(Plan.make_plan(level, wrong_site)["code"]), "FOREIGN_LOCATION")
	var forged: Dictionary = level.duplicate(true)
	forged["runtime_status"] = "PLAYABLE"
	assert_eq(str(Plan.make_plan(forged, (data["locations"] as Array)[0])["code"]), "UNAUTHORIZED_LEVEL")
	assert_true(Graybox.build({"ok": true, "code": "HOST_AUTHORIZED"}) == null)
