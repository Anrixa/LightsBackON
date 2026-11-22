extends RefCounted
## EXP019 A01 — physical, source-bound geometry for all 200 expedition worksites.
## Adds collision only to opt-in expedition stages. EXP017 previews remain
## non-colliding; C01–C12 world, player, host, saves and rewards are unchanged.
const Access := preload("res://scripts/world/exp017_site_access.gd")
const QUALIFICATION: String = "AUTOMATED_GEOMETRY_AND_PHYSICS_ONLY_CONTROLLER_RELEASE_HELD"
const WIDTH_M: float = 1.75
const RAMP_FRACTION: float = 0.28
const GROUND_Y: float = -0.08
const THICKNESS_M: float = 0.16
const MAX_RISE_RATIO: float = 0.55


static func _reject(code: String) -> Dictionary:
	return {"ok": false, "code": code, "qualification": QUALIFICATION}


static func _planar(point: Vector3, y: float = GROUND_Y) -> Vector3:
	return Vector3(point.x, y, point.z)


static func _inside(point: Vector3) -> bool:
	return point.is_finite() and point.x >= 2.0 and point.x <= 50.0 and \
			point.z >= 2.0 and point.z <= 50.0


## Independent route audit: four continuous traversable ramps/spans and four
## alternative ground detours. Every segment's slope and tile bounds are checked
## before any physics body is created. Task positions are never moved.
static func inspect(plan: Dictionary) -> Dictionary:
	var source: Dictionary = Access.inspect(plan)
	if not bool(source.get("ok", false)):
		return _reject("EXP019_A01_UNQUALIFIED_EXP017_SOURCE")
	var points: Array = source["points"]
	var serial: int = int(plan["serial"])
	var routes: Array[Dictionary] = []
	for i: int in range(4):
		var a: Vector3 = points[i]
		var b: Vector3 = points[i + 1]
		var along: Vector3 = b - a
		along.y = 0.0
		var distance: float = along.length()
		if distance < 7.0:
			return _reject("EXP019_A01_TOO_SHORT_FOR_SAFE_RAMP")
		var side: Vector3 = Vector3(-along.z, 0.0, along.x).normalized()
		var midpoint: Vector3 = _planar(a.lerp(b, 0.5))
		var option_a: Vector3 = midpoint + side * 3.0
		var option_b: Vector3 = midpoint - side * 3.0
		var detour: Vector3 = option_a if _inside(option_a) else option_b
		var height: float = 0.94 + float((serial + i) % 3) * 0.07
		var rise_ratio: float = height / (distance * RAMP_FRACTION)
		if rise_ratio > MAX_RISE_RATIO or not _inside(detour):
			return _reject("EXP019_A01_INSUFFICIENT_SLOPE_OR_DETOUR")
		var up_a: Vector3 = _planar(a.lerp(b, RAMP_FRACTION), height - THICKNESS_M * 0.5)
		var up_b: Vector3 = _planar(a.lerp(b, 1.0 - RAMP_FRACTION), height - THICKNESS_M * 0.5)
		var begin: Vector3 = _planar(a)
		var finish: Vector3 = _planar(b)
		for point: Vector3 in [begin, up_a, up_b, finish, detour]:
			if not _inside(point):
				return _reject("EXP019_A01_ROUTE_OUTSIDE_TILE")
		routes.append({"index": i, "start": begin, "rise": up_a,
			"crest": up_b, "finish": finish, "detour": detour,
			"barrier": midpoint, "side": side, "height_m": height,
			"slope_ratio": rise_ratio, "distance_m": distance})
	var fingerprint: String = ("%s|%s|%s|%s" % [
		source["level_id"], source["layout_signature"],
		source["access"], source["barrier"]]).sha256_text()
	return {"ok": true, "level_id": source["level_id"],
		"location_id": source["location_id"], "region_id": source["region_id"],
		"routes": routes, "signature": fingerprint,
		"surface_count": 4 * 5, "barrier_count": 4,
		"qualification": QUALIFICATION, "physical_collision": true,
		"human_controller_certified": false}


static func _material(color: Color) -> StandardMaterial3D:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.83
	return mat


