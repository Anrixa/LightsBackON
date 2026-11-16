extends Control
## DS13 — original, resolution-independent control glyphs. No external icons.
## View-only: read the live InputMap; never install bindings or consume input.
## The companion text in InputPrompt remains the accessible, localized action.
##
## Key caps, mouse bodies, pad face buttons, shoulders, triggers, sticks and
## D-pads use the Stormglass design tokens and the same Noto Sans font as UI.

const UiText := preload("res://scripts/ui/ui_text.gd")
const ThemeTokens := preload("res://scripts/ui/theme_tokens.gd")
const RECHECK_SECONDS: float = 0.25
const MIN_WIDTH: float = 42.0
const MAX_WIDTH: float = 112.0
const HEIGHT: float = 42.0

var action: String = ""
var device: String = UiText.DEVICE_KBM
var scale_percent: float = 100.0
var tokens: Dictionary = {}
var _info: Dictionary = {}
var _elapsed: float = 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE


func configure(input_action: String, input_device: String, scale: float, design_tokens: Dictionary) -> void:
	action = input_action
	device = input_device
	scale_percent = scale
	tokens = design_tokens
	_elapsed = 0.0
	refresh_binding()


## Bounded live refresh catches an InputMap remap while a HUD or tablet stays
## open. This is cosmetic polling, not an additional input-action dispatcher.
func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_elapsed += maxf(0.0, delta)
	if _elapsed >= RECHECK_SECONDS:
		_elapsed = fmod(_elapsed, RECHECK_SECONDS)
		refresh_binding()


func refresh_binding() -> void:
	var next: Dictionary = describe(action, device)
	if _info == next:
		return
	_info = next
	var word: String = str(next.get("label", ""))
	var base_width: float = MIN_WIDTH
	if str(next.get("kind", "")) == "keyboard":
		base_width = clampf(22.0 + float(word.length()) * 12.0, MIN_WIDTH, MAX_WIDTH)
	elif str(next.get("kind", "")) == "unbound":
		base_width = MAX_WIDTH
	elif str(next.get("kind", "")) == "shoulder":
		base_width = 60.0
	elif str(next.get("kind", "")) == "mouse":
		base_width = 50.0
	custom_minimum_size = Vector2(base_width, HEIGHT) * scale_percent / 100.0
	tooltip_text = word
	set_meta("binding_label", word)
	set_meta("binding_kind", str(next.get("kind", "")))
	queue_redraw()


func glyph_info() -> Dictionary:
	return _info.duplicate(true)


## Semantic model is testable headless, independent of the renderer.
## The first compatible live InputMap binding wins (same rule as UiText.binding).
static func describe(input_action: String, input_device: String) -> Dictionary:
	var unknown: Dictionary = {"kind": "unbound", "label": UiText.t("input.unbound"), "code": -1}
	if not InputMap.has_action(input_action):
		return unknown
	for event: InputEvent in InputMap.action_get_events(input_action):
		if input_device == UiText.DEVICE_KBM:
			if event is InputEventKey:
				var text: String = UiText._event_label(event, input_device)
				return {"kind": "keyboard", "label": text, "code": 0} if text != "" else unknown
			if event is InputEventMouseButton:
				var mouse: int = int((event as InputEventMouseButton).button_index)
				var label: String = UiText._event_label(event, input_device)
				return {"kind": "mouse", "label": label, "code": mouse}
		elif input_device == UiText.DEVICE_PAD:
			if event is InputEventJoypadButton:
				var button: int = int((event as InputEventJoypadButton).button_index)
				var label: String = UiText._event_label(event, input_device)
				var kind: String = "dpad" if button >= JOY_BUTTON_DPAD_UP and button <= JOY_BUTTON_DPAD_RIGHT else "button"
				if button in [JOY_BUTTON_LEFT_SHOULDER, JOY_BUTTON_RIGHT_SHOULDER, JOY_BUTTON_BACK, JOY_BUTTON_START]:
					kind = "shoulder"
				if button in [JOY_BUTTON_LEFT_STICK, JOY_BUTTON_RIGHT_STICK]:
					kind = "stick"
				return {"kind": kind, "label": label, "code": button}
			if event is InputEventJoypadMotion:
				var axis: int = int((event as InputEventJoypadMotion).axis)
				var label: String = UiText._event_label(event, input_device)
				var kind: String = "shoulder" if axis in [JOY_AXIS_TRIGGER_LEFT, JOY_AXIS_TRIGGER_RIGHT] else "stick"
				return {"kind": kind, "label": label, "code": axis}
	return unknown


func _draw() -> void:
	if _info.is_empty() or tokens.is_empty():
		return
	var ink: Color = ThemeTokens.color(tokens, "text")
	var edge: Color = ThemeTokens.color(tokens, "text_muted")
	var hot: Color = ThemeTokens.color(tokens, "action")
	var fill: Color = ThemeTokens.color(tokens, "elevated")
	var frame: Rect2 = Rect2(Vector2.ZERO, size).grow(-maxf(1.0, scale_percent * 0.015))
	var kind: String = str(_info.get("kind", "unbound"))
	match kind:
		"mouse":
			_draw_mouse(frame, fill, edge, hot)
		"button":
			_draw_button(frame, fill, edge, hot)
		"dpad":
			_draw_dpad(frame, fill, edge, hot)
		"stick":
			_draw_stick(frame, fill, edge, hot)
		_:
			_draw_cap(frame, fill, edge, hot if kind == "shoulder" else ink)
	if kind not in ["mouse", "dpad", "stick"]:
		_draw_text(frame, str(_info.get("label", "")), ink)


