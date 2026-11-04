extends RefCounted
## V01 world presentation from host-authoritative state. Never changes gameplay causes.
## Window panes are procedural Godot meshes attached to the authored F05 kit markers.
## Restoration switches them from cool unpowered glass to warm light; the drained
## pump basement hides its water visual only after the host latches its pump objective.

const TabletPresenter := preload("res://scripts/ui/tablet_presenter.gd")
const CONFIG_PATH: String = "res://content/offline_solo.json"
const SERVICES: Array[String] = ["APT_W", "MARKET", "PUB", "APT_E", "WORKSHOP"]
const PUMP_LATCH: String = "LATCH_PUMP_DRAIN"

var _world: Node3D
var _panes: Dictionary = {}
var _lights: Dictionary = {}
var _materials: Dictionary = {}
var _last_status: Dictionary = {}
var _water: Node3D


func setup(world: Node3D) -> void:
	_world = world
	_panes.clear()
	_lights.clear()
	_last_status.clear()
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	var d: Dictionary = config["restoration"]
	_materials = {
		"dark": _material(Color(str(d["dark_glass_color"])), false),
		"grid": _material(Color(str(d["grid_glass_color"])), true),
		"temporary": _material(Color(str(d["temporary_glass_color"])), true)
	}
	var glass: QuadMesh = QuadMesh.new()
	glass.size = Vector2(float(d["pane_width_cm"]), float(d["pane_height_cm"])) / 100.0
	for service: String in SERVICES:
		var building: Node3D = world.get_node_or_null(NodePath("Buildings/" + service)) as Node3D
		if building == null:
			continue
		var panes: Array[MeshInstance3D] = []
		var markers: Array[Node] = building.find_children("WindowLight", "Marker3D", true, false)
		for node: Node in markers:
			var marker: Marker3D = node as Marker3D
			var pane: MeshInstance3D = MeshInstance3D.new()
			pane.name = "PowerGlass"
			pane.mesh = glass
			pane.material_override = _materials["dark"]
			pane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			marker.add_child(pane)
			panes.append(pane)
		_panes[service] = panes
		if markers.is_empty():
			continue
		var bulb: OmniLight3D = OmniLight3D.new()
		bulb.name = "ServiceGlow"
		bulb.light_color = Color(str(d["grid_glass_color"]))
		bulb.omni_range = float(d["light_range_cm"]) / 100.0
		bulb.light_energy = float(d["light_energy_percent"]) / 100.0
		bulb.shadow_enabled = false
		building.add_child(bulb)
		bulb.global_position = (markers[0] as Marker3D).global_position
		bulb.visible = false
		_lights[service] = bulb
	_water = world.get_node_or_null("Props/FLOOD_WATER") as Node3D


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
		for pane: MeshInstance3D in _panes.get(service, []):
			pane.material_override = _materials[next]
		if _lights.has(service):
			var light: OmniLight3D = _lights[service]
			light.visible = next != "dark"
			light.light_color = Color(str(
				(JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH)) as Dictionary)["restoration"][
					"temporary_glass_color" if next == "temporary" else "grid_glass_color"]))
	if _water != null:
		_water.visible = not drained


func window_count(service: String) -> int:
	return (_panes.get(service, []) as Array).size()


func state_of(service: String) -> String:
	return str(_last_status.get(service, ""))


func flood_visible() -> bool:
	return _water != null and _water.visible


static func _material(color: Color, powered: bool) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = color
	if powered:
		material.emission_enabled = true
		material.emission = color
	return material
