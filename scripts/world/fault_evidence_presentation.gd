extends RefCounted
## DS10: first-person meter, cabinet mechanics and real host-ping markers.
## This is a view of accepted host repair/meter/comms state only. It cannot
## inspect a panel, change a breaker, infer a hidden fault or mutate a save.

const UiText := preload("res://scripts/ui/ui_text.gd")
const DRESSING_PATH: String = "res://content/world/alder_street_dressing.json"
const REPAIR_CABINETS: Dictionary = {
	"R_JW_FUSE": {"prop": "CABINET_JW", "junction": "JW"},
	"R_JE_TRUNK": {"prop": "CABINET_JE", "junction": "JE"},
}
const PING_KEYS: Dictionary = {
	"PING_LOOK": "ping.look",
	"PING_HELP": "ping.need_help",
	"PING_FAULT": "ping.fault_here",
	"PING_EQUIPMENT": "ping.equipment",
}
const OPEN_STATES: Array[String] = ["opened", "component_removed", "replacement_installed"]
const METER_FIELDS: Array[String] = ["source_present", "demand_pu", "capacity_pu", "breaker"]
const METER_LABELS: Dictionary = {
	"source_present": "world.meter.source",
	"demand_pu": "world.meter.demand",
	"capacity_pu": "world.meter.capacity",
	"breaker": "world.meter.breaker",
}

var _cabinets: Dictionary = {}  # repair ID -> visual nodes + authored junction
var _pings: Dictionary = {}  # ephemeral host-issued ping ID -> event; not a save
var _meter_root: Node3D
var _meter_screen: Label3D
var _last_meter_text: String = ""


func setup(world: Node3D, eyes: Camera3D) -> void:
	_cabinets.clear()
	_pings.clear()
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(DRESSING_PATH))
	if not data is Dictionary:
		return
	var style: Dictionary = (data as Dictionary).get("cabinet_style", {})
	for repair_id: String in REPAIR_CABINETS:
		var spec: Dictionary = REPAIR_CABINETS[repair_id]
		var prop_id: String = str(spec["prop"])
		var holder: Node3D = world.get_node_or_null(NodePath("Dressing/Cabinet_" + prop_id)) as Node3D
		var prop: Node3D = world.get_node_or_null(NodePath("Props/" + prop_id)) as Node3D
		if holder == null or prop == null:
			continue
		var original: MeshInstance3D = prop.get_node_or_null("Mesh") as MeshInstance3D
		if original == null or not original.mesh is BoxMesh:
			continue
		_cabinets[repair_id] = _make_cabinet(holder, (original.mesh as BoxMesh).size, style, spec)
	if eyes != null:
		_make_meter(eyes)


