extends RefCounted
## DS dispatch-stage look. Owner playtest (23 Nov 2026): "only Alder Street looks good". The 200 dispatch levels were lit by
## one flat daylight, painted in bright untextured StandardMaterial3D colours, and every host target was a bare grey slab.
## This layer brings the approved Alder Street Stormglass look (DS08, ADR-016/017) to the dispatch stage:
## 1. the same night environment, moon and rain as Alder Street (scripts/world/street_look.gd);
## 2. the same Stormglass surface shader on static, collision-carrying or schematic geometry, keeping each layer's hue
##    so colour cues survive but at night values;
## 3. a typed equipment unit (meter, switch, console, board, crate, junction box) for every host target, in the Alder
##    cabinet style, instead of the 0.75 x 0.43 m grey slab;
## 4. one warm crew work light per station, so the work area reads as lit against the cool rain.
## Presentation only: no collision, no host target, position, text or state changes. Aim uses host positions, not these
## meshes. Groups whose materials change at runtime (task anchors, supply lights, feedback, approach routes) are left
## alone. Tunables live in assets/design/dispatch_stage_look.json, so content and rules revisions do not change.

const StreetLook := preload("res://scripts/world/street_look.gd")
const Graybox := preload("res://scripts/world/expedition_graybox.gd")
const ART_PATH: String = "res://assets/design/dispatch_stage_look.json"
const ROOT_NAME: String = "DispatchStageLook"
const FILL_LIGHT_NAME: String = "SourceHeadlessLight"
const PLATE_NAME: String = "WorksitePlate"
const HUB_RADIUS_M: float = 0.25
const RELIC_PREFIX: String = "FIND_"
## Head clearance for schematic overhead walkways the player cannot stand on (camera eye is about 1.7 m).
const OVERHEAD_CLEARANCE_M: float = 2.6
const ASSEMBLY_MATCH_M: float = 0.15


static func load_art(path: String = ART_PATH) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


## Applies the look. `positions` are the host target positions (id -> Vector3), `stations` the plan's station list.
## Returns {"ok", "skinned", "units", "work_lights"}.
static func apply(stage: Node3D, world: Node3D, stations: Array, positions: Dictionary) -> Dictionary:
	var art: Dictionary = load_art()
	var look: Dictionary = StreetLook.load_look()
	if art.is_empty() or look.is_empty():
		return {"ok": false, "code": "LOOK_SOURCE_MISSING"}
	StreetLook.apply_environment(stage, look)
	StreetLook.add_rain(stage, look)
	var fill: DirectionalLight3D = stage.get_node_or_null(FILL_LIGHT_NAME) as DirectionalLight3D
	if fill != null:
		fill.light_energy = float(art["fill_light_energy"])
	var root: Node3D = Node3D.new()
	root.name = ROOT_NAME
	root.set_meta("presentation_only", true)
	world.add_child(root)
	var cache: Dictionary = {}
	var skinned: int = _skin(world, art, look, cache)
	var dressed: Array[Vector2] = _ground_assemblies(world)
	var overhead: int = _clear_overhead(world)
	var centres: Array[Vector3] = []
	for station: Dictionary in stations:
		centres.append(station["position"])
	var units: int = _units(world, root, art["unit"], centres, positions, dressed, cache)
	var lights: int = _work_lights(root, art["work_light"], centres, cache)
	_perimeter(root, art["perimeter"], look, cache)
	_skyline(root, art["skyline"], cache)
	var lamps: int = _lamps(root, art["lamps"], look["street_lamp"], centres, cache)
	return {"ok": true, "skinned": skinned, "units": units, "work_lights": lights, "lamps": lamps,
		"grounded_assemblies": dressed.size(), "overhead_fixed": overhead}


# --- Surfaces -----------------------------------------------------------------------------------------------------

static func _skin(world: Node3D, art: Dictionary, look: Dictionary, cache: Dictionary) -> int:
	var patterns: Dictionary = art["group_patterns"]
	var count: int = 0
	for group_name: String in patterns:
		for group: Node in world.find_children(group_name, "", true, false):
			for node: Node in group.find_children("*", "GeometryInstance3D", true, false):
				if _skin_one(node as GeometryInstance3D, patterns[group_name], art["surface"], look, cache):
					count += 1
	return count


