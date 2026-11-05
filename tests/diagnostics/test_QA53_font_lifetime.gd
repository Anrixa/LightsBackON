extends "res://tests/test_case.gd"
## QA53 diagnostic-only: classify remaining headless font/CanvasItem teardown warnings.
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


## Minimal label controls distinguish Godot's headless TextServer cache
## from our project-specific font and dynamic menu/theme construction.
func test_QA53_plain_labels_without_project_theme_are_released() -> void:
	_assert_labels_released(3, false)


func test_QA53_themed_labels_are_released() -> void:
	_assert_labels_released(3, true)


func _assert_labels_released(count: int, use_project_theme: bool) -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var tokens: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/ui/tokens.json"))
	var weak_controls: Array[WeakRef] = []
	for i: int in count:
		var root: Control = Control.new()
		root.size = Vector2(440, 350)
		tree.root.add_child(root)
		if use_project_theme:
			root.theme = ThemeTokens.build(tokens)
		var label: Label = Label.new()
		label.text = "Panel %d: an example wrapped label" % i
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size.x = 120.0
		root.add_child(label)
		weak_controls.append(weakref(label))
		tree.root.remove_child(root)
		root.free()
		root = null
		label = null
	for ref: WeakRef in weak_controls:
		assert_true(ref.get_ref() == null, "Control/Label nodes are explicitly freed")


func test_QA53_unused_confirmation_dialogs_are_released() -> void:
	# Compare the only native Window subtree created by the MainMenu with
	# bare Label probes. The main menu normally never opens this dialog on a
	# fresh profile, yet it eagerly allocates one per menu instance.
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var refs: Array[WeakRef] = []
	for _i: int in 3:
		var dialog: ConfirmationDialog = ConfirmationDialog.new()
		dialog.name = "UnusedConfirmation"
		dialog.title = "Replace existing progress?"
		dialog.dialog_text = "Continue with a new shift?"
		tree.root.add_child(dialog)
		refs.append(weakref(dialog))
		tree.root.remove_child(dialog)
		dialog.free()
		dialog = null
	for ref: WeakRef in refs:
		assert_true(ref.get_ref() == null, "unused ConfirmationDialogs must free")


func test_QA53_explicitly_shaped_plain_labels_are_released() -> void:
	_assert_shaped_labels_released(3, false)


func test_QA53_explicitly_shaped_project_labels_are_released() -> void:
	_assert_shaped_labels_released(3, true)


func _assert_shaped_labels_released(count: int, use_project_theme: bool) -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var tokens: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/ui/tokens.json"))
	for i: int in count:
		var parent: Control = Control.new()
		parent.size = Vector2(240, 180)
		tree.root.add_child(parent)
		if use_project_theme:
			parent.theme = ThemeTokens.build(tokens)
		var text: Label = Label.new()
		text.text = "Lengthy translated briefing for step %d, repeated for wrapping in the compact viewport." % i
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		parent.add_child(text)
		text.size = Vector2(120, 96)
		assert_true(text.get_line_count() > 0, "force TextParagraph shaping before teardown")
		var ref: WeakRef = weakref(text)
		tree.root.remove_child(parent)
		parent.free()
		parent = null
		text = null
		assert_true(ref.get_ref() == null, "shaped label node is freed")
