extends RefCounted
## DS stage audit: scene-graph checks for every playable dispatch level (owner request, 23 Nov 2026: "every stage,
## level and playable area should be checked and accurately designed"). Read-only: it inspects a built stage and
## reports defects; it never changes host state. Used by tests/integration/test_DS_stage_audit.gd and by the
## internal audit runner. Geometry is judged from world AABBs, so it is cheap enough to run on all 200 levels.

const Spawn := preload("res://scripts/world/dispatch_spawn.gd")
const FLOOR_SIZE_M: float = 52.0
## A visible mesh whose bottom is this far above everything under it, with nothing holding it up, is "floating".
const FLOAT_GAP_M: float = 0.3
## Meshes named here are schematic overhead runs drawn between targets (procedure conduits, cables, glows).
const AIRBORNE_HINTS: Array[String] = ["Operation_", "Cable", "Wire", "Glow"]
const IGNORE_ROOTS: Array[String] = ["DispatchStageLook"]
const TARGET_PROBE_RADIUS_M: float = 0.12
const CONTACT_M: float = 0.03
const STATION_CLEAR_M: float = 0.8
const HUB_FURNITURE_M: float = 2.2
## Building-sized volumes only; posts, units and rails near a station are furniture.
const BUILDING_FOOTPRINT_M2: float = 6.0


## Returns {"ok": bool, "floating": [...], "out_of_bounds": [...], "buried_targets": [...], "spawn": {...}}.
static func audit(stage: Node3D) -> Dictionary:
	var world: Node3D = stage.get_node_or_null("ExpeditionWorld") as Node3D
	if world == null:
		return {"ok": false, "code": "NO_WORLD"}
	var boxes: Array[Dictionary] = _boxes(world)
	var floating: Array[String] = _floating(boxes)
	var outside: Array[String] = []
	for b: Dictionary in boxes:
		var a: AABB = b["aabb"]
		var c: Vector3 = a.get_center()
		if c.x < -0.5 or c.z < -0.5 or c.x > FLOOR_SIZE_M + 0.5 or c.z > FLOOR_SIZE_M + 0.5:
			outside.append(str(b["path"]))
	var buried: Array[String] = _buried_targets(stage)
	var enclosed: Array[String] = _enclosed_stations(world)
	var spawn: Dictionary = _spawn(stage)
	return {"ok": floating.is_empty() and outside.is_empty() and buried.is_empty() and enclosed.is_empty() and
		bool(spawn.get("ok", false)), "floating": floating, "out_of_bounds": outside, "buried_targets": buried,
		"enclosed_stations": enclosed, "spawn": spawn, "meshes": boxes.size()}


static func _boxes(world: Node3D) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for node: Node in world.find_children("*", "GeometryInstance3D", true, false):
		var g: GeometryInstance3D = node as GeometryInstance3D
		if g is Label3D or not g.is_visible_in_tree():
			continue
		var path: String = str(world.get_path_to(g))
		if IGNORE_ROOTS.has(path.get_slice("/", 0)):
			continue
		var aabb: AABB = g.global_transform * g.get_aabb()
		if aabb.size.length() < 0.001:
			continue
		out.append({"path": path, "aabb": aabb, "airborne": _airborne(path)})
	return out


static func _airborne(path: String) -> bool:
	for hint: String in AIRBORNE_HINTS:
		if path.contains(hint):
			return true
	return false


## A mesh floats when nothing connects it to the ground: support spreads from meshes that touch the floor through
## any mesh whose box touches it (a vane bolted to a housing, a brace hanging from a span), so a part counts as held
## only if a chain of touching parts reaches the ground.
static func _floating(boxes: Array[Dictionary]) -> Array[String]:
	var held: Array[bool] = []
	var frontier: Array[int] = []
	for i: int in boxes.size():
		var grounded: bool = bool(boxes[i]["airborne"]) or (boxes[i]["aabb"] as AABB).position.y <= FLOAT_GAP_M
		held.append(grounded)
		if grounded:
			frontier.append(i)
	while not frontier.is_empty():
		var i: int = frontier.pop_back()
		var a: AABB = (boxes[i]["aabb"] as AABB).grow(CONTACT_M)
		for j: int in boxes.size():
			if not held[j] and a.intersects(boxes[j]["aabb"]):
				held[j] = true
				frontier.append(j)
	var out: Array[String] = []
	for i: int in boxes.size():
		if not held[i]:
			out.append("%s (bottom %.2f m)" % [boxes[i]["path"], (boxes[i]["aabb"] as AABB).position.y])
	return out


