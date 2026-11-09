extends RefCounted
## Local A04 preferences. Gameplay/simulation never reads these values.
## The G06 offline profile saves a strictly validated snapshot through SaveService.

signal changed(snapshot: Dictionary)

const PATH: String = "res://content/accessibility.json"
const BOOLEAN_KEYS: Array[String] = ["reduce_camera_motion", "reduce_flashes", "hints_enabled"]
## DS09: the 3D resolution choice is one of a fixed list, never clamped to an in-between value.
const RENDER_SCALE_KEY: String = "render_scale_percent"
## Keys added after the first profile schema. A saved profile without them is still valid and keeps the
## default for the missing key; nothing is rewritten until the player changes a setting (no save migration).
const ADDED_KEYS: Array[String] = [RENDER_SCALE_KEY]

var _config: Dictionary = {}
var _values: Dictionary = {}


func _init() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	_config = parsed if parsed is Dictionary else {}
	_values = (_config.get("defaults", {}) as Dictionary).duplicate(true)
	# JSON.parse_string decodes numeric literals as floats; the UI scale is an integer setting.
	_values["ui_scale_percent"] = int(_values["ui_scale_percent"])
	_values[RENDER_SCALE_KEY] = int(_values[RENDER_SCALE_KEY])


func value(key: String) -> Variant:
	return _values.get(key)


func snapshot() -> Dictionary:
	return _values.duplicate(true)


## A malformed setting never silently changes a preference.
func set_value(key: String, next: Variant) -> bool:
	var checked: Variant = null
	if key == "ui_scale_percent":
		if typeof(next) != TYPE_INT and typeof(next) != TYPE_FLOAT:
			return false
		var limits: Dictionary = _config["ui_scale_percent"]
		checked = clampi(int(next), int(limits["min"]), int(limits["max"]))
	elif key == RENDER_SCALE_KEY:
		if typeof(next) != TYPE_INT or not render_scale_options().has(next):
			return false
		checked = next
	elif BOOLEAN_KEYS.has(key):
		if typeof(next) != TYPE_BOOL:
			return false
		checked = next
	else:
		return false
	if _values[key] != checked:
		_values[key] = checked
		changed.emit(snapshot())
	return true


## Load an entire profile atomically: a malformed key, float, or partial record
## never changes one preference while leaving the rest stale.
func restore_snapshot(values: Dictionary) -> bool:
	var defaults: Dictionary = _config.get("defaults", {})
	var incoming: Dictionary = values.duplicate(true)
	for key: String in ADDED_KEYS:
		if not incoming.has(key):
			incoming[key] = int(defaults[key])
	values = incoming
	if values.size() != _values.size():
		return false
	for key: String in _values:
		if not values.has(key):
			return false
		var v: Variant = values[key]
		if key == RENDER_SCALE_KEY:
			if typeof(v) != TYPE_INT or not render_scale_options().has(v):
				return false
		elif key == "ui_scale_percent":
			if typeof(v) != TYPE_INT:
				return false
			var limits: Dictionary = _config["ui_scale_percent"]
			if int(v) < int(limits["min"]) or int(v) > int(limits["max"]):
				return false
		elif BOOLEAN_KEYS.has(key):
			if typeof(v) != TYPE_BOOL:
				return false
		else:
			return false
	if values != _values:
		_values = values.duplicate(true)
		changed.emit(snapshot())
	return true


## Use the existing V07 reflow, not a stretched viewport.
func apply_to_views(hud: Node, tablet: Node) -> void:
	for view: Node in [hud, tablet]:
		if view != null and view.has_method("set_ui_scale"):
			view.call("set_ui_scale", int(_values["ui_scale_percent"]))


## Presentation hooks; the player camera and VFX must consume these once built.
func camera_motion_multiplier() -> float:
	return 0.0 if bool(_values["reduce_camera_motion"]) else 1.0


func flash_multiplier() -> float:
	return 0.0 if bool(_values["reduce_flashes"]) else 1.0


## The 3D resolution options in display order; 0 is Auto.
func render_scale_options() -> Array[int]:
	var out: Array[int] = []
	for option: Variant in (_config.get(RENDER_SCALE_KEY, {}) as Dictionary).get("options", []):
		out.append(int(option))
	return out


func render_scale_auto() -> int:
	return int((_config[RENDER_SCALE_KEY] as Dictionary)["auto"])


func render_scale_is_auto() -> bool:
	return int(_values[RENDER_SCALE_KEY]) == render_scale_auto()


## The percentage actually used for a window of window_px pixels. Auto picks the largest fixed option whose 3D pixel
## count stays within auto_max_render_pixels: 2560x1600 -> 75 %, 1920x1080 and 1920x1200 -> 100 %, 3840x2160 -> 50 %.
## Why a pixel budget: the DS08 Intel UHD bench was GPU fill-bound (14.0 ms at 100 %, 10.8 ms at 75 %, 8.6 ms in a
## 1920x1080 window), so the cost follows the number of 3D pixels, not the window size.
func resolved_render_scale_percent(window_px: Vector2) -> int:
	if not render_scale_is_auto():
		return int(_values[RENDER_SCALE_KEY])
	var budget: float = float((_config[RENDER_SCALE_KEY] as Dictionary)["auto_max_render_pixels"])
	var fixed: Array[int] = render_scale_options()
	fixed.erase(render_scale_auto())
	fixed.sort()
	fixed.reverse()
	for percent: int in fixed:
		var f: float = float(percent) / 100.0
		if window_px.x * f * window_px.y * f <= budget:
			return percent
	return fixed[fixed.size() - 1]


## Bilinear is the only 3D scaling mode the Compatibility renderer supports. The 2D canvas (HUD, tablet, menus) is
## drawn after the scaled 3D image at full window resolution, so text stays sharp at every option.
func apply_render_scale(viewport: Viewport) -> void:
	if viewport == null:
		return
	viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	viewport.scaling_3d_scale = float(resolved_render_scale_percent(viewport.get_visible_rect().size)) / 100.0
