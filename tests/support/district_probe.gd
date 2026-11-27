extends "res://scripts/diagnostics/reach_grid.gd"
## V01 test support: mounts a district scene in the running SceneTree and asks the physics world about it. The
## walkability grid itself lives in scripts/diagnostics/reach_grid.gd (shared with the RB02 location stage audit). A
## path found on the grid is then walked by a real CharacterBody3D at the content walk speed, so the claim
## "traversable" rests on move_and_slide against the scene's collision, not on the grid alone.

const WAYPOINT_REACHED_M: float = 0.15
const MAX_STEPS_PER_WAYPOINT: int = 90
const GRAVITY_M_S2: float = 9.8

var root: Node3D
var floor_angle_deg: float
var last_blocker: String = ""  # what the walker last slid against when it got stuck, for failure messages
var last_steps: int = 0  # physics ticks the last walk took


func _init(scene_path: String, dims: Dictionary, envelope_cm: Array) -> void:
	root = (load(scene_path) as PackedScene).instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(root)
	setup(root.get_world_3d().direct_space_state, dims, envelope_cm)
	floor_angle_deg = float(dims["floor_max_angle_deg"])


func free_scene() -> void:
	if root:
		root.get_parent().remove_child(root)
		root.free()
		root = null


## Names of the collision objects overlapping an axis-aligned box (meters).
func box_overlaps(center: Vector3, size: Vector3) -> Array[String]:
	var box := BoxShape3D.new()
	box.size = size
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = box
	q.transform = Transform3D(Basis.IDENTITY, center)
	var out: Array[String] = []
	for hit: Dictionary in space.intersect_shape(q, 8):
		out.append(str(root.get_path_to(hit["collider"] as Node)))
	return out


## Walks a CharacterBody3D (player capsule) through the waypoints at speed_m_s with gravity; returns where it ended.
func walk(path: Array[Vector3], speed_m_s: float) -> Vector3:
	var body := CharacterBody3D.new()
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = radius_m
	cap.height = height_m
	cs.shape = cap
	cs.position.y = height_m * 0.5
	body.add_child(cs)
	body.floor_max_angle = deg_to_rad(floor_angle_deg)
	root.add_child(body)
	body.global_position = path[0] + Vector3(0.0, 0.05, 0.0)
	var dt: float = 1.0 / float(Engine.physics_ticks_per_second)
	# Outside a physics frame move_and_slide integrates over the *process* frame delta, which here is however long the
	# runner's first frame took (100+ ms on a cold start). Scale the velocity so every call moves exactly one physics tick.
	var frame_dt: float = root.get_process_delta_time()
	assert(frame_dt > 0.0, "walk() needs the runner to have finished one frame")
	var to_tick: float = dt / frame_dt
	var vy: float = 0.0
	last_steps = 0
	for wp: Vector3 in path:
		var steps: int = 0
		while _flat(wp - body.global_position).length() > WAYPOINT_REACHED_M and steps < MAX_STEPS_PER_WAYPOINT:
			var dir: Vector3 = _flat(wp - body.global_position).normalized()
			vy = 0.0 if body.is_on_floor() else vy - GRAVITY_M_S2 * dt
			body.velocity = Vector3(dir.x * speed_m_s, vy, dir.z * speed_m_s) * to_tick
			body.move_and_slide()
			steps += 1
			last_steps += 1
		if steps >= MAX_STEPS_PER_WAYPOINT:
			var hit: KinematicCollision3D = body.get_last_slide_collision()
			last_blocker = "%s at %s" % [hit.get_collider(), hit.get_position()] if hit else "nothing"
			break  # stuck: the caller compares the end point with the goal
	var end: Vector3 = body.global_position
	root.remove_child(body)
	body.free()
	return end


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)