func _make_cabinet(holder: Node3D, size: Vector3, style: Dictionary, spec: Dictionary) -> Dictionary:
	# The authored cabinet itself is unchanged. A shallow visible inset overlays
	# its original front; the hinged face conceals it until an accepted open step.
	var front: float = size.z + 0.035
	var interior: Node3D = Node3D.new()
	interior.name = "DS10Interior"
	holder.add_child(interior)
	var dark: Color = Color("#19232B")
	var brass: Color = Color("#D6C88A")
	_box(interior, "Well", Vector3(size.x * 0.5, size.y * 0.53, front),
		Vector3(size.x * 0.80, size.y * 0.58, 0.025), dark)
	var carrier: MeshInstance3D = _box(interior, "FuseCarrier",
		Vector3(size.x * 0.39, size.y * 0.57, front + 0.028),
		Vector3(0.13, 0.30, 0.06), brass)
	var trunk: MeshInstance3D = _box(interior, "TrunkEnd",
		Vector3(size.x * 0.61, size.y * 0.53, front + 0.03),
		Vector3(0.10, 0.32, 0.07), Color("#E3A55F"))
	# A stationary isolator is readable with the door closed. Its angle is
	# sourced from the grid junction, never guessed from the repair stage.
	var isolator: Node3D = Node3D.new()
	isolator.name = "IsolatorHandle"
	isolator.position = Vector3(size.x * 0.78, size.y * 0.32, front + 0.085)
	holder.add_child(isolator)
	_box(isolator, "Handle", Vector3.ZERO, Vector3(0.055, 0.21, 0.055), brass)
	# The hinge rotates a project-made door, with no collision or rigid body.
	var hinge: Node3D = Node3D.new()
	hinge.name = "DS10DoorHinge"
	hinge.position = Vector3(size.x * 0.085, size.y * 0.53, front + 0.075)
	holder.add_child(hinge)
	_box(hinge, "Door", Vector3(size.x * 0.415, 0, 0),
		Vector3(size.x * 0.83, size.y * 0.68, 0.040), Color(str(style.get("body", "#4F6B5C"))))
	_box(hinge, "DoorTrim", Vector3(size.x * 0.79, -size.y * 0.03, 0.031),
		Vector3(0.04, 0.18, 0.036), Color(str(style.get("trim", "#2E3E36"))))
	var condition: Label3D = Label3D.new()
	condition.name = "RepairProgress"
	condition.font_size = 50
	condition.pixel_size = 0.0017
	condition.no_depth_test = true
	condition.modulate = Color("#F3F5EF")
	condition.position = Vector3(size.x * 0.5, size.y + 0.19, front)
	holder.add_child(condition)
	var ping: Label3D = Label3D.new()
	ping.name = "HostPing"
	ping.font_size = 52
	ping.pixel_size = 0.002
	ping.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	ping.no_depth_test = true
	ping.modulate = Color("#FFC86B")
	ping.position = Vector3(size.x * 0.5, size.y + 0.52, front)
	ping.visible = false
	holder.add_child(ping)
	return {"door": hinge, "interior": interior, "carrier": carrier, "trunk": trunk,
		"isolator": isolator, "progress": condition, "ping": ping,
		"junction": str(spec["junction"]), "state": ""}


func _make_meter(eyes: Camera3D) -> void:
	_meter_root = Node3D.new()
	_meter_root.name = "DS10Meter"
	_meter_root.position = Vector3(0.34, -0.22, -0.68)
	eyes.add_child(_meter_root)
	_box(_meter_root, "Housing", Vector3.ZERO, Vector3(0.31, 0.36, 0.11), Color("#253845"))
	_box(_meter_root, "Display", Vector3(0, 0.045, 0.061), Vector3(0.27, 0.19, 0.008), Color("#CCE4C9"))
	_meter_screen = Label3D.new()
	_meter_screen.name = "Reading"
	_meter_screen.position = Vector3(0, 0.045, 0.07)
	_meter_screen.font_size = 25
	_meter_screen.pixel_size = 0.00080
	_meter_screen.modulate = Color("#142B26")
	_meter_screen.no_depth_test = true
	_meter_screen.text = "?"
	_meter_root.add_child(_meter_screen)
	_meter_root.visible = false


## Public only for renderer-independent regression assertions.
func cabinet_open(repair_id: String) -> bool:
	if not _cabinets.has(repair_id):
		return false
	return bool((_cabinets[repair_id] as Dictionary)["interior"].visible)


func meter_text() -> String:
	return _last_meter_text


func ping_visible(repair_id: String) -> bool:
	if not _cabinets.has(repair_id):
		return false
	return bool(((_cabinets[repair_id] as Dictionary)["ping"] as Label3D).visible)