## Replaces a plain opaque StandardMaterial3D with the Stormglass surface in the same hue. A string role uses the
## look's own material (asphalt, paving); an integer is a shader pattern.
static func _skin_one(geo: GeometryInstance3D, role: Variant, s: Dictionary, look: Dictionary, cache: Dictionary) -> bool:
	var old: StandardMaterial3D = geo.material_override as StandardMaterial3D
	if old == null or old.emission_enabled or old.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
		return false
	if role is String and role == "buildings":
		# Landmark facades take Alder Street's own building palettes (brick, render, corrugated), chosen per node name.
		var walls: Array = []
		for id: String in look["buildings"]:
			if look["buildings"][id] is Dictionary and (look["buildings"][id] as Dictionary).has("wall"):
				walls.append(look["buildings"][id]["wall"])
		var pick: int = absi(hash(str(geo.name))) % walls.size()
		geo.material_override = StreetLook.surface_material(walls[pick], cache, "building_%d" % pick)
		return true
	if role is String:
		geo.material_override = StreetLook.surface_material(look["materials"][role], cache, "look_" + str(role))
		return true
	if role is Dictionary:
		# A look material with overrides: Alder's street asphalt is very wet, which over a 52 m yard read as black
		# puddle holes; the yard keeps the asphalt but drier and at a larger scale.
		var def: Dictionary = (look["materials"][str(role["from"])] as Dictionary).duplicate()
		for key: String in role:
			if key != "from":
				def[key] = role[key]
		geo.material_override = StreetLook.surface_material(def, cache, "look_override_" + str(geo.name))
		return true
	var base: Color = old.albedo_color
	base = Color.from_hsv(base.h, base.s * float(s["saturation_scale"]), minf(base.v, float(s["max_value"])))
	var accent: Color = Color.from_hsv(base.h, base.s, base.v * float(s["accent_value_scale"]))
	var def: Dictionary = {"pattern": int(role), "base": base.to_html(false), "accent": accent.to_html(false),
		"roughness_percent": s["roughness_percent"], "wetness_percent": s["wetness_percent"], "scale_cm": s["scale_cm"]}
	geo.material_override = StreetLook.surface_material(def, cache, "skin_%d_%s" % [int(role), def["base"]])
	return true


# --- Composition fixes for older schematic layers ------------------------------------------------------------------

## EXP014 worksite assemblies are anchored at their host target, whose y is device height (about 1.4 m), so the whole
## cabinet floated above the ground. Stand them on the floor. Returns the ground-plane spots they now dress, so no
## second unit is drawn on the same target.
static func _ground_assemblies(world: Node3D) -> Array[Vector2]:
	var spots: Array[Vector2] = []
	for group: Node in world.find_children("Assemblies", "", true, false):
		for node: Node in group.get_children():
			var assembly: Node3D = node as Node3D
			if assembly == null:
				continue
			assembly.position.y = 0.0
			spots.append(Vector2(assembly.global_position.x, assembly.global_position.z))
	return spots


## EXP017 elevated service access is a non-colliding schematic. Its "entry rise" and "descent" ramps run from the
## ground straight up to the walkway (zero horizontal run), which drew five plates stacked in a column at every station,
## and the walkway spans sat at eye height, where the camera clipped through them. Hide the degenerate ramps, lift the
## spans above head height and extend the pylons to carry them, so the layer reads as an overhead gantry.
static func _clear_overhead(world: Node3D) -> int:
	var fixed: int = 0
	for group: Node in world.find_children("ElevatedServiceAccess", "", true, false):
		var span_y: float = OVERHEAD_CLEARANCE_M
		for node: Node in group.get_children():
			var mi: MeshInstance3D = node as MeshInstance3D
			if mi == null:
				continue
			var name: String = str(mi.name)
			if name.contains("EntryRise") or name.contains("ServiceDescent"):
				mi.visible = false
				fixed += 1
			elif name.contains("_Span"):
				var half: float = (mi.mesh as BoxMesh).size.y * 0.5 if mi.mesh is BoxMesh else 0.07
				mi.position.y = maxf(mi.position.y, OVERHEAD_CLEARANCE_M + half)
				span_y = mi.position.y - half
				fixed += 1
		for node: Node in group.get_children():
			var pylon: MeshInstance3D = node as MeshInstance3D
			if pylon == null or not str(pylon.name).begins_with("ServicePylon") or not pylon.mesh is BoxMesh:
				continue
			var box: BoxMesh = (pylon.mesh as BoxMesh).duplicate() as BoxMesh
			box.size.y = span_y
			pylon.mesh = box
			pylon.position.y = span_y * 0.5
			fixed += 1
	return fixed


