extends "res://tests/test_case.gd"
## DS05 live controller/pseudo-locale regressions. These are code-side proofs;
## viewport calculations and simulated inputs do not replace real GPU/UX01 QA.

const UiText := preload("res://scripts/ui/ui_text.gd")
const ThemeTokens := preload("res://scripts/ui/theme_tokens.gd")
const MenuScene := preload("res://scenes/menu/main_menu.tscn")

var _scene: Node3D
var _tree: SceneTree
var _locale_before: String = ""


func before_each() -> void:
	_tree = Engine.get_main_loop() as SceneTree
	_locale_before = UiText.locale()
	UiText.set_locale(UiText.LOCALE_PSEUDO)
	_scene = (load("res://scenes/mission/mission_root.tscn") as PackedScene).instantiate()
	_tree.root.add_child(_scene)


func after_each() -> void:
	UiText.set_locale(_locale_before)
	if _scene != null and is_instance_valid(_scene):
		_tree.root.remove_child(_scene)
		_scene.free()
	_scene = null
	_tree.root.get_viewport().gui_release_focus()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func test_DS05_menu_title_wraps_and_scales_with_viewport_under_pseudolocale() -> void:
	var menu: Control = MenuScene.instantiate() as Control
	_tree.root.add_child(menu)
	var heading: Label = menu.get("_heading")
	var scroll: ScrollContainer = menu.get("_scroll")
	assert_true(heading != null and scroll != null)
	assert_eq(heading.autowrap_mode, TextServer.AUTOWRAP_WORD_SMART,
		"35% translation expansion must wrap rather than horizontally clip title")
	assert_true(heading.text.contains("~"), "test must use the expanded pseudo-locale")
	for viewport: Vector2 in [Vector2(1280, 720), Vector2(960, 540)]:
		menu.call("_layout_for_size", viewport)
		var expected: int = ThemeTokens.px(46.0, ThemeTokens.effective_percent(100, viewport))
		assert_eq(heading.get_theme_font_size("font_size"), expected)
		var panel: PanelContainer = menu.get("_panel")
		var safe: int = ThemeTokens.safe_area(menu.get("_tokens"), viewport)
		assert_true(panel.custom_minimum_size.x <= viewport.x - float(safe * 2))
	assert_true((menu.get("start_button") as Button).focus_mode == Control.FOCUS_ALL)
	assert_true(scroll.follow_focus, "D-pad focus follows actions past the fold")
	_tree.root.remove_child(menu)
	menu.free()


func test_DS05_accessibility_bounds_never_strand_controller_focus() -> void:
	var model: RefCounted = _scene.get("settings")
	var panel: PanelContainer = _scene.get("accessibility")
	_scene.call("_toggle_pause")
	_scene.call("_toggle_accessibility")
	var down: Button = panel.get("scale_down")
	var up: Button = panel.get("scale_up")
	var row: Control = down.get_parent() as Control
	assert_true(row is HFlowContainer, "translated scale controls wrap at 720p")
	model.call("set_value", "ui_scale_percent", 90)
	_scene.call("_settings_changed", model.call("snapshot"), false)
	down.grab_focus()
	panel.call("_adjust_scale", -10)
	assert_eq(int(model.call("value", "ui_scale_percent")), 80)
	assert_true(down.disabled and not up.disabled)
	assert_eq(_tree.root.gui_get_focus_owner(), up,
		"at lower bound, focus transfers to an enabled action")
	model.call("set_value", "ui_scale_percent", 140)
	_scene.call("_settings_changed", model.call("snapshot"), false)
	up.grab_focus()
	panel.call("_adjust_scale", 10)
	assert_eq(int(model.call("value", "ui_scale_percent")), 150)
	assert_true(up.disabled and not down.disabled)
	assert_eq(_tree.root.gui_get_focus_owner(), down,
		"at upper bound, focus transfers back to decrement")
	_scene.call("_toggle_pause")
	_scene.call("_toggle_pause")


func test_DS05_tablet_objectives_scroll_with_35_percent_longer_text() -> void:
	_scene.call("_open_tablet")
	var tablet: PanelContainer = _scene.get("tablet")
	var overlay: Control = _scene.get("_overlay")
	# Exercise actual tablet tree reflow in a bounded 720p overlay; no
	# exported Windows render is claimed by this headless layout probe.
	overlay.size = Vector2(1280, 720)
	tablet.call("_show_tab", "objectives")
	tablet.call("set_ui_scale", 150)
	var scroll: ScrollContainer = tablet.get("_objective_scroll")
	assert_true(scroll != null and scroll.is_inside_tree())
	assert_eq(scroll.name, "ObjectivesScroll")
	assert_eq(scroll.focus_mode, Control.FOCUS_ALL)
	assert_true((tablet.call("focusables") as Array).has(scroll),
		"the controller can focus the objective list and scroll it")
	assert_true(scroll.get_child(0).get_child_count() > 0,
		"objective list remains populated after the tab/layout rebuild")
	assert_eq(tablet.get("tab"), "objectives")
	var close: Button = tablet.get("close_button")
	assert_true(close.is_visible_in_tree(), "Close stays outside the scrolling evidence")
	assert_eq(close.focus_mode, Control.FOCUS_ALL)
	var effective: float = float(tablet.get("scale_percent"))
	assert_true(is_equal_approx(effective, 100.0),
		"150% UI at 720p uses the same design-canvas scale as 100% at 1080p")
	scroll.grab_focus()
	tablet.call("set_device", UiText.DEVICE_PAD)
	assert_eq(_tree.root.gui_get_focus_owner(), tablet.get("_objective_scroll"),
		"controller focus must survive device-prompt rebuild")
	tablet.call("set_ui_scale", 80)
	assert_eq(_tree.root.gui_get_focus_owner(), tablet.get("_objective_scroll"),
		"controller focus must survive UI scale rebuild")
	assert_true((tablet.get("close_button") as Button).is_visible_in_tree())
	tablet.call("close")
	assert_false(tablet.visible)
	assert_true(bool((_scene.get("player") as Node).get("enabled")),
		"returning from objectives restores world movement controls")


func test_DS05_network_footer_keeps_close_in_focus_graph_after_reflow() -> void:
	_scene.call("_open_tablet")
	var tablet: PanelContainer = _scene.get("tablet")
	(_scene.get("_overlay") as Control).size = Vector2(1280, 720)
	tablet.call("set_ui_scale", 150)
	assert_eq(tablet.get("tab"), "network")
	var close: Button = tablet.get("close_button")
	var zoom: Array = tablet.get("zoom_buttons")
	assert_true(zoom.size() == 3)
	assert_true(close.is_visible_in_tree())
	assert_true((tablet.call("focusables") as Array).has(close))
	for b: Button in zoom:
		assert_true(b.is_visible_in_tree(), "map tools remain available on network tab")
	var footer: Control = close.get_parent() as Control
	assert_true(footer is HFlowContainer, "footer actions wrap rather than clip")
	assert_true(close.get_focus_neighbor(SIDE_LEFT) != NodePath(""),
		"Close has an explicit D-pad path from the preceding map tool")
	tablet.call("_show_tab", "objectives")
	assert_true((tablet.get("close_button") as Button).is_visible_in_tree())
	for b: Button in tablet.get("zoom_buttons"):
		assert_false(b.visible, "hidden map actions cannot trap controller focus")
	tablet.call("close")