## Mesh and BoxShape use identical transforms. Tilted collision is real, not
## painted stair/ramp geometry. Geometry is authored into collision layer 1.
static func _beam(body: StaticBody3D, name: String, a: Vector3, b: Vector3,
		width: float, thickness: float, material: Material) -> void:
	var diff: Vector3 = b - a
	if diff.length() < 0.01:
		return
	var length: float = diff.length()
	var size: Vector3 = Vector3(width, thickness, length + 0.04)
	var transform: Transform3D = Transform3D(
		Basis.looking_at(-diff.normalized(), Vector3.UP), (a + b) * 0.5)
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = size
	var surface: MeshInstance3D = MeshInstance3D.new()
	surface.name = name
	surface.mesh = mesh
	surface.material_override = material
	surface.transform = transform
	body.add_child(surface)
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = size
	var collision: CollisionShape3D = CollisionShape3D.new()
	collision.name = name + "_Collision"
	collision.shape = shape
	collision.transform = transform
	body.add_child(collision)


static func _block(body: StaticBody3D, name: String, where: Vector3,
		size: Vector3, yaw: float, material: Material) -> void:
	var a: Vector3 = Vector3(0, 0, -size.z * 0.5)
	var b: Vector3 = Vector3(0, 0, size.z * 0.5)
	var basis: Basis = Basis(Vector3.UP, yaw)
	var m: Vector3 = where + basis * a
	var n: Vector3 = where + basis * b
	_beam(body, name, m, n, size.x, size.y, material)


static func build(plan: Dictionary, preview: Node3D) -> Node3D:
	var audit: Dictionary = inspect(plan)
	if not bool(audit.get("ok", false)) or preview == null or \
			str(preview.get_meta("source_level_id", "")) != str(audit["level_id"]) or \
			preview.get_node_or_null("CandidateGround/FoundationCollision") == null or \
			preview.get_node_or_null("EXP017_A02_SiteAccess") == null:
		return null
	var root: Node3D = Node3D.new()
	root.name = "EXP019_A01_PhysicalWorksite"
	root.set_meta("source_level_id", audit["level_id"])
	root.set_meta("source_location_id", audit["location_id"])
	root.set_meta("source_region_id", audit["region_id"])
	root.set_meta("route_signature", audit["signature"])
	root.set_meta("qualification", QUALIFICATION)
	var body: StaticBody3D = StaticBody3D.new()
	body.name = "PhysicalSurfaces"
	body.collision_layer = 1
	body.collision_mask = 1
	root.add_child(body)
	var catwalk: Material = _material(Color("#9AAFB6"))
	var pavement: Material = _material(Color("#756D59"))
	var obstacle: Material = _material(Color("#A5574A"))
	var tread: Material = _material(Color("#D8B783"))
	for route: Dictionary in audit["routes"]:
		var i: int = int(route["index"])
		var points: Array[Vector3] = [route["start"], route["rise"],
			route["crest"], route["finish"]]
		for segment: int in range(3):
			_beam(body, "Raised%02d_Segment%d" % [i, segment],
				points[segment], points[segment + 1], WIDTH_M,
				THICKNESS_M, catwalk)
		_beam(body, "Detour%02d_Entry" % i, route["start"],
			route["detour"], 1.55, 0.10, pavement)
		_beam(body, "Detour%02d_Exit" % i, route["detour"],
			route["finish"], 1.55, 0.10, pavement)
		var direction: Vector3 = route["finish"] - route["start"]
		var angle: float = atan2(direction.x, direction.z)
		var midway: Vector3 = route["barrier"]
		_block(body, "BlockedDirectPath%02d" % i,
			Vector3(midway.x, 0.34, midway.z),
			Vector3(2.35, 0.68, 0.55), angle, obstacle)
		# Collidable stair treads beside the always-present accessible ramp.
		# The controller's autonomous step-up is NOT certified by these treads.
		var side: Vector3 = route["side"]
		for step: int in range(7):
			var t: float = (float(step) + 0.5) / 7.0
			var point: Vector3 = route["start"].lerp(route["rise"], t) + side * 2.4
			var altitude: float = float(route["height_m"]) * (float(step) + 1.0) / 7.0
			_block(body, "Stair%02d_%02d" % [i, step],
				Vector3(point.x, altitude * 0.5, point.z),
				Vector3(1.1, altitude, maxf(0.65, float(route["distance_m"]) * RAMP_FRACTION / 7.0)),
				angle, tread)
	return root
