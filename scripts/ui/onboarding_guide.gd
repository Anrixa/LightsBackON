extends RefCounted
## First-repair tutorial. Only accepted game events advance it. No markers,
## client hints or UI controls can decide fault causes or repair a panel.

const PATH: String = "res://content/accessibility.json"

var _steps: Array = []
var _thresholds: Array = []
var _index: int = 0
var _hint_level: int = -1
var _hints_enabled: bool = true


func _init() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	var doc: Dictionary = parsed if parsed is Dictionary else {}
	_steps = (doc.get("steps", []) as Array).duplicate(true)
	_thresholds = (doc.get("idle_hint_seconds", []) as Array).duplicate()


func set_hints_enabled(enabled: bool) -> void:
	_hints_enabled = enabled


func completed() -> bool:
	return _index >= _steps.size()


func step_id() -> String:
	return "" if completed() else str((_steps[_index] as Dictionary)["id"])


func instruction_key() -> String:
	return "" if completed() else str((_steps[_index] as Dictionary)["text_key"])


## DS09: input actions whose live binding labels fill the instruction's %s slots, as [{"kbm": action, "pad": action}].
func instruction_bindings() -> Array:
	return [] if completed() else ((_steps[_index] as Dictionary).get("bindings", []) as Array)


func observe(event_id: String) -> bool:
	if completed() or event_id != str((_steps[_index] as Dictionary)["event"]):
		return false
	_index += 1
	_hint_level = -1
	return true


func request_hint_key() -> String:
	if completed() or not _hints_enabled:
		return ""
	var keys: Array = (_steps[_index] as Dictionary)["hint_keys"]
	_hint_level = mini(_hint_level + 1, keys.size() - 1)
	return str(keys[_hint_level])


## Idle time is measured by the caller and reset after valid progression.
func idle_hint_key(idle_seconds: float) -> String:
	if completed() or not _hints_enabled:
		return ""
	var tier: int = -1
	for i: int in range(_thresholds.size()):
		if idle_seconds >= float(_thresholds[i]):
			tier = i
	if tier < 0:
		return ""
	var keys: Array = (_steps[_index] as Dictionary)["hint_keys"]
	return str(keys[mini(tier, keys.size() - 1)])


## Reconcile this presentation guide against the player's own authoritative
## repair progress after a checkpoint reload. Meter snapshots are intentionally
## *not* saved, so an unfinished repair must be measured again first.
## Never move backwards or infer an unknown fault from a mission marker.
func sync_from_world(measured: bool, isolated: bool, restored: bool, resumed: bool = false) -> bool:
	var next_index: int = _index
	if restored:
		next_index = maxi(next_index, _after_event("repair_restored"))
	elif isolated and measured:
		next_index = maxi(next_index, _after_event("junction_isolated"))
	elif measured:
		next_index = maxi(next_index, _after_event("meter_measured"))
	elif resumed:
		next_index = maxi(next_index, _after_event("player_moved"))
	if next_index == _index:
		return false
	_index = next_index
	_hint_level = -1
	return true


func _after_event(event_id: String) -> int:
	for i: int in range(_steps.size()):
		if str((_steps[i] as Dictionary)["event"]) == event_id:
			return i + 1
	return 0
