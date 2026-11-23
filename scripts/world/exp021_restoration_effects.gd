extends RefCounted
## EXP021 A03 — original grid-powered lighting, environmental recovery and
## accessibility contract. Uses EXP017's existing lamps: zero new lights,
## zero animation timers, no flash pulses, no camera movement, no host commands.
const Art := preload("res://scripts/world/exp021_environment_art.gd")
const Accessibility := preload("res://scripts/ui/accessibility_settings.gd")
const LOADS: Array[String] = ["LOAD_A", "LOAD_B", "LOAD_C", "SIGN"]
const ESSENTIAL: Array[String] = ["LOAD_A", "LOAD_B", "LOAD_C"]
const QUALIFICATION: String = "HOST_READ_ONLY_HEADLESS_ONLY_PHYSICAL_ACCESSIBILITY_RELEASE_HELD"
const DARK: Color = Color("#111C26")
const READABLE: Color = Color("#EAF5ED")

var _root: Node3D
var _lights: Dictionary = {}
var _current: Dictionary = {}
var _target: Dictionary = {}
var _finale: OmniLight3D
var _glow_current: float = 0.0
var _glow_target: float = 0.0
var _last_host_revision: int = -1
var _last_grid_tick: int = -1
var _level_id: String = ""
var _reduce_flashes: bool = true
var _reduce_camera_motion: bool = true
var _ui_scale: int = 100
var _last_verified: bool = false
var _hazard_mitigated: bool = false


static func inspect(plan: Dictionary) -> Dictionary:
	var source: Dictionary = Art.inspect(plan)
	if not bool(source.get("ok", false)):
		return {"ok": false, "code": "EXP021_A03_ART_SOURCE_REJECTED"}
	return {"ok": true, "level_id": source["level_id"],
		"region_id": source["region_id"],
		"signature": (str(source["source_signature"]) + "|fx_v1").sha256_text(),
		"authority": "READ_ONLY_GRID_VISUAL", "qualification": QUALIFICATION}


static func _linear_channel(value: float) -> float:
	return value / 12.92 if value <= 0.04045 else pow((value + 0.055) / 1.055, 2.4)


static func contrast_ratio(foreground: Color, background: Color) -> float:
	var fg: float = 0.2126 * _linear_channel(foreground.r) + \
		0.7152 * _linear_channel(foreground.g) + \
		0.0722 * _linear_channel(foreground.b)
	var bg: float = 0.2126 * _linear_channel(background.r) + \
		0.7152 * _linear_channel(background.g) + \
		0.0722 * _linear_channel(background.b)
	return (maxf(fg, bg) + 0.05) / (minf(fg, bg) + 0.05)


func setup(world: Node3D, plan: Dictionary) -> Dictionary:
	var audit: Dictionary = inspect(plan)
	if not bool(audit.get("ok", false)) or world == null or \
			str(world.get_meta("source_level_id", "")) != str(audit.get("level_id", "")):
		return {"ok": false, "code": "EXP021_A03_WRONG_WORLD"}
	_root = world.get_node_or_null("EXP017_A03_HostRestorationPresentation") as Node3D
	if _root == null or str(_root.get_meta("source_level_id", "")) != str(audit["level_id"]):
		return {"ok": false, "code": "EXP021_A03_HOST_PRESENTATION_MISSING"}
	for load: String in LOADS:
		var lamp: OmniLight3D = _root.get_node_or_null(
			"HostSupplyLights/Supply_%s/HostPoweredLamp" % load) as OmniLight3D
		if lamp == null:
			_lights.clear()
			return {"ok": false, "code": "EXP021_A03_MISSING_GRID_LAMP"}
		_lights[load] = lamp
		_current[load] = 0.0
		_target[load] = 0.0
	_finale = _root.get_node_or_null("VerifiedRestorationGlow") as OmniLight3D
	if _finale == null or contrast_ratio(READABLE, DARK) < 7.0:
		return {"ok": false, "code": "EXP021_A03_ACCESSIBILITY_OR_FINALE_MISSING"}
	_level_id = str(audit["level_id"])
	_root.set_meta("exp021_visual_signature", audit["signature"])
	return {"ok": true, "level_id": _level_id,
		"lights_reused": _lights.size(), "new_light_nodes": 0,
		"qualification": QUALIFICATION}


