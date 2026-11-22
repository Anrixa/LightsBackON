extends "res://tests/test_case.gd"
const Atlas := preload("res://scripts/world/dispatch_atlas.gd")
const Plan := preload("res://scripts/world/expedition_layout_plan.gd")
const Regional := preload("res://scripts/world/expedition_regional_facilities.gd")
const Identity := preload("res://scripts/world/exp017_region_identity.gd")
const Access := preload("res://scripts/world/exp017_site_access.gd")
const Graybox := preload("res://scripts/world/expedition_graybox.gd")


func _no_collision(node: Node) -> bool:
	if node is CollisionObject3D or node is CollisionShape3D or node is Area3D:
		return false
	for child: Node in node.get_children():
		if not _no_collision(child):
			return false
	return true


func test_EXP017_A02_200_distinct_source_bound_approaches_verticality_and_obstacles() -> void:
	var catalog: Dictionary = Atlas.load_catalog()
	var signatures: Dictionary = {}
	var site_count: int = 0
	for i: int in range(200):
		var plan: Dictionary = Plan.make_plan(catalog["levels"][i], catalog["locations"][i])
		var audit: Dictionary = Access.inspect(plan)
		assert_true(audit.get("ok", false), "LV_%03d source access" % (i + 1))
		if not audit.get("ok", false):
			continue
		signatures[str(audit["layout_signature"])] = true
		assert_true(float(audit["height_m"]) >= 1.2)
		assert_eq((audit["source_task_ids"] as Array).size(), 5)
		var regional: Node3D = Regional.build(plan)
		if regional == null:
			assert_true(false, "region geometry missing")
			continue
		var art: Node3D = Identity.attach(plan, regional)
		assert_true(art != null)
		var route: Node3D = Access.build(plan, regional)
		assert_true(route != null)
		if route != null:
			assert_eq(route.get_meta("source_level_id"), plan["id"])
			assert_true(_no_collision(route))
			assert_eq(route.get_node("ElevatedServiceAccess").get_child_count(), 48)
			assert_eq(route.get_node("ObstructedEmergencyApproach").get_child_count(), 8)
			assert_eq(route.get_node("EnvironmentalObstructions").get_child_count(), 4)
			site_count += 1
			route.free()
		regional.free()
	assert_eq(site_count, 200)
	assert_eq(signatures.size(), 200)


func test_EXP017_A02_graybox_retains_one_ground_and_five_original_markers() -> void:
	var catalog: Dictionary = Atlas.load_catalog()
	for i: int in [0, 23, 57, 104, 151, 199]:
		var plan: Dictionary = Plan.make_plan(catalog["levels"][i], catalog["locations"][i])
		var world: Node3D = Graybox.build(plan)
		assert_true(world != null)
		if world == null:
			continue
		assert_true(world.get_node_or_null("CandidateGround") != null)
		assert_eq(world.get_node("Stations").get_child_count(), 5)
		assert_true(world.get_node_or_null("EXP017_A02_SiteAccess") != null)
		assert_eq(world.get_meta("qualification"), "SCHEMATIC_NOT_PLAYABLE")
		world.free()


func test_EXP017_A02_mismatched_region_and_corrupt_station_are_rejected() -> void:
	var catalog: Dictionary = Atlas.load_catalog()
	var plan: Dictionary = Plan.make_plan(catalog["levels"][0], catalog["locations"][0])
	var regional: Node3D = Regional.build(plan)
	assert_true(Identity.attach(plan, regional) != null)
	var foreign: Dictionary = plan.duplicate(true)
	foreign["location_id"] = "LOC_002"
	assert_false(Access.inspect(foreign).get("ok", false))
	assert_true(Access.build(foreign, regional) == null)
	var corrupt: Dictionary = plan.duplicate(true)
	corrupt["stations"][0]["id"] = "JOB_099_1"
	assert_false(Access.inspect(corrupt).get("ok", false))
	var wrong: Node3D = Regional.build(Plan.make_plan(catalog["levels"][8], catalog["locations"][8]))
	assert_true(Access.build(plan, wrong) == null)
	regional.free()
	wrong.free()
