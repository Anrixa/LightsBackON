extends "res://tests/test_case.gd"
## RB01 (ADR-019 point 4): no developer text on a player screen, as a release build shows it.
## The same audit runs as a release gate (`bash tools/check_player_text.sh`, every shipped scene) and inside the C01 bot
## (every visible text after every step of a full shift). These tests pin the rules, the string table, the release menu
## and the C01 / C03 / C04 screens a player opens (tablet, pause, settings, results).

const Audit := preload("res://scripts/diagnostics/player_text_audit.gd")
const BuildFlavor := preload("res://scripts/ui/build_flavor.gd")
const UiText := preload("res://scripts/ui/ui_text.gd")
const MainMenu := preload("res://scripts/ui/main_menu.gd")
const MenuScene := preload("res://scenes/menu/main_menu.tscn")
const MissionScene := preload("res://scenes/mission/mission_root.tscn")
const C03Scene := preload("res://scenes/mission/c03_roof_preview.tscn")
const C04Scene := preload("res://scenes/mission/c04_sign_spur_preview.tscn")
const C04View := preload("res://scripts/world/c04_sign_spur_view.gd")
const C03_SWITCHES_PATH: String = "res://content/contracts/c03_roof_route/switches.json"
## The four lines the owner saw on 23 Nov 2026, plus the shapes they stand for.
const DEVELOPER_TEXT: Dictionary = {
	"load_a dark": "snake_case",
	"Job_001/1": "internal_id",
	"EXP011 energize or shed": "phase_label",
	"NO PLAYABILITY CERTIFICATION": "developer_wording",
	"Validated headless only": "developer_wording",
	"Host verified": "developer_wording",
	"DS07 look pass": "phase_label",
	"C01 preview": "phase_label",
	"SW_PUMP": "internal_id",
	"GEN_PORTABLE online": "internal_id",
	"ROOF ROUTE - DEV PREVIEW": "developer_wording",
	"Offline development build": "developer_wording",
	"Saved to user://profiles": "file_path",
}
const PLAYER_TEXT: Array[String] = [
	"Market Street feeder", "Load 12 / 24 PU", "WEST BREAKER\nTRIPPED", "Junction JW", "Press F3 for help",
	"Version 0.21.0", "Result: 3 stars", "?  NOT MEASURED", "ROOF ROUTE \u2014 PREVIEW (PROGRESS NOT SAVED)",
	"Solo play. Online co-op is not available in this version.", "TEMP GRID  6 PU MAX",
]

var _tree: SceneTree
var _holder: Node


func before_each() -> void:
	_tree = Engine.get_main_loop() as SceneTree
	_holder = Node.new()
	_holder.name = "RB01Holder"
	_tree.root.add_child(_holder)
	BuildFlavor.simulate_release(true)


func after_each() -> void:
	BuildFlavor.simulate_release(false)
	if _tree.has_meta("expedition_reopen_atlas"):
		_tree.remove_meta("expedition_reopen_atlas")
	if is_instance_valid(_holder):
		_tree.root.remove_child(_holder)
		_holder.free()
	_tree.root.get_viewport().gui_release_focus()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func test_RB01_rules_flag_the_developer_text_the_owner_saw() -> void:
	for text: String in DEVELOPER_TEXT:
		var rules: Array[String] = Audit.violations(text)
		assert_true(rules.has(str(DEVELOPER_TEXT[text])), "%s -> %s (got %s)" % [text, DEVELOPER_TEXT[text], rules])


func test_RB01_rules_pass_real_player_text() -> void:
	for text: String in PLAYER_TEXT:
		assert_eq(Audit.violations(text), [] as Array[String], text)


func test_RB01_string_table_has_no_developer_text() -> void:
	var table: Dictionary = Audit.load_table()
	assert_true(table.size() > 500, "the player string table loads")
	var findings: Array[Dictionary] = Audit.scan_table(table)
	assert_true(findings.is_empty(), Audit.format_findings(findings))


func test_RB01_shipped_scenes_follow_the_release_export_preset() -> void:
	var scenes: Array[String] = Audit.shipped_scenes()
	for required: String in ["res://scenes/menu/main_menu.tscn", "res://scenes/mission/mission_root.tscn",
			"res://scenes/mission/c03_roof_preview.tscn", "res://scenes/mission/c04_sign_spur_preview.tscn",
			"res://scenes/boot/boot.tscn", "res://scenes/world/alder_street.tscn"]:
		assert_true(scenes.has(required), required)
	for path: String in scenes:
		assert_false(path.begins_with("res://tests/") or path.begins_with("res://scenes/lookdev/"),
			"%s is excluded from the release export" % path)
	for path: String in Audit.INTERNAL_ONLY_SCENES:
		assert_true(scenes.has(path), "%s is still packed, so it stays listed until RB14 removes it" % path)


## The release menu is the only way into the EXP stage, and it is closed: the atlas button is hidden and disabled, its
## handler refuses, and a stale "reopen the atlas" flag from an EXP run does nothing.
func test_RB01_release_menu_hides_the_dispatch_atlas() -> void:
	_tree.set_meta("expedition_reopen_atlas", true)
	var menu: Control = MenuScene.instantiate() as Control
	_holder.add_child(menu)
	var atlas: Button = menu.get("dispatch_atlas_button") as Button
	assert_false(atlas.visible, "no atlas button in a release build")
	assert_true(atlas.disabled)
	menu.call("_open_dispatch_atlas")
	assert_true(menu.get("_dispatch_atlas_panel") == null, "the atlas handler refuses in a release build")
	assert_true(menu.find_child("DispatchAtlasOverlay", true, false) == null, "no atlas overlay opened")
	var findings: Array[Dictionary] = Audit.scan_tree(menu, false)
	assert_true(Audit.count_text_nodes(menu, false) > 10, "the menu scan reads real text")
	assert_true(findings.is_empty(), Audit.format_findings(findings))


