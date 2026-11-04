extends RefCounted
## Presentation-only restoration: authoritative power state selects the target.
## Reduced flashes uses a longer monotone fade, never brightness pulses.

const TabletPresenter := preload("res://scripts/ui/tablet_presenter.gd")
const CONFIG_PATH: String = "res://content/offline_solo.json"
const SERVICES: Array[String] = ["APT_W", "MARKET", "PUB", "APT_E", "WORKSHOP"]

var _world: Node3D
var _panes: Dictionary = {}
var _lights: Dictionary = {}
var _materials: Dictionary = {}
var _last_status: Dictionary = {}
var _colors: Dictionary = {}
var _energies: Dictionary = {}
var _fades: Dictionary = {}
var _water: Node3D
var _dark: Color
var _grid: Color
var _temporary: Color
var _max_energy: float = 0.0
var _normal_duration: float = 0.0
var _reduced_duration: float = 0.0
var _reduce_flashes: bool = true


func setup(world: Node3D) -> void:
	_world = world
	_panes.clear()
	_lights.clear()
	_materials.clear()
	_last_status.clear()
	_colors.clear()
	_energies.clear()
	_fades.clear()
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	var d: Dictionary = config["restoration"]
	_dark = Color(str(d["dark_glass_color"]))
	_grid = Color(str(d["grid_glass_color"]))
	_temporary = Color(str(d["temporary_glass_color"]))
	_max_energy = float(d["light_energy_percent"]) / 100.0
	_normal_duration = float(ProjectSettings.get_setting("a04_presentation/normal_transition_ms")) / 1000.0
	_reduced_duration = float(ProjectSettings.get_setting("a04_presentation/reduced_transition_ms")) / 1000.0
	var glass: QuadMesh = QuadMesh.new()
	glass.size = Vector2(float(d["pane_width_cm"]), float(d["pane_height_cm"])) / 100.0
	for service: String in SERVICES:
		var building: Node3D = world.get_node_or_null(NodePath("Buildings/" + service)) as Node3D
		if building == null:
			continue
		var panes: Array[MeshInstance3D] = []
		var markers: Array[Node] = building.find_children("WindowLight", "Marker3D", true, false)
		var material: StandardMaterial3D = _material(_dark)
		_materials[service] = material
		for node: Node in markers:
			var marker: Marker3D = node as Marker3D
			var pane: MeshInstance3D = MeshInstance3D.new()
			pane.name = "PowerGlass"
			pane.mesh = glass
			pane.material_override = material
			pane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			marker.add_child(pane)
			panes.append(pane)
		_panes[service] = panes
		_colors[service] = _dark
		_energies[service] = 0.0
		if markers.is_empty():
			continue
		var bulb: OmniLight3D = OmniLight3D.new()
		bulb.name = "ServiceGlow"
		bulb.light_color = _grid
		bulb.omni_range = float(d["light_range_cm"]) / 100.0
		bulb.light_energy = 0.0
		bulb.shadow_enabled = false
		building.add_child(bulb)
		bulb.global_position = (markers[0] as Marker3D).global_position
		bulb.visible = false
		_lights[service] = bulb
	_water = world.get_node_or_null("Props/FLOOD_WATER") as Node3D


## Rebase ongoing transitions at the current rendered intensity on a settings
## change. This preserves continuity even if a power state changes mid-fade.
func set_reduce_flashes(enabled: bool) -> void:
	if _reduce_flashes == enabled:
		return
	_reduce_flashes = enabled
	for service: String in _fades.keys():
		var previous: Dictionary = _fades[service]
		_fades[service] = _fade(service, previous["target_color"], float(previous["target_energy"]))


func reduce_flashes_enabled() -> bool:
	return _reduce_flashes


func apply(state: Dictionary, drained: bool) -> void:
	if _world == null:
		return
	var grid: Dictionary = state["grid"]
	var nodes: Dictionary = grid["nodes"]
	var edges: Dictionary = grid["edges"]
	for service: String in SERVICES:
		if not nodes.has(service):
			continue
		var source: String = TabletPresenter.root_source(service, nodes, edges)
		var next: String = "dark" if source == "" else ("grid" if source == "GRID" else "temporary")
		if _last_status.get(service, "") == next:
			continue
		_last_status[service] = next
		var color: Color = _dark
		if next == "grid":
			color = _grid
		elif next == "temporary":
			color = _temporary
		var energy: float = 0.0 if next == "dark" else _max_energy
		_fades[service] = _fade(service, color, energy)
	if _water != null:
		_water.visible = not drained


## Cosmetic frame updates never modify host state, mission ticks or saves.
func advance(delta: float) -> void:
	for service: String in _fades.keys():
		var f: Dictionary = _fades[service]
		f["elapsed"] = float(f["elapsed"]) + maxf(0.0, delta)
		var duration: float = _reduced_duration if _reduce_flashes else _normal_duration
		var t: float = clampf(float(f["elapsed"]) / maxf(duration, 0.001), 0.0, 1.0)
		var eased: float = t * t * (3.0 - 2.0 * t)
		var start_color: Color = f["start_color"]
		var end_color: Color = f["target_color"]
		var energy: float = lerpf(float(f["start_energy"]), float(f["target_energy"]), eased)
		_render(service, start_color.lerp(end_color, eased), energy)
		if t >= 1.0:
			_fades.erase(service)
		else:
			_fades[service] = f


func is_transitioning(service: String) -> bool:
	return _fades.has(service)


func light_energy_of(service: String) -> float:
	return float(_energies.get(service, 0.0))


func window_count(service: String) -> int:
	return (_panes.get(service, []) as Array).size()


func state_of(service: String) -> String:
	return str(_last_status.get(service, ""))


func flood_visible() -> bool:
	return _water != null and _water.visible


func _fade(service: String, target_color: Color, target_energy: float) -> Dictionary:
	return {"start_color": _colors.get(service, _dark), "target_color": target_color,
		"start_energy": float(_energies.get(service, 0.0)), "target_energy": target_energy,
		"elapsed": 0.0}


func _render(service: String, color: Color, energy: float) -> void:
	_colors[service] = color
	_energies[service] = energy
	var material: StandardMaterial3D = _materials.get(service) as StandardMaterial3D
	if material != null:
		material.albedo_color = color
		material.emission_enabled = energy > 0.001
		material.emission = color
		material.emission_energy_multiplier = energy / maxf(_max_energy, 0.001)
	if _lights.has(service):
		var bulb: OmniLight3D = _lights[service]
		bulb.visible = energy > 0.001
		bulb.light_color = color
		bulb.light_energy = energy


static func _material(color: Color) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = color
	return material
