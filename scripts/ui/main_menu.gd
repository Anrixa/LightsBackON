extends Control
## Actual boot destination for the offline Alder Street build. No Steam login,
## game account, third-party add-on or cloud persistence is required.

const UiText := preload("res://scripts/ui/ui_text.gd")
const ThemeTokens := preload("res://scripts/ui/theme_tokens.gd")
const OfflinePersistence := preload("res://scripts/persistence/offline_persistence.gd")

const MISSION_PATH: String = "res://scenes/mission/mission_root.tscn"
var start_button: Button
var continue_button: Button
var _store: OfflinePersistence
var _save_available: bool = false
var _save_ready: bool = false
var _save_message: Label
var _tokens: Dictionary = {}
var _scroll: ScrollContainer
var _panel: PanelContainer
var _heading: Label
var _margin: MarginContainer


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var tokens: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/ui/tokens.json"))
	_tokens = tokens
	theme = ThemeTokens.build(tokens)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var background: ColorRect = ColorRect.new()
	background.color = ThemeTokens.color(tokens, "background")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	# The menu contains localized multi-line guidance and three actions. A fixed
	# centered panel clips those controls at smaller windows and text sizes.
	# Scroll only when necessary, and follow keyboard/controller focus.
	_scroll = ScrollContainer.new()
	_scroll.name = "MenuScroll"
	_scroll.follow_focus = true
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_scroll)

	var middle: CenterContainer = CenterContainer.new()
	middle.name = "MenuCenter"
	middle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	middle.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.add_child(middle)

	_panel = PanelContainer.new()
	_panel.name = "MenuPanel"
	middle.add_child(_panel)
	_margin = MarginContainer.new()
	_panel.add_child(_margin)
	var layout: VBoxContainer = VBoxContainer.new()
	layout.add_theme_constant_override("separation", 18)
	_margin.add_child(layout)

	var eyebrow: Label = Label.new()
	eyebrow.text = UiText.t("offline.menu.subtitle")
	eyebrow.theme_type_variation = "StrongLabel"
	eyebrow.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	eyebrow.add_theme_color_override("font_color", ThemeTokens.color(tokens, "restored"))
	layout.add_child(eyebrow)

	_heading = Label.new()
	_heading.name = "MenuHeading"
	_heading.text = UiText.t("offline.menu.title")
	_heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_heading.add_theme_font_size_override("font_size", 46)
	_heading.add_theme_color_override("font_color", ThemeTokens.color(tokens, "text"))
	layout.add_child(_heading)

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

	# The visible StartButton is created once after checkpoint status is known.
	_store = OfflinePersistence.new()
	var identity: Dictionary = _store.initialize()
	var save_status: Dictionary = _store.checkpoint_status() if identity.get("ok", false) else identity
	_save_message = Label.new()
	_save_message.name = "SaveStatus"
	_save_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(_save_message)

	continue_button = Button.new()
	continue_button.name = "ContinueButton"
	continue_button.text = UiText.t("offline.menu.continue")
	continue_button.custom_minimum_size.y = 56.0
	continue_button.visible = _save_available
	continue_button.pressed.connect(_continue_shift)
	layout.add_child(continue_button)

	start_button = Button.new()
	start_button.name = "StartButton"
	start_button.text = UiText.t("offline.menu.new_shift")
	start_button.custom_minimum_size.y = 56.0
	start_button.pressed.connect(_request_new_shift)
	layout.add_child(start_button)

	var confirmation: ConfirmationDialog = ConfirmationDialog.new()
	confirmation.name = "ReplaceCheckpointConfirmation"
	confirmation.title = UiText.t("offline.menu.replace_title")
	confirmation.dialog_text = UiText.t("offline.menu.replace_warning")
	confirmation.confirmed.connect(func() -> void: _launch(false, true))
	add_child(confirmation)
	var quit_button: Button = Button.new()
	quit_button.name = "QuitButton"
	quit_button.text = UiText.t("offline.menu.quit")
	quit_button.custom_minimum_size.y = 48.0
	quit_button.pressed.connect(func() -> void: get_tree().quit())
	layout.add_child(quit_button)
	resized.connect(func() -> void: _layout_for_size(size))
	_layout_for_size(size)
	_apply_save_status(save_status)
	(continue_button if _save_available else start_button if _save_ready else quit_button).grab_focus()


## Treat 620 px as a maximum, not a fixed minimum. Preserve a safe border
## and let the actions remain scrollable at narrow resolutions.
func _layout_for_size(viewport_size: Vector2) -> void:
	if _scroll == null or _panel == null or _margin == null:
		return
	var safe: int = ThemeTokens.safe_area(_tokens, viewport_size)
	var effective: float = ThemeTokens.effective_percent(100, viewport_size)
	# Match the rest of the UI's design-canvas scaling; the original hardcoded
	# 46px heading remained huge on 720p even when the panel got narrower.
	theme = ThemeTokens.build(_tokens, effective)
	if _heading != null:
		_heading.add_theme_font_size_override("font_size", ThemeTokens.px(46.0, effective))
	var available_width: float = maxf(220.0, viewport_size.x - float(safe * 2))
	var panel_width: float = minf(620.0, available_width)
	_scroll.offset_left = float(safe)
	_scroll.offset_top = float(safe)
	_scroll.offset_right = -float(safe)
	_scroll.offset_bottom = -float(safe)
	_panel.custom_minimum_size = Vector2(panel_width, 0.0)
	var inset: int = mini(44, maxi(14, roundi(panel_width * 0.06)))
	for side: String in ["left", "right", "top", "bottom"]:
		_margin.add_theme_constant_override("margin_" + side, inset)


## A checkpoint that cannot be read must not become a deceptively playable but
## unsaveable new shift. Keep its files untouched and expose the actual fault.
func _apply_save_status(status: Dictionary) -> void:
	_save_ready = bool(status.get("ok", false))
	_save_available = _save_ready and bool(status.get("available", false))
	continue_button.visible = _save_available
	start_button.disabled = not _save_ready
	_save_message.text = UiText.t("offline.menu.progress_found") if _save_available else (
		UiText.tf("offline.menu.save_error", [str(status.get("code", "UNAVAILABLE"))]) if not _save_ready
		else UiText.t("offline.menu.no_progress"))
	_save_message.add_theme_color_override("font_color", ThemeTokens.color(_tokens,
		"fault" if not _save_ready else "text_muted"))


func _request_new_shift() -> void:
	# The checkpoint may have changed since the menu first opened.
	_apply_save_status(_store.checkpoint_status())
	if not _save_ready:
		return
	if _save_available:
		(get_node("ReplaceCheckpointConfirmation") as ConfirmationDialog).popup_centered()
	else:
		_launch(false)


func _continue_shift() -> void:
	_apply_save_status(_store.checkpoint_status())
	if _save_available:
		_launch(true)


func _launch(resume: bool, replacement_confirmed: bool = false) -> void:
	_apply_save_status(_store.checkpoint_status())
	if not _save_ready or (resume and not _save_available):
		return
	if not resume and _save_available and not replacement_confirmed:
		(get_node("ReplaceCheckpointConfirmation") as ConfirmationDialog).popup_centered()
		return
	# The flag is scene-local launch state, not a save file or a gameplay authority.
	get_tree().set_meta("offline_resume", resume)
	get_tree().change_scene_to_file(MISSION_PATH)
