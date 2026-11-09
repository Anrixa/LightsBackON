extends RefCounted
## Presentation-only recovery cues. The host's grid snapshot determines whether
## a service has grid, temporary or no power; animations never decide supply.
## All fades are monotone, including when accessibility changes mid-transition.

const TabletPresenter := preload("res://scripts/ui/tablet_presenter.gd")
const UiText := preload("res://scripts/ui/ui_text.gd")
const TOKENS_PATH: String = "res://content/ui/tokens.json"
# DS08 status plaques: one supply icon per state (ADR-004: icon + text), tinted with the token for that state.
const STATUS_ICONS: Dictionary = {
	"dark": ["res://assets/ui/icons/48/icon_supply_dark.png", "fault"],
	"temporary": ["res://assets/ui/icons/48/icon_supply_temporary.png", "action"],
	"grid": ["res://assets/ui/icons/48/icon_supply_restored.png", "restored"],
}
const CONFIG_PATH: String = "res://content/offline_solo.json"
const SERVICES: Array[String] = ["APT_W", "MARKET", "PUB", "APT_E", "WORKSHOP"]
# Offset successive panes over the first 35% of a fade. A code-side cosmetic
# value, not a puzzle rule or a reason to change the C01 content revision.
const PANE_CASCADE_FRACTION: float = 0.35
const GLASS_ROUGHNESS: float = 0.12

var _world: Node3D
var _panes: Dictionary = {}
var _lights: Dictionary = {}
var _materials: Dictionary = {}
var _pane_energies: Dictionary = {}
var _pane_colors: Dictionary = {}
var _labels: Dictionary = {}
var _icons: Dictionary = {}
var _token_colors: Dictionary = {}
var _base_labels: Dictionary = {}
var _last_status: Dictionary = {}
var _colors: Dictionary = {}
var _energies: Dictionary = {}
var _fades: Dictionary = {}
var _water: Node3D
var _dark: Color
var _grid: Color
var _temporary: Color
var _max_energy: float = 0.0
## Window emission at full supply. 1.0 = the graybox look; the DS08 look raises it so lit glass blooms.
var _glass_emission: float = 1.0
var _normal_duration: float = 0.0
var _reduced_duration: float = 0.0
var _reduce_flashes: bool = true


## `look_windows` (optional) is the DS08 look's "windows" block; it replaces the graybox glass colours and lamp values.
func setup(world: Node3D, look_windows: Dictionary = {}) -> void:
	_world = world
	_icons.clear()
	var tokens: Variant = JSON.parse_string(FileAccess.get_file_as_string(TOKENS_PATH))
	_token_colors = (tokens as Dictionary)["colors"] if tokens is Dictionary else {}
	_panes.clear()
	_lights.clear()
	_materials.clear()
	_pane_energies.clear()
	_pane_colors.clear()
	_labels.clear()
	_base_labels.clear()
	_last_status.clear()
	_colors.clear()
	_energies.clear()
	_fades.clear()
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	var d: Dictionary = (config["restoration"] as Dictionary).duplicate()
	for key: String in look_windows.keys():
		if d.has(key):
			d[key] = look_windows[key]
	_dark = Color(str(d["dark_glass_color"]))
	_grid = Color(str(d["grid_glass_color"]))
	_temporary = Color(str(d["temporary_glass_color"]))
	_max_energy = float(d["light_energy_percent"]) / 100.0
	_glass_emission = float(look_windows.get("glass_emission_percent", 100)) / 100.0
	_normal_duration = float(ProjectSettings.get_setting("a04_presentation/normal_transition_ms")) / 1000.0
	_reduced_duration = float(ProjectSettings.get_setting("a04_presentation/reduced_transition_ms")) / 1000.0
	var glass: QuadMesh = QuadMesh.new()
	glass.size = Vector2(float(d["pane_width_cm"]), float(d["pane_height_cm"])) / 100.0
	for service: String in SERVICES:
		var building: Node3D = world.get_node_or_null(NodePath("Buildings/" + service)) as Node3D
		if building == null:
			continue
		# Preserve the authored name on every sign. The second line describes
		# measured supply, so a color-blind player need not infer it from glow.
		var label: Label3D = building.get_node_or_null("Label") as Label3D
		if label != null:
			_labels[service] = label
			_base_labels[service] = label.text
			var icon: Sprite3D = label.get_node_or_null("StatusIcon") as Sprite3D
			if icon != null:
				_icons[service] = icon
		var panes: Array[MeshInstance3D] = []
		var materials: Array[StandardMaterial3D] = []
		var levels: Array[float] = []
		var colors: Array[Color] = []
		var markers: Array[Node] = building.find_children("WindowLight", "Marker3D", true, false)
		for node: Node in markers:
			var marker: Marker3D = node as Marker3D
			var pane: MeshInstance3D = MeshInstance3D.new()
			pane.name = "PowerGlass"
			pane.mesh = glass
			var material: StandardMaterial3D = _material(_dark)
			if _glass_emission > 1.0:
				# DS08 look: lit glass that also catches the sky and lamps, so emission blooms and dark panes read as glass
				material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
				material.roughness = GLASS_ROUGHNESS
			pane.material_override = material
			pane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			marker.add_child(pane)
			panes.append(pane)
			materials.append(material)
			levels.append(0.0)
			colors.append(_dark)
		_panes[service] = panes
		_materials[service] = materials
		_pane_energies[service] = levels
		_pane_colors[service] = colors
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


