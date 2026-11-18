extends Node3D
## CT-L1/C04 P01: non-colliding, original preview-only visualization of the
## dedicated 4-PU sign feeder. The real SessionHost remains the sole authority
## for switches, repairs, source selection, protection and optional rewards.
## Nothing here writes a campaign checkpoint or infers power from cable art.

const UiText := preload("res://scripts/ui/ui_text.gd")

var _controls: Dictionary = {}
var _indicators: Dictionary = {}
var _sign_label: Label3D
var _spur_label: Label3D


static func _point(cm: Array) -> Vector3:
	return Vector3(float(cm[0]), float(cm[1]), float(cm[2])) / 100.0


static func _material() -> StandardMaterial3D:
	var result: StandardMaterial3D = StandardMaterial3D.new()
	result.albedo_color = Color("#697E8B")
	result.roughness = 0.65
	result.metallic = 0.35
	return result


func _box(parent: Node3D, name: String, size_m: Vector3, offset: Vector3, material: Material) -> void:
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = size_m
	var model: MeshInstance3D = MeshInstance3D.new()
	model.name = name
	model.mesh = mesh
	model.material_override = material
	model.position = offset
	parent.add_child(model)


func _label(parent: Node3D, name: String, value: String, offset: Vector3) -> Label3D:
	var label: Label3D = Label3D.new()
	label.name = name
	label.text = value
	label.font_size = 38
	label.pixel_size = 0.004
	label.modulate = Color("#E6F0F2")
	label.position = offset
	label.rotation.y = PI
	parent.add_child(label)
	return label


## Validate the complete overlay before adding any new marker or visual node.
## C01 already owns SW_SIGN, SW_JW_BREAKER and SW_JE_BREAKER.
func setup(world: Node3D, overlay: Dictionary, controls: Dictionary) -> bool:
	if overlay.get("contract_id") != "C04" or controls.get("contract_id") != "C04":
		return false
	var markers: Node3D = world.get_node_or_null("Markers") as Node3D
	if markers == null:
		return false
	var known: Dictionary = {}
	for node: Node in markers.get_children():
		known[str(node.name)] = true
	var extra: Dictionary = {}
	var records: Array = overlay.get("markers", [])
	for rec: Dictionary in records:
		var id: String = str(rec.get("id", ""))
		var coords: Array = rec.get("pos_cm", [])
		var kind: String = str(rec.get("kind", ""))
		if id.is_empty() or known.has(id) or extra.has(id) or coords.size() != 3:
			return false
		if not ["panel", "switch"].has(kind):
			return false
		extra[id] = {"kind": kind, "coords": coords}
	for required: String in ["PANEL_SPUR", "SW_SPUR_BREAKER", "SW_EAST_SIGN"]:
		if not extra.has(required):
			return false
	var live: Dictionary = {}
	for control: Dictionary in controls.get("switches", []):
		var id: String = str(control.get("id", ""))
		var target: String = str(control.get("target", ""))
		var field: String = str(control.get("field", ""))
		if not id.begins_with("SW_") or target.is_empty() or live.has(id):
			return false
		if not ["enabled", "isolated", "tripped"].has(field):
			return false
		if not known.has(id) and not extra.has(id):
			return false
		live[id] = {"target": target, "field": field}
	if live.size() != 5:
		return false
	var cable: Array = overlay.get("conduit_cm", [])
	if cable.size() < 2 or cable.size() > 12:
		return false
	for coords: Array in cable:
		if coords.size() != 3:
			return false
		for dimension: Variant in coords:
			if not (dimension is int) or absi(int(dimension)) > 20000:
				return false
	_controls = live
	for id: String in extra:
		var record: Dictionary = extra[id]
		var marker: Marker3D = Marker3D.new()
		marker.name = id
		marker.position = _point(record["coords"])
		marker.set_meta("kind", str(record["kind"]))
		markers.add_child(marker)
	_build_stations(markers, extra)
	_build_conduit(cable)
	var sign: Node3D = markers.get_node_or_null("SIGN") as Node3D
	if sign != null:
		_sign_label = _label(self, "C04SignSupply", "%s\\nUNKNOWN" % UiText.t("node.c01.sign"),
			sign.position + Vector3(0.0, 0.3, -0.25))
	return true


