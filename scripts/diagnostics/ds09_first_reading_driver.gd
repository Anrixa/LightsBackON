extends Node
## DS09 scripted first minute: time from the menu's Start to the first meter reading at the west junction cabinet.
## A bot that already knows the way plays the route the onboarding text describes ("the west junction cabinet, ahead on
## the right ... equip the meter and read its panel") through the normal input path (Input.action_press /
## InputEventAction), like the QA140 driver. Its time is a floor for a person, not a measure of one: a target to test
## with people (plan DS09), never a playtest result.
## Internal exports and the editor only (CLAUDE.md section 9: debug tools never ship). Writes
## user://ds09/first_reading.json. No network, no account or device identifiers.

const ARG: String = "--ds09-first-reading"
const MENU_IDLE_S: float = 2.0
const LOAD_TIMEOUT_S: float = 90.0
const ROUTE_TIMEOUT_S: float = 60.0
const PANEL_MARKER: String = "District/Markers/PANEL_JW"
const PANEL_ID: String = "PANEL_JW"
## Where the bot stops: in front of the panel face (+Z side of the cabinet), well inside the 230 cm interaction ray.
const STAND_OFFSET_M: Vector3 = Vector3(0.0, 0.0, 1.3)
const ARRIVE_M: float = 0.35
const WALK_ALIGN_RAD: float = 0.35
const AIM_ALIGN_RAD: float = 0.04
const STEER_GAIN: float = 2.5
const STEER_MIN: float = 0.35

var _t_start_usec: int = 0
var _t_play_usec: int = 0
var _held: Array[String] = []


static func requested(args: PackedStringArray) -> bool:
	return args.has(ARG)


static func allowed() -> bool:
	return OS.has_feature("internal") or OS.has_feature("editor")


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	if not await _wait_for(func() -> bool: return _scene_named("MainMenu"), LOAD_TIMEOUT_S):
		_finish(3, "menu_missing")
		return
	await get_tree().create_timer(MENU_IDLE_S, true, false, true).timeout
	var menu: Node = get_tree().current_scene
	var start: Variant = menu.get("start_button")
	if not (start is Button) or (start as Button).disabled:
		_finish(3, "start_unavailable")
		return
	_t_start_usec = Time.get_ticks_usec()
	(start as Button).pressed.emit()
	var confirm: Node = menu.get_node_or_null("ReplaceCheckpointConfirmation")
	if confirm is ConfirmationDialog and (confirm as ConfirmationDialog).visible:
		(confirm as ConfirmationDialog).get_ok_button().pressed.emit()
	var playable: Callable = func() -> bool:
		var s: Node = get_tree().current_scene
		return s != null and s.name == "MissionRoot" and s.is_node_ready() and not bool(s.call("is_warming"))
	if not await _wait_for(playable, LOAD_TIMEOUT_S):
		_finish(4, "mission_not_playable")
		return
	_t_play_usec = Time.get_ticks_usec()
	var scene: Node = get_tree().current_scene
	var reached: bool = await _walk_and_aim(scene)
	if not reached:
		_finish(5, "route_failed")
		return
	_tap("tool_slot_1")
	await get_tree().process_frame
	_tap("interact")
	var measured: Callable = func() -> bool:
		var guide: RefCounted = (scene.get("onboarding") as Node).get("guide") as RefCounted
		return str(guide.call("step_id")) != "MEASURE" and str(guide.call("step_id")) != "MOVE"
	if not await _wait_for(measured, 10.0):
		_finish(6, "no_reading")
		return
	_finish(0, "ok")


