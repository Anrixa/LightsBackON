extends RefCounted
## DS08 diegetic dressing for a built district: work van, utility cabinets with stencilled plates, street lamps, kerbs,
## lane marks, substation, poles and overhead feeder, cable marker posts, a distant skyline, and building signs.
## Presentation only: every node here is visual (no collision bodies), graybox meshes it replaces are hidden not freed,
## and no gameplay node path, stable ID or content revision changes. Supply state on signs is NOT decided here:
## each service building's existing "Label" node becomes its status plaque, and RestorationPresentation writes its text
## and icon from the host snapshot (DS04). Debug-ID billboards (district "Labels" group) are hidden.
## Shape proportions below are art constants for project-made primitives; tunable colours and positions are in
## content/world/alder_street_dressing.json and content/world/look_stormglass.json.

const DRESSING_PATH: String = "res://content/world/alder_street_dressing.json"
const UiText := preload("res://scripts/ui/ui_text.gd")
const KitBuilder := preload("res://scripts/world/kit_builder.gd")
const DistrictBuilder := preload("res://scripts/world/district_builder.gd")
const TOKENS_PATH: String = "res://content/ui/tokens.json"
const PERCENT: float = 100.0
const MODULE_CM: int = 400
const FACE_NORMAL: Dictionary = {"south": Vector3(0, 0, -1), "north": Vector3(0, 0, 1), "west": Vector3(-1, 0, 0),
	"east": Vector3(1, 0, 0)}
# Van proportions (m), in the VAN prop's local box (2.0 x 2.5 x 5.5, cab toward local -Z).
const VAN_WHEEL_RADIUS: float = 0.38
const VAN_WHEEL_WIDTH: float = 0.28
const VAN_CAB_LENGTH: float = 1.15
const VAN_CAB_HEIGHT: float = 1.95
const VAN_BODY_HEIGHT: float = 2.35
const VAN_FLOOR: float = 0.45
# Cabinet proportions (m), inside the CABINET prop box (1.5 x 1.75 x 0.5).
const CABINET_PLINTH: float = 0.15
const CABINET_CAP: float = 0.06
# Street furniture (m).
const KERB_SINK_CM: float = 0.0
const MARK_LIFT_M: float = 0.026
const MARKER_POST_HEIGHT: float = 0.7
const MARKER_POST_SIZE: float = 0.09
const POLE_RADIUS: float = 0.13
const CROSSARM_LENGTH: float = 1.8
const WIRE_RADIUS: float = 0.012
const WIRE_SAG_M: float = 0.45
const WIRE_SEGMENTS: int = 8
const SKYLINE_DEPTH_M: float = 12.0
const SKYLINE_WINDOW_M: Vector2 = Vector2(1.4, 1.2)
const SKYLINE_WINDOW_PITCH_M: Vector2 = Vector2(2.6, 3.2)

var _font: FontFile
var _font_strong: FontVariation
var _tokens: Dictionary = {}
var _mats: Dictionary = {}


static func load_dressing(path: String = DRESSING_PATH) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


## Builds all dressing under `world/Dressing`. `d` is the district data, `look` the Stormglass look, `dress` the
## district dressing data. Returns the Dressing node.
func build(world: Node3D, d: Dictionary, look: Dictionary, dress: Dictionary) -> Node3D:
	var tokens_parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(TOKENS_PATH))
	_tokens = tokens_parsed if tokens_parsed is Dictionary else {}
	_font = load(str(_tokens["font"]["path"])) as FontFile
	_font_strong = FontVariation.new()
	_font_strong.base_font = _font
	_font_strong.variation_opentype = {"wght": int(_tokens["font"]["weight_strong"])}
	var root: Node3D = Node3D.new()
	root.name = "Dressing"
	world.add_child(root)
	_hide_debug_labels(world)
	_signs(world, root, d, look, dress)
	_cabinets(world, root, dress)
	_van(world, root, dress["van"])
	_lamps(root, look["street_lamp"], dress["lamps"])
	_kerbs(root, dress)
	_lane_marks(root, d, dress["lane_marks"])
	_substation(root, dress)
	_cable_markers(root, dress["cable_markers"])
	_skyline(root, dress["skyline"])
	return root


func _hide_debug_labels(world: Node3D) -> void:
	var labels: Node3D = world.get_node_or_null("Labels") as Node3D
	if labels != null:
		labels.visible = false


# --- Signs --------------------------------------------------------------------------------------------------------