func test_RB01_internal_builds_keep_the_dispatch_atlas() -> void:
	BuildFlavor.simulate_release(false)
	if not BuildFlavor.is_internal():
		assert_true(true, "an exported release build: nothing to check")
		return
	var menu: Control = MenuScene.instantiate() as Control
	_holder.add_child(menu)
	var atlas: Button = menu.get("dispatch_atlas_button") as Button
	assert_true(atlas.visible and not atlas.disabled, "engineering access stays in internal builds")
	assert_true(atlas.is_in_group(Audit.INTERNAL_ONLY_GROUP))
	assert_true(Audit.scan_tree(menu, true).is_empty(), "internal-only text is exempt in an internal build")


## Only the main menu (behind the atlas) and this audit name the EXP stage scene.
func test_RB01_no_other_path_opens_an_internal_only_scene() -> void:
	var allowed: Array[String] = ["res://scripts/ui/main_menu.gd", "res://scripts/diagnostics/player_text_audit.gd"]
	var sources: Array[String] = []
	_collect_sources("res://scripts", sources)
	_collect_sources("res://scenes", sources)
	assert_true(sources.size() > 50, "source walk found the scripts")
	for path: String in sources:
		var text: String = FileAccess.get_file_as_string(path)
		for scene: String in Audit.INTERNAL_ONLY_SCENES:
			if text.contains(scene.get_file()) and not allowed.has(path) and path != scene:
				assert_true(false, "%s references internal-only %s" % [path, scene])


func test_RB01_c01_screens_have_no_developer_text() -> void:
	var scene: Node = MissionScene.instantiate()
	_holder.add_child(scene)
	_assert_clean(scene, "C01 first frame", true)
	scene.call("_open_tablet")
	_assert_clean(scene, "C01 tablet", true)
	(scene.get("tablet") as Control).call("close")
	scene.call("_toggle_pause")
	_assert_clean(scene, "C01 pause", true)
	scene.call("_toggle_accessibility")
	_assert_clean(scene, "C01 settings", true)
	scene.call("_toggle_accessibility")
	scene.call("_toggle_pause")
	scene.call("_finish")
	_assert_clean(scene, "C01 results", true)
	_assert_clean(scene, "C01 every panel, hidden ones included", false)


func test_RB01_c03_and_c04_previews_have_no_developer_text() -> void:
	for packed: PackedScene in [C03Scene, C04Scene]:
		var scene: Node = packed.instantiate()
		_holder.add_child(scene)
		_assert_clean(scene, packed.resource_path + " first frame", true)
		_assert_clean(scene, packed.resource_path + " all text", false)
		_holder.remove_child(scene)
		scene.free()


## Switch plates name what they switch, from the table, never a shortened ID ("JW BREAKER" from SW_JW_BREAKER).
func test_RB01_world_stations_use_table_names() -> void:
	var ids: Array[String] = []
	ids.assign(C04View.WORKSITE_ORDER)
	var c03: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(C03_SWITCHES_PATH))
	for rec: Dictionary in c03["switches"]:
		ids.append(str(rec["id"]))
	for id: String in ids:
		assert_true(UiText.has("world.station." + id.to_lower()), "%s has a player name" % id)
	var preview: Node = C03Scene.instantiate()
	_holder.add_child(preview)
	var view: Node = preview.get("_ladder_view") as Node
	var label: Label3D = view.get_node("C03SwitchStations/SW_JW_BREAKER/SwitchState") as Label3D
	assert_true(label.text.begins_with(UiText.station_name("SW_JW_BREAKER")), label.text)
	assert_false(label.text.contains("JW BREAKER"), "no ID-derived name")


func test_RB01_save_errors_show_reasons_not_codes() -> void:
	for code: String in ["CORRUPT", "NEWER_SCHEMA", "TARGET_NEWER_SCHEMA", "BAD_IDENTITY", "WRITE_FAILED", "NOT_READY", ""]:
		var reason: String = MainMenu.save_reason(code)
		assert_true(reason != "" and not reason.begins_with("save.reason."), "%s has a table reason" % code)
		var shown: String = UiText.tf("offline.menu.save_error", [reason])
		assert_eq(Audit.violations(shown), [] as Array[String], shown)
		if code != "":
			assert_false(shown.contains(code), "%s is not shown" % code)


func _assert_clean(root: Node, where: String, visible_only: bool) -> void:
	assert_true(Audit.count_text_nodes(root, visible_only) > 0, "%s: the scan reads text" % where)
	var findings: Array[Dictionary] = Audit.scan_tree(root, visible_only)
	assert_true(findings.is_empty(), "%s:\n%s" % [where, Audit.format_findings(findings)])


func _collect_sources(dir_path: String, out: Array[String]) -> void:
	var d: DirAccess = DirAccess.open(dir_path)
	if d == null:
		return
	for sub: String in d.get_directories():
		_collect_sources(dir_path.path_join(sub), out)
	for file: String in d.get_files():
		if file.ends_with(".gd") or file.ends_with(".tscn"):
			out.append(dir_path.path_join(file))
