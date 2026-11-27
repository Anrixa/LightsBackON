extends RefCounted
## DS11: visual-only temporary-supply tradeoff for C01.
## Every load, route, breaker and countdown value comes from SessionHost.authoritative_state().
## Neither rendering nor sound advances the host clock, changes a cable or writes a save.
## Curves are authored world points, never loose rigid bodies or physics ropes.

const UiText := preload("res://scripts/ui/ui_text.gd")
const HeroProps := preload("res://scripts/world/hero_prop_builder.gd")
const LocationData := preload("res://scripts/world/location_data.gd")
const CM_PER_M: float = 100.0
const REFUSAL_SECONDS: float = 4.0

var _world: Node3D
var _config: Dictionary = {}
var _anchor_positions: Dictionary = {}
var _root: Node3D
var _generator: Node3D
var _readout: Label3D
var _pad_label: Label3D
var _route_label: Label3D
var _ring: Array[MeshInstance3D] = []
var _cables: Dictionary = {}  # edge ID -> visual-only authored-curve root
var _sound: AudioStreamPlayer3D
var _last_warning: bool = false
var _refusal_seconds: float = 0.0
var _refusal_ids: Array[String] = []
var _last_view: Dictionary = {}


static func load_config() -> Dictionary:
	return LocationData.dressing(LocationData.load_location()).get("temporary_supply", {})


func setup(world: Node3D) -> void:
	_world = world
	_config = load_config()
	_anchor_positions.clear()
	_cables.clear()
	_ring.clear()
	_last_view.clear()
	_last_warning = false
	_refusal_seconds = 0.0
	if _config.is_empty():
		return
	var district: Dictionary = LocationData.layout(LocationData.load_location(LocationData.ALDER_STREET, false))
	for marker: Dictionary in district.get("markers", []):
		if str(marker.get("kind", "")) == "anchor":
			_anchor_positions[str(marker["id"])] = _cm(marker["pos_cm"])
	_root = Node3D.new()
	_root.name = "DS11TemporarySupply"
	world.add_child(_root)
	_make_generator()
	_make_pad()
	_make_cables()


func _make_generator() -> void:
	_generator = Node3D.new()
	_generator.name = "PortableGenerator"
	_root.add_child(_generator)
	var dims: Vector3 = _cm(_config["body_cm"])
	_box(_generator, "Housing", Vector3(0.0, dims.y * 0.54, 0.0), dims,
		Color(str(_config["body_color"])))
	_box(_generator, "Deck", Vector3(0.0, dims.y * 0.86, 0.0),
		Vector3(dims.x * 0.83, dims.y * 0.18, dims.z * 1.03),
		Color(str(_config["housing_color"])))
	for side: float in [-1.0, 1.0]:
		_box(_generator, "Frame", Vector3(side * dims.x * 0.46, dims.y * 0.56, 0.0),
			Vector3(0.045, dims.y * 0.94, dims.z * 1.09), Color("#263C45"))
		_box(_generator, "Foot", Vector3(side * dims.x * 0.35, 0.09, 0.0),
			Vector3(0.13, 0.18, dims.z * 1.08), Color("#1F2B32"))
	_box(_generator, "ControlPlate", Vector3(0.0, dims.y * 0.64, dims.z * 0.51),
		Vector3(dims.x * 0.70, dims.y * 0.50, 0.034), Color("#1F303C"))
	var front: float = dims.z * 0.56
	_readout = _label(_generator, "LoadReadout", UiText.t("world.generator.idle"),
		Vector3(0.0, dims.y * 0.74, front), 38, Color("#F3F5EF"))
	_readout.pixel_size = 0.0015
	# Sixteen radial segments form a physical progress ring, not an animation
	# with an invented timer. Lit segments = exact host overload_ticks / trip_ticks.
	for i: int in int(_config["ring_segments"]):
		var theta: float = float(i) * TAU / float(int(_config["ring_segments"])) - PI * 0.5
		var node: MeshInstance3D = _box(_generator, "TripSegment%d" % i,
			Vector3(cos(theta) * dims.x * 0.25, dims.y * 0.42 + sin(theta) * dims.y * 0.15, front + 0.010),
			Vector3(0.07, 0.028, 0.018), Color("#52616B"))
		node.rotation.z = theta + PI * 0.5
		_ring.append(node)
	_sound = AudioStreamPlayer3D.new()
	_sound.name = "OverloadWarning"
	_sound.unit_size = 1.0
	_sound.max_distance = 14.0
	_sound.stream = _warning_sample()
	_generator.add_child(_sound)
	# These original inert details move and hide with the DS11 host-state generator.
	HeroProps.new().dress_generator(_generator, dims)
	_generator.visible = false