## Steer with the pad look axis toward the stand point, walk when roughly facing it, then turn to the panel and wait
## until the host-side target selector picks the panel (the same check that shows the "[E] Measure" prompt).
func _walk_and_aim(scene: Node) -> bool:
	var player: Node3D = scene.get("player") as Node3D
	var panel: Node3D = scene.get_node_or_null(PANEL_MARKER) as Node3D
	if player == null or panel == null:
		return false
	var stand: Vector3 = panel.global_position + STAND_OFFSET_M
	var deadline: int = Time.get_ticks_usec() + int(ROUTE_TIMEOUT_S * 1000000.0)
	while Time.get_ticks_usec() < deadline:
		await get_tree().physics_frame
		var to_stand: Vector3 = stand - player.global_position
		to_stand.y = 0.0
		if to_stand.length() <= ARRIVE_M:
			break
		var err: float = _yaw_error(player, to_stand)
		_steer(err)
		if absf(err) < WALK_ALIGN_RAD:
			_hold("move_forward", 1.0)
		else:
			_release("move_forward")
	_release_all()
	while Time.get_ticks_usec() < deadline:
		await get_tree().physics_frame
		var to_panel: Vector3 = panel.global_position - player.global_position
		to_panel.y = 0.0
		var err: float = _yaw_error(player, to_panel)
		_steer(err)
		if absf(err) < AIM_ALIGN_RAD and str(scene.get("_target")) == PANEL_ID:
			_release_all()
			return true
	_release_all()
	return false


## Signed yaw from the player's forward to a flat direction; positive means the target is to the left.
static func _yaw_error(player: Node3D, direction: Vector3) -> float:
	var forward: Vector3 = -player.global_transform.basis.z
	forward.y = 0.0
	return forward.normalized().signed_angle_to(direction.normalized(), Vector3.UP)


func _steer(err: float) -> void:
	_release("look_left")
	_release("look_right")
	if absf(err) < AIM_ALIGN_RAD * 0.5:
		return
	var strength: float = clampf(absf(err) * STEER_GAIN, STEER_MIN, 1.0)
	_hold("look_left" if err > 0.0 else "look_right", strength)


func _hold(action: String, strength: float) -> void:
	Input.action_press(action, strength)
	if not _held.has(action):
		_held.append(action)


func _release(action: String) -> void:
	Input.action_release(action)
	_held.erase(action)


func _release_all() -> void:
	for action: String in _held.duplicate():
		Input.action_release(action)
	_held.clear()


func _tap(action: String) -> void:
	var press: InputEventAction = InputEventAction.new()
	press.action = action
	press.pressed = true
	press.strength = 1.0
	Input.parse_input_event(press)
	var release: InputEventAction = InputEventAction.new()
	release.action = action
	release.pressed = false
	Input.parse_input_event(release)


func _scene_named(scene_name: String) -> bool:
	var s: Node = get_tree().current_scene
	return s != null and s.name == scene_name and s.is_node_ready()


func _wait_for(condition: Callable, timeout_s: float) -> bool:
	var deadline: int = Time.get_ticks_usec() + int(timeout_s * 1000000.0)
	while Time.get_ticks_usec() < deadline:
		if bool(condition.call()):
			return true
		await get_tree().process_frame
	return false


func _finish(exit_code: int, result: String) -> void:
	_release_all()
	var now: int = Time.get_ticks_usec()
	var scene: Node = get_tree().current_scene
	var report: Dictionary = {
		"result": result,
		"exit_code": exit_code,
		"start_to_playable_ms": roundi(float(_t_play_usec - _t_start_usec) / 1000.0) if _t_play_usec > 0 else -1,
		"playable_to_reading_ms": roundi(float(now - _t_play_usec) / 1000.0) if exit_code == 0 else -1,
		"start_to_reading_ms": roundi(float(now - _t_start_usec) / 1000.0) if exit_code == 0 else -1,
		"shader_warmup": scene.get("warmup_stats") if scene != null and scene.get("warmup_stats") is Dictionary else {},
		"adapter_name": RenderingServer.get_video_adapter_name(),
		"viewport_size": [int(get_viewport().get_visible_rect().size.x), int(get_viewport().get_visible_rect().size.y)],
		"render_scale": get_viewport().scaling_3d_scale,
		"engine": str(Engine.get_version_info()["string"]),
	}
	DirAccess.make_dir_recursive_absolute("user://ds09")
	var file: FileAccess = FileAccess.open("user://ds09/first_reading.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "  ", false) + "\n")
		file.close()
	print("DS09_FIRST_READING %s start_to_playable_ms=%d playable_to_reading_ms=%d start_to_reading_ms=%d" % [result,
		report["start_to_playable_ms"], report["playable_to_reading_ms"], report["start_to_reading_ms"]])
	get_tree().quit(exit_code)
