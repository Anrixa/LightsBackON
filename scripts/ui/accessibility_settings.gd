extends RefCounted
## Local A04 preferences. The simulation never reads these values. Persistence
## and connections to live camera/VFX consumers require a future running MissionRoot.

signal changed(snapshot: Dictionary)

const PATH: String = "res://content/accessibility.json"
const BOOLEAN_KEYS: Array[String] = ["reduce_camera_motion", "reduce_flashes", "hints_enabled"]

var _config: Dictionary = {}
var _values: Dictionary = {}


func _init() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	_config = parsed if parsed is Dictionary else {}
	_values = (_config.get("defaults", {}) as Dictionary).duplicate(true)
	# JSON.parse_string decodes numeric literals as floats; the UI scale is an integer setting.
	_values["ui_scale_percent"] = int(_values["ui_scale_percent"])


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
