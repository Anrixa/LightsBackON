extends Node
## QA-C01: a bot completes the whole C01 shift through the player's own input path, in the real Alder Street scene.
## It walks (on a navigation mesh baked at runtime from the street's static colliders, never from authored waypoints),
## turns and pitches with the look axes, picks tools from the same action plan the on-screen prompt shows, presses
## Interact, carries the generator, walks back up to re-measure when the prompt asks for it, and starts extraction from
## the van zone. The host validates every command exactly as for a person: range, physics sight, lock owner, tool, state.
## A bot that knows the route proves reachability and completability, not feel or pacing for people (UX01 stays human).
## Internal exports and the editor only (CLAUDE.md section 9). Opt-in: `-- --c01-playthrough`. Writes
## user://c01_playthrough/result.json and exits 0 on mission complete, non-zero with the failing phase otherwise.
## RB01: it also reads every visible text on screen after each step, as a release build shows it, and fails the run
## ("player_text", exit 5) if any internal ID, phase label, raw snake_case or developer wording reached the player.

const PlayerTextAudit := preload("res://scripts/diagnostics/player_text_audit.gd")
const BuildFlavor := preload("res://scripts/ui/build_flavor.gd")
const ARG: String = "--c01-playthrough"
const PLAYER_TEXT_EXIT: int = 5
const MISSION_PATH: String = "res://scenes/mission/mission_root.tscn"
const TOOLS: Array[String] = ["meter", "screwdriver", "puller", "cutter", "crimper"]
const LOAD_TIMEOUT_S: float = 120.0
const LEG_TIMEOUT_S: float = 90.0
const AIM_TIMEOUT_S: float = 8.0
const LATCH_TIMEOUT_S: float = 40.0
const VERIFY_TIMEOUT_S: float = 30.0
const EXTRACT_TIMEOUT_S: float = 20.0
const STUCK_WINDOW_MS: int = 2500
const STUCK_MIN_PROGRESS_M: float = 0.3
const MAX_PRESSES_PER_GOAL: int = 40
const PRESS_SETTLE_FRAMES: int = 6
const LOOK_GAIN: float = 2.5
const LOOK_MIN: float = 0.25
const YAW_DEADBAND_RAD: float = 0.02
const AIM_TOLERANCE_RAD: float = 0.05
const WALK_ALIGN_RAD: float = 0.5
const WAYPOINT_REACH_M: float = 0.6
const GOAL_REACH_M: float = 0.35
## The player controller has no step-up: only the authored ramp collision is climbable, so the navmesh must not
## advertise ledges (for example the side of the basement stair) that a CharacterBody3D cannot walk onto.
const NAV_AGENT_RADIUS_M: float = 0.4
const NAV_AGENT_HEIGHT_M: float = 1.7
const NAV_MAX_CLIMB_M: float = 0.05
const NAV_MAX_SLOPE_DEG: float = 45.0
const NAV_CELL_M: float = 0.1
const NAV_CELL_HEIGHT_M: float = 0.05
const PANEL_STAND: Vector3 = Vector3(0.0, 0.0, 1.05)
const ITEM_STAND: Vector3 = Vector3(0.0, 0.0, 1.4)
const TRUNK_STAND: Vector3 = Vector3(-1.0, 0.0, 0.0)
const VAN_ZONE_POINT: Vector3 = Vector3(6.0, 0.0, 16.0)
const PUMP_LATCH: String = "LATCH_PUMP_DRAIN"
const GENERATOR: String = "GEN_PORTABLE"

var _scene: Node
var _session: RefCounted
var _player: CharacterBody3D
var _map: RID
var _region: RID
var _held: Array[String] = []
var _log: Array[String] = []
var _presses: int = 0
var _remeasure_trips: int = 0
var _distance_m: float = 0.0
var _t0_usec: int = 0
var _done: bool = false
var _text_scans: int = 0
var _text_nodes_read: int = 0
var _text_findings: Dictionary = {}


static func requested(args: PackedStringArray) -> bool:
	return args.has(ARG)


