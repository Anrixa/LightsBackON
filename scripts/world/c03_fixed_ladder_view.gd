extends Node3D
## C03-P01: authored fixed-ladder preview geometry and reversible, collision-gated
## local movement. The host owns permission; this view never grants ladder access.
## No physical rope/ladder simulation or network peer position is invented.

const UiText := preload("res://scripts/ui/ui_text.gd")

var _arrivals: Dictionary = {}  # authored ladder endpoint id -> destination in meters
var _beacon: MeshInstance3D
var _beacon_off: Material
var _beacon_on: Material


static func _point(cm: Array) -> Vector3:
	return Vector3(float(cm[0]), float(cm[1]), float(cm[2])) / 100.0


static func _paint(color: Color, luminous: bool = false) -> StandardMaterial3D:
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = 0.45
	m.roughness = 0.32
	m.emission_enabled = luminous
	if luminous:
		m.emission = color
		m.emission_energy_multiplier = 1.1
	return m


func _box(parent: Node3D, name: String, pos: Vector3, size_m: Vector3,
		material: Material) -> MeshInstance3D:
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = size_m
	var visual: MeshInstance3D = MeshInstance3D.new()
	visual.name = name
	visual.mesh = mesh
	visual.material_override = material
	visual.position = pos
	parent.add_child(visual)
	return visual


func _label(parent: Node3D, name: String, message: String, pos: Vector3) -> void:
	var label: Label3D = Label3D.new()
	label.name = name
	label.text = message
	label.font_size = 42
	label.pixel_size = 0.004
	label.modulate = Color("#E6F0F2")
	label.position = pos
	label.rotation.y = PI
	parent.add_child(label)


## Markers exist only in the C03 preview scene. Other Alder contract marker
## coordinates and the authored world scene stay byte-identical.
func setup(world: Node3D, definition: Dictionary) -> bool:
	if definition.get("contract_id") != "C03":
		return false
	var markers: Node3D = world.get_node_or_null("Markers") as Node3D
	if markers == null:
		return false
	_arrivals.clear()
	for rec: Dictionary in definition.get("markers", []):
		var id: String = str(rec.get("id", ""))
		var point: Array = rec.get("pos_cm", [])
		if id == "" or point.size() != 3 or markers.has_node(id):
			return false
		var marker: Marker3D = Marker3D.new()
		marker.name = id
		marker.position = _point(point)
		markers.add_child(marker)
	for rec: Dictionary in definition.get("transitions", []):
		var id: String = str(rec.get("id", ""))
		var coords: Array = rec.get("arrival_cm", [])
		if id == "" or coords.size() != 3 or not markers.has_node(id) or _arrivals.has(id):
			return false
		_arrivals[id] = _point(coords)
	_build_ladder(definition.get("ladder_geometry", {}))
	_build_roof_props(definition)
	return true


func _build_ladder(definition: Dictionary) -> void:
	var base: Vector3 = _point(definition.get("base_cm", [2100, 0, 4165]))
	var height_m: float = float(definition.get("height_cm", 800)) / 100.0
	var width_m: float = float(definition.get("width_cm", 90)) / 100.0
	var depth_m: float = float(definition.get("rail_depth_cm", 18)) / 100.0
	var rungs: int = maxi(2, int(definition.get("rungs", 24)))
	var steel: StandardMaterial3D = _paint(Color("#9FAFB8"))
	var handrail: StandardMaterial3D = _paint(Color("#D4AB54"))
	var root: Node3D = Node3D.new()
	root.name = "C03FixedLadder"
	root.position = base
	add_child(root)
	for side: int in [-1, 1]:
		_box(root, "Rail_%s" % str(side), Vector3(float(side) * width_m * 0.5, height_m * 0.5, 0.0),
			Vector3(0.10, height_m, depth_m), steel)
	for i: int in rungs:
		var y: float = float(i + 1) * height_m / float(rungs + 1)
		_box(root, "Rung_%02d" % i, Vector3(0.0, y, -depth_m * 0.3),
			Vector3(width_m, 0.07, 0.10), handrail)
	_label(root, "LadderPlate", UiText.t("offline.object.roof_ladder"),
		Vector3(0.0, 1.95, -0.17))


func _build_roof_props(definition: Dictionary) -> void:
	var metal: StandardMaterial3D = _paint(Color("#6A899B"))
	var trim: StandardMaterial3D = _paint(Color("#D7B66C"))
	var panel: Vector3 = _point(definition.get("roof_panel_cm", [2210, 870, 4650]))
	_box(self, "RoofJunctionPanel", panel, Vector3(1.15, 1.05, 0.20), metal)
	_box(self, "RoofJunctionTrim", panel + Vector3(0.0, 0.0, -0.125),
		Vector3(1.03, 0.04, 0.05), trim)
	_label(self, "RoofPanelLabel", UiText.t("node.c03.roof"),
		panel + Vector3(0.0, 0.25, -0.16))
	var beacon: Vector3 = _point(definition.get("roof_beacon_cm", [2140, 850, 4540]))
	_box(self, "BeaconBase", beacon, Vector3(0.65, 0.85, 0.65), metal)
	_beacon_off = _paint(Color("#40596C"))
	_beacon_on = _paint(Color("#FFD180"), true)
	_beacon = _box(self, "RoofBeacon", beacon + Vector3(0.0, 0.66, 0.0),
		Vector3(0.43, 0.43, 0.43), _beacon_off)
	_label(self, "RoofBeaconLabel", UiText.t("node.c03.beacon"),
		beacon + Vector3(0.0, 1.10, -0.45))


func destination(endpoint: String) -> Vector3:
	return _arrivals.get(endpoint, Vector3.INF)


## Collision clearance is checked before sending the host intent and again
## before moving. The test does not trust a client's claimed player position.
func can_transfer(player: CharacterBody3D, endpoint: String) -> bool:
	var arrival: Vector3 = destination(endpoint)
	if arrival == Vector3.INF or player == null or not player.is_inside_tree():
		return false
	var collision: CollisionShape3D = player.get_node_or_null("BodyCollision") as CollisionShape3D
	if collision == null or collision.shape == null:
		return false
	var query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	query.shape = collision.shape
	query.transform = Transform3D(player.global_transform.basis, arrival)
	query.collision_mask = player.collision_mask
	query.exclude = [player.get_rid()] as Array[RID]
	query.margin = 0.01
	var space: PhysicsDirectSpaceState3D = player.get_world_3d().direct_space_state
	return space.intersect_shape(query, 1).is_empty()


## Called only from a successful host use_ladder reply, never the key press.
func transfer(player: CharacterBody3D, endpoint: String) -> bool:
	if not can_transfer(player, endpoint):
		return false
	player.global_position = destination(endpoint)
	player.velocity = Vector3.ZERO
	player.reset_physics_interpolation()
	return true


## The beacon never guesses restoration: an actual host grid snapshot supplies
## the flag. Dark preview uses the unpowered material.
func apply_host(snapshot: Dictionary) -> void:
	if _beacon == null:
		return
	var grid: Dictionary = snapshot.get("grid", {})
	var nodes: Dictionary = grid.get("nodes", {})
	var powered: bool = nodes.has("ROOF_BEACON") and bool(nodes["ROOF_BEACON"].get("supplied", false))
	_beacon.material_override = _beacon_on if powered else _beacon_off