## Restore the original, existing settings schema; never alter its save format.
## A partial or malformed preference dictionary is rejected atomically.
func set_preferences(values: Dictionary) -> bool:
	var settings: Variant = Accessibility.new()
	if not settings.restore_snapshot(values):
		return false
	var selected: Dictionary = settings.snapshot()
	_reduce_flashes = bool(selected["reduce_flashes"])
	_reduce_camera_motion = bool(selected["reduce_camera_motion"])
	_ui_scale = int(selected["ui_scale_percent"])
	return true


## Independent negative validation before touching light energies. Darkness
## takes effect in this exact call; ignition is monotonic and bounded per frame.
func reflect(board: Dictionary, grid: Dictionary) -> Dictionary:
	if _root == null or str(board.get("level_id", "")) != _level_id or \
			typeof(board.get("host_revision")) != TYPE_INT or \
			int(board["host_revision"]) < _last_host_revision or \
			typeof(board.get("mission_verified")) != TYPE_BOOL or \
			typeof(grid.get("tick")) != TYPE_INT or \
			int(grid["tick"]) < _last_grid_tick or \
			not grid.get("nodes") is Dictionary:
		return {"ok": false, "code": "EXP021_A03_STALE_OR_FOREIGN_HOST"}
	var nodes: Dictionary = grid["nodes"]
	if not nodes.get("GRID") is Dictionary or \
			typeof(nodes["GRID"].get("online")) != TYPE_BOOL:
		return {"ok": false, "code": "EXP021_A03_INVALID_GRID_SOURCE"}
	var proposed: Dictionary = {}
	for load: String in LOADS:
		if not nodes.get(load) is Dictionary or \
				typeof(nodes[load].get("supplied")) != TYPE_BOOL:
			return {"ok": false, "code": "EXP021_A03_BAD_CONSUMER"}
		var lit: bool = bool(nodes[load]["supplied"])
		if lit and not bool(nodes["GRID"]["online"]):
			return {"ok": false, "code": "EXP021_A03_IMPOSSIBLE_SUPPLY"}
		proposed[load] = 0.85 if lit else 0.0
	var verified: bool = bool(board["mission_verified"])
	for load: String in ESSENTIAL:
		if float(proposed[load]) <= 0.0:
			verified = false
	var worksite: Variant = board.get("worksite", {})
	var mitigated: bool = false
	if worksite is Dictionary and worksite.get("site_hazards") is Dictionary:
		mitigated = bool(worksite["site_hazards"].get("solved", false))
	# Only after all four source payloads are valid can the scene be mutated.
	for load: String in LOADS:
		_target[load] = float(proposed[load])
		if float(_target[load]) <= 0.0:
			_current[load] = 0.0
		(_lights[load] as OmniLight3D).light_energy = float(_current[load])
	_glow_target = 1.25 if verified else 0.0
	if not verified:
		_glow_current = 0.0
	_finale.light_energy = _glow_current
	_last_verified = verified
	_hazard_mitigated = mitigated
	_last_host_revision = int(board["host_revision"])
	_last_grid_tick = int(grid["tick"])
	_root.set_meta("exp021_hazard_mitigated", mitigated)
	return {"ok": true, "host_revision": _last_host_revision,
		"verified": verified, "hazard_mitigated": mitigated,
		"authority": "READ_ONLY_GRID_VISUAL"}


## Fixed positive slew rate, no oscillation, pulse or repeated flash.
## Loss of host supply always kills illumination immediately in reflect().
func advance(delta: float) -> void:
	if _root == null:
		return
	var dt: float = clampf(delta, 0.0, 0.25)
	var rate: float = 0.70 if _reduce_flashes else 1.50
	for load: String in LOADS:
		_current[load] = move_toward(float(_current[load]),
			float(_target[load]), rate * dt)
		(_lights[load] as OmniLight3D).light_energy = float(_current[load])
	_glow_current = move_toward(_glow_current, _glow_target, rate * dt)
	_finale.light_energy = _glow_current


func light_energy(load: String) -> float:
	return float(_current.get(load, 0.0))


func is_restored() -> bool:
	return _last_verified


func is_mitigated() -> bool:
	return _hazard_mitigated


func configured_ui_scale() -> int:
	return _ui_scale


func camera_offset_from_effects() -> Vector3:
	# No camera movement by design, irrespective of preference.
	return Vector3.ZERO


func reduced_flashes_enabled() -> bool:
	return _reduce_flashes


func reduces_camera_motion() -> bool:
	return _reduce_camera_motion