## A station must stand in the open: a building volume (mesh-only landmarks do not collide) round a station put the
## player inside walls to work. Station furniture within HUB_FURNITURE_M of the station is allowed.
static func _enclosed_stations(world: Node3D) -> Array[String]:
	var out: Array[String] = []
	var stations: Node = world.get_node_or_null("Stations")
	if stations == null:
		return out
	var solids: Array[AABB] = Spawn.solids(world)
	for node: Node in stations.get_children():
		var p: Vector3 = (node as Node3D).global_position
		var probe: AABB = AABB(Vector3(p.x - STATION_CLEAR_M, 0.6, p.z - STATION_CLEAR_M),
			Vector3(STATION_CLEAR_M * 2.0, 1.0, STATION_CLEAR_M * 2.0))
		for box: AABB in solids:
			var c: Vector3 = box.get_center()
			if Vector2(c.x - p.x, c.z - p.z).length() < HUB_FURNITURE_M:
				continue
			if box.size.x * box.size.z >= BUILDING_FOOTPRINT_M2 and box.intersects(probe):
				out.append("%s in %s" % [node.name, str(box)])
				break
	return out


## A host target whose point sits inside a collider cannot be seen or reached cleanly.
static func _buried_targets(stage: Node3D) -> Array[String]:
	var out: Array[String] = []
	var defs: Variant = stage.get("_definitions")
	if not defs is Dictionary or not (defs as Dictionary).get("positions") is Dictionary:
		return out
	var space: PhysicsDirectSpaceState3D = stage.get_world_3d().direct_space_state
	var shape: SphereShape3D = SphereShape3D.new()
	shape.radius = TARGET_PROBE_RADIUS_M
	var query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	var player: CollisionObject3D = stage.get("player") as CollisionObject3D
	if player != null:
		query.exclude = [player.get_rid()]
	for id: String in (defs["positions"] as Dictionary):
		if id == "ZONE_EXTRACT":
			continue
		query.transform = Transform3D(Basis.IDENTITY, defs["positions"][id])
		if not space.intersect_shape(query, 1).is_empty():
			out.append(id)
	return out


## The player must start on open floor inside the site, not inside or on top of geometry.
static func _spawn(stage: Node3D) -> Dictionary:
	var player: CharacterBody3D = stage.get("player") as CharacterBody3D
	if player == null:
		return {"ok": false, "code": "NO_PLAYER"}
	var p: Vector3 = player.global_position
	var inside: bool = p.x > 0.5 and p.z > 0.5 and p.x < FLOOR_SIZE_M - 0.5 and p.z < FLOOR_SIZE_M - 0.5
	var space: PhysicsDirectSpaceState3D = stage.get_world_3d().direct_space_state
	var query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	var capsule: CapsuleShape3D = CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = 1.6
	query.shape = capsule
	query.transform = Transform3D(Basis.IDENTITY, p + Vector3(0, 0.15, 0))
	query.exclude = [player.get_rid()]
	var blocked: bool = not space.intersect_shape(query, 1).is_empty()
	# Landmarks are mesh-only, so a collider test alone let the player start inside a building or facing a wall.
	var world: Node3D = stage.get_node_or_null("ExpeditionWorld") as Node3D
	var solids: Array[AABB] = Spawn.solids(world) if world != null else []
	var in_mesh: bool = Spawn.body_blocked(p, solids)
	var first: Vector3 = Vector3.ZERO
	var stations: Node = world.get_node_or_null("Stations") if world != null else null
	if stations != null and stations.get_child_count() > 0:
		first = (stations.get_child(0) as Node3D).global_position
	var view: bool = Spawn.view_blocked(p, first, solids)
	return {"ok": inside and not blocked and not in_mesh and not view, "position": p, "inside_site": inside,
		"blocked": blocked, "inside_geometry": in_mesh, "view_blocked": view}