static func allowed() -> bool:
	return OS.has_feature("internal") or OS.has_feature("editor")


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_t0_usec = Time.get_ticks_usec()
	BuildFlavor.simulate_release(true)
	get_tree().set_meta("offline_resume", false)
	get_tree().change_scene_to_file(MISSION_PATH)
	var playable: Callable = func() -> bool:
		var s: Node = get_tree().current_scene
		return s != null and s.name == "MissionRoot" and s.is_node_ready() and not bool(s.call("is_warming"))
	if not await _until(playable, LOAD_TIMEOUT_S):
		_finish(2, "mission_not_ready")
		return
	_scene = get_tree().current_scene
	_session = _scene.get("session") as RefCounted
	_player = _scene.get("player") as CharacterBody3D
	_bake_navigation()
	for i: int in 4:
		await get_tree().physics_frame
	_audit_text("first_frame")
	var first: Array[Array] = [
		["west_repair", "PANEL_JW", PANEL_STAND, func() -> bool: return _repair_state("R_JW_FUSE") == "restored"],
		["generator_pickup", GENERATOR, ITEM_STAND, func() -> bool: return _carrying()],
		["generator_to_pump", "PAD_PUMP", ITEM_STAND, func() -> bool: return not _carrying()],
		["generator_start", GENERATOR, ITEM_STAND, func() -> bool: return _generator_online()],
	]
	if not await _run_phases(first):
		return
	if not await _until(func() -> bool: return bool(_mission().call("is_latched", PUMP_LATCH)), LATCH_TIMEOUT_S):
		_finish(3, "pump_latch")
		return
	_say("basement drained (latch)")
	var second: Array[Array] = [
		["generator_stop", GENERATOR, ITEM_STAND, func() -> bool: return not _generator_online()],
		["east_measure", "PANEL_JE", PANEL_STAND, func() -> bool: return _measured("PANEL_JE")],
		["east_trunk_repair", "TRUNK_JE", TRUNK_STAND, func() -> bool: return _repair_state("R_JE_TRUNK") == "restored"],
		["generator_recover", GENERATOR, ITEM_STAND, func() -> bool: return _carrying()],
		["generator_stow", "VAN_BAY", ITEM_STAND, func() -> bool: return not _carrying()],
	]
	if not await _run_phases(second):
		return
	if not await _until(func() -> bool: return bool(_mission().call("verified")), VERIFY_TIMEOUT_S):
		_finish(3, "grid_verification")
		return
	_say("grid verified")
	if not await _go_to(VAN_ZONE_POINT):
		_finish(4, "walk_to_van_zone")
		return
	if not await _until(func() -> bool: return str(_scene.get("_target")) == "ZONE_VAN", 5.0):
		_finish(4, "extraction_prompt")
		return
	_tap("interact")
	_presses += 1
	if not await _until(func() -> bool: return bool(_scene.get("_finished")), EXTRACT_TIMEOUT_S):
		_finish(4, "extraction")
		return
	_finish(0, "ok")


func _run_phases(phases: Array[Array]) -> bool:
	for phase: Array in phases:
		if not await _work_at(str(phase[1]), phase[2] as Vector3, phase[3] as Callable):
			_finish(3, str(phase[0]))
			return false
		_say("phase %s done" % phase[0])
	return true


## Walk to a stand point beside an entity, aim at it and press Interact with the tool the prompt asks for until done().
func _work_at(id: String, stand_offset: Vector3, done: Callable) -> bool:
	if bool(done.call()):
		return true
	var target: Vector3 = _session.call("entity_position", id)
	if not await _go_to(target + stand_offset):
		return false
	var tries: int = 0
	while not bool(done.call()) and tries < MAX_PRESSES_PER_GOAL:
		tries += 1
		if not await _aim(id, target):
			_say("cannot target %s from %s" % [id, _player.global_position])
			return false
		var plan: Dictionary = _session.call("action_for", id, TOOLS[int(_scene.get("_slot")) - 1])
		var panel: String = _panel_for(id)
		if plan.has("blocked") and not plan.has("next_step") and panel != "" and panel != id and not _measured(panel):
			# The prompt asks for a fresh junction reading (prove-dead rule): walk back up, measure, return.
			_remeasure_trips += 1
			_say("prompt '%s': re-measure %s" % [plan["blocked"], panel])
			if not await _work_at(panel, PANEL_STAND, func() -> bool: return _measured(panel)):
				return false
			if not await _go_to(target + stand_offset):
				return false
			continue
		if plan.has("blocked"):
			var tool: String = _tool_for(id, str(plan["next_step"])) if plan.has("next_step") else "meter"
			_tap("tool_slot_%d" % (TOOLS.find(tool) + 1))
			await get_tree().physics_frame
			continue
		_say("E on %s: %s %s" % [id, plan.get("kind", "?"), JSON.stringify(plan.get("payload", {}))])
		_tap("interact")
		_presses += 1
		for i: int in PRESS_SETTLE_FRAMES:
			await get_tree().physics_frame
		_audit_text("after E on " + id)
	return bool(done.call())


