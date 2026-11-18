extends Node3D
## CT-L1/C04 P01–P05: non-colliding, original preview-only visualization of the
## dedicated 4-PU sign feeder. The real SessionHost remains the sole authority
## for switches, repairs, source selection, protection and optional rewards.
## Nothing here writes a campaign checkpoint or infers power from cable art.

const UiText := preload("res://scripts/ui/ui_text.gd")
const APPROACHES_PATH: String = "res://content/world/c04_preview_approaches.json"

## Each physical C04 switch must represent its exact original-blueprint
## target and operation. Matching IDs alone must not accept a remapped switch.
const EXPECTED_SWITCHES: Dictionary = {
	"SW_SIGN": {"target": "SIGN", "field": "enabled"},
	"SW_EAST_SIGN": {"target": "EAST_SIGN", "field": "isolated"},
	"SW_JW_BREAKER": {"target": "JW", "field": "tripped"},
	"SW_JE_BREAKER": {"target": "JE", "field": "tripped"},
	"SW_SPUR_BREAKER": {"target": "SPUR", "field": "tripped"}
}

## P04: source-pinned worksite coordinates allow a small art tolerance but
## reject displaced, sunken or overlapping targets before creating any scene
## nodes. This is a geometry preflight, not a certified traversable route.
const EXPECTED_INHERITED_SITES: Dictionary = {
	"PANEL_JW": Vector3(29.6, 1.4, 24.3),
	"SW_JW_BREAKER": Vector3(30.4, 1.4, 24.3),
	"PANEL_JE": Vector3(72.6, 1.4, 24.3),
	"SW_JE_BREAKER": Vector3(73.4, 1.4, 24.3),
	"SW_SIGN": Vector3(64.6, 1.4, 41.9)
}
const EXPECTED_OVERLAY_SITES: Dictionary = {
	"PANEL_SPUR": Vector3(60.2, 1.4, 39.5),
	"SW_SPUR_BREAKER": Vector3(61.0, 1.4, 39.5),
	"SW_EAST_SIGN": Vector3(66.9, 1.4, 40.5)
}
const MAX_SITE_DRIFT_M: float = 0.25
const MIN_SITE_SEPARATION_M: float = 0.65
const WORKSITE_ORDER: Array[String] = [
	"PANEL_JW", "SW_JW_BREAKER", "PANEL_JE", "SW_JE_BREAKER",
	"PANEL_SPUR", "SW_SPUR_BREAKER", "SW_EAST_SIGN", "SW_SIGN"
]

## These coordinates are staging hints grounded in the P02/P04 approach probes.
## They are not a route graph, traversal guarantee or new host interaction zone.
const EXPECTED_APPROACHES: Dictionary = {
	"PANEL_JE": {"point": Vector3(72.6, 0.06, 26.1), "key": "offline.c04.guide.east"},
	"PANEL_JW": {"point": Vector3(29.6, 0.06, 25.9), "key": "offline.c04.guide.west"},
	"PANEL_SPUR": {"point": Vector3(60.2, 0.06, 37.9), "key": "offline.c04.guide.spur"},
	"SW_SIGN": {"point": Vector3(64.6, 0.06, 40.2), "key": "offline.c04.guide.sign"},
	"SW_EAST_SIGN": {"point": Vector3(66.9, 0.06, 38.8), "key": "offline.c04.guide.isolator"},
	"ZONE_VAN": {"point": Vector3(8.0, 0.06, 14.4), "key": "offline.c04.guide.van"}
}
const MAX_APPROACH_DRIFT_M: float = 0.25
const MAX_APPROACH_TARGET_DISTANCE_M: float = 2.15
const MIN_APPROACH_TARGET_DISTANCE_M: float = 0.60

var _controls: Dictionary = {}
var _indicators: Dictionary = {}
var _sign_label: Label3D
var _bonus_label: Label3D
var _spur_label: Label3D


static func _point(cm: Array) -> Vector3:
	return Vector3(float(cm[0]), float(cm[1]), float(cm[2])) / 100.0


