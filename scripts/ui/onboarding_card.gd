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


func _init() -> void:
	var tokens: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/ui/tokens.json"))
	theme = ThemeTokens.build(tokens)
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
	hint_button.custom_minimum_size.y = ThemeTokens.BUTTON_HEIGHT_PX
	hint_button.pressed.connect(show_hint)
	layout.add_child(hint_button)
	refresh()


func observe(event_id: String) -> void:
	if bool(guide.call("observe", event_id)):
		refresh()


func set_hints_enabled(enabled: bool) -> void:
	guide.call("set_hints_enabled", enabled)
	hint_button.disabled = not enabled


func show_hint() -> void:
	var key: String = str(guide.call("request_hint_key"))
	if key != "":
		hint.text = UiText.t(key)


func refresh() -> void:
	var key: String = str(guide.call("instruction_key"))
	instruction.text = UiText.t(key) if key != "" else UiText.t("guide.complete")
	hint.text = ""
	hint_button.visible = key != ""
