extends "res://tests/test_case.gd"
## EXP01: future-content scope and UI gate; no new mission authority is inferred.

const Atlas := preload("res://scripts/world/dispatch_atlas.gd")
const AtlasPanel := preload("res://scripts/ui/dispatch_atlas_panel.gd")

func test_EXP01_catalog_contains_200_distinct_locations_levels_and_1000_tasks() -> void:
	var data: Dictionary = Atlas.load_catalog()
	var audit: Dictionary = Atlas.inspect(data)
	print("EXP01_ATLAS regions=%d locations=%d levels=%d tasks=%d collectibles=%d mechanics=%d puzzles=%d" % [
		int(audit.get("regions", 0)), int(audit.get("locations", 0)),
		int(audit.get("levels", 0)), int(audit.get("tasks", 0)),
		int(audit.get("collectibles", 0)), int(audit.get("mechanics", 0)),
		int(audit.get("puzzle_signatures", 0))])
	assert_true(bool(audit["ok"]), str(audit["failures"]))
	assert_eq(int(audit["regions"]), 25)
	assert_eq(int(audit["locations"]), 200)
	assert_eq(int(audit["levels"]), 200)
	assert_eq(int(audit["tasks"]), 1000)
	assert_eq(int(audit["collectibles"]), 200)
	assert_eq(int(audit["puzzle_signatures"]), 200)
	assert_true(int(audit["mechanics"]) >= 20)
	assert_eq(str(data["authority"]), Atlas.AUTHORITY)


func test_EXP01_each_level_is_source_planned_and_safely_nonplayable() -> void:
	var data: Dictionary = Atlas.load_catalog()
	for level: Dictionary in data["levels"]:
		assert_eq(str(level["runtime_status"]), "DESIGN_BRIEFING_ONLY")
		assert_eq(str(level["scoring_authority"]), "PREVIEW_POINTS_ONLY")
		var tasks: Array = level["tasks"]
		assert_eq(tasks.size(), 5)
		assert_eq(str(tasks[3]["kind"]), "optional_discovery")
		assert_false(bool(tasks[3]["required"]))
		assert_eq(str(level["collectible"]["effect"]), "LORE_ONLY_NO_POWER_OR_CREDITS")
		assert_true(Atlas.preview_points(level) > 0)


func test_EXP01_region_filter_and_text_search_reference_real_authored_sites() -> void:
	var data: Dictionary = Atlas.load_catalog()
	var all: Array[Dictionary] = Atlas.search_levels(data)
	assert_eq(all.size(), 200)
	var first_region: String = str((data["regions"] as Array)[0]["id"])
	assert_eq(Atlas.search_levels(data, first_region).size(), 8)
	var first_level: Dictionary = (data["levels"] as Array)[0]
	assert_eq(Atlas.find_level(data, str(first_level["id"])), first_level)
	assert_eq(Atlas.search_levels(data, "", "West Junction Arcade").size(), 1)
	assert_eq(Atlas.search_levels(data, "", "no-such-location-428").size(), 0)


func test_EXP01_forged_runtime_authority_fails_closed_without_mutating_source() -> void:
	var data: Dictionary = Atlas.load_catalog()
	var fake: Dictionary = data.duplicate(true)
	((fake["levels"] as Array)[0] as Dictionary)["runtime_status"] = "PLAYABLE"
	var report: Dictionary = Atlas.inspect(fake)
	assert_false(bool(report["ok"]))
	assert_true(str(report["failures"]).contains("UNAUTHORIZED_LEVEL"))
	assert_eq(str((data["levels"] as Array)[0]["runtime_status"]), "DESIGN_BRIEFING_ONLY")


func test_EXP01_ui_browses_source_without_creating_gameplay_session() -> void:
	var panel: Control = AtlasPanel.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(panel)
	assert_true(panel.find_child("CloseAtlasButton", true, false) != null)
	assert_true(panel.get_node_or_null("LevelList") != null or panel.find_child("LevelList", true, false) != null)
	var list: ItemList = panel.find_child("LevelList", true, false) as ItemList
	assert_eq(list.item_count, 200)
	var details: RichTextLabel = panel.find_child("LevelDetails", true, false) as RichTextLabel
	assert_true(details.text.contains("PLANNED STORY COLLECTIBLE"))
	assert_true(details.text.contains("NOT real rewards"))
	assert_true(panel.find_children("*", "CharacterBody3D", true, false).is_empty())
	panel.get_parent().remove_child(panel)
	panel.free()
