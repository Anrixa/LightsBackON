extends "res://tests/test_case.gd"
## EXP017 A01 source-bound 25-region architecture regressions.
const Atlas := preload("res://scripts/world/dispatch_atlas.gd")
const Plan := preload("res://scripts/world/expedition_layout_plan.gd")
const Regional := preload("res://scripts/world/expedition_regional_facilities.gd")
const Identity := preload("res://scripts/world/exp017_region_identity.gd")


func _no_collision(node: Node) -> bool:
	if node is CollisionObject3D or node is CollisionShape3D or node is Area3D:
		return false
	for child: Node in node.get_children():
		if not _no_collision(child):
			return false
	return true


func test_EXP017_A01_200_sites_25_architectural_silhouettes() -> void:
	var atlas: Dictionary = Atlas.load_catalog()
	var signatures: Dictionary = {}
	var geometry_by_region: Dictionary = {}
	for i: int in range(200):
		var plan: Dictionary = Plan.make_plan(atlas["levels"][i], atlas["locations"][i])
		var audit: Dictionary = Identity.inspect(plan)
		assert_true(audit.get("ok", false), "invalid visual source %d" % i)
		if not audit.get("ok", false):
			continue
		signatures[str(audit["region_id"])] = audit["signature"]
		var region: Node3D = Regional.build(plan)
		assert_true(region != null)
		if region == null:
			continue
		var art: Node3D = Identity.attach(plan, region)
		assert_true(art != null, "missing geometry LV_%03d" % (i + 1))
		if art != null:
			assert_eq(art.get_child_count(), 4)
			assert_true(_no_collision(art))
			assert_eq(art.get_meta("source_level_id"), plan["id"])
			for index: int in range(3):
				var landmark: Node3D = art.get_child(index) as Node3D
				assert_true(landmark.get_child_count() > 0)
				if i % 8 == 0:
					geometry_by_region[str(audit["region_id"])] = str(landmark.name)
		region.free()
	assert_eq(signatures.size(), 25)
	assert_eq(geometry_by_region.size(), 25)
	var unique_signatures: Dictionary = {}
	for signature: Variant in signatures.values():
		unique_signatures[str(signature)] = true
	assert_eq(unique_signatures.size(), 25)


func test_EXP017_A01_foreign_region_and_unqualified_plans_fail_closed() -> void:
	var atlas: Dictionary = Atlas.load_catalog()
	var plan: Dictionary = Plan.make_plan(atlas["levels"][0], atlas["locations"][0])
	var region: Node3D = Regional.build(plan)
	var cross: Dictionary = plan.duplicate(true)
	cross["region_id"] = "REG_02"
	assert_false(Identity.inspect(cross).get("ok", false))
	assert_true(Identity.attach(cross, region) == null)
	var spoiled: Dictionary = plan.duplicate(true)
	spoiled["hazard"] = "imaginary risk"
	assert_false(Identity.inspect(spoiled).get("ok", false))
	assert_true(Identity.attach(spoiled, region) == null)
	region.free()