## Rebase from CURRENT rendered pane and lamp values, never from a theoretical
## target. Changing Reduce Flashes while the lights turn on or off cannot jump.
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
		# This label switches with the HOST snapshot, not at the end of a fade.
		# Animation is visual evidence, never the source of gameplay truth.
		if _labels.has(service):
			var sign: Label3D = _labels[service]
			var base: String = str(_base_labels[service])
			sign.text = (base + "\n" if base != "" else "") + _power_caption(next)
		if _icons.has(service):
			_set_icon(_icons[service], next)
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
		var progress: float = clampf(float(f["elapsed"]) / maxf(duration, 0.001), 0.0, 1.0)
		var eased: float = _smoothstep(progress)
		_render(service, f, progress, eased)
		if progress >= 1.0:
			_fades.erase(service)
		else:
			_fades[service] = f


func is_transitioning(service: String) -> bool:
	return _fades.has(service)


## Pane and lamp energy at full supply (graybox 0.55 from offline_solo.json, or the DS08 look's value).
func max_energy() -> float:
	return _max_energy


func light_energy_of(service: String) -> float:
	return float(_energies.get(service, 0.0))


func pane_energy_of(service: String, index: int) -> float:
	var levels: Array = _pane_energies.get(service, [])
	return float(levels[index]) if index >= 0 and index < levels.size() else 0.0


func window_count(service: String) -> int:
	return (_panes.get(service, []) as Array).size()


func state_of(service: String) -> String:
	return str(_last_status.get(service, ""))


func state_label_of(service: String) -> String:
	if not _labels.has(service):
		return ""
	return (_labels[service] as Label3D).text


func flood_visible() -> bool:
	return _water != null and _water.visible


func _fade(service: String, target_color: Color, target_energy: float) -> Dictionary:
	return {
		"start_color": _colors.get(service, _dark),
		"target_color": target_color,
		"start_energy": float(_energies.get(service, 0.0)),
		"target_energy": target_energy,
		"start_pane_energy": (_pane_energies.get(service, []) as Array).duplicate(),
		"start_pane_color": (_pane_colors.get(service, []) as Array).duplicate(),
		"elapsed": 0.0,
	}


func _render(service: String, fade: Dictionary, progress: float, eased: float) -> void:
	var start_color: Color = fade["start_color"]
	var target_color: Color = fade["target_color"]
	var color: Color = start_color.lerp(target_color, eased)
	var energy: float = lerpf(float(fade["start_energy"]), float(fade["target_energy"]), eased)
	_colors[service] = color
	_energies[service] = energy
	if _lights.has(service):
		var bulb: OmniLight3D = _lights[service]
		bulb.visible = energy > 0.001
		bulb.light_color = color
		bulb.light_energy = energy

	# Each window has its own authored material. On startup, sign updates,
	# interruption or an accessibility toggle, the previous rendered window
	# intensity is retained as the next starting value.
	var materials: Array = _materials.get(service, [])
	var levels: Array = _pane_energies.get(service, [])
	var colors: Array = _pane_colors.get(service, [])
	var initial_levels: Array = fade["start_pane_energy"]
	var initial_colors: Array = fade["start_pane_color"]
	for i: int in range(materials.size()):
		var delay: float = 0.0
		if materials.size() > 1:
			delay = PANE_CASCADE_FRACTION * float(i) / float(materials.size() - 1)
		var local_progress: float = clampf((progress - delay) / (1.0 - delay), 0.0, 1.0)
		var local_eased: float = _smoothstep(local_progress)
		var pane_energy: float = lerpf(float(initial_levels[i]), float(fade["target_energy"]), local_eased)
		var pane_start_color: Color = initial_colors[i]
		var pane_color: Color = pane_start_color.lerp(target_color, local_eased)
		levels[i] = pane_energy
		colors[i] = pane_color
		var material: StandardMaterial3D = materials[i] as StandardMaterial3D
		material.albedo_color = pane_color
		material.emission_enabled = pane_energy > 0.001
		material.emission = pane_color
		material.emission_energy_multiplier = pane_energy / maxf(_max_energy, 0.001) * _glass_emission


## Caption under the service name. The plaque icon (DS08) carries the same state as a shape; the words are the
## colour-blind-safe channel and never depend on the glow.
static func _power_caption(status: String) -> String:
	match status:
		"grid": return UiText.t("world.supply.grid")
		"temporary": return UiText.t("world.supply.temporary")
	return UiText.t("world.supply.dark")


func _set_icon(icon: Sprite3D, status: String) -> void:
	var entry: Array = STATUS_ICONS.get(status, STATUS_ICONS["dark"])
	icon.texture = load(str(entry[0])) as Texture2D
	icon.modulate = Color(str(_token_colors.get(str(entry[1]), "#F3F5EF")))


## Which supply icon a plaque shows (DS08 tests): "dark" / "temporary" / "grid", or "" without a plaque.
func icon_state_of(service: String) -> String:
	if not _icons.has(service):
		return ""
	var tex: Texture2D = (_icons[service] as Sprite3D).texture
	for status: String in STATUS_ICONS.keys():
		if tex != null and tex.resource_path == str(STATUS_ICONS[status][0]):
			return status
	return ""


static func _smoothstep(t: float) -> float:
	return t * t * (3.0 - 2.0 * t)


static func _material(color: Color) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = color
	return material