## Godot JSON.parse_string reads JSON numbers as floats even when serialized
## without a decimal point. Preserve strict integral-centimeter placement
## without incorrectly rejecting valid authored data.
static func _valid_cm(coords: Array) -> bool:
	if coords.size() != 3:
		return false
	for dimension: Variant in coords:
		if not (dimension is int or dimension is float):
			return false
		var amount: float = float(dimension)
		if is_nan(amount) or is_inf(amount) or absf(amount) > 20000.0:
			return false
		if amount != float(int(amount)):
			return false
	return true


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
func setup(world: Node3D, overlay: Dictionary, controls: Dictionary,
		approaches_override: Variant = null) -> bool:
	if overlay.get("contract_id") != "C04" or controls.get("contract_id") != "C04":
		return false
	var markers: Node3D = world.get_node_or_null("Markers") as Node3D
	if markers == null:
		return false
	var known: Dictionary = {}
	for node: Node in markers.get_children():
		known[str(node.name)] = true
	# Reject forged/mistyped stations before adding any nodes to the scene.
	# The original C04 overlay has one meter panel and two switch plates.
	if not (overlay.get("markers") is Array) or not (controls.get("switches") is Array):
		return false
	var expected_kinds: Dictionary = {
		"PANEL_SPUR": "panel",
		"SW_SPUR_BREAKER": "switch",
		"SW_EAST_SIGN": "switch"
	}
	# The inherited Alder markers are real, scene-bound work targets. Do not
	# build attractive but unreachable controls over a moved or forged anchor.
	for id: String in EXPECTED_INHERITED_SITES:
		var inherited: Marker3D = markers.get_node_or_null(id) as Marker3D
		var kind: String = "panel" if id.begins_with("PANEL_") else "switch"
		if inherited == null or str(inherited.get_meta("kind", "")) != kind:
			return false
		if inherited.position.distance_to(EXPECTED_INHERITED_SITES[id]) > 0.02:
			return false
	var extra: Dictionary = {}
	var records: Array = overlay["markers"]
	if records.size() != expected_kinds.size():
		return false
	for candidate: Variant in records:
		if not (candidate is Dictionary):
			return false
		var rec: Dictionary = candidate
		var id: String = str(rec.get("id", ""))
		if not expected_kinds.has(id) or known.has(id) or extra.has(id):
			return false
		if rec.get("kind") != expected_kinds[id] or not (rec.get("pos_cm") is Array):
			return false
		var coords: Array = rec["pos_cm"]
		if not _valid_cm(coords):
			return false
		if _point(coords).distance_to(EXPECTED_OVERLAY_SITES[id]) > MAX_SITE_DRIFT_M:
			return false
		extra[id] = {"kind": str(rec["kind"]), "coords": coords}
	# Prevent overlapping interaction plates in the intended curb-side work
	# positions. This check cannot substitute for a walked/capsule route test.
	var positions: Array[Vector3] = []
	for id: String in EXPECTED_INHERITED_SITES:
		positions.append(EXPECTED_INHERITED_SITES[id])
	for id: String in extra:
		var position: Vector3 = _point(extra[id]["coords"])
		for previous: Vector3 in positions:
			if position.distance_to(previous) < MIN_SITE_SEPARATION_M:
				return false
		positions.append(position)
	var live: Dictionary = {}
	for candidate: Variant in controls["switches"]:
		if not (candidate is Dictionary):
			return false
		var control: Dictionary = candidate
		var id: String = str(control.get("id", ""))
		var target: String = str(control.get("target", ""))
		var field: String = str(control.get("field", ""))
		if not id.begins_with("SW_") or target.is_empty() or live.has(id):
			return false
		var required: Dictionary = EXPECTED_SWITCHES.get(id, {})
		if required.is_empty() or target != required["target"] or field != required["field"]:
			return false
		if not known.has(id) and not extra.has(id):
			return false
		live[id] = {"target": target, "field": field}
	# C04 must expose exactly its five source-authorized switches. An
	# unexpected inherited switch is not allowed to displace a real control.
	if live.size() != EXPECTED_SWITCHES.size():
		return false
	for required_id: String in EXPECTED_SWITCHES:
		if not live.has(required_id):
			return false
	if not (overlay.get("conduit_cm") is Array):
		return false
	var cable: Array = overlay["conduit_cm"]
	if cable.size() < 2 or cable.size() > 12:
		return false
	for item: Variant in cable:
		if not (item is Array):
			return false
		var coords: Array = item
		if not _valid_cm(coords):
			return false
	# P05: preflight the whole guide dataset while the world is still pristine.
	# Caller-supplied malformed data must fail closed, never silently fall back.
	var approach_source: Variant = approaches_override
	if approach_source == null:
		approach_source = JSON.parse_string(FileAccess.get_file_as_string(APPROACHES_PATH))
	var approaches: Dictionary = _validate_approaches(world, markers, extra, approach_source)
	if approaches.size() != EXPECTED_APPROACHES.size():
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
	_build_approach_cues(approaches)
	var sign: Node3D = markers.get_node_or_null("SIGN") as Node3D
	if sign != null:
		_sign_label = _label(self, "C04SignSupply", "%s\nUNKNOWN" % UiText.t("node.c01.sign"),
			sign.position + Vector3(0.0, 0.3, -0.25))
		_bonus_label = _label(self, "C04SignBonus", "%s\nUNKNOWN" % UiText.t("offline.c04.sign_bonus_label"),
			sign.position + Vector3(0.0, -0.2, -0.25))
	return true


