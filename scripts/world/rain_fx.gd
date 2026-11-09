extends GPUParticles3D
## DS08 rain: a box of thin falling streaks that follows the active camera. Particles are emitted in world space
## (local_coords off), so walking does not drag the rain along. Purely cosmetic: no flashes (lightning is not in v1),
## nothing here reads or writes game state. Values come from content/world/look_stormglass.json "rain".

const PERCENT: float = 100.0
const VISIBILITY_MARGIN_M: float = 4.0

var _height_m: float = 0.0


func configure(r: Dictionary) -> void:
	var box: Vector3 = _cm(r["box_cm"])
	_height_m = float(r["height_above_camera_cm"]) / PERCENT
	var fall: float = float(r["fall_speed_cm_s"]) / PERCENT
	var wind: Vector3 = _cm(r["wind_cm_s"])
	var velocity: Vector3 = wind + Vector3.DOWN * fall
	amount = int(r["amount"])
	lifetime = float(r["lifetime_ms"]) / 1000.0
	preprocess = lifetime
	local_coords = false
	explosiveness = 0.0
	randomness = 0.3
	fixed_fps = 0
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var depth: float = fall * lifetime + _height_m
	visibility_aabb = AABB(Vector3(-box.x * 0.5, -depth, -box.z * 0.5) - Vector3.ONE * VISIBILITY_MARGIN_M,
		Vector3(box.x, depth + box.y, box.z) + Vector3.ONE * VISIBILITY_MARGIN_M * 2.0)
	var pm: ParticleProcessMaterial = ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = box * 0.5
	pm.direction = velocity.normalized()
	pm.spread = 2.0
	pm.initial_velocity_min = velocity.length() * 0.9
	pm.initial_velocity_max = velocity.length() * 1.1
	pm.gravity = Vector3.ZERO
	process_material = pm
	var streak: Array = r["streak_cm"]
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2(float(streak[0]), float(streak[1])) / PERCENT
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	mat.billboard_keep_scale = true
	var c: Color = Color(str(r["color"]))
	c.a = float(r["alpha_percent"]) / PERCENT
	mat.albedo_color = c
	mat.disable_receive_shadows = true
	quad.material = mat
	draw_pass_1 = quad


func _process(_delta: float) -> void:
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam != null:
		global_position = cam.global_position + Vector3.UP * _height_m


static func _cm(v: Array) -> Vector3:
	return Vector3(float(v[0]), float(v[1]), float(v[2])) / PERCENT
