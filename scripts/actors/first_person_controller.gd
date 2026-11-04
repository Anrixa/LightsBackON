extends CharacterBody3D
## Real first-person solo character for the V01 graybox. Collision is owned by
## CharacterBody3D; power state and mission commands never live in this actor.
## A later Steam peer can drive the same view through authoritative movement sync.

signal moved

const DIMENSIONS_PATH: String = "res://content/world/kit_dimensions.json"
const TUNING_PATH: String = "res://content/movement.json"
const SCENE_TUNING_PATH: String = "res://content/offline_solo.json"

var camera: Camera3D
var enabled: bool = true
var carrying: bool = false
var _movement: Dictionary = {}
var _tuning: Dictionary = {}
var _look: Dictionary = {}
var _camera_rest_position: Vector3 = Vector3.ZERO
var _reduce_camera_motion: bool = true
var _step_phase: float = 0.0
var _camera_bob_y: float = 0.0


func _ready() -> void:
	var dimensions: Dictionary = _json(DIMENSIONS_PATH)
	_movement = _json(TUNING_PATH)
	_tuning = _json(SCENE_TUNING_PATH)["player"]
	_look = _json(SCENE_TUNING_PATH)["camera"]
	var radius_m: float = float(dimensions["player_radius_cm"]) / 100.0
	var body_height_m: float = float(dimensions["player_height_cm"]) / 100.0

	var capsule: CapsuleShape3D = CapsuleShape3D.new()
	capsule.radius = radius_m
	capsule.height = body_height_m
	var collider: CollisionShape3D = CollisionShape3D.new()
	collider.name = "BodyCollision"
	collider.shape = capsule
	add_child(collider)

	camera = Camera3D.new()
	camera.name = "Eyes"
	camera.position.y = float(dimensions["camera_height_cm"]) / 100.0 - body_height_m * 0.5
	camera.fov = float(_look["fov_deg"])
	camera.current = true
	_camera_rest_position = camera.position
	add_child(camera)

	collision_layer = 1
	collision_mask = 1
	floor_max_angle = deg_to_rad(float(dimensions["floor_max_angle_deg"]))


static func _json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


func set_controls_active(active: bool) -> void:
	enabled = active
	if not active:
		velocity.x = 0.0
		velocity.z = 0.0
		_reset_camera_motion()


## Only cosmetic displacement is suppressed; look/pitch and movement remain available.
func set_reduce_camera_motion(reduced: bool) -> void:
	_reduce_camera_motion = reduced
	if reduced:
		_reset_camera_motion()


func camera_motion_offset_y() -> float:
	return _camera_bob_y


func _reset_camera_motion() -> void:
	_step_phase = 0.0
	_camera_bob_y = 0.0
	if camera != null:
		camera.position = _camera_rest_position


func _unhandled_input(event: InputEvent) -> void:
	if not enabled or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if event is InputEventMouseMotion:
		var motion: Vector2 = (event as InputEventMouseMotion).relative
		rotation.y -= motion.x * float(_tuning["look_microradians_per_pixel"]) / 1000000.0
		_pitch(-motion.y * float(_tuning["look_microradians_per_pixel"]) / 1000000.0)


func _physics_process(delta: float) -> void:
	if not enabled:
		return
	var pad: Vector2 = Input.get_vector("look_left", "look_right", "look_up", "look_down")
	rotation.y -= pad.x * float(_tuning["pad_look_milliradians_per_second"]) / 1000.0 * delta
	_pitch(-pad.y * float(_tuning["pad_look_milliradians_per_second"]) / 1000.0 * delta)

	var input_axis: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction: Vector3 = (global_transform.basis * Vector3(input_axis.x, 0.0, input_axis.y)).normalized()
	var speed: int = int(_movement["walk_mm_s"])
	if carrying:
		speed = int(_movement["carry_mm_s"])
	elif Input.is_action_pressed("crouch"):
		speed = int(_movement["crouch_mm_s"])
	elif Input.is_action_pressed("sprint"):
		speed = int(_movement["sprint_mm_s"])
	velocity.x = direction.x * float(speed) / 1000.0
	velocity.z = direction.z * float(speed) / 1000.0
	if not is_on_floor():
		velocity.y -= float(_tuning["gravity_cm_s2"]) / 100.0 * delta
	elif velocity.y < 0.0:
		velocity.y = 0.0
	var before: Vector3 = global_position
	move_and_slide()
	var horizontal: Vector2 = Vector2(global_position.x - before.x, global_position.z - before.z)
	_update_camera_motion(delta, horizontal.length())
	if horizontal.length_squared() > 0.000001:
		moved.emit()


## Distance-driven walking bob; no gameplay transform or aiming rotation changes.
func _update_camera_motion(delta: float, walked_m: float) -> void:
	if camera == null or _reduce_camera_motion:
		return
	var moving: bool = walked_m > 0.0 and is_on_floor()
	if moving:
		_step_phase += walked_m * float(ProjectSettings.get_setting("a04_presentation/camera_bob_cycles_per_meter")) * TAU
	var target: float = sin(_step_phase) * float(ProjectSettings.get_setting("a04_presentation/camera_bob_amplitude_cm")) / 100.0 if moving else 0.0
	var weight: float = minf(1.0, delta * float(ProjectSettings.get_setting("a04_presentation/camera_bob_smoothing_per_second")))
	_camera_bob_y = lerpf(_camera_bob_y, target, weight)
	camera.position = _camera_rest_position + Vector3(0.0, _camera_bob_y, 0.0)


func _pitch(delta_radians: float) -> void:
	if camera == null:
		return
	camera.rotation.x = clampf(camera.rotation.x + delta_radians,
		deg_to_rad(float(_tuning["pitch_min_deg"])),
		deg_to_rad(float(_tuning["pitch_max_deg"])))


func position_cm() -> Vector3i:
	return Vector3i(roundi(global_position.x * 100.0), roundi(global_position.y * 100.0),
		roundi(global_position.z * 100.0))
