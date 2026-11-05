extends "res://tests/test_case.gd"
## QA53: classify remaining headless font/CanvasItem teardown warnings.
## WeakRefs prove whether UI-owned Theme/StyleBox resources survive their owners,
## independently of Godot's imported font cache and renderer shutdown messages.
## These tests do not replace GPU measurements or suppress engine diagnostics.

const ThemeTokens := preload("res://scripts/ui/theme_tokens.gd")
const Menu := preload("res://scenes/menu/main_menu.tscn")


func test_QA53_theme_owned_style_is_released_on_theme_release() -> void:
	var tokens: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/ui/tokens.json"))
	var style: StyleBox = null
	var theme: Theme = ThemeTokens.build(tokens)
	style = theme.get_stylebox("panel", "PanelContainer")
	var weak_style: WeakRef = weakref(style)
	var weak_theme: WeakRef = weakref(theme)
	# Drop every test-owned strong reference before checking the resource graph.
	style = null
	theme = null
	assert_true(weak_theme.get_ref() == null,
		"newly-built theme must not be globally retained by its own style data")
	assert_true(weak_style.get_ref() == null,
		"theme's private panel style must die with its owning theme")


func test_QA53_single_menu_and_theme_are_released() -> void:
	_assert_menus_released(1)


func test_QA53_multiple_sequential_menu_themes_are_released() -> void:
	_assert_menus_released(3)


func _assert_menus_released(count: int) -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var weak_menus: Array[WeakRef] = []
	var weak_themes: Array[WeakRef] = []
	var weak_styles: Array[WeakRef] = []
	for _index: int in count:
		var menu: Control = Menu.instantiate() as Control
		tree.root.add_child(menu)
		var visual_theme: Theme = menu.theme
		var panel_style: StyleBox = visual_theme.get_stylebox("panel", "PanelContainer")
		weak_menus.append(weakref(menu))
		weak_themes.append(weakref(visual_theme))
		weak_styles.append(weakref(panel_style))
		tree.root.remove_child(menu)
		menu.free()
		menu = null
		visual_theme = null
		panel_style = null
	for ref: WeakRef in weak_menus:
		assert_true(ref.get_ref() == null, "menu nodes were freed")
	for ref: WeakRef in weak_themes:
		assert_true(ref.get_ref() == null, "menu-owned theme was released")
	for ref: WeakRef in weak_styles:
		assert_true(ref.get_ref() == null, "menu-owned panel style was released")