func _bake_navigation() -> void:
	var mesh: NavigationMesh = NavigationMesh.new()
	mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	mesh.agent_radius = NAV_AGENT_RADIUS_M
	mesh.agent_height = NAV_AGENT_HEIGHT_M
	mesh.agent_max_climb = NAV_MAX_CLIMB_M
	mesh.agent_max_slope = NAV_MAX_SLOPE_DEG
	mesh.cell_size = NAV_CELL_M
	mesh.cell_height = NAV_CELL_HEIGHT_M
	var source: NavigationMeshSourceGeometryData3D = NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(mesh, source, _scene)
	NavigationServer3D.bake_from_source_geometry_data(mesh, source)
	_map = NavigationServer3D.map_create()
	NavigationServer3D.map_set_cell_size(_map, NAV_CELL_M)
	NavigationServer3D.map_set_cell_height(_map, NAV_CELL_HEIGHT_M)
	NavigationServer3D.map_set_active(_map, true)
	_region = NavigationServer3D.region_create()
	NavigationServer3D.region_set_map(_region, _map)
	NavigationServer3D.region_set_navigation_mesh(_region, mesh)
	NavigationServer3D.map_force_update(_map)
	_say("navmesh polygons=%d" % mesh.get_polygon_count())


func _go_to(goal: Vector3) -> bool:
	await get_tree().physics_frame
	var start: Vector3 = NavigationServer3D.map_get_closest_point(_map, _player.global_position)
	var end: Vector3 = NavigationServer3D.map_get_closest_point(_map, goal)
	var path: PackedVector3Array = NavigationServer3D.map_get_path(_map, start, end, true)
	if path.is_empty():
		_say("no path to %s" % goal)
		return false
	var deadline: int = Time.get_ticks_msec() + int(LEG_TIMEOUT_S * 1000.0)
	var index: int = 1
	var last_position: Vector3 = _player.global_position
	var last_check: int = Time.get_ticks_msec()
	var previous: Vector3 = _player.global_position
	while index < path.size() and Time.get_ticks_msec() < deadline:
		await get_tree().physics_frame
		_distance_m += Vector2(_player.global_position.x - previous.x, _player.global_position.z - previous.z).length()
		previous = _player.global_position
		var to_point: Vector3 = path[index] - _player.global_position
		to_point.y = 0.0
		if to_point.length() < (GOAL_REACH_M if index == path.size() - 1 else WAYPOINT_REACH_M):
			index += 1
			continue
		var error: float = _yaw_error(to_point)
		_steer_yaw(error)
		if absf(error) < WALK_ALIGN_RAD:
			_hold("move_forward", 1.0)
		else:
			_release("move_forward")
		if Time.get_ticks_msec() - last_check > STUCK_WINDOW_MS:
			if _player.global_position.distance_to(last_position) < STUCK_MIN_PROGRESS_M:
				_say("stuck at %s heading to %s" % [_player.global_position, path[index]])
				_release_all()
				return false
			last_position = _player.global_position
			last_check = Time.get_ticks_msec()
	_release_all()
	return index >= path.size()


## Turn and pitch with the look axes until the scene's own target selector (the reticle prompt) picks the entity.
func _aim(id: String, target: Vector3) -> bool:
	var deadline: int = Time.get_ticks_msec() + int(AIM_TIMEOUT_S * 1000.0)
	while Time.get_ticks_msec() < deadline:
		await get_tree().physics_frame
		var camera: Camera3D = _player.get("camera") as Camera3D
		var to_target: Vector3 = target - camera.global_position
		var flat: Vector3 = Vector3(to_target.x, 0.0, to_target.z)
		var yaw_error: float = _yaw_error(flat)
		var forward: Vector3 = -camera.global_transform.basis.z
		var pitch_error: float = atan2(to_target.y, flat.length()) - asin(clampf(forward.y, -1.0, 1.0))
		_steer_yaw(yaw_error)
		_release("look_up")
		_release("look_down")
		if absf(pitch_error) > YAW_DEADBAND_RAD:
			_hold("look_up" if pitch_error > 0.0 else "look_down", clampf(absf(pitch_error) * LOOK_GAIN, LOOK_MIN, 1.0))
		if absf(yaw_error) < AIM_TOLERANCE_RAD and absf(pitch_error) < AIM_TOLERANCE_RAD and str(_scene.get("_target")) == id:
			_release_all()
			return true
	_release_all()
	return false


func _panel_for(id: String) -> String:
	var repair: Dictionary = _repair_at(id)
	return str(repair.get("panel", ""))