func _signs(world: Node3D, root: Node3D, d: Dictionary, look: Dictionary, dress: Dictionary) -> void:
	var s: Dictionary = look["signs"]
	var palettes: Dictionary = look["buildings"]
	var defs: Dictionary = dress["signs"]
	for b: Dictionary in d["buildings"]:
		var id: String = str(b["id"])
		if not defs.has(id):
			continue
		var building: Node3D = world.get_node_or_null(NodePath("Buildings/" + id)) as Node3D
		if building == null:
			continue
		var palette: Dictionary = palettes.get(id, {})
		var face: String = str(b["front"])
		var n: Vector3 = FACE_NORMAL[face]
		var right: Vector3 = Vector3.UP.cross(n)
		var entrance: Array = DistrictBuilder.entrance_local_cm(b)
		var door: Vector3 = building.global_position + KitBuilder.cm(entrance) - n * float(DistrictBuilder.ENTRANCE_STAND_OFF_CM) / PERCENT
		var face_w: float = float(b["size_cm"][0 if face == "south" or face == "north" else 1]) / PERCENT
		var def: Dictionary = defs[id]
		_fascia(root, id, door, n, right, face_w, building.global_position, b, s, palette, str(def["fascia_key"]))
		var label: Label3D = building.get_node_or_null("Label") as Label3D
		if label != null:
			_plaque(label, door, n, right, s, str(def["plaque_key"]))


func _fascia(root: Node3D, id: String, door: Vector3, n: Vector3, right: Vector3, face_w: float, origin: Vector3,
		b: Dictionary, s: Dictionary, palette: Dictionary, key: String) -> void:
	var height: float = float(s["fascia_height_cm"]) / PERCENT
	var depth: float = float(s["fascia_depth_cm"]) / PERCENT
	var width: float = minf(float(int(s["fascia_width_modules"]) * MODULE_CM) / PERCENT, face_w - 1.0)
	# keep the board on the facade: slide it along the face so both ends stay inside the building width
	var w: float = float(b["size_cm"][0]) / PERCENT
	var dz: float = float(b["size_cm"][1]) / PERCENT
	var face_corners: Dictionary = {"south": [Vector3(0, 0, 0), Vector3(w, 0, 0)], "north": [Vector3(0, 0, dz), Vector3(w, 0, dz)],
		"west": [Vector3(0, 0, 0), Vector3(0, 0, dz)], "east": [Vector3(w, 0, 0), Vector3(w, 0, dz)]}
	var ends: Array = face_corners[str(b["front"])]
	var t0: float = (origin + (ends[0] as Vector3) - door).dot(right)
	var t1: float = (origin + (ends[1] as Vector3) - door).dot(right)
	var shift: float = clampf(0.0, minf(t0, t1) + width * 0.5, maxf(t0, t1) - width * 0.5)
	var center: Vector3 = door + right * shift + Vector3.UP * float(s["fascia_above_door_cm"]) / PERCENT
	center += n * depth * 0.5
	var board_color: String = str(palette.get("sign", ""))
	var holder: Node3D = Node3D.new()
	holder.name = "Fascia_" + id
	root.add_child(holder)
	holder.global_transform = Transform3D(_facing(n), center)
	if board_color != "":
		_box(holder, Vector3.ZERO, Vector3(width, height, depth), _flat(board_color, 0.6))
		_box(holder, Vector3(0, -height * 0.5 - 0.03, 0.02), Vector3(width + 0.1, 0.06, depth + 0.06), _flat("#1B2229", 0.5))
	var text: Label3D = _label(UiText.t(key), int(s["fascia_font_px"]), float(s["fascia_pixel_size_x10000"]) / 10000.0,
		Color(str(palette.get("sign_text", "#F3F5EF"))), int(s["outline_px"]), true)
	text.name = "Name"
	text.position = Vector3(0, 0, depth * 0.5 + 0.01)
	text.width = width / text.pixel_size
	text.autowrap_mode = TextServer.AUTOWRAP_OFF
	holder.add_child(text)


## Turns the building's existing status label (kept for RestorationPresentation and DS04 tests) into a plaque beside the
## door: a dark board, the tablet's name for the service, the supply line and a supply icon (both written by the host-
## driven presentation). Flat on the facade, no billboard.
func _plaque(label: Label3D, door: Vector3, n: Vector3, right: Vector3, s: Dictionary, key: String) -> void:
	var size: Vector3 = _cm3(s["plaque_cm"])
	var off: Array = s["plaque_offset_cm"]
	var center: Vector3 = door + right * float(off[0]) / PERCENT + Vector3.UP * float(off[1]) / PERCENT + n * size.z * 0.5
	label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	label.global_transform = Transform3D(_facing(n), center + n * (size.z * 0.5 + 0.01))
	label.text = UiText.t(key) if key != "" else ""
	label.font = _font_strong
	label.font_size = int(s["plaque_font_px"])
	label.pixel_size = float(s["plaque_pixel_size_x10000"]) / 10000.0
	label.modulate = Color(str(_tokens["colors"]["text"]))
	label.outline_size = 0
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.line_spacing = 2.0
	label.double_sided = false
	var icon_m: float = float(s["plaque_icon_cm"]) / PERCENT
	label.offset = Vector2((-size.x * 0.5 + icon_m + 0.14) / label.pixel_size, 0.0)
	var board: Node3D = Node3D.new()
	board.name = "PlaqueBoard"
	label.add_child(board)
	board.position = Vector3(0, 0, -size.z * 0.5 - 0.01)
	_box(board, Vector3.ZERO, size, _unshaded(str(s["plaque_color"])))
	var icon: Sprite3D = Sprite3D.new()
	icon.name = "StatusIcon"
	icon.pixel_size = icon_m / 48.0
	icon.position = Vector3(-size.x * 0.5 + icon_m * 0.5 + 0.08, 0, 0.005)
	icon.shaded = false
	icon.double_sided = false
	icon.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	label.add_child(icon)


