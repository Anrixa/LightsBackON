extends "res://tests/test_case.gd"
## EXP017 A01 — physically instantiated regional hero geometry, source-only.

const Atlas := preload("res://scripts/world/dispatch_atlas.gd")
const Plan := preload("res://scripts/world/expedition_layout_plan.gd")
const Regional := preload("res://scripts/world/expedition_regional_facilities.gd")
const Landmarks := preload("res://scripts/world/expedition_regional_landmarks.gd")


func _has_physics(node: Node) -> bool:
	if node is CollisionObject3D or node is CollisionShape3D or \
			node is NavigationRegion3D or node is Area3D:
		return true
	for child: Node in node.get_children():
		if _has_physics(child):
			return true
	return false


func test_EXP017_A01_25_source_pinned_visible_landmark_structures() -> void:
	var atlas: Dictionary = Atlas.load_catalog()
	var signatures: Dictionary = {}
	var families: Dictionary = {}
	for region_index: int in range(25):
		var level: Dictionary = atlas["levels"][region_index * 8]
		var location: Dictionary = atlas["locations"][region_index * 8]
		var plan: Dictionary = Plan.make_plan(level, location)
		assert_true(bool(plan.get("ok", false)), str(plan))
		if not bool(plan.get("ok", false)):
			continue
		var original: Dictionary = plan.duplicate(true)
		var region: String = "REG_%02d" % (region_index + 1)
		var recipe: Dictionary = Regional.RECIPES[region]
		var audit: Dictionary = Landmarks.inspect(region, str(recipe["cue"]))
		assert_true(bool(audit.get("ok", false)), str(audit))
		if not bool(audit.get("ok", false)):
			continue
		var signature: String = str(audit["structural_signature"])
		assert_false(signatures.has(signature),
			"Distinct regional additions must change actual structural geometry")
		signatures[signature] = true
		families[str(audit["family"])] = true
		var world: Node3D = Regional.build(plan)
		assert_true(world != null, str(level["id"]))
		if world == null:
			continue
		assert_eq(world.get_child_count(), 2,
			"A03 root geometry groups must remain unchanged")
		var base: Node3D = world.get_node("FacilitySilhouettes") as Node3D
		assert_eq(base.get_child_count(), 4)
		var hero: Node3D = base.get_child(0).get_node(
			"EXP017_A01_RegionalLandmark") as Node3D
		assert_true(hero != null)
		if hero != null:
			assert_true(hero.get_child_count() >= 3)
			assert_eq(str(hero.get_meta("structural_signature")), signature)
			assert_eq(str(hero.get_meta("region_id")), region)
			assert_true(bool(hero.get_meta("presentation_only")))
		assert_false(_has_physics(world))
		assert_eq(plan, original, "Visuals must not rewrite original job plan")
		world.free()
	assert_eq(signatures.size(), 25)
	assert_eq(families.size(), 5)


func test_EXP017_A01_foreign_risk_cue_and_region_fail_closed() -> void:
	assert_eq(str(Landmarks.inspect("REG_99", "trench").get("code")),
		"EXP017_A01_UNKNOWN_REGION")
	assert_eq(str(Landmarks.inspect("REG_01", "sand").get("code")),
		"EXP017_A01_RISK_CUE_DRIFT")
	assert_true(Landmarks.build("REG_01", "sand", Color.WHITE) == null)
