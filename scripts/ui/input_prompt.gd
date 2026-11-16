extends HBoxContainer
## DS13 glyph plus localized accessible verb. Pure presentation, never focusable.
## Parent layouts can wrap this group as one unit instead of separating the
## remappable key/button from the action it describes.

const InputGlyph := preload("res://scripts/ui/input_glyph.gd")
const ThemeTokens := preload("res://scripts/ui/theme_tokens.gd")
const UiText := preload("res://scripts/ui/ui_text.gd")

var glyph: InputGlyph
var caption: Label
var action: String = ""
var device: String = UiText.DEVICE_KBM


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	add_theme_constant_override("separation", 8)
	glyph = InputGlyph.new()
	glyph.name = "Glyph"
	add_child(glyph)
	caption = Label.new()
	caption.name = "Caption"
	caption.theme_type_variation = "StrongLabel"
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caption.focus_mode = Control.FOCUS_NONE
	caption.autowrap_mode = TextServer.AUTOWRAP_OFF
	# A flex-row label with auto wrap has an effectively zero intrinsic width:
	# at 720p/150% it can become a 20-line tower, pushing the prompt below
	# the safe area and shrinking the tablet map. Keep the caption one line;
	# outer HFlowContainers wrap complete glyph+verb units instead.
	caption.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	caption.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	add_child(caption)


func configure(input_action: String, text: String, input_device: String,
		scale: float, design_tokens: Dictionary, strong: bool = true) -> void:
	action = input_action
	device = input_device
	caption.text = text
	caption.theme_type_variation = "StrongLabel" if strong else "MutedLabel"
	glyph.configure(action, device, scale, design_tokens)
	add_theme_constant_override("separation", ThemeTokens.px(8.0, scale))
	# A screen reader still encounters the visible caption, while the glyph's
	# tooltip contains the precise remapped physical binding name.
	set_meta("action", action)


func set_device(input_device: String) -> void:
	device = input_device
	glyph.configure(action, device, glyph.scale_percent, glyph.tokens)


func refresh_binding() -> void:
	glyph.refresh_binding()
