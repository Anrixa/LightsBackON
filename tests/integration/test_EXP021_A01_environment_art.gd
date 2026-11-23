extends "res://tests/test_case.gd"
## EXP021 A01: source identity, actual mesh output and non-interference.
const Atlas := preload("res://scripts/world/dispatch_atlas.gd")
const Plan := preload("res://scripts/world/expedition_layout_plan.gd")
const Graybox := preload("res://scripts/world/expedition_graybox.gd")
const Art := preload("res://scripts/world/exp021_environment_art.gd")

func _no_collisions(node: Node) -> bool:
	if node is CollisionObject3D or node is CollisionShape3D or node is Area3D:
		return false
	for child: Node in node.get_children():
		if not _no_collisions(child):
			return false
	return true

func test_EXP021_A01_all_200_source_anchored_artworks() -> void:
	var catalog: Dictionary = Atlas.load_catalog()
	var signatures: Dictionary = {}
	var coverage: Dictionary = {}
	for index: int in range(200):
		var plan: Dictionary = Plan.make_plan(catalog["levels"][index], catalog["locations"][index])
		var result: Dictionary = Art.inspect(plan)
		assert_true(result.get("ok", false), "source plan %d" % index)
		if not result.get("ok", false):
			continue
		assert_eq(result["level_id"], "LV_%03d" % (index + 1))
		var region: String = str(result["region_id"])
		coverage[region] = true
		assert_false(signatures.has(str(result["source_signature"])), "unique site material/shape signature")
		signatures[str(result["source_signature"])] = true
		# Sample one actual attached mesh tree per eight-site region.
		if index % 8 == 0:
			var world: Node3D = Graybox.build(plan)
			assert_true(world != null)
			if world != null:
				var root: Node3D = world.get_node_or_null(
					"EXP014_A03_RegionalFacilities/EXP021_A01_EnvironmentArt") as Node3D
				assert_true(root != null, "world has environment art")
				if root != null:
					assert_eq(root.get_child_count(), 3)
					assert_true(_no_collisions(root))
					assert_eq(root.get_meta("source_level_id"), plan["id"])
					assert_eq(root.get_meta("source_region_id"), region)
					assert_true(root.get_node_or_null("WeatheredFacade/ServiceWall") is MeshInstance3D)
					assert_true(root.get_node_or_null("Infrastructure") != null)
				world.free()
	assert_eq(coverage.size(), 25)
	assert_eq(signatures.size(), 200)

func test_EXP021_A01_forged_region_and_invalid_risk_fail_closed() -> void:
	var catalog: Dictionary = Atlas.load_catalog()
	var plan: Dictionary = Plan.make_plan(catalog["levels"][0], catalog["locations"][0])
	var damaged: Dictionary = plan.duplicate(true)
	damaged["region_id"] = "REG_02"
	assert_false(Art.inspect(damaged).get("ok", false))
	damaged = plan.duplicate(true)
	damaged["hazard"] = "fabricated state"
	assert_false(Art.inspect(damaged).get("ok", false))
	assert_true(Art.attach(damaged, Node3D.new()) == null)
