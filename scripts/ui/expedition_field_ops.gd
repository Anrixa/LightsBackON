extends PanelContainer
## EXP020 A02: opt-in compact field operations tablet; purely presentational.
## It deliberately cannot send authenticated intents or alter host state.
signal closed

const WIDTH: float = 520.0
const HEIGHT: float = 520.0

var _current_tab: String = "briefing"
var _payload: Dictionary = {}
var _title: Label
var _content: Label
var _navigation: Label


func _init() -> void:
	name = "EXP020_FieldOperationsTablet"
	custom_minimum_size = Vector2(WIDTH, HEIGHT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var outer: MarginContainer = MarginContainer.new()
	for edge: String in ["left", "right", "top", "bottom"]:
		outer.add_theme_constant_override("margin_" + edge, 16)
	add_child(outer)
	var stack: VBoxContainer = VBoxContainer.new()
	stack.add_theme_constant_override("separation", 12)
	outer.add_child(stack)
	_title = Label.new()
	_title.text = "FIELD OPERATIONS"
	_title.add_theme_font_size_override("font_size", 22)
	stack.add_child(_title)
	var tabs: HBoxContainer = HBoxContainer.new()
	stack.add_child(tabs)
	for tab: String in ["briefing", "objectives", "network", "evidence"]:
		var button: Button = Button.new()
		button.text = tab.capitalize()
		button.pressed.connect(_select_tab.bind(tab))
		tabs.add_child(button)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size.y = 280
	stack.add_child(scroll)
	_content = Label.new()
	_content.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_content)
	_navigation = Label.new()
	_navigation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stack.add_child(_navigation)
	var dismiss: Button = Button.new()
	dismiss.text = "Close tablet [M]"
	dismiss.pressed.connect(_close)
	stack.add_child(dismiss)


func _select_tab(tab: String) -> void:
	if not ["briefing", "objectives", "network", "evidence"].has(tab):
		return
	_current_tab = tab
	_render()


func _close() -> void:
	visible = false
	closed.emit()


func show_data(model: Dictionary) -> void:
	if not bool(model.get("ok", false)) or model.get("readonly") != true:
		_payload = {}
	else:
		_payload = model.duplicate(true)
	_render()


func current_view_text() -> String:
	return _content.text if _content != null else ""


func selected_tab() -> String:
	return _current_tab


func _render() -> void:
	if _title == null or _content == null or _navigation == null:
		return
	if _payload.is_empty():
		_title.text = "FIELD OPERATIONS / DATA HELD"
		_content.text = "Host/source evidence unavailable."
		_navigation.text = "No state change permitted."
		return
	_title.text = str(_payload["location"]) + " • " + _current_tab.capitalize()
	var view: Array[String] = []
	for line: Variant in _payload.get(_current_tab, []):
		view.append(str(line))
	_content.text = "\n\n".join(view)
	_navigation.text = str(_payload["navigation"])