# --- Equipment units ----------------------------------------------------------------------------------------------

static func _units(world: Node3D, root: Node3D, u: Dictionary, centres: Array[Vector3], positions: Dictionary,
		dressed: Array[Vector2], cache: Dictionary) -> int:
	var targets: Node = world.get_node_or_null("HostTargets")
	var count: int = 0
	var ids: Array = positions.keys()
	ids.sort()
	for id: String in ids:
		if targets == null:
			break
		var marker: Node3D = targets.get_node_or_null(id) as Node3D
		if marker == null:
			continue
		var plate: MeshInstance3D = marker.get_node_or_null(PLATE_NAME) as MeshInstance3D
		if plate == null:
			continue
		var target: Vector3 = positions[id]
		if _is_dressed(Vector2(target.x, target.z), dressed):
			# An EXP014 cabinet assembly already stands on this target.
			plate.visible = false
			continue
		var holder: Node3D = Node3D.new()
		holder.name = "Unit_" + id
		holder.set_meta("host_entity", id)
		root.add_child(holder)
		holder.position = Vector3(target.x, 0.0, target.z)
		holder.basis = Basis.looking_at(-_front(target, centres), Vector3.UP)
		var kind: String = unit_kind(id)
		holder.set_meta("unit_kind", kind)
		_build_unit(holder, kind, target.y, u, cache)
		# The relic keeps its gold marker on top of a plinth; every other slab is replaced by the unit.
		plate.visible = kind == "relic"
		count += 1
	return count


static func _is_dressed(spot: Vector2, dressed: Array[Vector2]) -> bool:
	for other: Vector2 in dressed:
		if spot.distance_to(other) <= ASSEMBLY_MATCH_M:
			return true
	return false


## Equipment family from the authored host ID prefix/suffix. Decides shape only, never state.
static func unit_kind(id: String) -> String:
	if id.begins_with(RELIC_PREFIX):
		return "relic"
	if id.ends_with("_CTRL"):
		return "console"
	if id.ends_with("_BOARD"):
		return "board"
	if id.ends_with("_DEPOT"):
		return "crate"
	if id.begins_with("SW_"):
		return "switch"
	if id.begins_with("PANEL_") or id.begins_with("FC_") or id.begins_with("FD_"):
		return "meter"
	return "box"


## Units face away from their station hub, so a player walking round the hub sees every front. A unit at the hub
## centre faces the approach from the previous station (+Z for the first station: the spawn side).
static func _front(target: Vector3, centres: Array[Vector3]) -> Vector3:
	var best: int = 0
	var best_d: float = INF
	for i: int in centres.size():
		var d: float = Vector2(target.x - centres[i].x, target.z - centres[i].z).length()
		if d < best_d:
			best_d = d
			best = i
	if centres.is_empty():
		return Vector3.BACK
	var out: Vector3 = Vector3(target.x - centres[best].x, 0.0, target.z - centres[best].z)
	if best_d < HUB_RADIUS_M:
		out = Vector3.BACK if best == 0 else Vector3(centres[best - 1].x - centres[best].x, 0.0,
			centres[best - 1].z - centres[best].z)
	return out.normalized() if out.length() > 0.001 else Vector3.BACK