func _make_pad() -> void:
	var anchor_id: String = str(_config["pad_anchor_id"])
	if not _anchor_positions.has(anchor_id):
		return
	var pad: Node3D = Node3D.new()
	pad.name = "GeneratorPadMarkings"
	pad.position = _anchor_positions[anchor_id]
	_root.add_child(pad)
	var yellow: Color = Color("#E3B74C")
	for x: float in [-0.86, 0.86]:
		_box(pad, "PadLine", Vector3(x, 0.033, 0.0), Vector3(0.06, 0.014, 1.75), yellow)
	for z: float in [-0.87, 0.87]:
		_box(pad, "PadLine", Vector3(0.0, 0.033, z), Vector3(1.75, 0.014, 0.06), yellow)
	_pad_label = _label(pad, "PadLabel", UiText.t(str(_config["pad_label_key"])),
		Vector3(0.0, 0.04, 0.94), 58, Color("#F3F5EF"))
	_pad_label.rotation.x = -PI * 0.5
	_route_label = _label(pad, "RoutePlate", UiText.t(str(_config["route_label_key"])),
		Vector3(0.0, 1.50, -0.70), 60, Color("#FFC86B"))
	_route_label.no_depth_test = true


func _make_cables() -> void:
	var cable_material: StandardMaterial3D = _material(Color(str(_config["cable_color"])))
	var radius: float = float(_config["cable_radius_cm"]) / CM_PER_M
	var max_segments: int = int(_config["max_wire_segments"])
	for route: Dictionary in _config["routes"]:
		var id: String = str(route["edge_id"])
		var visual: Node3D = Node3D.new()
		visual.name = "Cable_" + id
		_root.add_child(visual)
		var points: Array[Vector3] = []
		for coords: Array in route["curve_cm"]:
			points.append(_cm(coords))
		var spline: Curve3D = Curve3D.new()
		spline.bake_interval = float(_config["cable_sample_cm"]) / CM_PER_M
		for i: int in points.size():
			var previous: Vector3 = points[maxi(0, i - 1)]
			var following: Vector3 = points[mini(points.size() - 1, i + 1)]
			var tangent: Vector3 = (following - previous) * 0.18
			spline.add_point(points[i], -tangent, tangent)
		var baked: PackedVector3Array = spline.get_baked_points()
		for i: int in mini(baked.size() - 1, max_segments):
			var a: Vector3 = baked[i]
			var b: Vector3 = baked[i + 1]
			var length: float = a.distance_to(b)
			if length < 0.001:
				continue
			var mesh: CylinderMesh = CylinderMesh.new()
			mesh.top_radius = radius
			mesh.bottom_radius = radius
			mesh.height = length
			mesh.radial_segments = 5
			mesh.rings = 1
			var segment: MeshInstance3D = MeshInstance3D.new()
			segment.name = "Segment"
			segment.mesh = mesh
			segment.material_override = cable_material
			segment.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var direction: Vector3 = (b - a) / length
			var axis: Vector3 = Vector3.UP.cross(direction)
			var basis: Basis = Basis.IDENTITY
			if axis.length_squared() > 0.000001:
				basis = Basis(axis.normalized(), Vector3.UP.angle_to(direction))
			elif direction.y < 0.0:
				basis = Basis(Vector3.RIGHT, PI)
			segment.transform = Transform3D(basis, (a + b) * 0.5)
			visual.add_child(segment)
		var endpoint: Vector3 = _cm(route["end_cm"])
		_box(visual, "Socket", endpoint, Vector3(0.25, 0.11, 0.25), Color(str(_config["socket_color"])))
		var label: Label3D = _label(visual, "SocketLabel", UiText.t(str(route["end_label_key"])),
			endpoint + Vector3.UP * 0.25, 42, Color("#F3F5EF"))
		label.no_depth_test = true
		visual.visible = false
		_cables[id] = visual


