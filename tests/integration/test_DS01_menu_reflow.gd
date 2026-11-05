extends "res://tests/test_case.gd"
## DS01 design-foundation regression: the real offline menu must reflow on
## compact windows without hiding primary actions or losing gamepad focus.

const MenuScene := preload("res://scenes/menu/main_menu.tscn")
const Tokens := preload("res://scripts/ui/theme_tokens.gd")


func test_DS01_menu_reflows_inside_safe_area_at_small_resolutions() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var menu: Control = MenuScene.instantiate() as Control
	tree.root.add_child(menu)
	var scroll: ScrollContainer = menu.get_node("MenuScroll") as ScrollContainer
	var panel: PanelContainer = menu.get_node("MenuScroll/MenuCenter/MenuPanel") as PanelContainer
	var tokens: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/ui/tokens.json"))
	assert_true(scroll != null and panel != null, "responsive structure is live")
	assert_true(scroll.follow_focus, "focused controls are scrolled into view")
	assert_eq(scroll.horizontal_scroll_mode, ScrollContainer.SCROLL_MODE_DISABLED)
	assert_eq(scroll.vertical_scroll_mode, ScrollContainer.SCROLL_MODE_AUTO)

	menu.call("_layout_for_size", Vector2(1920.0, 1080.0))
	assert_eq(panel.custom_minimum_size.x, 620.0, "desktop max panel width")
	menu.call("_layout_for_size", Vector2(440.0, 350.0))
	var safe: int = Tokens.safe_area(tokens, Vector2(440.0, 350.0))
	assert_true(panel.custom_minimum_size.x <= 440.0 - float(safe * 2),
		"panel does not intrude into left/right safe area")
	assert_eq(panel.custom_minimum_size.y, 0.0, "content height grows naturally for vertical scroll")
	assert_eq(scroll.offset_left, float(safe))
	assert_eq(scroll.offset_right, -float(safe))
	assert_eq(scroll.offset_top, float(safe))
	assert_eq(scroll.offset_bottom, -float(safe))
	tree.root.remove_child(menu)
	menu.free()


func test_DS01_primary_and_secondary_actions_remain_focusable() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var menu: Control = MenuScene.instantiate() as Control
	tree.root.add_child(menu)
	var start: Button = menu.get("start_button") as Button
	var resume: Button = menu.get("continue_button") as Button
	assert_true(start != null and resume != null, "menu exposes both shift actions")
	if start != null and resume != null:
		assert_eq(start.focus_mode, Control.FOCUS_ALL)
		assert_eq(resume.focus_mode, Control.FOCUS_ALL)
		var scroll: ScrollContainer = menu.get_node("MenuScroll") as ScrollContainer
		assert_true(scroll.is_ancestor_of(start) and scroll.is_ancestor_of(resume),
			"shift actions participate in the focus-following scroll area")
		menu.call("_layout_for_size", Vector2(440.0, 350.0))
		assert_true(start.is_inside_tree() and resume.is_inside_tree(), "reflow does not remove actions")
	tree.root.remove_child(menu)
	menu.free()


## QA65: invalid or newer checkpoint data must never be silently replaced
## by launching an unsaveable new shift from the menu.
const OfflinePersistence := preload("res://scripts/persistence/offline_persistence.gd")
const SaveService := preload("res://scripts/persistence/save_service.gd")


func test_QA65_corrupt_checkpoint_disables_start_and_preserves_file() -> void:
	var root: String = "user://test_runtime/qa65_corrupt_%d" % Time.get_ticks_usec()
	var store: OfflinePersistence = OfflinePersistence.new()
	assert_true(store.initialize(root).get("ok", false))
	var path: String = store.checkpoint_path()
	assert_eq(DirAccess.make_dir_recursive_absolute(path.get_base_dir()), OK)
	var writer: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	writer.store_string("{ damaged checkpoint")
	writer.close()
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var menu: Control = MenuScene.instantiate() as Control
	tree.root.add_child(menu)
	menu.set("_store", store)
	menu.call("_apply_save_status", store.checkpoint_status())
	assert_true((menu.get("start_button") as Button).disabled, "new shift is unavailable for an unreadable save")
	assert_false((menu.get("continue_button") as Button).visible)
	assert_true((menu.find_child("SaveStatus", true, false) as Label).text.contains("CORRUPT"))
	tree.remove_meta("offline_resume")
	menu.call("_request_new_shift")
	assert_false(tree.has_meta("offline_resume"), "unsafe new shift must not set the launch flag")
	assert_eq(FileAccess.get_file_as_string(path), "{ damaged checkpoint",
		"corrupt record bytes are never replaced by a menu click")
	tree.root.remove_child(menu)
	menu.free()
	_qa65_remove_tree(root)


func test_QA65_future_schema_checkpoint_remains_untouched() -> void:
	var root: String = "user://test_runtime/qa65_future_%d" % Time.get_ticks_usec()
	var store: OfflinePersistence = OfflinePersistence.new()
	assert_true(store.initialize(root).get("ok", false))
	var path: String = store.checkpoint_path()
	var future: RefCounted = SaveService.new()
	future.call("configure", 999, "future-build", "future-content")
	assert_true(future.call("write_record", path, "checkpoint", "SOLO_C01",
		{"campaign_id": "SOLO_C01"}, "2026-11-06T00:00:00Z").get("ok", false))
	var preserved: String = FileAccess.get_file_as_string(path)
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var menu: Control = MenuScene.instantiate() as Control
	tree.root.add_child(menu)
	menu.set("_store", store)
	menu.call("_apply_save_status", store.checkpoint_status())
	assert_true((menu.get("start_button") as Button).disabled)
	assert_false((menu.get("continue_button") as Button).visible)
	tree.remove_meta("offline_resume")
	menu.call("_request_new_shift")
	assert_false(tree.has_meta("offline_resume"))
	assert_eq(FileAccess.get_file_as_string(path), preserved, "future schema cannot be rewritten")
	tree.root.remove_child(menu)
	menu.free()
	_qa65_remove_tree(root)


static func _qa65_remove_tree(path: String) -> void:
	var dir: DirAccess = DirAccess.open(path)
	if dir == null:
		return
	for filename: String in dir.get_files():
		DirAccess.remove_absolute(path.path_join(filename))
	for directory: String in dir.get_directories():
		_qa65_remove_tree(path.path_join(directory))
	DirAccess.remove_absolute(path)