# --- Cabinets -----------------------------------------------------------------------------------------------------

func _cabinets(world: Node3D, root: Node3D, dress: Dictionary) -> void:
	var style: Dictionary = dress["cabinet_style"]
	for c: Dictionary in dress["cabinets"]:
		var prop: Node3D = world.get_node_or_null(NodePath("Props/" + str(c["prop"]))) as Node3D
		if prop == null:
			continue
		var mesh: MeshInstance3D = prop.get_node_or_null("Mesh") as MeshInstance3D
		if mesh == null:
			continue
		var size: Vector3 = (mesh.mesh as BoxMesh).size
		mesh.visible = false
		var holder: Node3D = Node3D.new()
		holder.name = "Cabinet_" + str(c["prop"])
		root.add_child(holder)
		holder.global_position = prop.global_position
		var body: Material = _flat(str(style["body"]), 0.55)
		var trim: Material = _flat(str(style["trim"]), 0.6)
		var plinth_mat: Material = _flat("#6A7178", 0.9)
		_box(holder, Vector3(size.x * 0.5, CABINET_PLINTH * 0.5, size.z * 0.5), Vector3(size.x + 0.12, CABINET_PLINTH, size.z + 0.12), plinth_mat)
		var body_h: float = size.y - CABINET_PLINTH - CABINET_CAP
		_box(holder, Vector3(size.x * 0.5, CABINET_PLINTH + body_h * 0.5, size.z * 0.5), Vector3(size.x, body_h, size.z), body)
		_box(holder, Vector3(size.x * 0.5, size.y - CABINET_CAP * 0.5, size.z * 0.5), Vector3(size.x + 0.08, CABINET_CAP, size.z + 0.1), trim)
		# front details on +Z: two door seams, a handle, louvres, plate, hazard stripe
		var front: float = size.z + 0.006
		_box(holder, Vector3(size.x * 0.5, CABINET_PLINTH + body_h * 0.5, front), Vector3(0.012, body_h - 0.1, 0.01), trim)
		_box(holder, Vector3(size.x * 0.5 + 0.12, CABINET_PLINTH + body_h * 0.48, front + 0.01), Vector3(0.03, 0.18, 0.03), _flat("#C9CED2", 0.3))
		for i: int in 4:
			_box(holder, Vector3(size.x * 0.25, CABINET_PLINTH + 0.18 + i * 0.07, front), Vector3(0.45, 0.025, 0.012), trim)
		_box(holder, Vector3(size.x * 0.5, CABINET_PLINTH + 0.06, front), Vector3(size.x - 0.04, 0.06, 0.012), _flat(str(style["hazard"]), 0.5))
		var plate_y: float = CABINET_PLINTH + body_h * 0.78
		_box(holder, Vector3(size.x * 0.5, plate_y, front), Vector3(size.x * 0.74, 0.3, 0.01), _unshaded(str(style["plate"])))
		var plate: Label3D = _label(UiText.t(str(c["plate_key"])), 72, 0.0028, Color(str(style["plate_text"])), 0, true)
		plate.name = "Plate"
		plate.position = Vector3(size.x * 0.5, plate_y, front + 0.008)
		holder.add_child(plate)


# --- Van ----------------------------------------------------------------------------------------------------------

