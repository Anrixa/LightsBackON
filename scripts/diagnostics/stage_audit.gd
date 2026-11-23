extends RefCounted
## DS stage audit: scene-graph checks for every playable dispatch level (owner request, 23 Nov 2026: "every stage,
## level and playable area should be checked and accurately designed"). Read-only: it inspects a built stage and
## reports defects; it never changes host state. Used by tests/integration/test_DS_stage_audit.gd and by the
## internal audit runner. Geometry is judged from world AABBs, so it is cheap enough to run on all 200 levels.
## audit_location() runs the same kind of checks on a designed location (RB02, ADR-019 quality gates) from its manifest.

const Spawn := preload("res://scripts/world/dispatch_spawn.gd")
const LocationData := preload("res://scripts/world/location_data.gd")
const ReachGrid := preload("res://scripts/diagnostics/reach_grid.gd")
const InteractionVisibility := preload("res://scripts/interaction/interaction_visibility.gd")
const SOLO_TUNING_PATH: String = "res://content/offline_solo.json"
## Markers a player works at: they must be reached on foot and seen with the interaction ray. Anchors are stood on.
const REACH_KINDS: Array[String] = ["panel", "switch", "consumer"]
const ANCHOR_REACH_M: float = 1.0
const ANCHOR_FLOOR_M: float = 0.3
const DEFAULT_SELECTION_RADIUS_CM: int = 45
## Opening shot: judged at 16:9 (the 1920x1080 evidence size). A wall is a non-floor surface hit within NEAR_WALL_M;
## the shot fails when walls fill more than the location's max_near_wall_percent of a SHOT_COLUMNS x SHOT_ROWS ray grid.
const SHOT_ASPECT: float = 16.0 / 9.0
const NEAR_WALL_M: float = 3.0
const FLOOR_NORMAL_Y: float = 0.5
const SHOT_COLUMNS: int = 32
const SHOT_ROWS: int = 18
## A landmark counts as framed when this share of its LANDMARK_SAMPLES face points are in the frame and in plain sight.
const FRAMED_SHARE: float = 0.5
const LANDMARK_SAMPLES: int = 9
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


## `ignore` lists node paths under `world` (the node and everything below it) to leave out: IGNORE_ROOTS for a
## dispatch stage, audit.backdrop for a location.
static func _boxes(world: Node3D, ignore: Array[String] = IGNORE_ROOTS) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for node: Node in world.find_children("*", "GeometryInstance3D", true, false):
		var g: GeometryInstance3D = node as GeometryInstance3D
		if g is Label3D or not g.is_visible_in_tree():
			continue
		var path: String = str(world.get_path_to(g))
		if _ignored(path, ignore):
			continue
		var aabb: AABB = g.global_transform * g.get_aabb()
		if aabb.size.length() < 0.001:
			continue
		out.append({"path": path, "aabb": aabb, "airborne": _airborne(path)})
	return out


static func _ignored(path: String, ignore: Array[String]) -> bool:
	for root: String in ignore:
		if path == root or path.begins_with(root + "/"):
			return true
	return false


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


# --- RB02: designed locations ---------------------------------------------------------------------------------------