## Called only with SessionHost.authoritative_state() and MeterModel.readings().
## Before a successful inspection the screen says ?, never a simulated zero.
func apply(state: Dictionary, tool: String, target: String, readings: Dictionary) -> void:
	var repair_states: Dictionary = (state.get("repairs", {}) as Dictionary).get("repairs", {})
	var grid_nodes: Dictionary = (state.get("grid", {}) as Dictionary).get("nodes", {})
	for repair_id: String in _cabinets:
		var visual: Dictionary = _cabinets[repair_id]
		var authoritative: Dictionary = repair_states.get(repair_id, {})
		var stage: String = str(authoritative.get("state", "undiagnosed"))
		var opened: bool = OPEN_STATES.has(stage)
		(visual["door"] as Node3D).rotation.y = -1.65 if opened else 0.0
		(visual["interior"] as Node3D).visible = opened
		(visual["carrier"] as MeshInstance3D).visible = opened and stage != "component_removed"
		(visual["trunk"] as MeshInstance3D).visible = opened and repair_id == "R_JE_TRUNK" and stage != "replacement_installed"
		var junction: Dictionary = grid_nodes.get(str(visual["junction"]), {})
		(visual["isolator"] as Node3D).rotation.z = -0.80 if bool(junction.get("isolated", false)) else 0.0
		if str(visual.get("state", "")) != stage:
			(visual["progress"] as Label3D).text = UiText.t("status.repair." + stage)
			visual["state"] = stage
		_render_ping(repair_id, visual)
	if _meter_root != null:
		_meter_root.visible = tool == "meter"
		if _meter_root.visible:
			var next: String = _format_reading(readings if target.begins_with("PANEL_") else {})
			if next != _last_meter_text:
				_last_meter_text = next
				_meter_screen.text = next


## Event-driven visual pings: host allocates IDs, lifetime and replacement.
## Tablet click alone does not make a marker; a refused ping creates nothing.
func on_host_event(event: Dictionary) -> void:
	var kind: String = str(event.get("type", ""))
	if kind == "ping_added":
		var p: Dictionary = event.get("ping", {})
		var id: String = str(p.get("id", ""))
		if id != "" and PING_KEYS.has(str(p.get("type", ""))):
			_pings[id] = p.duplicate(true)
	elif kind == "ping_removed":
		_pings.erase(str(event.get("ping", "")))
	for repair_id: String in _cabinets:
		_render_ping(repair_id, _cabinets[repair_id])


func _render_ping(repair_id: String, visual: Dictionary) -> void:
	var label: Label3D = visual["ping"]
	var chosen: Dictionary = {}
	for id: String in _pings:
		var ping: Dictionary = _pings[id]
		var entity: String = str(ping.get("entity", ""))
		if entity == str(visual["junction"]) or entity == "PANEL_" + str(visual["junction"]):
			chosen = ping
	if chosen.is_empty():
		label.visible = false
		return
	label.text = UiText.t(str(PING_KEYS[chosen["type"]]))
	label.visible = true


static func _format_reading(readings: Dictionary) -> String:
	var panel: Dictionary = readings.get("_panel", {})
	if not panel.has("tick"):
		return UiText.t("world.meter.unmeasured")
	var rows: Array[String] = []
	for field: String in METER_FIELDS:
		var reading: Dictionary = readings.get(field, {})
		if not bool(reading.get("known", false)):
			continue
		var value: Variant = reading.get("value")
		var shown: String = str(value)
		if value is bool:
			shown = UiText.t("meter.value.yes" if value else "meter.value.no")
		elif value is String and UiText.has("meter.value." + str(value)):
			shown = UiText.t("meter.value." + str(value))
		rows.append("%s: %s" % [UiText.t(str(METER_LABELS[field])), shown])
	if rows.is_empty():
		return UiText.t("world.meter.unmeasured")
	return "\n".join(PackedStringArray(rows.slice(0, 3)))


static func _box(parent: Node3D, name: String, center: Vector3, dimensions: Vector3, color: Color) -> MeshInstance3D:
	var node: MeshInstance3D = MeshInstance3D.new()
	node.name = name
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = dimensions
	node.mesh = mesh
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.58
	node.material_override = mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.position = center
	parent.add_child(node)
	return node