func _van(world: Node3D, root: Node3D, v: Dictionary) -> void:
	var prop: Node3D = world.get_node_or_null(NodePath("Props/" + str(v["prop"]))) as Node3D
	if prop == null:
		return
	var mesh: MeshInstance3D = prop.get_node_or_null("Mesh") as MeshInstance3D
	if mesh == null:
		return
	var size: Vector3 = (mesh.mesh as BoxMesh).size
	mesh.visible = false
	var h: Node3D = Node3D.new()
	h.name = "Van"
	root.add_child(h)
	h.global_position = prop.global_position
	var white: Material = _flat(str(v["body"]), 0.35)
	var glass: Material = _flat(str(v["glass"]), 0.08)
	var tyre: Material = _flat(str(v["tyre"]), 0.9)
	var stripe: Material = _flat(str(v["stripe"]), 0.4)
	var dark: Material = _flat("#22282E", 0.7)
	var w: float = size.x - 0.1
	var cx: float = size.x * 0.5
	var cargo_from: float = VAN_CAB_LENGTH + 0.25
	var cargo_len: float = size.z - cargo_from - 0.05
	_box(h, Vector3(cx, (VAN_FLOOR + VAN_BODY_HEIGHT) * 0.5, cargo_from + cargo_len * 0.5), Vector3(w, VAN_BODY_HEIGHT - VAN_FLOOR, cargo_len), white)
	_box(h, Vector3(cx, (VAN_FLOOR + VAN_CAB_HEIGHT) * 0.5, 0.25 + VAN_CAB_LENGTH * 0.5), Vector3(w, VAN_CAB_HEIGHT - VAN_FLOOR, VAN_CAB_LENGTH), white)
	_box(h, Vector3(cx, VAN_CAB_HEIGHT - 0.05, cargo_from - 0.02), Vector3(w, 0.1, 0.06), white)
	# windscreen and cab side windows
	_box(h, Vector3(cx, 1.55, 0.24), Vector3(w - 0.2, 0.55, 0.02), glass)
	for side: float in [-1.0, 1.0]:
		var sx: float = cx + side * (w * 0.5 + 0.006)
		_box(h, Vector3(sx, 1.55, 0.25 + VAN_CAB_LENGTH * 0.55), Vector3(0.012, 0.45, VAN_CAB_LENGTH * 0.6), glass)
		_box(h, Vector3(sx, 1.08, (0.3 + size.z - 0.06) * 0.5), Vector3(0.014, 0.2, size.z - 0.36), stripe)
		for z: float in [0.95, size.z - 1.0]:
			var wheel: MeshInstance3D = MeshInstance3D.new()
			var cyl: CylinderMesh = CylinderMesh.new()
			cyl.top_radius = VAN_WHEEL_RADIUS
			cyl.bottom_radius = VAN_WHEEL_RADIUS
			cyl.height = VAN_WHEEL_WIDTH
			wheel.mesh = cyl
			wheel.material_override = tyre
			wheel.rotation_degrees = Vector3(0, 0, 90)
			wheel.position = Vector3(cx + side * (w * 0.5 - VAN_WHEEL_WIDTH * 0.3), VAN_WHEEL_RADIUS, z)
			h.add_child(wheel)
		var text: Label3D = _label(UiText.t(str(v["label_key"])), 110, 0.004, Color(str(v["label_color"])), 0, true)
		text.position = Vector3(sx + side * 0.004, 1.75, cargo_from + cargo_len * 0.5)
		text.rotation_degrees = Vector3(0, 90.0 * side, 0)
		h.add_child(text)
	# bumpers, rear doors with reflective chevrons
	_box(h, Vector3(cx, 0.45, 0.2), Vector3(w + 0.04, 0.22, 0.12), dark)
	_box(h, Vector3(cx, 0.45, size.z - 0.02), Vector3(w + 0.04, 0.2, 0.1), dark)
	_box(h, Vector3(cx, 1.4, size.z - 0.04), Vector3(0.015, VAN_BODY_HEIGHT - VAN_FLOOR - 0.1, 0.02), dark)
	for i: int in 4:
		var y: float = 0.75 + i * 0.22
		_box(h, Vector3(cx - 0.45, y, size.z - 0.035), Vector3(0.7, 0.08, 0.01), _flat(str(v["stripe_reflective"]) if i % 2 == 0 else str(v["stripe"]), 0.3))
		_box(h, Vector3(cx + 0.45, y, size.z - 0.035), Vector3(0.7, 0.08, 0.01), _flat(str(v["stripe"]) if i % 2 == 0 else str(v["stripe_reflective"]), 0.3))
	# lights: headlamps, tail lamps, roof beacon bar (steady, never flashing), rear work flood
	for side: float in [-1.0, 1.0]:
		_box(h, Vector3(cx + side * (w * 0.5 - 0.22), 0.78, 0.22), Vector3(0.26, 0.12, 0.03), _emissive("#FFF4E0", 2.5))
		_box(h, Vector3(cx + side * (w * 0.5 - 0.1), 1.2, size.z - 0.01), Vector3(0.12, 0.3, 0.03), _emissive("#FF4A3A", 1.2))
	_box(h, Vector3(cx, VAN_BODY_HEIGHT + 0.07, cargo_from + 0.3), Vector3(1.2, 0.12, 0.25), _emissive(str(v["beacon"]), 3.0))
	_box(h, Vector3(cx, VAN_BODY_HEIGHT + 0.08, size.z - 0.25), Vector3(0.5, 0.14, 0.18), _emissive(str(v["flood_color"]), 3.0))
	var flood: SpotLight3D = SpotLight3D.new()
	flood.name = "WorkFlood"
	flood.light_color = Color(str(v["flood_color"]))
	flood.light_energy = float(v["flood_energy_percent"]) / PERCENT
	flood.spot_range = float(v["flood_range_cm"]) / PERCENT
	flood.spot_angle = 55.0
	flood.shadow_enabled = false
	flood.position = Vector3(cx, VAN_BODY_HEIGHT + 0.1, size.z + 0.1)
	flood.rotation_degrees = Vector3(-62, 180, 0)
	h.add_child(flood)
	var beacon: OmniLight3D = OmniLight3D.new()
	beacon.name = "Beacon"
	beacon.light_color = Color(str(v["beacon"]))
	beacon.light_energy = 0.8
	beacon.omni_range = 5.0
	beacon.position = Vector3(cx, VAN_BODY_HEIGHT + 0.4, cargo_from + 0.3)
	h.add_child(beacon)