## Audits a built location `world` (the district scene, dressed, inside the running SceneTree so physics answers) from
## its bundle (LocationData.load_location). Returns {"ok", "floating", "out_of_bounds", "unreachable", "spawns",
## "opening_shot", "meshes", "targets"}. Checks: nothing floats; nothing but the declared backdrop leaves the envelope;
## every panel, switch and consumer marker is reached on foot from the opening spawn and seen with the interaction ray,
## and every anchor is stood on; every crew spawn is clear; the opening shot frames the hero landmark and the first
## job, and no wall fills the frame.
static func audit_location(world: Node3D, bundle: Dictionary) -> Dictionary:
	var m: Dictionary = bundle["manifest"]
	var lay: Dictionary = LocationData.layout(bundle)
	var dims: Dictionary = LocationData.dimensions()
	var solo: Dictionary = LocationData._json(SOLO_TUNING_PATH) as Dictionary
	var backdrop: Array[String] = []
	for p: Variant in m["audit"]["backdrop"]:
		backdrop.append(str(p))
	var boxes: Array[Dictionary] = _boxes(world, backdrop)
	var env: Vector2 = Vector2(float(lay["envelope_cm"][0]), float(lay["envelope_cm"][1])) / 100.0
	var outside: Array[String] = []
	for b: Dictionary in boxes:
		var c: Vector3 = (b["aabb"] as AABB).get_center()
		if c.x < -0.5 or c.z < -0.5 or c.x > env.x + 0.5 or c.z > env.y + 0.5:
			outside.append(str(b["path"]))
	var space: PhysicsDirectSpaceState3D = world.get_world_3d().direct_space_state
	var grid: ReachGrid = ReachGrid.new()
	grid.setup(space, dims, lay["envelope_cm"])
	grid.build_grid()
	var start: Vector3 = _marker_m(bundle, LocationData.spawn_marker_id(bundle))
	var parent: PackedInt32Array = grid.search(grid.cell_of(start))
	var unreachable: Array[String] = []
	var targets: int = 0
	for mk: Dictionary in lay["markers"]:
		var kind: String = str(mk["kind"])
		if not REACH_KINDS.has(kind) and kind != "anchor":
			continue
		targets += 1
		var radius_cm: float = float((solo["selection_radius_cm"] as Dictionary).get(kind, DEFAULT_SELECTION_RADIUS_CM))
		if not _reached(grid, parent, space, _marker_m(bundle, str(mk["id"])), kind, dims, radius_cm / 100.0):
			unreachable.append(str(mk["id"]))
	var spawns: Dictionary = {}
	var spawns_ok: bool = true
	for id: Variant in m["spawn"]["markers"]:
		var p: Vector3 = _marker_m(bundle, str(id))
		var inside: bool = p.x > 0.5 and p.z > 0.5 and p.x < env.x - 0.5 and p.z < env.y - 0.5
		var clear: bool = inside and grid.capsule_fits(p) and grid.standable(grid.cell_of(p))
		spawns[str(id)] = clear
		spawns_ok = spawns_ok and clear
	var shot: Dictionary = opening_shot(world, bundle, int(solo["camera"]["fov_deg"]),
		float(dims["camera_height_cm"]) / 100.0)
	var floating: Array[String] = _floating(boxes)
	var ok: bool = floating.is_empty() and outside.is_empty() and unreachable.is_empty() and spawns_ok and bool(shot["ok"])
	return {"ok": ok, "floating": floating, "out_of_bounds": outside, "unreachable": unreachable, "spawns": spawns,
		"opening_shot": shot, "meshes": boxes.size(), "targets": targets}


static func _marker_m(bundle: Dictionary, id: String) -> Vector3:
	var pos: Array = LocationData.marker(bundle, id)["pos_cm"]
	return Vector3(float(pos[0]), float(pos[1]), float(pos[2])) / 100.0


## True when a cell connected to the spawn lets the player work the target: for an anchor, a cell within
## ANCHOR_REACH_M on the anchor's floor; otherwise an eye point from which the host's own sight check passes.
static func _reached(grid: ReachGrid, parent: PackedInt32Array, space: PhysicsDirectSpaceState3D, pos: Vector3,
		kind: String, dims: Dictionary, radius_m: float) -> bool:
	var reach_m: float = float(dims["interact_ray_cm"]) / 100.0
	var eye_m: float = float(dims["camera_height_cm"]) / 100.0
	var r: int = ceili((reach_m + radius_m) / ReachGrid.CELL_M) + 1
	var c: int = grid.cell_of(pos)
	for dj: int in range(-r, r + 1):
		for di: int in range(-r, r + 1):
			var i: int = c % grid.nx + di
			var j: int = c / grid.nx + dj
			if i < 0 or j < 0 or i >= grid.nx or j >= grid.nz or parent[i + j * grid.nx] == -1:
				continue
			var f: Vector3 = grid.feet(i + j * grid.nx)
			if kind == "anchor":
				if Vector2(f.x - pos.x, f.z - pos.z).length() <= ANCHOR_REACH_M and absf(f.y - pos.y) <= ANCHOR_FLOOR_M:
					return true
			elif InteractionVisibility.can_reach(space, f + Vector3(0.0, eye_m, 0.0), pos, reach_m, radius_m):
				return true
	return false


