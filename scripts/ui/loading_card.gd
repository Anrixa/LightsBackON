extends RefCounted
## DS09 full-screen loading card, shared by the main menu (shown before the scene change) and the mission (kept up while
## the shader warm-up runs), so the hand-over between the two is one unchanged picture. Presentation only.
## Children by name: LoadingTitle, LoadingDetail, and with a briefing LoadingBriefing; with progress LoadingProgress.

const UiText := preload("res://scripts/ui/ui_text.gd")
const ThemeTokens := preload("res://scripts/ui/theme_tokens.gd")

const COLUMN_WIDTH_PX: int = 620
const PROGRESS_HEIGHT_PX: int = 10


## heading_px: the title size the caller already uses for its own heading (the menu's 46 px at its effective scale).
static func build(tokens: Dictionary, scale_percent: float, heading_px: int, with_briefing: bool, with_progress: bool) -> ColorRect:
	var card: ColorRect = ColorRect.new()
	card.name = "LoadingCard"
	card.color = ThemeTokens.color(tokens, "background")
	card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.theme = ThemeTokens.build(tokens, scale_percent)
	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(center)
	var column: VBoxContainer = VBoxContainer.new()
	column.name = "LoadingColumn"
	column.custom_minimum_size.x = float(ThemeTokens.px(float(COLUMN_WIDTH_PX), scale_percent))
	column.add_theme_constant_override("separation", ThemeTokens.px(14.0, scale_percent))
	center.add_child(column)
	_line(column, "LoadingEyebrow", UiText.t("offline.menu.subtitle"), tokens, "restored", "StrongLabel")
	var title: Label = _line(column, "LoadingTitle", UiText.t("offline.loading.title"), tokens, "text", "")
	title.add_theme_font_size_override("font_size", heading_px)
	if with_briefing:
		# The shift briefing names the first job, so the first thing the player reads already points at the west cabinet.
		_line(column, "LoadingBriefing", UiText.t("offline.loading.briefing"), tokens, "text", "")
	_line(column, "LoadingDetail", UiText.t("offline.loading.detail"), tokens, "text_muted", "")
	if with_progress:
		var bar: ProgressBar = ProgressBar.new()
		bar.name = "LoadingProgress"
		bar.min_value = 0.0
		bar.max_value = 100.0
		bar.show_percentage = false
		bar.custom_minimum_size.y = float(ThemeTokens.px(float(PROGRESS_HEIGHT_PX), scale_percent))
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.focus_mode = Control.FOCUS_NONE
		column.add_child(bar)
	return card


static func set_progress(card: Control, fraction: float) -> void:
	if card == null:
		return
	var bar: ProgressBar = card.find_child("LoadingProgress", true, false) as ProgressBar
	if bar != null:
		bar.value = clampf(fraction, 0.0, 1.0) * 100.0


static func _line(parent: Control, node_name: String, text: String, tokens: Dictionary, color_token: String,
		variation: String) -> Label:
	var label: Label = Label.new()
	label.name = node_name
	label.text = text
	label.theme_type_variation = variation
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", ThemeTokens.color(tokens, color_token))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label
