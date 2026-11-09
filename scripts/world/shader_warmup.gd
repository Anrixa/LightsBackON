extends Node3D
## DS09 shader warm-up behind the loading card (plan U7, DS08 finding "cold shader cache").
## The Compatibility (GLES3) renderer compiles a material's program the first time an object using it is drawn, with
## variants for the lights and fog that reach it. On a cold cache that was one 3.4 s (Intel UHD) / 4.7 s (RTX 5090)
## first mission frame. Here a hidden camera visits the spawn and every local light and looks around, one view per
## frame, while the opaque loading card covers the screen: the compiles happen in frames nobody sees, spread over many
## frames so the card keeps drawing, and the first visible mission frame finds a warm cache. Objects are drawn in place
## with their real lights, so the variants match play. Presentation only: no state is read or changed.

signal progressed(fraction: float)
signal finished(stats: Dictionary)

const CONFIG_PATH: String = "res://content/world/shader_warmup.json"
const CM_PER_M: float = 100.0

var _views: Array[Transform3D] = []
var _camera: Camera3D
var _return_camera: Camera3D
var _index: int = 0
var _last_usec: int = 0
var _start_usec: int = 0
var _worst_frame_ms: float = 0.0
var _vantages: int = 0
var _done: bool = false


static func load_config() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	return parsed if parsed is Dictionary else {}


## Eye-height positions: the spawn first, then each local light (sorted by distance from the spawn, then by node path,
## so the tour is the same every run), skipping any closer than the minimum spacing to one already chosen.
static func vantages(spawn: Vector3, lights: Array[Node3D], config: Dictionary) -> Array[Vector3]:
	var eye_y: float = spawn.y
	var spacing: float = float(config["vantage_min_spacing_cm"]) / CM_PER_M
	var limit: int = int(config["max_vantages"])
	var candidates: Array[Dictionary] = []
	for light: Node3D in lights:
		var p: Vector3 = light.global_position
		candidates.append({"pos": Vector3(p.x, eye_y, p.z), "key": str(light.get_path()),
			"dist": Vector2(p.x - spawn.x, p.z - spawn.z).length()})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a["key"] < b["key"] if is_equal_approx(float(a["dist"]), float(b["dist"])) else float(a["dist"]) < float(b["dist"]))
	var out: Array[Vector3] = [spawn]
	for c: Dictionary in candidates:
		if out.size() >= limit:
			break
		var pos: Vector3 = c["pos"]
		var near: bool = false
		for chosen: Vector3 in out:
			if chosen.distance_to(pos) < spacing:
				near = true
				break
		if not near:
			out.append(pos)
	return out


## One transform per (vantage, yaw step); a slight downward pitch keeps the ground, kerbs and cabinets in view.
static func views(points: Array[Vector3], config: Dictionary) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	var steps: int = maxi(1, int(config["yaw_steps"]))
	var pitch: float = deg_to_rad(float(config["pitch_deg"]))
	for p: Vector3 in points:
		for i: int in range(steps):
			var basis: Basis = Basis.from_euler(Vector3(pitch, TAU * float(i) / float(steps), 0.0))
			out.append(Transform3D(basis, p))
	return out


## lights: the local lights of the dressed street; player_camera: made current again for the last warm-up frame, so the
## first-person view (tool, hands, HUD-adjacent 3D) is drawn once while the card is still up.
func setup(spawn_eye: Vector3, lights: Array[Node3D], player_camera: Camera3D) -> void:
	var config: Dictionary = load_config()
	var points: Array[Vector3] = vantages(spawn_eye, lights, config)
	_vantages = points.size()
	_views = views(points, config)
	_return_camera = player_camera
	_camera = Camera3D.new()
	_camera.name = "WarmupCamera"
	_camera.fov = float(config["fov_deg"])
	if player_camera != null:
		_camera.far = player_camera.far
		_camera.near = player_camera.near
	add_child(_camera)


func view_count() -> int:
	return _views.size()


func is_done() -> bool:
	return _done


func _ready() -> void:
	_start_usec = Time.get_ticks_usec()
	_last_usec = _start_usec
	_camera.make_current()


## _process runs before the frame is drawn, so the view set here is the one this frame renders. The time between two
## calls is one whole frame, compile stalls included; the worst one is reported.
func _process(_delta: float) -> void:
	if _done:
		return
	var now: int = Time.get_ticks_usec()
	if _index > 0:
		_worst_frame_ms = maxf(_worst_frame_ms, float(now - _last_usec) / 1000.0)
	_last_usec = now
	if _index < _views.size():
		_camera.global_transform = _views[_index]
	elif _index == _views.size() and _return_camera != null:
		_return_camera.make_current()
	elif _index > _views.size():
		_finish(now)
		return
	_index += 1
	progressed.emit(float(_index) / float(_views.size() + 2))


func _finish(now: int) -> void:
	_done = true
	var stats: Dictionary = {"views": _views.size(), "vantages": _vantages,
		"total_ms": roundi(float(now - _start_usec) / 1000.0), "worst_frame_ms": roundi(_worst_frame_ms)}
	print("DS09 shader warm-up: %d views from %d vantages, %d ms, worst frame %d ms" % [stats["views"], stats["vantages"],
		stats["total_ms"], stats["worst_frame_ms"]])
	progressed.emit(1.0)
	finished.emit(stats)