static func _build_unit(h: Node3D, kind: String, height: float, u: Dictionary, cache: Dictionary) -> void:
	var body: Material = _flat(str(u["body"]), 0.55, cache)
	var trim: Material = _flat(str(u["trim"]), 0.6, cache)
	var head: Vector3 = _v3(u["head_size"])
	match kind:
		"relic":
			_box(h, Vector3(0, (height - 0.2) * 0.5, 0), Vector3(0.34, height - 0.2, 0.34), _flat(str(u["plinth"]), 0.9, cache))
		"crate":
			_box(h, Vector3(0, 0.06, 0), Vector3(0.9, 0.12, 0.7), _flat(str(u["plinth"]), 0.9, cache))
			_box(h, Vector3(0, 0.47, 0), Vector3(0.8, 0.7, 0.6), _flat(str(u["crate"]), 0.8, cache))
			_box(h, Vector3(0, 0.47, 0.302), Vector3(0.82, 0.08, 0.01), trim)
			_box(h, Vector3(0, 0.6, 0.306), Vector3(0.5, 0.22, 0.01), _unshaded(str(u["plate"]), cache))
		"console":
			_post(h, height - 0.1, u, cache)
			var desk: Vector3 = _v3(u["console_size"])
			var top: MeshInstance3D = _box(h, Vector3(0, height, 0), desk, body)
			top.rotation_degrees.x = float(u["console_tilt_deg"])
			var screen: MeshInstance3D = _box(top, Vector3(0, desk.y * 0.5 + 0.004, 0), Vector3(desk.x * 0.8, 0.006, desk.z * 0.7),
				_emissive(str(u["screen"]), float(u["screen_energy"]), cache))
			screen.name = "Screen"
		"board":
			for side: float in [-1.0, 1.0]:
				_box(h, Vector3(side * 0.26, height * 0.5, 0), Vector3(0.05, height + 0.2, 0.05), _flat(str(u["post"]), 0.5, cache))
			_box(h, Vector3(0, height, 0), Vector3(0.6, 0.42, 0.05), body)
			_box(h, Vector3(0, height + 0.02, 0.028), Vector3(0.5, 0.3, 0.008), _unshaded(str(u["plate"]), cache))
			_box(h, Vector3(0, height - 0.18, 0.028), Vector3(0.56, 0.035, 0.008), _flat(str(u["hazard"]), 0.5, cache))
		_:
			_post(h, height - head.y * 0.5, u, cache)
			_cabinet_head(h, height, head, body, trim, u, cache)
			_head_detail(h, kind, height, head, u, cache)


static func _post(h: Node3D, top: float, u: Dictionary, cache: Dictionary) -> void:
	var mat: Material = _flat(str(u["post"]), 0.5, cache)
	var r: float = float(u["post_radius"])
	var post: MeshInstance3D = MeshInstance3D.new()
	var cyl: CylinderMesh = CylinderMesh.new()
	cyl.top_radius = r
	cyl.bottom_radius = r
	cyl.height = top
	post.mesh = cyl
	post.material_override = mat
	post.position = Vector3(0, top * 0.5, 0)
	h.add_child(post)
	var base: Vector3 = _v3(u["base_size"])
	_box(h, Vector3(0, base.y * 0.5, 0), base, mat)


## Alder cabinet language at unit scale: body, overhanging cap, door seam, handle, white plate, hazard stripe.
static func _cabinet_head(h: Node3D, y: float, s: Vector3, body: Material, trim: Material, u: Dictionary,
		cache: Dictionary) -> void:
	var front: float = s.z * 0.5 + 0.004
	_box(h, Vector3(0, y, 0), s, body)
	_box(h, Vector3(0, y + s.y * 0.5 + 0.015, -0.01), Vector3(s.x + 0.04, 0.03, s.z + 0.05), trim)
	_box(h, Vector3(s.x * 0.18, y, front), Vector3(0.008, s.y - 0.04, 0.006), trim)
	_box(h, Vector3(s.x * 0.18 + 0.04, y, front + 0.008), Vector3(0.016, 0.07, 0.016), _flat("#C9CED2", 0.3, cache))
	_box(h, Vector3(0, y - s.y * 0.5 + 0.03, front), Vector3(s.x - 0.03, 0.025, 0.006), _flat(str(u["hazard"]), 0.5, cache))