## This is the sole derivation of temporary supply presentation from a host
## snapshot. Never extrapolate a 1.5-second trip using render-frame delta.
static func project(state: Dictionary, config: Dictionary) -> Dictionary:
	var grid: Dictionary = state.get("grid", {})
	var nodes: Dictionary = grid.get("nodes", {})
	var edges: Dictionary = grid.get("edges", {})
	var protections: Dictionary = grid.get("protections", {})
	var equipment: Dictionary = (state.get("equipment", {}) as Dictionary).get("items", {})
	var item: Dictionary = equipment.get(str(config.get("generator_id", "")), {})
	var anchor: String = str(item.get("anchor", ""))
	var source: Dictionary = nodes.get(str(config.get("source_id", "")), {})
	var breaker: Dictionary = nodes.get(str(config.get("breaker_id", "")), {})
	var protection: Dictionary = protections.get(str(config.get("protected_route_id", "")), {})
	var capacity: int = maxi(0, int(source.get("capacity", 0)))
	var load_pu: int = maxi(0, int(source.get("load", 0)))
	var ticks: int = maxi(0, int(protection.get("overload_ticks", 0)))
	var trip_ticks: int = maxi(1, int(grid.get("trip_ticks", 1)))
	var tripped: bool = bool(breaker.get("tripped", false))
	var online: bool = bool(source.get("online", false))
	var overload: bool = online and (load_pu > capacity or bool(source.get("overloaded", false)))
	var warning: bool = overload and not tripped and ticks > 0
	var routes: Dictionary = {}
	var linked: bool = false
	for route: Dictionary in config.get("routes", []):
		var id: String = str(route["edge_id"])
		var enabled: bool = bool((edges.get(id, {}) as Dictionary).get("enabled", false))
		routes[id] = enabled
		linked = linked or enabled
	return {
		"anchor": anchor,
		"on_pad": anchor == str(config.get("pad_anchor_id", "")),
		"placed": anchor != "",
		"online": online,
		"load": load_pu,
		"capacity": capacity,
		"overloaded": overload,
		"warning": warning,
		"tripped": tripped,
		"trip_ticks": ticks,
		"trip_total": trip_ticks,
		"trip_percent": mini(100, ticks * 100 / trip_ticks),
		"routes": routes,
		"visible": (anchor == str(config.get("pad_anchor_id", ""))) or linked or online,
	}


func apply(state: Dictionary) -> Dictionary:
	var view: Dictionary = project(state, _config)
	_last_view = view.duplicate(true)
	if _root == null:
		return view
	var anchor: String = str(view["anchor"])
	_generator.visible = bool(view["placed"]) and _anchor_positions.has(anchor)
	if _generator.visible:
		_generator.position = _anchor_positions[anchor]
	var load: int = int(view["load"])
	var capacity: int = int(view["capacity"])
	var status_key: String = "world.generator.idle"
	if bool(view["tripped"]):
		status_key = "world.generator.tripped"
	elif bool(view["warning"]):
		status_key = "world.generator.warning"
	elif bool(view["online"]):
		status_key = "world.generator.running"
	_readout.text = UiText.tf("world.generator.gauge", [load, capacity]) + "\n" + UiText.t(status_key)
	for i: int in _ring.size():
		var item: MeshInstance3D = _ring[i]
		var material: StandardMaterial3D = item.material_override as StandardMaterial3D
		var filled: bool = float(i) / float(_ring.size()) < float(view["trip_percent"]) / 100.0
		material.albedo_color = Color(str(_config["trip_color"])) if bool(view["warning"]) and filled else Color("#52616B")
	for id: String in _cables:
		(_cables[id] as Node3D).visible = bool(view["on_pad"]) and bool((view["routes"] as Dictionary).get(id, false))
	if bool(view["warning"]) and not _last_warning and _sound != null and DisplayServer.get_name() != "headless":
		_sound.play()
	_last_warning = bool(view["warning"])
	if _route_label != null:
		_route_label.text = UiText.t("world.generator.dual_refused") if _refusal_seconds > 0.0 else UiText.t(str(_config["route_label_key"]))
		_route_label.modulate = Color(str(_config["trip_color"])) if _refusal_seconds > 0.0 else Color.WHITE
	return view


