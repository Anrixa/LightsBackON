extends RefCounted
## DS dispatch spawn. A fixed "5.5 m behind station 01 on +Z" spawn put the player against or inside a landmark
## building on about half the levels (landmarks are mesh-only, so nothing stopped it), and was clamped back into
## the station's sign stack where station 01 sits near the site edge. This picks a spawn from candidates round
## station 01: inside the site, clear of every visible solid mesh, with an unobstructed view of the station, preferring
## the approach from behind (away from station 02), and faces the player at the station.
## Presentation and placement only: host checks keep measuring from the player's real position.

const SITE_MIN_M: float = 2.0
const SITE_MAX_M: float = 50.0
const RADII_M: Array[float] = [5.5, 4.5, 6.5, 3.5, 7.5]
const DIRECTIONS: int = 16
const EYE_HEIGHT_M: float = 1.6
const BODY_HALF_M: float = 0.45
const BODY_HEIGHT_M: float = 1.8
const SOLID_MIN_HEIGHT_M: float = 0.5
## Units and cabinets at the station hub itself are the thing to look at, not an obstruction.
const HUB_IGNORE_M: float = 2.2
const PLAYER_Y_M: float = 0.91


## Visible solid meshes (labels, thin ground ribbons and decals excluded) as world AABBs.
static func solids(world: Node3D) -> Array[AABB]:
	var out: Array[AABB] = []
	for node: Node in world.find_children("*", "GeometryInstance3D", true, false):
		var g: GeometryInstance3D = node as GeometryInstance3D
		if g is Label3D or not g.is_visible_in_tree():
			continue
		var box: AABB = g.global_transform * g.get_aabb()
		if box.size.y < SOLID_MIN_HEIGHT_M or box.end.y < SOLID_MIN_HEIGHT_M:
			continue
		out.append(box)
	return out


## True when a standing body at `p` (feet height) overlaps any solid.
static func body_blocked(p: Vector3, boxes: Array[AABB]) -> bool:
	var body: AABB = AABB(Vector3(p.x - BODY_HALF_M, 0.05, p.z - BODY_HALF_M),
		Vector3(BODY_HALF_M * 2.0, BODY_HEIGHT_M, BODY_HALF_M * 2.0))
	for box: AABB in boxes:
		if box.intersects(body):
			return true
	return false


## True when a solid outside the hub stands between the eye at `p` and the station.
static func view_blocked(p: Vector3, station: Vector3, boxes: Array[AABB]) -> bool:
	var eye: Vector3 = Vector3(p.x, EYE_HEIGHT_M, p.z)
	var goal: Vector3 = Vector3(station.x, 1.2, station.z)
	for box: AABB in boxes:
		var c: Vector3 = box.get_center()
		if Vector2(c.x - station.x, c.z - station.z).length() < HUB_IGNORE_M:
			continue
		if box.intersects_segment(eye, goal) != null:
			return true
	return false


## Returns {"ok", "position", "yaw", "radius", "fallback"}. `first`/`second` are the first two station positions.
static func choose(world: Node3D, first: Vector3, second: Vector3) -> Dictionary:
	var boxes: Array[AABB] = solids(world)
	var behind: Vector3 = Vector3(first.x - second.x, 0.0, first.z - second.z)
	behind = behind.normalized() if behind.length() > 0.01 else Vector3.BACK
	var best: Dictionary = {}
	var best_score: float = INF
	for radius: float in RADII_M:
		for i: int in DIRECTIONS:
			var angle: float = TAU * float(i) / float(DIRECTIONS)
			var dir: Vector3 = behind.rotated(Vector3.UP, angle)
			var p: Vector3 = Vector3(first.x, PLAYER_Y_M, first.z) + dir * radius
			if p.x < SITE_MIN_M or p.z < SITE_MIN_M or p.x > SITE_MAX_M or p.z > SITE_MAX_M:
				continue
			if body_blocked(p, boxes) or view_blocked(p, first, boxes):
				continue
			# Prefer approaching from behind, then the preferred distance (list order).
			var score: float = minf(angle, TAU - angle) + float(RADII_M.find(radius)) * 0.5
			if score < best_score:
				best_score = score
				best = {"position": p, "radius": radius}
	if best.is_empty():
		var fallback: Vector3 = Vector3(first.x, PLAYER_Y_M, first.z) + behind * RADII_M[0]
		fallback.x = clampf(fallback.x, SITE_MIN_M, SITE_MAX_M)
		fallback.z = clampf(fallback.z, SITE_MIN_M, SITE_MAX_M)
		best = {"position": fallback, "radius": RADII_M[0], "fallback": true}
	var p2: Vector3 = best["position"]
	# The controller looks along its local -Z, so face the station with yaw = atan2(-dx, -dz).
	var to: Vector3 = Vector3(first.x - p2.x, 0.0, first.z - p2.z)
	best["yaw"] = atan2(-to.x, -to.z)
	best["ok"] = not best.has("fallback")
	return best