# --- Street lamps, kerbs, marks ------------------------------------------------------------------------------------

func _lamps(root: Node3D, s: Dictionary, lamps: Array) -> void:
	var pole_mat: Material = _flat(str(s["pole_color"]), 0.5)
	var lens: Material = _emissive(str(s["lens_color"]), float(s["lens_emission_percent"]) / PERCENT)
	var height: float = float(s["pole_height_cm"]) / PERCENT
	var radius: float = float(s["pole_radius_cm"]) / PERCENT
	var arm: float = float(s["arm_cm"]) / PERCENT
	var head: Vector3 = _cm3(s["head_cm"])
	var i: int = 0
	for l: Dictionary in lamps:
		var h: Node3D = Node3D.new()
		h.name = "Lamp%d" % i
		i += 1
		root.add_child(h)
		h.position = _cm3(l["pos_cm"])
		h.rotation_degrees.y = float(l["yaw"])
		var pole: MeshInstance3D = MeshInstance3D.new()
		var cyl: CylinderMesh = CylinderMesh.new()
		cyl.top_radius = radius * 0.7
		cyl.bottom_radius = radius
		cyl.height = height
		pole.mesh = cyl
		pole.material_override = pole_mat
		pole.position = Vector3(0, height * 0.5, 0)
		h.add_child(pole)
		_box(h, Vector3(0, 0.3, 0), Vector3(radius * 3.0, 0.6, radius * 3.0), pole_mat)
		_box(h, Vector3(0, height - 0.05, arm * 0.5), Vector3(0.07, 0.07, arm), pole_mat)
		_box(h, Vector3(0, height, arm), head, pole_mat)
		_box(h, Vector3(0, height - head.y * 0.5 - 0.01, arm), Vector3(head.x * 0.85, 0.02, head.z * 0.8), lens)
		var light: SpotLight3D = SpotLight3D.new()
		light.light_color = Color(str(s["light_color"]))
		light.light_energy = float(s["light_energy_percent"]) / PERCENT
		light.spot_range = float(s["light_range_cm"]) / PERCENT
		light.spot_angle = float(s["light_angle_deg"])
		light.spot_attenuation = float(s["light_attenuation_percent"]) / PERCENT
		light.shadow_enabled = false
		light.distance_fade_enabled = true
		light.distance_fade_begin = float(s["light_fade_begin_cm"]) / PERCENT
		light.distance_fade_length = float(s["light_fade_length_cm"]) / PERCENT
		light.position = Vector3(0, height - head.y, arm)
		light.rotation_degrees = Vector3(-90, 0, 0)
		h.add_child(light)


func _kerbs(root: Node3D, dress: Dictionary) -> void:
	var mat: Material = _flat(str(dress["kerb_color"]), 0.75)
	var h: float = float(dress["kerb_height_cm"]) / PERCENT
	for k: Dictionary in dress["kerbs"]:
		var lo: Array = k["min_cm"]
		var size: Array = k["size_cm"]
		var sz: Vector3 = Vector3(float(size[0]) / PERCENT, h, float(size[1]) / PERCENT)
		_box(root, Vector3(float(lo[0]) / PERCENT + sz.x * 0.5, h * 0.5 + KERB_SINK_CM, float(lo[1]) / PERCENT + sz.z * 0.5), sz, mat)