static func _head_detail(h: Node3D, kind: String, y: float, s: Vector3, u: Dictionary, cache: Dictionary) -> void:
	var front: float = s.z * 0.5 + 0.006
	match kind:
		"meter":
			var gauge: MeshInstance3D = MeshInstance3D.new()
			var disc: CylinderMesh = CylinderMesh.new()
			disc.top_radius = s.y * 0.28
			disc.bottom_radius = s.y * 0.28
			disc.height = 0.012
			gauge.mesh = disc
			gauge.material_override = _unshaded(str(u["gauge"]), cache)
			gauge.position = Vector3(-s.x * 0.15, y + 0.02, front)
			gauge.rotation_degrees.x = 90.0
			h.add_child(gauge)
			var needle: MeshInstance3D = _box(h, Vector3(-s.x * 0.15, y + 0.04, front + 0.01), Vector3(0.006, s.y * 0.22, 0.004),
				_flat(str(u["lever"]), 0.4, cache))
			needle.rotation_degrees.z = -35.0
		"switch":
			var lever: MeshInstance3D = _box(h, Vector3(-s.x * 0.15, y + 0.03, front + 0.05), Vector3(0.03, 0.03, 0.12),
				_flat(str(u["lever"]), 0.4, cache))
			lever.rotation_degrees.x = -30.0
			_box(h, Vector3(-s.x * 0.15, y + 0.03, front + 0.005), Vector3(0.07, 0.1, 0.01), _flat("#1D2328", 0.5, cache))
		_:
			_box(h, Vector3(-s.x * 0.12, y + s.y * 0.18, front), Vector3(s.x * 0.5, s.y * 0.26, 0.006), _unshaded(str(u["plate"]), cache))
			for i: int in 3:
				_box(h, Vector3(-s.x * 0.12, y - s.y * 0.06 - i * 0.03, front), Vector3(s.x * 0.45, 0.012, 0.006),
					_flat(str(u["trim"]), 0.6, cache))


# --- Crew work lights ---------------------------------------------------------------------------------------------

static func _work_lights(root: Node3D, w: Dictionary, centres: Array[Vector3], cache: Dictionary) -> int:
	var frame: Material = _flat(str(w["frame"]), 0.5, cache)
	var lens: Material = _emissive(str(w["lens"]), float(w["lens_energy"]), cache)
	var mast: float = float(w["mast_height"])
	var head: Vector3 = _v3(w["head_size"])
	var count: int = 0
	for i: int in centres.size():
		var h: Node3D = Node3D.new()
		h.name = "WorkLight%02d" % (i + 1)
		root.add_child(h)
		var c: Vector3 = centres[i]
		# Stand the tripod on the approach side (toward the previous station, or the spawn side for the first), off to
		# one side of the path, so it lights the fronts the player walks up to and never stands inside the hub.
		var back: Vector3 = Vector3.BACK if i == 0 else Vector3(centres[i - 1].x - c.x, 0.0, centres[i - 1].z - c.z).normalized()
		var side: Vector3 = Vector3(-back.z, 0.0, back.x)
		h.position = Vector3(c.x, 0.0, c.z) + back * float(w["back_m"]) + side * float(w["side_m"])
		# Tripod: three splayed legs, a mast, a lamp head aimed back at the hub.
		for leg: int in 3:
			var angle: float = TAU * float(leg) / 3.0
			var foot: Vector3 = Vector3(cos(angle) * 0.45, 0.0, sin(angle) * 0.45)
			_rod(h, foot, Vector3(0, 0.9, 0), 0.02, frame)
		_rod(h, Vector3(0, 0.9, 0), Vector3(0, mast, 0), 0.025, frame)
		var aim: Vector3 = Vector3(c.x, 0.0, c.z) - h.position
		var lamp: Node3D = Node3D.new()
		lamp.name = "Head"
		h.add_child(lamp)
		lamp.position = Vector3(0, mast, 0)
		lamp.basis = Basis.looking_at(Vector3(aim.x, -1.4, aim.z).normalized(), Vector3.UP)
		_box(lamp, Vector3.ZERO, head, frame)
		_box(lamp, Vector3(0, 0, -head.z * 0.5 - 0.004), Vector3(head.x * 0.86, head.y * 0.8, 0.006), lens)
		var light: OmniLight3D = OmniLight3D.new()
		light.name = "CrewLight"
		light.light_color = Color(str(w["color"]))
		light.light_energy = float(w["energy"])
		light.omni_range = float(w["range"])
		light.omni_attenuation = float(w["attenuation"])
		light.shadow_enabled = false
		light.position = Vector3(0, 0, -0.3)
		lamp.add_child(light)
		count += 1
	return count


