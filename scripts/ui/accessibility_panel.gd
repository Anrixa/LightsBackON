extends PanelContainer
## Controller-focusable A04 controls. Owning UI connects settings_changed
## to HUD/tablet reflow and later to the camera/VFX presentation hooks.

signal settings_changed(values: Dictionary)

const Settings := preload("res://scripts/ui/accessibility_settings.gd")
const ThemeTokens := preload("res://scripts/ui/theme_tokens.gd")
const UiText := preload("res://scripts/ui/ui_text.gd")

var settings: RefCounted = Settings.new()
var scale_label: Label
var scale_down: Button
var scale_up: Button
var motion_toggle: CheckBox
var flash_toggle: CheckBox
var hints_toggle: CheckBox
var _tokens: Dictionary = {}


func _init() -> void:
	_tokens = JSON.parse_string(FileAccess.get_file_as_string("res://content/ui/tokens.json"))
	_build()


func set_settings(model: RefCounted) -> void:
	settings = model
	_sync()


## The pause overlay owns focus; entering settings explicitly focuses its first
## enabled button rather than leaving the controller on a hidden pause action.
func focus_first() -> void:
	if is_inside_tree() and is_visible_in_tree():
		scale_down.grab_focus()


## Match the actual effective viewport scale of the HUD and tablet and keep
## every control large enough to select by gamepad or mouse.
func set_ui_scale(percent: int) -> void:
	var viewport_size: Vector2 = get_viewport_rect().size if is_inside_tree() else ThemeTokens.DESIGN_SIZE
	var scale: float = ThemeTokens.effective_percent(percent, viewport_size)
	theme = ThemeTokens.build(_tokens, scale)
	var height: float = float(ThemeTokens.px(ThemeTokens.BUTTON_HEIGHT_PX, scale))
	for button: Button in [scale_down, scale_up]:
		button.custom_minimum_size = Vector2(float(ThemeTokens.px(int(_tokens["min_target_px"]), scale)), height)
	for toggle: CheckBox in [motion_toggle, flash_toggle, hints_toggle]:
		toggle.custom_minimum_size.y = height
		toggle.add_theme_stylebox_override("focus", ThemeTokens.focus_box(_tokens, scale))


func _build() -> void:
	theme = ThemeTokens.build(_tokens)
	var layout: VBoxContainer = VBoxContainer.new()
	layout.add_theme_constant_override("separation", ThemeTokens.GAP_PX)
	add_child(layout)
	var title: Label = Label.new()
	title.text = UiText.t("accessibility.title")
	title.theme_type_variation = "HeaderMedium"
	layout.add_child(title)
	var scale_row: HBoxContainer = HBoxContainer.new()
	layout.add_child(scale_row)
	scale_down = _button(scale_row, UiText.t("accessibility.scale_down"))
	scale_label = Label.new()
	scale_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scale_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	scale_row.add_child(scale_label)
	scale_up = _button(scale_row, UiText.t("accessibility.scale_up"))
	scale_down.pressed.connect(_adjust_scale.bind(-10))
	scale_up.pressed.connect(_adjust_scale.bind(10))
	motion_toggle = _toggle(layout, "accessibility.reduce_motion")
	flash_toggle = _toggle(layout, "accessibility.reduce_flashes")
	hints_toggle = _toggle(layout, "accessibility.hints")
	motion_toggle.toggled.connect(_set_boolean.bind("reduce_camera_motion"))
	flash_toggle.toggled.connect(_set_boolean.bind("reduce_flashes"))
	hints_toggle.toggled.connect(_set_boolean.bind("hints_enabled"))
	_sync()


func _button(parent: Control, title: String) -> Button:
	var button: Button = Button.new()
	button.text = title
	button.focus_mode = Control.FOCUS_ALL
	button.custom_minimum_size = Vector2(float(_tokens["min_target_px"]), float(ThemeTokens.BUTTON_HEIGHT_PX))
	parent.add_child(button)
	return button


func _toggle(parent: Control, key: String) -> CheckBox:
	var checkbox: CheckBox = CheckBox.new()
	checkbox.text = UiText.t(key)
	checkbox.focus_mode = Control.FOCUS_ALL
	checkbox.custom_minimum_size.y = ThemeTokens.BUTTON_HEIGHT_PX
	checkbox.add_theme_stylebox_override("focus", ThemeTokens.focus_box(_tokens, 100.0))
	parent.add_child(checkbox)
	return checkbox


func _adjust_scale(delta: int) -> void:
	settings.call("set_value", "ui_scale_percent", int(settings.call("value", "ui_scale_percent")) + delta)
	_sync()
	settings_changed.emit(settings.call("snapshot"))


func _set_boolean(enabled: bool, key: String) -> void:
	settings.call("set_value", key, enabled)
	settings_changed.emit(settings.call("snapshot"))


func _sync() -> void:
	if scale_label == null:
		return
	var percent: int = int(settings.call("value", "ui_scale_percent"))
	scale_label.text = UiText.tf("accessibility.scale", [percent])
	scale_down.disabled = percent <= int(_tokens["ui_scale_percent"]["min"])
	scale_up.disabled = percent >= int(_tokens["ui_scale_percent"]["max"])
	motion_toggle.set_pressed_no_signal(bool(settings.call("value", "reduce_camera_motion")))
	flash_toggle.set_pressed_no_signal(bool(settings.call("value", "reduce_flashes")))
	hints_toggle.set_pressed_no_signal(bool(settings.call("value", "hints_enabled")))