func _lane_marks(root: Node3D, d: Dictionary, m: Dictionary) -> void:
	var route: Dictionary = {}
	for r: Dictionary in d["routes"]:
		if str(r["id"]) == str(m["route"]):
			route = r
	if route.is_empty():
		return
	var mat: Material = _flat(str(m["color"]), 0.55)
	var lo: Vector2 = Vector2(float(route["min_cm"][0]), float(route["min_cm"][1])) / PERCENT
	var size: Vector2 = Vector2(float(route["size_cm"][0]), float(route["size_cm"][1])) / PERCENT
	var w: float = float(m["width_cm"]) / PERCENT
	var inset: float = float(m["edge_inset_cm"]) / PERCENT
	var dash: float = float(m["dash_cm"]) / PERCENT
	var gap: float = float(m["gap_cm"]) / PERCENT
	var mid_z: float = lo.y + size.y * 0.5
	var x: float = lo.x + gap * 0.5
	while x + dash <= lo.x + size.x:
		_box(root, Vector3(x + dash * 0.5, MARK_LIFT_M, mid_z), Vector3(dash, 0.004, w), mat)
		x += dash + gap
	for z: float in [lo.y + inset, lo.y + size.y - inset]:
		_box(root, Vector3(lo.x + size.x * 0.5, MARK_LIFT_M, z), Vector3(size.x, 0.004, w * 0.8), mat)


# --- Substation, poles, cable markers ------------------------------------------------------------------------------

func _substation(root: Node3D, dress: Dictionary) -> void:
	var s: Dictionary = dress["substation"]
	var lo: Vector2 = Vector2(float(s["min_cm"][0]), float(s["min_cm"][1])) / PERCENT
	var size: Vector2 = Vector2(float(s["size_cm"][0]), float(s["size_cm"][1])) / PERCENT
	var h: Node3D = Node3D.new()
	h.name = "Substation"
	root.add_child(h)
	var fence: Material = _flat(str(s["fence"]), 0.5)
	var fh: float = float(s["fence_height_cm"]) / PERCENT
	_box(h, Vector3(lo.x + size.x * 0.5, 0.06, lo.y + size.y * 0.5), Vector3(size.x, 0.12, size.y), _flat("#6A7178", 0.9))
	var corners: Array[Vector2] = [lo, Vector2(lo.x + size.x, lo.y), lo + size, Vector2(lo.x, lo.y + size.y)]
	for c: int in 4:
		var a: Vector2 = corners[c]
		var b: Vector2 = corners[(c + 1) % 4]
		var length: float = a.distance_to(b)
		var steps: int = maxi(1, int(length / 1.5))
		for i: int in steps + 1:
			var p: Vector2 = a.lerp(b, float(i) / float(steps))
			_box(h, Vector3(p.x, fh * 0.5, p.y), Vector3(0.06, fh, 0.06), fence)
		var mid: Vector2 = (a + b) * 0.5
		var horizontal: bool = absf(a.y - b.y) < 0.01
		for y: float in [0.3, fh * 0.55, fh - 0.03]:
			_box(h, Vector3(mid.x, y, mid.y), Vector3(length if horizontal else 0.04, 0.04, 0.04 if horizontal else length), fence)
	var t: Vector3 = _cm3(s["transformer_cm"])
	var tc: Vector3 = Vector3(lo.x + size.x * 0.5, t.y * 0.5 + 0.12, lo.y + size.y * 0.5)
	var body: Material = _flat(str(s["color"]), 0.5)
	_box(h, tc, t, body)
	for i: int in 7:
		_box(h, tc + Vector3(-t.x * 0.4 + i * t.x * 0.8 / 6.0, 0, t.z * 0.5 + 0.08), Vector3(0.05, t.y * 0.8, 0.16), body)
	for i: int in 3:
		var bushing: MeshInstance3D = MeshInstance3D.new()
		var cyl: CylinderMesh = CylinderMesh.new()
		cyl.top_radius = 0.05
		cyl.bottom_radius = 0.09
		cyl.height = 0.45
		bushing.mesh = cyl
		bushing.material_override = _flat("#B8C0C4", 0.3)
		bushing.position = tc + Vector3(-0.6 + i * 0.6, t.y * 0.5 + 0.22, 0)
		h.add_child(bushing)
	var sign: Label3D = _label(UiText.t(str(s["label_key"])), 64, 0.003, Color("#1B2229"), 0, true)
	var board_pos: Vector3 = Vector3(lo.x + size.x * 0.5, 1.4, lo.y + size.y + 0.04)
	_box(h, board_pos - Vector3(0, 0, 0.02), Vector3(1.4, 0.36, 0.02), _unshaded("#E4C23A"))
	sign.position = board_pos
	h.add_child(sign)
	# poles and an overhead three-wire feeder from the transformer toward the west junction
	var pole_mat: Material = _flat(str(dress["pole_color"]), 0.85)
	var wire_mat: Material = _flat(str(dress["wire_color"]), 0.4)
	var ph: float = float(dress["pole_height_cm"]) / PERCENT
	var tops: Array[Vector3] = [tc + Vector3(0, t.y * 0.5 + 0.45, 0)]
	for p: Dictionary in dress["poles"]:
		var pos: Vector3 = _cm3(p["pos_cm"])
		var pole: MeshInstance3D = MeshInstance3D.new()
		var cyl: CylinderMesh = CylinderMesh.new()
		cyl.top_radius = POLE_RADIUS * 0.8
		cyl.bottom_radius = POLE_RADIUS
		cyl.height = ph
		pole.mesh = cyl
		pole.material_override = pole_mat
		pole.position = pos + Vector3(0, ph * 0.5, 0)
		h.add_child(pole)
		_box(h, pos + Vector3(0, ph - 0.4, 0), Vector3(CROSSARM_LENGTH, 0.1, 0.1), pole_mat)
		tops.append(pos + Vector3(0, ph - 0.3, 0))
	var last: Vector3 = tops[tops.size() - 1]
	_box(h, Vector3(last.x + 0.18, last.y * 0.5, last.z), Vector3(0.08, last.y, 0.08), _flat("#3A3F44", 0.6))
	for i: int in tops.size() - 1:
		for k: int in 3:
			var off: Vector3 = Vector3((k - 1) * (CROSSARM_LENGTH * 0.42 if i > 0 else 0.6), 0, 0)
			var off_b: Vector3 = Vector3((k - 1) * CROSSARM_LENGTH * 0.42, 0, 0)
			_wire(h, tops[i] + off, tops[i + 1] + off_b, wire_mat)


