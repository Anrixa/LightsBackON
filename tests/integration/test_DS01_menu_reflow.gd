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
	var start: Button = menu.get_node("MenuScroll/MenuCenter/MenuPanel/MarginContainer/VBoxContainer/StartButton") as Button
	var resume: Button = menu.get_node("MenuScroll/MenuCenter/MenuPanel/MarginContainer/VBoxContainer/ContinueButton") as Button
	assert_true(start != null and resume != null, "new and continue actions retain their IDs")
	assert_eq(start.focus_mode, Control.FOCUS_ALL)
	assert_eq(resume.focus_mode, Control.FOCUS_ALL)
	menu.call("_layout_for_size", Vector2(440.0, 350.0))
	assert_true(start.is_inside_tree() and resume.is_inside_tree(), "reflow does not remove actions")
	tree.root.remove_child(menu)
	menu.free()
