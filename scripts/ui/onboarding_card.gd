extends PanelContainer
## Presentation-only first-repair instructions. Advance from authoritative
## accepted gameplay events delivered by the eventual MissionRoot adapter.

const Guide := preload("res://scripts/ui/onboarding_guide.gd")
const UiText := preload("res://scripts/ui/ui_text.gd")
const ThemeTokens := preload("res://scripts/ui/theme_tokens.gd")

var guide: RefCounted = Guide.new()
var instruction: Label
var hint: Label
var hint_button: Button
var _tokens: Dictionary = {}
var _idle_seconds: float = 0.0
var _hints_enabled: bool = true
var _device: String = UiText.DEVICE_KBM


func _init() -> void:
	_tokens = JSON.parse_string(FileAccess.get_file_as_string("res://content/ui/tokens.json"))
	theme = ThemeTokens.build(_tokens)
	var layout: VBoxContainer = VBoxContainer.new()
	add_child(layout)
	instruction = Label.new()
	instruction.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(instruction)
	hint = Label.new()
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(hint)
	hint_button = Button.new()
	hint_button.text = UiText.t("guide.more_help")
	hint_button.focus_mode = Control.FOCUS_NONE  # never steal active world input
	hint_button.custom_minimum_size.y = ThemeTokens.BUTTON_HEIGHT_PX
	hint_button.pressed.connect(show_hint)
	layout.add_child(hint_button)
	refresh()


func observe(event_id: String) -> void:
	if bool(guide.call("observe", event_id)):
		_idle_seconds = 0.0
		refresh()


## Resume presentation from durable world progress, without saving a separate
## tutorial flag that could diverge from the restored repair state.
func sync_from_world(measured: bool, isolated: bool, restored: bool, resumed: bool = false) -> void:
	if bool(guide.call("sync_from_world", measured, isolated, restored, resumed)):
		_idle_seconds = 0.0
		refresh()


func set_hints_enabled(enabled: bool) -> void:
	# Disabled guidance must not silently accrue idle time. Reset only when
	# the preference changes: unrelated UI-scale/viewport refreshes must not
	# erase a manually requested hint.
	if _hints_enabled != enabled:
		_idle_seconds = 0.0
		hint.text = ""
	_hints_enabled = enabled
	guide.call("set_hints_enabled", enabled)
	hint_button.disabled = not enabled


## The visible button also advertises the remappable H / D-pad hint action.
## Gameplay dispatch does not rely on pointer capture or GUI focus.
func set_device(device: String) -> void:
	_device = device
	_update_binding()
	_update_instruction()


func set_ui_scale(percent: int) -> void:
	var size: Vector2 = get_viewport_rect().size if is_inside_tree() else ThemeTokens.DESIGN_SIZE
	var scale: float = ThemeTokens.effective_percent(percent, size)
	theme = ThemeTokens.build(_tokens, scale)
	hint_button.custom_minimum_size.y = float(ThemeTokens.px(ThemeTokens.BUTTON_HEIGHT_PX, scale))


func advance_idle(delta: float) -> void:
	if not _hints_enabled:
		return
	_idle_seconds += maxf(delta, 0.0)
	if hint.text == "":
		var key: String = str(guide.call("idle_hint_key", _idle_seconds))
		if key != "":
			hint.text = UiText.t(key)


## Instructions name real keys from the live InputMap for the device in use (DS09: "Equip the meter (1) ... press E").
func _update_instruction() -> void:
	var key: String = str(guide.call("instruction_key"))
	if key == "":
		instruction.text = UiText.t("guide.complete")
		return
	var labels: Array = []
	for b: Variant in guide.call("instruction_bindings"):
		var actions: Dictionary = b as Dictionary
		labels.append(UiText.binding(str(actions.get(_device, actions.get(UiText.DEVICE_KBM, ""))), _device))
	instruction.text = UiText.tf(key, labels) if not labels.is_empty() else UiText.t(key)


func _update_binding() -> void:
	hint_button.text = "%s (%s)" % [UiText.t("guide.more_help"), UiText.binding("onboarding_hint", _device)]


func show_hint() -> void:
	var key: String = str(guide.call("request_hint_key"))
	if key != "":
		hint.text = UiText.t(key)


func refresh() -> void:
	var key: String = str(guide.call("instruction_key"))
	_update_instruction()
	hint.text = ""
	hint_button.visible = key != ""
	_update_binding()