func _wire(parent: Node3D, a: Vector3, b: Vector3, mat: Material) -> void:
	var prev: Vector3 = a
	for i: int in range(1, WIRE_SEGMENTS + 1):
		var t: float = float(i) / float(WIRE_SEGMENTS)
		var p: Vector3 = a.lerp(b, t) + Vector3.DOWN * WIRE_SAG_M * 4.0 * t * (1.0 - t)
		var seg: MeshInstance3D = MeshInstance3D.new()
		var cyl: CylinderMesh = CylinderMesh.new()
		cyl.top_radius = WIRE_RADIUS
		cyl.bottom_radius = WIRE_RADIUS
		cyl.height = prev.distance_to(p)
		cyl.radial_segments = 4
		cyl.rings = 1
		seg.mesh = cyl
		seg.material_override = mat
		seg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mid: Vector3 = (prev + p) * 0.5
		var dir: Vector3 = (p - prev).normalized()
		var axis: Vector3 = Vector3.UP.cross(dir)
		var basis: Basis = Basis.IDENTITY
		if axis.length() > 0.0001:
			basis = Basis(axis.normalized(), Vector3.UP.angle_to(dir))
		seg.transform = Transform3D(basis, mid)
		parent.add_child(seg)
		prev = p


func _cable_markers(root: Node3D, m: Dictionary) -> void:
	var post: Material = _flat(str(m["post_color"]), 0.6)
	var cap: Material = _flat(str(m["color"]), 0.4)
	var spacing: float = float(m["spacing_cm"]) / PERCENT
	for path: Array in m["paths_cm"]:
		var carry: float = 0.0
		for i: int in path.size() - 1:
			var a: Vector2 = Vector2(float(path[i][0]), float(path[i][1])) / PERCENT
			var b: Vector2 = Vector2(float(path[i + 1][0]), float(path[i + 1][1])) / PERCENT
			var length: float = a.distance_to(b)
			var s: float = carry
			while s <= length:
				var p: Vector2 = a.lerp(b, s / maxf(length, 0.001))
				_box(root, Vector3(p.x, MARKER_POST_HEIGHT * 0.5, p.y), Vector3(MARKER_POST_SIZE, MARKER_POST_HEIGHT, MARKER_POST_SIZE), post)
				_box(root, Vector3(p.x, MARKER_POST_HEIGHT + 0.05, p.y), Vector3(MARKER_POST_SIZE * 1.4, 0.1, MARKER_POST_SIZE * 1.4), cap)
				s += spacing
			carry = s - length


# --- Skyline -------------------------------------------------------------------------------------------------------