func _build_stations(markers: Node3D, added: Dictionary) -> void:
	var group: Node3D = Node3D.new()
	group.name = "C04ControlStations"
	add_child(group)
	var casing: StandardMaterial3D = _material()
	for id: String in added:
		var marker: Node3D = markers.get_node(id) as Node3D
		var station: Node3D = Node3D.new()
		station.name = id
		station.position = marker.position
		group.add_child(station)
		_box(station, "Plate", Vector3(0.57, 0.35, 0.08),
			Vector3(0.0, 0.10, 0.02), casing)
		var description: String = UiText.t("node.c04.spur") if id == "PANEL_SPUR" else id.trim_prefix("SW_").replace("_", " ")
		var indicator: Label3D = _label(station, "State", "%s\\nUNKNOWN" % description,
			Vector3(0.0, 0.17, -0.06))
		if id == "PANEL_SPUR":
			_spur_label = indicator
		else:
			_indicators[id] = indicator


func _build_conduit(path: Array) -> void:
	var group: Node3D = Node3D.new()
	group.name = "C04DedicatedConduit"
	add_child(group)
	var casing: Material = _material()
	for i: int in range(path.size() - 1):
		var start: Vector3 = _point(path[i])
		var finish: Vector3 = _point(path[i + 1])
		var delta: Vector3 = finish - start
		if delta.length_squared() <= 0.0001:
			continue
		var cylinder: CylinderMesh = CylinderMesh.new()
		cylinder.top_radius = 0.035
		cylinder.bottom_radius = 0.035
		cylinder.height = delta.length()
		cylinder.radial_segments = 6
		var segment: MeshInstance3D = MeshInstance3D.new()
		segment.name = "Segment_%02d" % i
		segment.mesh = cylinder
		segment.material_override = casing
		segment.position = (start + finish) * 0.5
		segment.quaternion = Quaternion(Vector3.UP, delta.normalized())
		group.add_child(segment)


static func _host_bool(snapshot: Dictionary, collection: String, target: String, field: String) -> Variant:
	var grid: Dictionary = snapshot.get("grid", {})
	var entries: Dictionary = grid.get(collection, {})
	var component: Dictionary = entries.get(target, {})
	if not component.has(field) or not (component[field] is bool):
		return null
	return component[field]


static func _control_status(snapshot: Dictionary, source: Dictionary) -> String:
	var target: String = str(source["target"])
	var field: String = str(source["field"])
	var value: Variant = _host_bool(snapshot, "nodes", target, field)
	if value == null:
		value = _host_bool(snapshot, "edges", target, field)
	if value == null:
		return "UNKNOWN"
	match field:
		"enabled":
			return "ENABLED" if value else "DISABLED"
		"isolated":
			return "ISOLATED" if value else "CONNECTED"
		"tripped":
			return "TRIPPED" if value else "RESET"
	return "UNKNOWN"


## State text reports host observation, never infers load supply from the
## neutral conduit mesh or an unapproved local interaction.
func apply_host(snapshot: Dictionary) -> void:
	for id: String in _indicators:
		var label: Label3D = _indicators[id] as Label3D
		label.text = "%s\\n%s" % [id.trim_prefix("SW_").replace("_", " "),
			_control_status(snapshot, _controls[id])]
	if _spur_label != null:
		var feeder: Variant = _host_bool(snapshot, "edges", "E_GRID_SPUR", "enabled")
		_spur_label.text = "%s\\n%s" % [UiText.t("node.c04.spur"),
			"UNKNOWN" if feeder == null else "INSTALLED" if feeder else "NOT INSTALLED"]
	if _sign_label != null:
		var supplied: Variant = _host_bool(snapshot, "nodes", "SIGN", "supplied")
		_sign_label.text = "%s\\n%s" % [UiText.t("node.c01.sign"),
			"UNKNOWN" if supplied == null else "SUPPLIED" if supplied else "UNSUPPLIED"]
