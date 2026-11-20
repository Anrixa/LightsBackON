extends "res://tests/test_case.gd"
## EXP014 A03: geometry-source audit only. NO physical reachability claim.

const Atlas := preload("res://scripts/world/dispatch_atlas.gd")
const Plan := preload("res://scripts/world/expedition_layout_plan.gd")
const Graybox := preload("res://scripts/world/expedition_graybox.gd")
const Regional := preload("res://scripts/world/expedition_regional_facilities.gd")


func _has_physics(node: Node) -> bool:
	if node is CollisionObject3D or node is CollisionShape3D or \
			node is NavigationRegion3D or node is Area3D:
		return true
	for child: Node in node.get_children():
		if _has_physics(child):
			return true
	return false


func test_EXP014_A03_every_region_has_distinct_actual_geometry_and_source_risk() -> void:
	var catalog: Dictionary = Atlas.load_catalog()
	assert_true(bool(Atlas.inspect(catalog).get("ok", false)))
	assert_eq(Regional.RECIPES.size(), 25)
	var signatures: Dictionary = {}
	var sites: Dictionary = {}
	var count: int = 0
	for level: Dictionary in catalog["levels"]:
		var location: Dictionary = Atlas.find_location(catalog, str(level["location_id"]))
		var plan: Dictionary = Plan.make_plan(level, location)
		assert_true(bool(plan.get("ok", false)), str(level["id"]))
		if not bool(plan.get("ok", false)):
			continue
		var original: Dictionary = plan.duplicate(true)
		var audit: Dictionary = Regional.inspect(plan)
		assert_true(bool(audit.get("ok", false)), str(audit))
		if not bool(audit.get("ok", false)):
			continue
		assert_eq(audit["authority"], "PRESENTATION_ONLY")
		assert_eq(audit["qualification"], Regional.QUALIFICATION)
		assert_eq(audit["risk"], location["risk"])
		assert_eq(audit["source_task_markers"], 5)
		assert_true(not sites.has(audit["site_signature"]),
			"200 sites need 200 deterministic spatial identities")
		sites[audit["site_signature"]] = true
		var region: String = str(audit["region_id"])
		if signatures.has(region):
			assert_eq(signatures[region], audit["geometry_signature"])
		else:
			signatures[region] = audit["geometry_signature"]
		var node: Node3D = Regional.build(plan)
		assert_true(node != null, str(level["id"]))
		if node != null:
			assert_eq(node.get_child_count(), 2)
			assert_eq((node.get_node("FacilitySilhouettes") as Node3D).get_child_count(), 4)
			assert_false(_has_physics(node), "Added region physics is forbidden")
			assert_true(bool(node.get_meta("presentation_only")))
			assert_eq(str(node.get_meta("source_location_id")), str(location["id"]))
			var hazard: Node3D = (node.get_node("EnvironmentalEncounter") as Node3D).get_child(0)
			assert_eq(str(hazard.get_meta("source_risk")), str(location["risk"]))
			var evidence: Node3D = node.get_node("EnvironmentalEncounter") as Node3D
			var source_task: String = str(evidence.get_meta("source_task_evidence", ""))
			var is_original_task: bool = false
			for task: Dictionary in level["tasks"]:
				if str(task["id"]) == source_task:
					is_original_task = true
			assert_true(is_original_task, "Environmental evidence must reference an original task")
			assert_eq(str((evidence.get_node("SiteSpecificEvidenceBearing") as Node3D).
				get_meta("source_task_id")), source_task)
			node.free()
		assert_eq(plan, original, "Presentation cannot mutate mission source plan")
		count += 1
	assert_eq(count, 200)
	assert_eq(sites.size(), 200)
	assert_eq(signatures.size(), 25)
	var distinct: Dictionary = {}
	for signature: String in signatures.values():
		assert_false(distinct.has(signature), "Regional geometry was only recolored")
		distinct[signature] = true
	assert_eq(distinct.size(), 25)


func test_EXP014_A03_graybox_integration_keeps_existing_ground_and_task_markers() -> void:
	var catalog: Dictionary = Atlas.load_catalog()
	for serial: int in range(1, 201, 8):
		var level: Dictionary = catalog["levels"][serial - 1]
		var location: Dictionary = catalog["locations"][serial - 1]
		var plan: Dictionary = Plan.make_plan(level, location)
		var world: Node3D = Graybox.build(plan)
		assert_true(world != null, "Region preview missing at site %d" % serial)
		if world == null:
			continue
		assert_true(world.has_node("CandidateGround/FoundationCollision"),
			"Existing EXP02 ground remains untouched")
		assert_eq((world.get_node("Stations") as Node3D).get_child_count(), 5)
		assert_true(world.has_node("EXP014_A03_RegionalFacilities"))
		var regional: Node3D = world.get_node("EXP014_A03_RegionalFacilities") as Node3D
		assert_false(_has_physics(regional))
		assert_eq(regional.get_meta("source_region_id"), "REG_%02d" % ((serial - 1) / 8 + 1))
		world.free()


func test_EXP014_A03_cross_site_splice_and_out_of_bounds_fail_closed() -> void:
	var catalog: Dictionary = Atlas.load_catalog()
	var level: Dictionary = catalog["levels"][0]
	var location: Dictionary = catalog["locations"][0]
	var original: Dictionary = Plan.make_plan(level, location)
	assert_true(bool(Regional.inspect(original).get("ok", false)))
	var altered: Dictionary = original.duplicate(true)
	altered["region_id"] = "REG_25"
	assert_eq(Regional.inspect(altered)["code"], "EXP014_A03_FOREIGN_REGION")
	altered = original.duplicate(true)
	altered["hazard"] = "cosmetic renamed hazard"
	assert_eq(Regional.inspect(altered)["code"], "EXP014_A03_SOURCE_RISK_DRIFT")
	altered = original.duplicate(true)
	altered["stations"][0]["id"] = "JOB_200_1"
	assert_eq(Regional.inspect(altered)["code"], "EXP014_A03_UNBOUND_TASK_MARKER")
	altered = original.duplicate(true)
	altered["stations"][0]["position"] = Vector3(100.0, 0.0, 10.0)
	assert_eq(Regional.inspect(altered)["code"], "EXP014_A03_UNBOUND_TASK_MARKER")
	altered = original.duplicate(true)
	altered["not_certified"] = "PLAYABLE"
	assert_eq(Regional.inspect(altered)["code"], "EXP014_A03_UNQUALIFIED_PLAN")
	assert_true(Regional.build(altered) == null)
