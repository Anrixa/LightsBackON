extends Control
## Actual boot destination for the offline Alder Street build. No Steam login,
## game account, third-party add-on or cloud persistence is required.

const UiText := preload("res://scripts/ui/ui_text.gd")
const ThemeTokens := preload("res://scripts/ui/theme_tokens.gd")

const MISSION_PATH: String = "res://scenes/mission/mission_root.tscn"
var start_button: Button


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var tokens: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/ui/tokens.json"))
	theme = ThemeTokens.build(tokens)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var background: ColorRect = ColorRect.new()
	background.color = ThemeTokens.color(tokens, "background")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	var middle: CenterContainer = CenterContainer.new()
	middle.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(middle)

	var panel: PanelContainer = PanelContainer.new()
	panel.custom_minimum_size = Vector2(620.0, 500.0)
	middle.add_child(panel)
	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 44)
	margin.add_theme_constant_override("margin_right", 44)
	margin.add_theme_constant_override("margin_top", 42)
	margin.add_theme_constant_override("margin_bottom", 42)
	panel.add_child(margin)
	var layout: VBoxContainer = VBoxContainer.new()
	layout.add_theme_constant_override("separation", 18)
	margin.add_child(layout)

	var eyebrow: Label = Label.new()
	eyebrow.text = UiText.t("offline.menu.subtitle")
	eyebrow.theme_type_variation = "StrongLabel"
	eyebrow.add_theme_color_override("font_color", ThemeTokens.color(tokens, "restored"))
	layout.add_child(eyebrow)

	var heading: Label = Label.new()
	heading.text = UiText.t("offline.menu.title")
	heading.add_theme_font_size_override("font_size", 46)
	heading.add_theme_color_override("font_color", ThemeTokens.color(tokens, "text"))
	layout.add_child(heading)

	var description: Label = Label.new()
	description.text = UiText.t("offline.menu.description")
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(description)
	var controls: Label = Label.new()
	controls.text = UiText.t("offline.menu.controls")
	controls.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	controls.add_theme_color_override("font_color", ThemeTokens.color(tokens, "text_muted"))
	layout.add_child(controls)
	var warning: Label = Label.new()
	warning.text = UiText.t("offline.menu.multiplayer_notice")
	warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	warning.add_theme_color_override("font_color", ThemeTokens.color(tokens, "action"))
	layout.add_child(warning)

	start_button = Button.new()
	start_button.text = UiText.t("offline.menu.play")
	start_button.custom_minimum_size.y = 56.0
	start_button.pressed.connect(func() -> void: get_tree().change_scene_to_file(MISSION_PATH))
	layout.add_child(start_button)
	var quit_button: Button = Button.new()
	quit_button.text = UiText.t("offline.menu.quit")
	quit_button.custom_minimum_size.y = 48.0
	quit_button.pressed.connect(func() -> void: get_tree().quit())
	layout.add_child(quit_button)
	start_button.grab_focus()