## The first view a player gets: from the opening spawn's eye, at the opening-shot yaw and pitch. Returns {"ok",
## "hero", "hero_framed_share", "first_job", "first_job_framed_share", "near_wall_percent", ...}. A target is framed
## when at least FRAMED_SHARE of points sampled over its box face are in the frame and their sight ray first hits the
## target itself (or nothing).
static func opening_shot(world: Node3D, bundle: Dictionary, fov_deg: int, eye_height_m: float) -> Dictionary:
	var m: Dictionary = bundle["manifest"]
	var shot: Dictionary = m["spawn"]["opening_shot"]
	var eye: Vector3 = _marker_m(bundle, str(shot["from"])) + Vector3(0.0, eye_height_m, 0.0)
	var basis: Basis = Basis.from_euler(Vector3(deg_to_rad(float(shot["pitch_deg"])),
		deg_to_rad(float(shot["yaw_deg"])), 0.0))
	var space: PhysicsDirectSpaceState3D = world.get_world_3d().direct_space_state
	var hero: Dictionary = {}
	for lm: Dictionary in m["landmarks"]:
		if str(lm["role"]) == "hero":
			hero = lm["ref"]
	var tan_v: float = tan(deg_to_rad(float(fov_deg)) * 0.5)
	var hero_share: float = _framed_share(world, space, eye, basis, tan_v, hero)
	var job_share: float = _framed_share(world, space, eye, basis, tan_v, shot["first_job"])
	var walls: int = 0
	for row: int in SHOT_ROWS:
		for col: int in SHOT_COLUMNS:
			var u: float = ((float(col) + 0.5) / float(SHOT_COLUMNS) * 2.0 - 1.0) * tan_v * SHOT_ASPECT
			var v: float = (1.0 - (float(row) + 0.5) / float(SHOT_ROWS) * 2.0) * tan_v
			var dir: Vector3 = (basis * Vector3(u, v, -1.0)).normalized()
			var hit: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(eye, eye + dir * NEAR_WALL_M))
			if not hit.is_empty() and absf((hit["normal"] as Vector3).y) < FLOOR_NORMAL_Y:
				walls += 1
	var near_pct: int = roundi(100.0 * float(walls) / float(SHOT_ROWS * SHOT_COLUMNS))
	var ok: bool = hero_share >= FRAMED_SHARE and job_share >= FRAMED_SHARE \
		and near_pct <= int(shot["max_near_wall_percent"])
	return {"ok": ok, "hero": hero, "hero_framed_share": hero_share, "first_job": shot["first_job"],
		"first_job_framed_share": job_share, "near_wall_percent": near_pct, "eye": eye,
		"yaw_deg": int(shot["yaw_deg"]), "fov_deg": fov_deg}


## Share of LANDMARK_SAMPLES points over the referenced node's nearest box face that are in the frame and in plain sight.
static func _framed_share(world: Node3D, space: PhysicsDirectSpaceState3D, eye: Vector3, basis: Basis, tan_v: float,
		ref: Dictionary) -> float:
	var target: Node3D = _ref_node(world, ref)
	if target == null:
		return 0.0
	var box: AABB = _node_box(target)
	if box.size == Vector3.ZERO:
		return 0.0
	var seen: int = 0
	var inv: Basis = basis.inverse()
	for sx: int in 3:
		for sy: int in 3:
			# a 3 x 3 spread over the face, kept inside the box edges
			var p: Vector3 = _face_point(box, eye, 0.2 + 0.3 * float(sx), 0.2 + 0.3 * float(sy))
			var local: Vector3 = inv * (p - eye)
			if local.z >= 0.0 or absf(local.x / -local.z) > tan_v * SHOT_ASPECT or absf(local.y / -local.z) > tan_v:
				continue
			var hit: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(eye, p))
			if hit.is_empty() or (hit["position"] as Vector3).distance_to(p) < 0.05 \
					or hit["collider"] == target or target.is_ancestor_of(hit["collider"] as Node):
				seen += 1
	return float(seen) / float(LANDMARK_SAMPLES)


## A point on the box face that looks toward the eye; fx runs along the face, fy up it. 1 cm outside the face, so the
## sight ray ends in front of the surface it is testing.
static func _face_point(box: AABB, eye: Vector3, fx: float, fy: float) -> Vector3:
	var d: Vector3 = eye - box.get_center()
	var y: float = box.position.y + box.size.y * fy
	if absf(d.x) * box.size.z >= absf(d.z) * box.size.x:
		var x: float = box.end.x + 0.01 if d.x > 0.0 else box.position.x - 0.01
		return Vector3(x, y, box.position.z + box.size.z * fx)
	var z: float = box.end.z + 0.01 if d.z > 0.0 else box.position.z - 0.01
	return Vector3(box.position.x + box.size.x * fx, y, z)


static func _ref_node(world: Node3D, ref: Dictionary) -> Node3D:
	var kind: String = str(ref.keys()[0])
	var group: String = str({"building": "Buildings", "prop": "Props", "marker": "Markers"}.get(kind, ""))
	return world.get_node_or_null(NodePath(group + "/" + str(ref[kind]))) as Node3D


## World box of a node's box collision shapes (the solid the player sees), else of its meshes.
static func _node_box(node: Node3D) -> AABB:
	var out: AABB = AABB()
	var any: bool = false
	for child: Node in node.find_children("*", "CollisionShape3D", true, false):
		var cs: CollisionShape3D = child as CollisionShape3D
		if cs.shape is BoxShape3D:
			var size: Vector3 = (cs.shape as BoxShape3D).size
			var b: AABB = cs.global_transform * AABB(-size * 0.5, size)
			out = b if not any else out.merge(b)
			any = true
	if any:
		return out
	var meshes: Array[Node] = node.find_children("*", "GeometryInstance3D", true, false)
	if node is GeometryInstance3D:
		meshes.append(node)
	for child: Node in meshes:
		var g: GeometryInstance3D = child as GeometryInstance3D
		var b: AABB = g.global_transform * g.get_aabb()
		out = b if not any else out.merge(b)
		any = true
	return out
