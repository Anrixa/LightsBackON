extends "res://tests/test_case.gd"
## DS dispatch-stage look: the Alder Street Stormglass look on the experimental dispatch levels. Presentation only;
## these tests check the scene graph, never visuals, and that the host still owns every target.
const Stage := preload("res://scenes/expeditions/mission_stage.tscn")
const Look := preload("res://scripts/world/dispatch_stage_look.gd")
const LEVELS: Array[String] = ["LV_001", "LV_077", "LV_200"]


func _with_stage(level_id: String, check: Callable) -> void:
	var holder: Node3D = Node3D.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(holder)
	var stage: Node3D = Stage.instantiate()
	stage.set("level_id", level_id)
	holder.add_child(stage)
	var world: Node3D = stage.get_node_or_null("ExpeditionWorld") as Node3D
	assert_true(world != null, "%s: ExpeditionWorld missing" % level_id)
	if world != null:
		check.call(stage, world)
	holder.remove_child(stage)
	stage.free()
	holder.get_parent().remove_child(holder)
	holder.free()


func test_DS_DISPATCH_LOOK_environment_units_and_lights_apply_on_every_sample_level() -> void:
	for level_id: String in LEVELS:
		_with_stage(level_id, func(stage: Node3D, world: Node3D) -> void:
			var report: Dictionary = stage.get_meta("dispatch_look", {})
			assert_true(bool(report.get("ok", false)), "%s: %s" % [level_id, str(report)])
			assert_true(stage.get_node_or_null("WorldLight") is WorldEnvironment, "%s: Stormglass environment" % level_id)
			assert_true(stage.get_node_or_null("Rain") != null, "%s: rain" % level_id)
			assert_eq(int(report.get("work_lights", 0)), 5, "%s: one crew light per station" % level_id)
			assert_true(int(report.get("lamps", 0)) > 0, "%s: street lamps" % level_id)
			assert_true(int(report.get("skinned", 0)) > 20, "%s: static surfaces skinned" % level_id)
			var look: Node3D = world.get_node_or_null(Look.ROOT_NAME) as Node3D
			assert_true(look != null)
			if look != null:
				# Presentation only: nothing in the look layer may collide or carry an interaction area.
				assert_eq(look.find_children("*", "CollisionObject3D", true, false).size(), 0,
					"%s: look layer must not collide" % level_id))


func test_DS_DISPATCH_LOOK_every_host_target_keeps_one_visible_unit() -> void:
	_with_stage("LV_077", func(stage: Node3D, world: Node3D) -> void:
		var positions: Dictionary = stage.get("_definitions")["positions"]
		var targets: Node3D = world.get_node("HostTargets") as Node3D
		var units: Node3D = world.get_node(Look.ROOT_NAME) as Node3D
		var assemblies: Array[Node] = world.find_children("Assemblies", "", true, false)
		for id: String in positions:
			if id == "ZONE_EXTRACT":
				continue
			var marker: Node3D = targets.get_node(id) as Node3D
			# The host marker and its position are untouched.
			assert_true(marker.position.is_equal_approx(positions[id]), id)
			var plate: MeshInstance3D = marker.get_node("WorksitePlate") as MeshInstance3D
			var unit: Node3D = units.get_node_or_null("Unit_" + id) as Node3D
			var dressed_by_assembly: bool = false
			for group: Node in assemblies:
				for node: Node in group.get_children():
					var a: Node3D = node as Node3D
					if Vector2(a.global_position.x - positions[id].x, a.global_position.z - positions[id].z).length() <= 0.15:
						dressed_by_assembly = true
			if Look.unit_kind(id) == "relic":
				assert_true(plate.visible and unit != null, "%s: relic keeps its marker on a plinth" % id)
			elif dressed_by_assembly:
				assert_true(unit == null and not plate.visible, "%s: one visual per target" % id)
			else:
				assert_true(unit != null and not plate.visible, "%s: slab replaced by a unit" % id))


func test_DS_DISPATCH_LOOK_floating_and_degenerate_schematics_are_fixed() -> void:
	_with_stage("LV_077", func(_stage: Node3D, world: Node3D) -> void:
		for group: Node in world.find_children("Assemblies", "", true, false):
			for node: Node in group.get_children():
				assert_eq((node as Node3D).position.y, 0.0, "%s stands on the ground" % node.name)
		for group: Node in world.find_children("ElevatedServiceAccess", "", true, false):
			for node: Node in group.get_children():
				var mi: MeshInstance3D = node as MeshInstance3D
				if mi == null:
					continue
				var name: String = str(mi.name)
				if name.contains("EntryRise") or name.contains("ServiceDescent"):
					assert_false(mi.visible, "%s: zero-run ramp hidden" % name)
				elif name.contains("_Span"):
					assert_true(mi.position.y >= Look.OVERHEAD_CLEARANCE_M, "%s clears head height" % name))


func test_DS_DISPATCH_LOOK_unit_kinds_follow_authored_ids() -> void:
	assert_eq(Look.unit_kind("FIND_077"), "relic")
	assert_eq(Look.unit_kind("FC_077_CTRL"), "console")
	assert_eq(Look.unit_kind("LB_077_BOARD"), "board")
	assert_eq(Look.unit_kind("LG_077_DEPOT"), "crate")
	assert_eq(Look.unit_kind("SW_EAST"), "switch")
	assert_eq(Look.unit_kind("PANEL_WEST"), "meter")
	assert_eq(Look.unit_kind("DV_077_A"), "box")
