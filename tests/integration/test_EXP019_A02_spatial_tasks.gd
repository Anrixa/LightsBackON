extends "res://tests/test_case.gd"
const Atlas := preload("res://scripts/world/dispatch_atlas.gd")
const Plan := preload("res://scripts/world/expedition_layout_plan.gd")
const Factory := preload("res://scripts/gameplay/expedition_contract_factory.gd")
const Runtime := preload("res://scripts/gameplay/expedition_host_session.gd")
const Spatial := preload("res://scripts/world/exp019_spatial_tasks.gd")
const Stage := preload("res://scenes/expeditions/mission_stage.tscn")


func test_EXP019_A02_all_1000_tasks_bind_to_exact_host_entities() -> void:
	var atlas: Dictionary = Atlas.load_catalog()
	var unique_tasks: Dictionary = {}
	for i: int in range(200):
		var level: Dictionary = atlas["levels"][i]
		var plan: Dictionary = Plan.make_plan(level, atlas["locations"][i])
		var defs: Dictionary = Factory.build(level, plan)
		var mapped: Dictionary = Spatial.inspect(plan, defs)
		assert_true(mapped.get("ok", false), "LV_%03d: %s" % [i + 1, mapped.get("code", "")])
		if not mapped.get("ok", false):
			continue
		assert_eq((mapped["anchors"] as Array).size(), 5)
		for binding: Dictionary in mapped["anchors"]:
			var id: String = binding["task_id"]
			assert_false(unique_tasks.has(id))
			unique_tasks[id] = true
			assert_true((binding["stand"] as Vector3).distance_to(binding["target"]) <= 2.30)
	assert_eq(unique_tasks.size(), 1000)


func test_EXP019_A02_scene_reflects_actual_host_inspection_and_denies_forgery() -> void:
	var holder: Node3D = Node3D.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(holder)
	var stage: Node3D = Stage.instantiate()
	stage.set("level_id", "LV_032")
	holder.add_child(stage)
	var runtime: Runtime = stage.get("runtime") as Runtime
	var view: Node3D = stage.get_node_or_null("ExpeditionWorld/EXP019_A02_SpatialTaskAnchors") as Node3D
	assert_true(runtime != null)
	assert_true(view != null)
	if view != null and runtime != null:
		var tasks: Dictionary = runtime.task_board()
		assert_true(Spatial.reflect(view, tasks).get("ok", false))
		assert_false(bool(view.get_node("Task01").get_meta("host_completed")))
		var hostile: Dictionary = tasks.duplicate(true)
		hostile["tasks"][0]["binding"] = "R_WEST"
		assert_false(Spatial.reflect(view, hostile).get("ok", false))
		assert_false(bool(view.get_node("Task01").get_meta("host_completed")))
		var stale: Dictionary = tasks.duplicate(true)
		stale["host_revision"] = -10
		assert_false(Spatial.reflect(view, stale).get("ok", false))
	holder.remove_child(stage)
	stage.free()
	holder.get_parent().remove_child(holder)
	holder.free()