## P04: paint plates for all C04-authorized stations, not only the three
## added in the overlay. Inherited C01 switch markers still use the unchanged
## host selector/range callback; a visual plate never grants an interaction.
func _build_stations(markers: Node3D, _added: Dictionary) -> void:
	var group: Node3D = Node3D.new()
	group.name = "C04ControlStations"
	add_child(group)
	var casing: StandardMaterial3D = _material()
	for id: String in WORKSITE_ORDER:
		var marker: Marker3D = markers.get_node(id) as Marker3D
		var station: Node3D = Node3D.new()
		station.name = id
		station.position = marker.position
		group.add_child(station)
		_box(station, "Plate", Vector3(0.57, 0.35, 0.08),
			Vector3(0.0, 0.10, 0.02), casing)
		var description: String = id.trim_prefix("SW_").trim_prefix("PANEL_").replace("_", " ")
		if id == "PANEL_SPUR":
			description = UiText.t("node.c04.spur")
		elif id.begins_with("PANEL_"):
			description += " WORKSITE"
		var caption: String = description if id.begins_with("PANEL_") and id != "PANEL_SPUR" else "%s\nUNKNOWN" % description
		var indicator: Label3D = _label(station, "State", caption,
			Vector3(0.0, 0.17, -0.06))
		if id == "PANEL_SPUR":
			_spur_label = indicator
		elif _controls.has(id):
			_indicators[id] = indicator


## An approach cue may reference only a real authored C04 marker or the van
## extraction zone. It never creates a host target or opens a shortcut.
func _validate_approaches(world: Node3D, markers: Node3D,
		extra: Dictionary, raw: Variant) -> Dictionary:
	if not (raw is Dictionary):
		return {}
	var data: Dictionary = raw
	if data.get("contract_id") != "C04" or not (data.get("approaches") is Array):
		return {}
	var entries: Array = data["approaches"]
	if entries.size() != EXPECTED_APPROACHES.size():
		return {}
	var van: Area3D = world.get_node_or_null("Zones/ZONE_VAN") as Area3D
	if van == null:
		return {}
	var accepted: Dictionary = {}
	for item: Variant in entries:
		if not (item is Dictionary):
			return {}
		var rec: Dictionary = item
		if not (rec.get("id") is String) or not (rec.get("label_key") is String):
			return {}
		var id: String = rec["id"]
		if not EXPECTED_APPROACHES.has(id) or accepted.has(id):
			return {}
		var expected: Dictionary = EXPECTED_APPROACHES[id]
		if rec["label_key"] != expected["key"] or not UiText.has(rec["label_key"]):
			return {}
		if not (rec.get("pos_cm") is Array):
			return {}
		var cm: Array = rec["pos_cm"]
		if not _valid_cm(cm):
			return {}
		var point: Vector3 = _point(cm)
		if point.distance_to(expected["point"]) > MAX_APPROACH_DRIFT_M:
			return {}
		if point.y < 0.02 or point.y > 0.25:
			return {}
		if id != "ZONE_VAN":
			var target: Vector3
			if extra.has(id):
				target = _point(extra[id]["coords"])
			else:
				var marker: Marker3D = markers.get_node_or_null(id) as Marker3D
				if marker == null:
					return {}
				target = marker.position
			var horizontal: float = Vector2(point.x - target.x, point.z - target.z).length()
			if horizontal < MIN_APPROACH_TARGET_DISTANCE_M or horizontal > MAX_APPROACH_TARGET_DISTANCE_M:
				return {}
		accepted[id] = {"position": point, "label_key": str(rec["label_key"])}
	return accepted


