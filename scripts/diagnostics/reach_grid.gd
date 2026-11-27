extends RefCounted
## Walkability grid over a mounted scene's physics (V01 reachability, shared by tests/support/district_probe.gd and the
## RB02 location stage audit in scripts/diagnostics/stage_audit.gd). Reachability is a 50 cm grid: a cell is standable
## when a ray finds a floor under it and a capsule slightly wider than the player fits there; neighbours connect when
## their floors differ by at most nav_max_step_cm (ramps, not ledges: the body has no step-up). Read-only: it only
## queries the physics space.

const CELL_M: float = 0.5
const RAY_TOP_M: float = 1.0  # below every roof and storey slab; starting inside a block building skips it
const RAY_BOTTOM_M: float = -3.0
const CLEARANCE_MARGIN_M: float = 0.05
const LIFT_M: float = 0.1  # keeps the query capsule off a 27 degree ramp it is standing on

var space: PhysicsDirectSpaceState3D
var radius_m: float
var height_m: float
var max_step_m: float
var nx: int
var nz: int
var floor_h: PackedFloat32Array  # NAN where the cell has no floor or the capsule does not fit


## dims is content/world/kit_dimensions.json; envelope_cm the location's [x, z] size.
func setup(physics: PhysicsDirectSpaceState3D, dims: Dictionary, envelope_cm: Array) -> void:
	space = physics
	radius_m = float(dims["player_radius_cm"]) / 100.0
	height_m = float(dims["player_height_cm"]) / 100.0
	max_step_m = float(dims["nav_max_step_cm"]) / 100.0
	nx = int(float(envelope_cm[0]) / 100.0 / CELL_M)
	nz = int(float(envelope_cm[1]) / 100.0 / CELL_M)


## Height of the first floor below (x, from_y, z), or NAN.
func floor_at(x: float, z: float, from_y: float = RAY_TOP_M) -> float:
	var hit: Dictionary = ray(Vector3(x, from_y, z), Vector3(x, RAY_BOTTOM_M, z))
	return (hit["position"] as Vector3).y if not hit.is_empty() else NAN


func ray(from: Vector3, to: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.hit_from_inside = false
	return space.intersect_ray(q)


## True when a player-sized capsule (plus margin) standing on feet touches nothing.
func capsule_fits(feet: Vector3) -> bool:
	var cap := CapsuleShape3D.new()
	cap.radius = radius_m + CLEARANCE_MARGIN_M
	cap.height = height_m
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = cap
	q.transform = Transform3D(Basis.IDENTITY, feet + Vector3(0.0, LIFT_M + height_m * 0.5, 0.0))
	return space.intersect_shape(q, 1).is_empty()


## Default scans the walkable ground. Higher starting rays permit isolated
## rooftop traversal probes without changing the ordinary ground-grid callers.
func build_grid(from_y: float = RAY_TOP_M) -> void:
	floor_h = PackedFloat32Array()
	floor_h.resize(nx * nz)
	for j: int in nz:
		for i: int in nx:
			var c: Vector3 = cell_center(i + j * nx)
			var h: float = floor_at(c.x, c.z, from_y)
			if not is_nan(h) and not capsule_fits(Vector3(c.x, h, c.z)):
				h = NAN
			floor_h[i + j * nx] = h


func cell_center(idx: int) -> Vector3:
	return Vector3((float(idx % nx) + 0.5) * CELL_M, 0.0, (float(idx / nx) + 0.5) * CELL_M)


func cell_of(p: Vector3) -> int:
	var i: int = clampi(int(p.x / CELL_M), 0, nx - 1)
	var j: int = clampi(int(p.z / CELL_M), 0, nz - 1)
	return i + j * nx


func standable(idx: int) -> bool:
	return not is_nan(floor_h[idx])


func feet(idx: int) -> Vector3:
	var c: Vector3 = cell_center(idx)
	return Vector3(c.x, floor_h[idx], c.z)


## Breadth-first search over standable cells; returns parent indices (-1 unreached, start points to itself).
func search(start: int) -> PackedInt32Array:
	var parent := PackedInt32Array()
	parent.resize(nx * nz)
	parent.fill(-1)
	if not standable(start):
		return parent
	parent[start] = start
	var queue: Array[int] = [start]
	var head: int = 0
	while head < queue.size():
		var cur: int = queue[head]
		head += 1
		for nb: int in _neighbours(cur):
			if parent[nb] == -1:
				parent[nb] = cur
				queue.append(nb)
	return parent


func _neighbours(idx: int) -> Array[int]:
	var out: Array[int] = []
	var i: int = idx % nx
	var j: int = idx / nx
	for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
			Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]:
		var a: int = i + d.x
		var b: int = j + d.y
		if a < 0 or b < 0 or a >= nx or b >= nz:
			continue
		var nb: int = a + b * nx
		if not _step_ok(idx, nb):
			continue
		# diagonals only when both orthogonal cells are open, so a path never cuts a wall corner
		if d.x != 0 and d.y != 0 and not (_step_ok(idx, a + j * nx) and _step_ok(idx, i + b * nx)):
			continue
		out.append(nb)
	return out


func _step_ok(a: int, b: int) -> bool:
	return standable(a) and standable(b) and absf(floor_h[a] - floor_h[b]) <= max_step_m


func path_to(parent: PackedInt32Array, goal: int) -> Array[Vector3]:
	var out: Array[Vector3] = []
	if parent[goal] == -1:
		return out
	var cur: int = goal
	while true:
		out.push_front(feet(cur))
		if parent[cur] == cur:
			break
		cur = parent[cur]
	return out