func _tool_for(id: String, step: String) -> String:
	var repair: Dictionary = _repair_at(id)
	return str((repair.get("tools", {}) as Dictionary).get(step, "meter"))


func _repair_at(id: String) -> Dictionary:
	var at: Vector3 = _session.call("entity_position", id)
	for repair: Dictionary in _session.call("repair_definitions"):
		if (_session.call("entity_position", str(repair["id"])) as Vector3).distance_to(at) < 0.5:
			return repair
	return {}


func _mission() -> RefCounted:
	return _session.get("mission") as RefCounted


func _carrying() -> bool:
	return str(_session.get("equipment").call("carrier_of", GENERATOR)) != ""


func _generator_online() -> bool:
	return bool(_session.get("grid").call("canonical_state")["nodes"]["GEN"]["online"])


func _repair_state(id: String) -> String:
	return str(_session.get("interaction").call("repair_state", id))


func _measured(panel: String) -> bool:
	var readings: Dictionary = _session.get("meter").call("readings", panel, _session.get("grid"))
	return (readings["_panel"] as Dictionary).has("tick")


func _yaw_error(direction: Vector3) -> float:
	var forward: Vector3 = -_player.global_transform.basis.z
	forward.y = 0.0
	return forward.normalized().signed_angle_to(direction.normalized(), Vector3.UP)


func _steer_yaw(error: float) -> void:
	_release("look_left")
	_release("look_right")
	if absf(error) < YAW_DEADBAND_RAD:
		return
	_hold("look_left" if error > 0.0 else "look_right", clampf(absf(error) * LOOK_GAIN, LOOK_MIN, 1.0))


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


func _until(condition: Callable, timeout_s: float) -> bool:
	var deadline: int = Time.get_ticks_msec() + int(timeout_s * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if bool(condition.call()):
			return true
		await get_tree().process_frame
	return false


func _say(line: String) -> void:
	var stamped: String = "%.1fs %s" % [float(Time.get_ticks_usec() - _t0_usec) / 1000000.0, line]
	_log.append(stamped)
	print("C01_PLAYTHROUGH ", stamped)
	_audit_text(line)


## Every visible Label, Label3D, Button and RichTextLabel on screen right now. Findings are kept once per node and text.
func _audit_text(where: String) -> void:
	if _scene == null or not is_instance_valid(_scene):
		return
	_text_scans += 1
	_text_nodes_read += PlayerTextAudit.count_text_nodes(_scene, true)
	for f: Dictionary in PlayerTextAudit.scan_tree(_scene, true):
		var key: String = "%s|%s" % [f["path"], f["text"]]
		if not _text_findings.has(key):
			f["seen_at"] = where
			_text_findings[key] = f
			print("C01_PLAYTHROUGH player text %s %s: \"%s\"" % [str(f["rules"]), f["path"], f["text"]])


func _finish(exit_code: int, result: String) -> void:
	if _done:
		return
	_audit_text("finish: " + result)
	_done = true
	_release_all()
	if result == "ok" and not _text_findings.is_empty():
		result = "player_text"
		exit_code = PLAYER_TEXT_EXIT
	var stars: int = -1
	if (result == "ok" or result == "player_text") and _session != null:
		stars = int((_mission().call("results") as Dictionary).get("stars", -1))
	var report: Dictionary = {
		"result": result,
		"exit_code": exit_code,
		"elapsed_s": snappedf(float(Time.get_ticks_usec() - _t0_usec) / 1000000.0, 0.1),
		"interact_presses": _presses,
		"remeasure_trips": _remeasure_trips,
		"walked_m": snappedf(_distance_m, 0.1),
		"player_text": {"scans": _text_scans, "text_nodes_read": _text_nodes_read,
			"findings": _text_findings.values()},
		"stars": stars,
		"display": DisplayServer.get_name(),
		"engine": str(Engine.get_version_info()["string"]),
		"log": _log,
	}
	DirAccess.make_dir_recursive_absolute("user://c01_playthrough")
	var file: FileAccess = FileAccess.open("user://c01_playthrough/result.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "  ", false) + "\n")
		file.close()
	print(("C01_PLAYTHROUGH_RESULT %s exit=%d elapsed_s=%.1f presses=%d remeasure_trips=%d walked_m=%.1f stars=%d" +
		" text_scans=%d text_findings=%d") % [result, exit_code, report["elapsed_s"], _presses, _remeasure_trips,
		report["walked_m"], stars, _text_scans, _text_findings.size()])
	if _region.is_valid():
		NavigationServer3D.free_rid(_region)
	if _map.is_valid():
		NavigationServer3D.free_rid(_map)
	get_tree().quit(exit_code)