## Neutral ground rings/labels are the only added guidance. No collision, power
## emission, authority, pathfinding, mission mutation or target registration.
func _build_approach_cues(approaches: Dictionary) -> void:
	var root: Node3D = Node3D.new()
	root.name = "C04ApproachCues"
	add_child(root)
	var paint: StandardMaterial3D = StandardMaterial3D.new()
	paint.albedo_color = Color("#D6B66F")
	paint.roughness = 0.95
	for id: String in EXPECTED_APPROACHES:
		var data: Dictionary = approaches[id]
		var cue: Node3D = Node3D.new()
		cue.name = id
		cue.position = data["position"]
		root.add_child(cue)
		var ring: CylinderMesh = CylinderMesh.new()
		ring.top_radius = 0.36
		ring.bottom_radius = 0.36
		ring.height = 0.02
		ring.radial_segments = 20
		var disc: MeshInstance3D = MeshInstance3D.new()
		disc.name = "GroundCue"
		disc.mesh = ring
		disc.material_override = paint
		disc.position = Vector3(0.0, 0.015, 0.0)
		cue.add_child(disc)
		var caption: Label3D = _label(cue, "Caption", UiText.t(data["label_key"]),
			Vector3(0.0, 1.35, 0.0))
		caption.rotation.y = 0.0
		caption.billboard = BaseMaterial3D.BILLBOARD_ENABLED


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
	# Missing or malformed snapshots cannot become fabricated power cues.
	var raw_grid: Variant = snapshot.get("grid")
	if not (raw_grid is Dictionary):
		return null
	var raw_entries: Variant = (raw_grid as Dictionary).get(collection)
	if not (raw_entries is Dictionary):
		return null
	var raw_component: Variant = (raw_entries as Dictionary).get(target)
	if not (raw_component is Dictionary):
		return null
	var component: Dictionary = raw_component
	return component[field] if component.get(field) is bool else null


static func _bonus_status(snapshot: Dictionary) -> String:
	# The bonus is the durable host mission latch, not instantaneous sign
	# illumination or a locally counted 100-tick timer.
	var raw_mission: Variant = snapshot.get("mission")
	if not (raw_mission is Dictionary):
		return "UNKNOWN"
	var raw_latched: Variant = (raw_mission as Dictionary).get("latched")
	if not (raw_latched is Dictionary):
		return "UNKNOWN"
	var latched: Dictionary = raw_latched
	if not latched.has("LATCH_SIGN_SUPPLY"):
		return UiText.t("offline.c04.sign_bonus_pending")
	var value: Variant = latched["LATCH_SIGN_SUPPLY"]
	if not (value is int and int(value) >= 0):
		return "UNKNOWN"
	return UiText.t("offline.c04.sign_bonus_verified")


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
		label.text = "%s\n%s" % [id.trim_prefix("SW_").replace("_", " "),
			_control_status(snapshot, _controls[id])]
	if _spur_label != null:
		var feeder: Variant = _host_bool(snapshot, "edges", "E_GRID_SPUR", "enabled")
		_spur_label.text = "%s\n%s" % [UiText.t("node.c04.spur"),
			"UNKNOWN" if feeder == null else "INSTALLED" if feeder else "NOT INSTALLED"]
	if _sign_label != null:
		var supplied: Variant = _host_bool(snapshot, "nodes", "SIGN", "supplied")
		_sign_label.text = "%s\n%s" % [UiText.t("node.c01.sign"),
			"UNKNOWN" if supplied == null else "SUPPLIED" if supplied else "UNSUPPLIED"]
	if _bonus_label != null:
		_bonus_label.text = "%s\n%s" % [UiText.t("offline.c04.sign_bonus_label"),
			_bonus_status(snapshot)]
