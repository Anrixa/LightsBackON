extends "res://tests/test_case.gd"
## QA54: narrow complete MainMenu teardown warnings to the smallest structural
## component group. Each case is run in its own pinned-Godot process by the
## dedicated resource workflow; do not use these results as GPU memory data.
##
## These are isolated *synthetic* controls. The actual full-menu reference is
## already provided by QA53_single and DS01; no game code is patched here.

const ThemeTokens := preload("res://scripts/ui/theme_tokens.gd")

const STRUCTURE: int = 0
const TEXT: int = 1
const BUTTONS: int = 2
const DIALOG: int = 3
const REFLOW: int = 4
const SIGNALS: int = 5


func test_QA54_structure_only() -> void:
	_assert_released(STRUCTURE)


func test_QA54_structured_text() -> void:
	_assert_released(TEXT)


func test_QA54_buttons() -> void:
	_assert_released(BUTTONS)


func test_QA54_dialog() -> void:
	_assert_released(DIALOG)


func test_QA54_reflow() -> void:
	_assert_released(REFLOW)


func test_QA54_signals_and_focus() -> void:
	_assert_released(SIGNALS)


func _assert_released(stage: int) -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var menu: Control = _create_synthetic_menu(stage)
	var menu_ref: WeakRef = weakref(menu)
	var theme_ref: WeakRef = weakref(menu.theme)
	var panel: PanelContainer = menu.get_node("MenuScroll/MenuCenter/MenuPanel") as PanelContainer
	var panel_ref: WeakRef = weakref(panel)
	panel = null
	tree.root.add_child(menu)
	menu.size = Vector2(1280.0, 720.0)
	if stage >= TEXT:
		var header: Label = menu.get_node("MenuScroll/MenuCenter/MenuPanel/Margin/Layout/Header") as Label
		assert_true(header.get_line_count() > 0, "render layout must actually shape heading")
		header = null
	if stage >= SIGNALS:
		var start: Button = menu.get_node("MenuScroll/MenuCenter/MenuPanel/Margin/Layout/NewShift") as Button
		start.grab_focus()
		assert_true(start.has_focus(), "focus reaches the synthetic button")
		start = null
	tree.root.remove_child(menu)
	menu.free()
	menu = null
	assert_true(menu_ref.get_ref() == null, "explicitly freed menu node must be released")
	assert_true(theme_ref.get_ref() == null, "theme ownership must not escape menu")
	assert_true(panel_ref.get_ref() == null, "owned panel must be released")


func _create_synthetic_menu(stage: int) -> Control:
	var tokens: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://content/ui/tokens.json"))
	var menu: Control = Control.new()
	menu.name = "SyntheticMenu"
	menu.theme = ThemeTokens.build(tokens)
	menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var background: ColorRect = ColorRect.new()
	background.color = ThemeTokens.color(tokens, "background")
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu.add_child(background)

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.name = "MenuScroll"
	scroll.follow_focus = true
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu.add_child(scroll)
	var center: CenterContainer = CenterContainer.new()
	center.name = "MenuCenter"
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)
	var panel: PanelContainer = PanelContainer.new()
	panel.name = "MenuPanel"
	panel.custom_minimum_size.x = 620.0
	center.add_child(panel)
	var margin: MarginContainer = MarginContainer.new()
	margin.name = "Margin"
	panel.add_child(margin)
	var layout: VBoxContainer = VBoxContainer.new()
	layout.name = "Layout"
	layout.add_theme_constant_override("separation", 18)
	margin.add_child(layout)

	if stage >= TEXT:
		var descriptions: Array[String] = [
			"RESTORE THE STREET",
			"Lights Back On",
			"Diagnose a storm-damaged network and restore safe power.",
			"Move, inspect, repair, and confirm your results.",
			"Local offline mission; online cooperative play is not available.",
			"No saved shift on this device."
		]
		for index: int in descriptions.size():
			var label: Label = Label.new()
			label.name = "Header" if index == 1 else "Description%d" % index
			label.text = descriptions[index]
			label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			if index == 0:
				label.theme_type_variation = "StrongLabel"
			if index == 1:
				label.add_theme_font_size_override("font_size", 46)
			layout.add_child(label)
	if stage >= BUTTONS:
		for name: String in ["Continue", "NewShift", "Quit"]:
			var button: Button = Button.new()
			button.name = name
			button.text = name
			button.custom_minimum_size.y = 56.0
			layout.add_child(button)
	if stage >= DIALOG:
		var dialog: ConfirmationDialog = ConfirmationDialog.new()
		dialog.name = "ReplaceCheckpointConfirmation"
		dialog.title = "Replace progress?"
		dialog.dialog_text = "Begin a new shift?"
		menu.add_child(dialog)
	if stage >= REFLOW:
		# The production menu rebuilds theme resources during _ready() layout.
		menu.theme = ThemeTokens.build(tokens, ThemeTokens.effective_percent(
			100, Vector2(1280.0, 720.0)))
		margin.add_theme_constant_override("margin_left", 36)
		margin.add_theme_constant_override("margin_right", 36)
	if stage >= SIGNALS:
		# Match the real menu's two self-referencing Callable patterns without
		# invoking scene changes or modifying profile storage.
		var confirmation: ConfirmationDialog = menu.get_node(
			"ReplaceCheckpointConfirmation") as ConfirmationDialog
		confirmation.confirmed.connect(func() -> void: menu.visible = true)
		menu.resized.connect(func() -> void: panel.custom_minimum_size.x = 620.0)
	return menu