# --- Site framing -------------------------------------------------------------------------------------------------

## A boundary wall round the 52 m site in Alder's boundary surface, so the stage reads as a fenced works yard.
static func _perimeter(root: Node3D, p: Dictionary, look: Dictionary, cache: Dictionary) -> void:
	var size: float = Graybox.FLOOR_SIZE_M
	var inset: float = float(p["inset"])
	var h: float = float(p["height"])
	var t: float = float(p["thickness"])
	var wall: Material = StreetLook.surface_material(look["materials"]["boundary"], cache, "look_boundary")
	var cap: Material = _flat(str(p["cap"]), 0.6, cache)
	var group: Node3D = Node3D.new()
	group.name = "Perimeter"
	root.add_child(group)
	var lo: float = inset
	var hi: float = size - inset
	var mid: float = size * 0.5
	var span: float = hi - lo
	for spec: Array in [[Vector3(mid, h * 0.5, lo), Vector3(span, h, t)], [Vector3(mid, h * 0.5, hi), Vector3(span, h, t)],
			[Vector3(lo, h * 0.5, mid), Vector3(t, h, span)], [Vector3(hi, h * 0.5, mid), Vector3(t, h, span)]]:
		var c: Vector3 = spec[0]
		var s: Vector3 = spec[1]
		_box(group, c, s, wall)
		_box(group, Vector3(c.x, h + 0.04, c.z), Vector3(s.x + 0.08, 0.08, s.z + 0.08), cap)


## Dark distant blocks with a few warm windows beyond the wall: the city still has power out there (DS07 skyline).
static func _skyline(root: Node3D, k: Dictionary, cache: Dictionary) -> void:
	var group: Node3D = Node3D.new()
	group.name = "Skyline"
	root.add_child(group)
	var body: Material = _flat(str(k["color"]), 0.9, cache)
	var lit: Material = _emissive(str(k["window"]), float(k["window_energy"]), cache)
	var n: int = int(k["count"])
	var size: float = Graybox.FLOOR_SIZE_M
	var centre: Vector3 = Vector3(size * 0.5, 0.0, size * 0.5)
	var radius: float = size * 0.5 + float(k["distance"])
	for i: int in n:
		# Deterministic layout from the index: no RNG, so every run of a level looks the same.
		var angle: float = TAU * (float(i) + 0.5) / float(n)
		var f: float = fposmod(float(i) * 0.6180339, 1.0)
		var w: float = lerpf(float(k["width_min"]), float(k["width_max"]), f)
		var h: float = lerpf(float(k["height_min"]), float(k["height_max"]), fposmod(f * 7.0, 1.0))
		var pos: Vector3 = centre + Vector3(cos(angle), 0.0, sin(angle)) * (radius + f * 6.0)
		var block: MeshInstance3D = _box(group, Vector3(pos.x, h * 0.5, pos.z), Vector3(w, h, w * 0.8), body)
		block.rotation.y = -angle
		if i % int(k["lit_every"]) == 0:
			_box(block, Vector3(0.0, h * 0.15, -w * 0.4 - 0.02), Vector3(w * 0.15, 0.9, 0.05), lit)


