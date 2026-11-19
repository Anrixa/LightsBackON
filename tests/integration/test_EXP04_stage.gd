extends "res://tests/test_case.gd"
## EXP04 smoke: source-bound 3D lore object exists in the opt-in scene.
## This checks scene wiring only, NOT continuous human/controller playability.

const Atlas := preload("res://scripts/world/dispatch_atlas.gd")
const Runtime := preload("res://scripts/gameplay/expedition_host_session.gd")
const StageScene := preload("res://scenes/expeditions/mission_stage.tscn")
var _holder: Node3D


func before_each() -> void:
	_holder = Node3D.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(_holder)


func after_each() -> void:
	_holder.get_parent().remove_child(_holder)
	_holder.free()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func test_EXP04_opt_in_stage_creates_visual_lore_with_host_authority() -> void:
	var stage: Node3D = StageScene.instantiate()
	stage.set("level_id", "LV_041")
	_holder.add_child(stage)
	var runtime: Runtime = stage.get("runtime") as Runtime
	assert_true(runtime != null)
	assert_eq(str(runtime.lore_state()["id"]), "FIND_041")
	assert_false(bool(runtime.lore_state()["collected"]))
	var marker: Node3D = stage.get_node_or_null(
		"ExpeditionWorld/HostTargets/FIND_041") as Node3D
	assert_true(marker != null)
	if marker != null:
		assert_eq(str(marker.get_meta("host_entity")), "FIND_041")
		assert_true(marker.find_child("WorksitePlate", false, false) != null)
	assert_true(stage.find_child("TaskStatuses", true, false) != null)
	assert_false(bool(runtime.task_board()["lore_collected"]))
	assert_true(runtime.authoritative_state().has("field_lore"))


func test_EXP04_lore_has_no_generator_or_equipment_grid_effect() -> void:
	var stage: Node3D = StageScene.instantiate()
	stage.set("level_id", "LV_101")
	_holder.add_child(stage)
	var runtime: Runtime = stage.get("runtime") as Runtime
	assert_true(runtime != null)
	var grid_before: Dictionary = runtime.grid.canonical_state()
	var item_id: String = str(runtime.lore_state()["id"])
	var positions: Dictionary = runtime.definition_snapshot()["positions"]
	assert_true(positions.has(item_id))
	assert_false(runtime.equipment.canonical_state().has(item_id))
	assert_eq(runtime.grid.canonical_state(), grid_before)