## A refused source tie is a real host reply (GRID_REFUSED/DUAL_SUPPLY).
## Highlight only the actual host-named conflicting IDs and never show a
## predicted edge as connected. This warning does not mask the game's refusal.
func on_host_refusal(reply: Dictionary) -> void:
	if bool(reply.get("ok", true)) or str(reply.get("code", "")) != "GRID_REFUSED" or str(reply.get("grid_code", "")) != "DUAL_SUPPLY":
		return
	_refusal_ids.clear()
	for id: Variant in reply.get("ids", []):
		if id is String:
			_refusal_ids.append(id)
	if _refusal_ids.has("E_TEMP_PUB") and _refusal_ids.has("E_JE_PUB"):
		_refusal_seconds = REFUSAL_SECONDS
		if _route_label != null:
			_route_label.text = UiText.t("world.generator.dual_refused")
			_route_label.modulate = Color(str(_config["trip_color"]))


func advance(delta: float) -> void:
	if _refusal_seconds <= 0.0:
		return
	_refusal_seconds = maxf(0.0, _refusal_seconds - maxf(0.0, delta))
	if _refusal_seconds == 0.0 and _route_label != null:
		_route_label.text = UiText.t(str(_config["route_label_key"]))
		_route_label.modulate = Color.WHITE


func last_view() -> Dictionary:
	return _last_view.duplicate(true)


func cable_visible(edge: String) -> bool:
	return _cables.has(edge) and (_cables[edge] as Node3D).visible


func warning_sound() -> AudioStreamPlayer3D:
	return _sound


func refusal_active() -> bool:
	return _refusal_seconds > 0.0


func ring_count() -> int:
	return _ring.size()


func _warning_sample() -> AudioStreamWAV:
	# Original generated tone, no third-party sample and no audio file import.
	var rate: int = int(_config["warning_tone_mix_rate"])
	var total: int = int(_config["warning_tone_ms"]) * rate / 1000
	var hz: float = float(_config["warning_tone_hz"])
	var amp: float = float(_config["warning_tone_amplitude_percent"]) / 100.0
	var pcm: PackedByteArray = PackedByteArray()
	pcm.resize(total * 2)
	for i: int in total:
		var fade: float = 1.0 - float(i) / float(total)
		var sample: int = roundi(sin(TAU * hz * float(i) / float(rate)) * amp * fade * 32767.0)
		pcm.encode_s16(i * 2, sample)
	var sound: AudioStreamWAV = AudioStreamWAV.new()
	sound.format = AudioStreamWAV.FORMAT_16_BITS
	sound.mix_rate = rate
	sound.stereo = false
	sound.data = pcm
	return sound


static func _cm(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2])) / CM_PER_M


static func _material(color: Color) -> StandardMaterial3D:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.48
	return mat


static func _box(parent: Node3D, name: String, pos: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = size
	var node: MeshInstance3D = MeshInstance3D.new()
	node.name = name
	node.mesh = mesh
	node.material_override = _material(color)
	node.position = pos
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
	return node


static func _label(parent: Node3D, name: String, text: String, pos: Vector3, font_size: int, color: Color) -> Label3D:
	var label: Label3D = Label3D.new()
	label.name = name
	label.text = text
	label.position = pos
	label.font_size = font_size
	label.pixel_size = 0.0021
	label.modulate = color
	label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	parent.add_child(label)
	return label