## Alder Street lamps (same spec from the look) beside the path between stations; fades with distance like Alder's.
static func _lamps(root: Node3D, l: Dictionary, s: Dictionary, centres: Array[Vector3], cache: Dictionary) -> int:
	var count: int = 0
	var pole_mat: Material = _flat(str(s["pole_color"]), 0.5, cache)
	var lens: Material = _emissive(str(s["lens_color"]), float(s["lens_emission_percent"]) / 100.0, cache)
	var height: float = float(s["pole_height_cm"]) / 100.0
	var arm: float = float(s["arm_cm"]) / 100.0
	var head: Vector3 = Vector3(float(s["head_cm"][0]), float(s["head_cm"][1]), float(s["head_cm"][2])) / 100.0
	for i: int in mini(centres.size() - 1, int(l["max"])):
		var a: Vector3 = centres[i]
		var b: Vector3 = centres[i + 1]
		var along: Vector3 = Vector3(b.x - a.x, 0.0, b.z - a.z).normalized()
		var side: Vector3 = Vector3(-along.z, 0.0, along.x) * (float(l["side_offset"]) * (1.0 if i % 2 == 0 else -1.0))
		var h: Node3D = Node3D.new()
		h.name = "Lamp%d" % i
		root.add_child(h)
		h.position = Vector3((a.x + b.x) * 0.5, 0.0, (a.z + b.z) * 0.5) + side
		h.basis = Basis.looking_at(side.normalized(), Vector3.UP)
		_rod(h, Vector3.ZERO, Vector3(0, height, 0), float(s["pole_radius_cm"]) / 100.0, pole_mat)
		_box(h, Vector3(0, height - 0.05, arm * 0.5), Vector3(0.07, 0.07, arm), pole_mat)
		_box(h, Vector3(0, height, arm), head, pole_mat)
		_box(h, Vector3(0, height - head.y * 0.5 - 0.01, arm), Vector3(head.x * 0.85, 0.02, head.z * 0.8), lens)
		var light: SpotLight3D = SpotLight3D.new()
		light.light_color = Color(str(s["light_color"]))
		light.light_energy = float(s["light_energy_percent"]) / 100.0
		light.spot_range = float(s["light_range_cm"]) / 100.0
		light.spot_angle = float(s["light_angle_deg"])
		light.spot_attenuation = float(s["light_attenuation_percent"]) / 100.0
		light.shadow_enabled = false
		light.distance_fade_enabled = true
		light.distance_fade_begin = float(s["light_fade_begin_cm"]) / 100.0
		light.distance_fade_length = float(s["light_fade_length_cm"]) / 100.0
		light.position = Vector3(0, height - head.y, arm)
		light.rotation_degrees = Vector3(-90, 0, 0)
		h.add_child(light)
		count += 1
	return count


# --- Primitives ---------------------------------------------------------------------------------------------------

static func _v3(a: Array) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


static func _box(parent: Node3D, center: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var mi: MeshInstance3D = MeshInstance3D.new()
	var box: BoxMesh = BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.material_override = mat
	mi.position = center
	parent.add_child(mi)
	return mi


static func _rod(parent: Node3D, a: Vector3, b: Vector3, radius: float, mat: Material) -> void:
	var mi: MeshInstance3D = MeshInstance3D.new()
	var cyl: CylinderMesh = CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = a.distance_to(b)
	mi.mesh = cyl
	mi.material_override = mat
	parent.add_child(mi)
	var dir: Vector3 = (b - a).normalized()
	var side: Vector3 = Vector3.RIGHT if absf(dir.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD
	var x: Vector3 = side.cross(dir).normalized()
	mi.transform = Transform3D(Basis(x, dir, x.cross(dir)), (a + b) * 0.5)


static func _flat(hex: String, roughness: float, cache: Dictionary) -> StandardMaterial3D:
	var key: String = "flat_%s_%d" % [hex, roundi(roughness * 100.0)]
	if not cache.has(key):
		var m: StandardMaterial3D = StandardMaterial3D.new()
		m.albedo_color = Color(hex)
		m.roughness = roughness
		cache[key] = m
	return cache[key]


static func _unshaded(hex: String, cache: Dictionary) -> StandardMaterial3D:
	var key: String = "unshaded_" + hex
	if not cache.has(key):
		var m: StandardMaterial3D = StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(hex)
		cache[key] = m
	return cache[key]


static func _emissive(hex: String, energy: float, cache: Dictionary) -> StandardMaterial3D:
	var key: String = "emissive_%s_%d" % [hex, roundi(energy * 100.0)]
	if not cache.has(key):
		var m: StandardMaterial3D = StandardMaterial3D.new()
		m.albedo_color = Color(hex)
		m.emission_enabled = true
		m.emission = Color(hex)
		m.emission_energy_multiplier = energy
		cache[key] = m
	return cache[key]