func _draw_cap(rect: Rect2, fill: Color, edge: Color, accent: Color) -> void:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = edge
	style.set_border_width_all(maxi(1, roundi(2.0 * scale_percent / 100.0)))
	style.set_corner_radius_all(maxi(2, roundi(8.0 * scale_percent / 100.0)))
	draw_style_box(style, rect)
	draw_line(rect.position + Vector2(7.0, rect.size.y - 5.0),
		rect.position + Vector2(rect.size.x - 7.0, rect.size.y - 5.0), accent.darkened(0.25),
		maxf(1.0, scale_percent / 100.0), true)


func _draw_button(rect: Rect2, fill: Color, edge: Color, accent: Color) -> void:
	var center: Vector2 = rect.get_center()
	var radius: float = minf(rect.size.x, rect.size.y) * 0.45
	draw_circle(center, radius, fill)
	draw_arc(center, radius - 2.0, 0.0, TAU, 40, edge, 2.0, true)
	draw_arc(center, radius - 5.0, 0.0, TAU, 40, accent, 1.3, true)


func _draw_mouse(rect: Rect2, fill: Color, edge: Color, accent: Color) -> void:
	var center: Vector2 = rect.get_center()
	var width: float = minf(rect.size.x * 0.70, 32.0 * scale_percent / 100.0)
	var height: float = rect.size.y * 0.95
	var body: Rect2 = Rect2(center - Vector2(width, height) * 0.5, Vector2(width, height))
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = edge
	style.set_border_width_all(maxi(1, roundi(2.0 * scale_percent / 100.0)))
	style.set_corner_radius_all(maxi(4, roundi(width * 0.37)))
	draw_style_box(style, body)
	var split: float = body.position.y + height * 0.40
	draw_line(Vector2(body.position.x, split), Vector2(body.end.x, split), edge, 1.5, true)
	var code: int = int(_info.get("code", 0))
	if code == MOUSE_BUTTON_LEFT:
		draw_rect(Rect2(body.position + Vector2(3.0, 3.0), Vector2(width * 0.47 - 3.0, height * 0.30)), accent)
	elif code == MOUSE_BUTTON_RIGHT:
		draw_rect(Rect2(body.position + Vector2(width * 0.53, 3.0), Vector2(width * 0.47 - 3.0, height * 0.30)), accent)
	elif code == MOUSE_BUTTON_MIDDLE or code == MOUSE_BUTTON_WHEEL_UP or code == MOUSE_BUTTON_WHEEL_DOWN:
		draw_rect(Rect2(center.x - 2.5, body.position.y + 4.0, 5.0, height * 0.24), accent)
	# Wheel direction is visible in the text tooltip; the mouse body never
	# substitutes LMB for the actual wheel-up/down remapped action.


func _draw_dpad(rect: Rect2, fill: Color, edge: Color, accent: Color) -> void:
	var c: Vector2 = rect.get_center()
	var unit: float = minf(rect.size.x, rect.size.y) / 6.0
	draw_rect(Rect2(c - Vector2(unit * 0.5, unit * 2.0), Vector2(unit, unit * 4.0)), fill)
	draw_rect(Rect2(c - Vector2(unit * 2.0, unit * 0.5), Vector2(unit * 4.0, unit)), fill)
	for offset: Vector2 in [Vector2(0, -1), Vector2(0, 1), Vector2(-1, 0), Vector2(1, 0)]:
		var part: Rect2 = Rect2(c + offset * unit * 1.3 - Vector2(unit * 0.47, unit * 0.47),
			Vector2(unit * 0.94, unit * 0.94))
		draw_rect(part, edge)
	var code: int = int(_info.get("code", 0))
	var direction: Vector2 = Vector2.ZERO
	match code:
		JOY_BUTTON_DPAD_UP: direction = Vector2.UP
		JOY_BUTTON_DPAD_DOWN: direction = Vector2.DOWN
		JOY_BUTTON_DPAD_LEFT: direction = Vector2.LEFT
		JOY_BUTTON_DPAD_RIGHT: direction = Vector2.RIGHT
	draw_circle(c + direction * unit * 1.3, unit * 0.48, accent)


func _draw_stick(rect: Rect2, fill: Color, edge: Color, accent: Color) -> void:
	var center: Vector2 = rect.get_center()
	var radius: float = minf(rect.size.x, rect.size.y) * 0.42
	draw_circle(center, radius, fill)
	draw_arc(center, radius, 0.0, TAU, 36, edge, 2.0, true)
	draw_circle(center, radius * 0.52, accent)
	_draw_text(rect, str(_info.get("label", "")), ThemeTokens.color(tokens, "background"))


func _draw_text(rect: Rect2, value: String, ink: Color) -> void:
	if value == "":
		return
	var font: Font = get_theme_default_font()
	if font == null:
		return
	var px: int = ThemeTokens.px(19.0 if value.length() <= 4 else 15.0, scale_percent)
	var baseline: float = rect.get_center().y + float(px) * 0.34
	draw_string(font, Vector2(rect.position.x + 3.0, baseline), value,
		HORIZONTAL_ALIGNMENT_CENTER, rect.size.x - 6.0, px, ink)
