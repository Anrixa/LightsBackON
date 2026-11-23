extends "res://tests/test_case.gd"
const Atlas := preload("res://scripts/world/dispatch_atlas.gd")
const Plan := preload("res://scripts/world/expedition_layout_plan.gd")
const Graybox := preload("res://scripts/world/expedition_graybox.gd")
const Presentation := preload("res://scripts/world/exp017_restoration_feedback.gd")
const Effects := preload("res://scripts/world/exp021_restoration_effects.gd")
const Settings := preload("res://scripts/ui/accessibility_settings.gd")

func _scene() -> Dictionary:
	var atlas: Dictionary = Atlas.load_catalog()
	var plan: Dictionary = Plan.make_plan(atlas["levels"][0], atlas["locations"][0])
	var world: Node3D = Graybox.build(plan)
	var projected: Node3D = Presentation.build(plan, world)
	world.add_child(projected)
	var effects: Variant = Effects.new()
	return {"world": world, "effect": effects, "result": effects.setup(world, plan)}

func _grid(online: bool, lit: bool, tick: int) -> Dictionary:
	return {"tick": tick, "nodes": {
		"GRID": {"online": online}, "LOAD_A": {"supplied": lit},
		"LOAD_B": {"supplied": lit}, "LOAD_C": {"supplied": lit},
		"SIGN": {"supplied": false}
	}}

func test_EXP021_A03_200_accessible_source_identifiers_and_material_contrast() -> void:
	var atlas: Dictionary = Atlas.load_catalog()
	var signatures: Dictionary = {}
	for i: int in range(200):
		var plan: Dictionary = Plan.make_plan(atlas["levels"][i], atlas["locations"][i])
		var audit: Dictionary = Effects.inspect(plan)
		assert_true(audit.get("ok", false))
		if audit.get("ok", false):
			assert_false(signatures.has(str(audit["signature"])))
			signatures[str(audit["signature"])] = true
	assert_eq(signatures.size(), 200)
	assert_true(Effects.contrast_ratio(Color("#EAF5ED"), Color("#111C26")) >= 7.0)

func test_EXP021_A03_power_on_slews_and_fail_darkens_immediately() -> void:
	var f: Dictionary = _scene()
	assert_true(f["result"].get("ok", false))
	assert_eq(f["result"].get("new_light_nodes"), 0)
	var fx: Variant = f["effect"]
	var board: Dictionary = {"level_id":"LV_001", "host_revision":2,
		"mission_verified":true, "worksite":{"site_hazards":{"solved":true}}}
	assert_true(fx.reflect(board, _grid(true, true, 5)).get("ok", false))
	assert_true(fx.is_restored())
	fx.advance(0.1)
	var first: float = fx.light_energy("LOAD_A")
	assert_true(first > 0.0 and first < 0.85, "bounded non-flashing lamp slew")
	fx.advance(0.1)
	assert_true(fx.light_energy("LOAD_A") > first)
	assert_true(fx.is_mitigated())
	assert_true(fx.reflect(board, _grid(false, false, 6)).get("ok", false))
	assert_eq(fx.light_energy("LOAD_A"), 0.0)
	assert_false(fx.is_restored())
	fx.advance(0.25)
	assert_eq(fx.light_energy("LOAD_A"), 0.0)
	f["world"].free()

func test_EXP021_A03_stale_grid_cannot_override_lighting_or_settings() -> void:
	var f: Dictionary = _scene()
	var fx: Variant = f["effect"]
	assert_true(fx.reflect({"level_id":"LV_001", "host_revision":4,
		"mission_verified":true}, _grid(true, true, 8)).get("ok", false))
	var malformed: Dictionary = _grid(false, true, 9)
	assert_false(fx.reflect({"level_id":"LV_001", "host_revision":5,
		"mission_verified":false}, malformed).get("ok", false))
	assert_true(fx.is_restored())
	assert_false(fx.reflect({"level_id":"LV_001", "host_revision":3,
		"mission_verified":false}, _grid(false, false, 10)).get("ok", false))
	var settings: Variant = Settings.new()
	var prefs: Dictionary = settings.snapshot()
	prefs["ui_scale_percent"] = 150
	prefs["reduce_flashes"] = true
	assert_true(fx.set_preferences(prefs))
	assert_eq(fx.configured_ui_scale(), 150)
	assert_true(fx.reduced_flashes_enabled())
	assert_eq(fx.camera_offset_from_effects(), Vector3.ZERO)
	prefs["ui_scale_percent"] = 151
	assert_false(fx.set_preferences(prefs))
	assert_eq(fx.configured_ui_scale(), 150)
	f["world"].free()
