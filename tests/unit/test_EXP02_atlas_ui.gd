extends "res://tests/test_case.gd"
## EXP02 UI selection reuses one original scene at a time; never enters gameplay.

const AtlasPanel := preload("res://scripts/ui/dispatch_atlas_panel.gd")


func test_EXP02_atlas_updates_single_graybox_for_each_selected_level() -> void:
	var panel: Control = AtlasPanel.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(panel)
	var viewport: SubViewport = panel.find_child("SchematicViewport", true, false) as SubViewport
	assert_true(viewport != null)
	var stage: Node3D = panel.find_child("SchematicStage", true, false) as Node3D
	assert_true(stage != null)
	assert_true(stage.find_child("Preview_LV_001", true, false) != null)
	var first: Node3D = stage.find_child("Preview_LV_001", true, false) as Node3D
	assert_eq(str(first.get_meta("qualification")), "SCHEMATIC_NOT_PLAYABLE")
	var list: ItemList = panel.find_child("LevelList", true, false) as ItemList
	list.select(1)
	list.item_selected.emit(1)
	assert_true(stage.find_child("Preview_LV_001", true, false) == null)
	assert_true(stage.find_child("Preview_LV_002", true, false) != null)
	assert_eq(stage.get_child_count(), 3, "one camera, one light, one preview world")
	assert_true(panel.find_children("*", "CharacterBody3D", true, false).is_empty())
	panel.get_parent().remove_child(panel)
	panel.free()


func test_EXP02_headless_preview_is_not_an_interaction_or_reward_source() -> void:
	var panel: Control = AtlasPanel.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(panel)
	var world: Node3D = panel.find_child("Preview_LV_001", true, false) as Node3D
	for stage: Node in world.get_node("Stations").get_children():
		assert_eq(str(stage.get_meta("authority")), "NONE_PREVIEW_ONLY")
		assert_true(stage is Marker3D)
	assert_eq(world.find_children("*", "Area3D", true, false).size(), 0)
	assert_eq(world.find_children("*", "CharacterBody3D", true, false).size(), 0)
	panel.get_parent().remove_child(panel)
	panel.free()