func _skyline(root: Node3D, s: Dictionary) -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = int(s["seed"])
	var blocks: Array[Transform3D] = []
	var windows: Array[Transform3D] = []
	var bw: Array = s["block_width_cm"]
	var lit_chance: float = float(s["lit_window_percent"]) / PERCENT
	for row: Dictionary in s["rows"]:
		var along_x: bool = str(row["along"]) == "x"
		var at: float = float(row["at_cm"]) / PERCENT
		var pos: float = float(row["from_cm"]) / PERCENT
		var end: float = float(row["to_cm"]) / PERCENT
		var hr: Array = row["height_cm"]
		# the face toward the district: rows past the far edge face back toward it
		var toward: float = 1.0 if at < 0.0 else -1.0
		while pos < end:
			var width: float = rng.randf_range(float(bw[0]), float(bw[1])) / PERCENT
			var height: float = rng.randf_range(float(hr[0]), float(hr[1])) / PERCENT
			var center: Vector3
			var scale: Vector3
			if along_x:
				center = Vector3(pos + width * 0.5, height * 0.5, at - toward * SKYLINE_DEPTH_M * 0.5)
				scale = Vector3(width - 0.4, height, SKYLINE_DEPTH_M)
			else:
				center = Vector3(at - toward * SKYLINE_DEPTH_M * 0.5, height * 0.5, pos + width * 0.5)
				scale = Vector3(SKYLINE_DEPTH_M, height, width - 0.4)
			blocks.append(Transform3D(Basis.from_scale(scale), center))
			var cols: int = int((width - 1.0) / SKYLINE_WINDOW_PITCH_M.x)
			var rows: int = int((height - 2.0) / SKYLINE_WINDOW_PITCH_M.y)
			for r: int in rows:
				for c: int in cols:
					if rng.randf() >= lit_chance:
						continue
					var u: float = pos + 0.8 + c * SKYLINE_WINDOW_PITCH_M.x + SKYLINE_WINDOW_M.x * 0.5
					var y: float = 2.0 + r * SKYLINE_WINDOW_PITCH_M.y
					var basis: Basis = Basis.from_scale(Vector3(SKYLINE_WINDOW_M.x, SKYLINE_WINDOW_M.y, 1.0))
					if along_x:
						basis = Basis(Vector3.UP, 0.0 if toward > 0.0 else PI) * basis
						windows.append(Transform3D(basis, Vector3(u, y, at + toward * 0.02)))
					else:
						basis = Basis(Vector3.UP, PI * 0.5 * toward) * basis
						windows.append(Transform3D(basis, Vector3(at + toward * 0.02, y, u)))
			pos += width
	root.add_child(_multimesh("Skyline", BoxMesh.new(), blocks, _unshaded(str(s["color"]))))
	var quad: QuadMesh = QuadMesh.new()
	root.add_child(_multimesh("SkylineWindows", quad, windows, _emissive(str(s["lit_window_color"]), 2.0)))


func _multimesh(name: String, mesh: Mesh, xforms: Array[Transform3D], mat: Material) -> MultiMeshInstance3D:
	var mm: MultiMesh = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i: int in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi: MultiMeshInstance3D = MultiMeshInstance3D.new()
	mmi.name = name
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mmi


# --- Primitives ----------------------------------------------------------------------------------------------------

func _box(parent: Node3D, center: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var mi: MeshInstance3D = MeshInstance3D.new()
	var box: BoxMesh = BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.material_override = mat
	mi.position = center
	parent.add_child(mi)
	return mi


func _label(text: String, font_px: int, pixel: float, color: Color, outline_px: int, strong: bool) -> Label3D:
	var l: Label3D = Label3D.new()
	l.text = text
	l.font = _font_strong if strong else _font
	l.font_size = font_px
	l.pixel_size = pixel
	l.modulate = color
	l.outline_size = outline_px
	l.outline_modulate = Color(0.06, 0.08, 0.1, 0.9)
	l.double_sided = false
	l.shaded = false
	return l


func _flat(hex: String, roughness: float) -> StandardMaterial3D:
	var key: String = "flat_%s_%d" % [hex, roundi(roughness * 100.0)]
	if _mats.has(key):
		return _mats[key]
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.albedo_color = Color(hex)
	m.roughness = roughness
	_mats[key] = m
	return m


func _unshaded(hex: String) -> StandardMaterial3D:
	var key: String = "unshaded_" + hex
	if _mats.has(key):
		return _mats[key]
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(hex)
	_mats[key] = m
	return m


func _emissive(hex: String, energy: float) -> StandardMaterial3D:
	var key: String = "emissive_%s_%d" % [hex, roundi(energy * 100.0)]
	if _mats.has(key):
		return _mats[key]
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.albedo_color = Color(hex)
	m.emission_enabled = true
	m.emission = Color(hex)
	m.emission_energy_multiplier = energy
	_mats[key] = m
	return m


## Basis whose +Z (the side Label3D text reads from) points along the facade normal `n`.
static func _facing(n: Vector3) -> Basis:
	return Basis.looking_at(-n, Vector3.UP)


static func _cm3(v: Array) -> Vector3:
	return Vector3(float(v[0]), float(v[1]), float(v[2])) / PERCENT
