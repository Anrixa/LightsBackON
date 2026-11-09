extends Node
## QA140: scripted, unattended scenario for QA56 frame captures on remote Windows test PCs.
## Plays the same route a person would follow in QA56 (menu idle, the menu's own Start action, mission idle, walk and look,
## repeated tablet and pause toggles) through the normal input path (InputEventAction / Input.action_press), marks one QA56
## segment per step, records engine-side render/memory monitors per segment, then quits normally so the frame CSV flushes.
## Internal exports and the editor binary only: a release export ignores --qa140-scenario (CLAUDE.md section 9, debug tools).
## Writes user://qa56/<session>_qa140.json next to the QA56 frame CSV. No network, no account or device identifiers.

const ARG: String = "--qa140-scenario"
const SCHEMA_VERSION: int = 1
# Step durations (seconds). Diagnostics timing only; no gameplay rule depends on them.
const MENU_IDLE_S: float = 20.0
const MISSION_LOAD_TIMEOUT_S: float = 60.0
const MISSION_IDLE_S: float = 30.0
const WALK_S: float = 40.0
const WALK_TURN_EVERY_S: float = 4.0
const WALK_LOOK_STRENGTH: float = 0.45
const TABLET_CYCLES: int = 20
const TABLET_STATE_S: float = 1.2
const PAUSE_CYCLES: int = 10
const PAUSE_STATE_S: float = 1.0
const FINAL_IDLE_S: float = 20.0
const SEGMENT_NAMES: Array[String] = [
	"menu_idle", "mission_idle", "walk_look", "tablet_toggle", "pause_toggle", "final_idle",
]

var _probe: Node
var _session_id: String = ""
var _segment: int = 0
var _segments: Array[Dictionary] = []
var _steps: Array[Dictionary] = []
var _held_actions: Array[String] = []
var _input_log: Array[Dictionary] = []
const INPUT_LOG_LIMIT: int = 64


static func requested(args: PackedStringArray) -> bool:
	return args.has(ARG)


static func allowed() -> bool:
	return OS.has_feature("internal") or OS.has_feature("editor")


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)


func setup(probe: Node, session_id: String) -> void:
	_probe = probe
	_session_id = session_id


func _ready() -> void:
	_begin_segment(0)
	set_process(true)
	_run.call_deferred()


func _process(_delta: float) -> void:
	if _segments.is_empty():
		return
	var current: Dictionary = _segments[_segments.size() - 1]
	current["frames"] = int(current["frames"]) + 1
	_peak(current, "video_mem_peak_bytes", Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED))
	_peak(current, "texture_mem_peak_bytes", Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED))
	_peak(current, "draw_calls_peak", Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	_peak(current, "primitives_peak", Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	_peak(current, "objects_peak", Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))


## Logs every real (non-driver) key, mouse button, touch and joypad button event, so an unexpected Start press can be
## attributed. Driver input uses InputEventAction / Input.action_press and never appears here.
func _input(event: InputEvent) -> void:
	if _input_log.size() >= INPUT_LOG_LIMIT:
		return
	if not (event is InputEventKey or event is InputEventMouseButton or event is InputEventScreenTouch
			or event is InputEventJoypadButton):
		return
	var scene: Node = get_tree().current_scene
	var entry: Dictionary = {"at_ms": Time.get_ticks_msec(), "type": event.get_class(), "device": event.device,
		"pressed": event.is_pressed(), "scene": str(scene.name) if scene != null else "", "text": event.as_text()}
	if event is InputEventMouseButton:
		var position: Vector2 = (event as InputEventMouseButton).position
		entry["position"] = [roundi(position.x), roundi(position.y)]
	_input_log.append(entry)


func _run() -> void:
	await _wait(MENU_IDLE_S)
	var menu: Node = get_tree().current_scene
	if menu != null and menu.name != "MainMenu":
		# Something other than the driver pressed Start during menu idle (QA139/QA140: a real click or key reached the
		# focused Start button). Keep measuring the mission, flag it, and keep the input log for diagnosis.
		_step("shift_started_before_driver_in_" + str(menu.name), false)
	else:
		var start: Variant = menu.get("start_button") if menu != null else null
		var started: bool = start is Button and not (start as Button).disabled
		_step("menu_start_available", started)
		if not started:
			_finish(3)
			return
		# The menu's own Start action; a fresh profile has no checkpoint to confirm.
		(start as Button).pressed.emit()
		var confirm: Node = menu.get_node_or_null("ReplaceCheckpointConfirmation")
		if confirm is ConfirmationDialog and (confirm as ConfirmationDialog).visible:
			(confirm as ConfirmationDialog).get_ok_button().pressed.emit()
			_step("replace_checkpoint_confirmed", true)
	var loaded: bool = await _wait_for_scene("MissionRoot", MISSION_LOAD_TIMEOUT_S)
	_step("mission_loaded", loaded)
	if not loaded:
		_finish(4)
		return
	# DS09: the mission keeps its loading card up while the shader warm-up runs; idle measurement starts on the first
	# frame the player can see. The warm-up's own frames stay in segment 0, and its stats go into the report.
	var warmed: bool = await _wait_for_warmup(MISSION_LOAD_TIMEOUT_S)
	_step("shader_warmup_done", warmed)
	_begin_segment(1)
	await _wait(MISSION_IDLE_S)
	_begin_segment(2)
	await _walk_and_look()
	_begin_segment(3)
	await _toggle_cycles("map_meter", "tablet", TABLET_CYCLES, TABLET_STATE_S)
	_begin_segment(4)
	await _toggle_cycles("pause", "_pause_panel", PAUSE_CYCLES, PAUSE_STATE_S)
	_begin_segment(5)
	await _wait(FINAL_IDLE_S)
	_finish(0)


func _walk_and_look() -> void:
	_hold("move_forward", 1.0)
	var turns: int = int(WALK_S / WALK_TURN_EVERY_S)
	for index: int in range(turns):
		var look: String = "look_left" if index % 2 == 0 else "look_right"
		_hold(look, WALK_LOOK_STRENGTH)
		if index % 3 == 2:
			_hold("sprint", 1.0)
		await _wait(WALK_TURN_EVERY_S)
		_release(look)
		_release("sprint")
	_release_all()
	_step("walk_completed", true)


## Each cycle presses the action once to open and once to close, and checks the panel really changed state.
func _toggle_cycles(action: String, panel_property: String, cycles: int, state_s: float) -> void:
	var observed_open: int = 0
	var observed_closed: int = 0
	for _cycle: int in range(cycles):
		_tap(action)
		await _wait(state_s)
		if _panel_visible(panel_property):
			observed_open += 1
		_tap(action)
		await _wait(state_s)
		if not _panel_visible(panel_property):
			observed_closed += 1
	_step("%s_opened_%d_of_%d" % [action, observed_open, cycles], observed_open == cycles)
	_step("%s_closed_%d_of_%d" % [action, observed_closed, cycles], observed_closed == cycles)


func _panel_visible(property: String) -> bool:
	var scene: Node = get_tree().current_scene
	if scene == null:
		return false
	var panel: Variant = scene.get(property)
	return panel is CanvasItem and (panel as CanvasItem).visible


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


func _hold(action: String, strength: float) -> void:
	Input.action_press(action, strength)
	if not _held_actions.has(action):
		_held_actions.append(action)


func _release(action: String) -> void:
	Input.action_release(action)
	_held_actions.erase(action)


func _release_all() -> void:
	for action: String in _held_actions.duplicate():
		Input.action_release(action)
	_held_actions.clear()


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, false, true).timeout


func _wait_for_scene(scene_name: String, timeout_s: float) -> bool:
	var deadline_usec: int = Time.get_ticks_usec() + int(timeout_s * 1000000.0)
	while Time.get_ticks_usec() < deadline_usec:
		var scene: Node = get_tree().current_scene
		if scene != null and scene.name == scene_name and scene.is_node_ready():
			return true
		await get_tree().process_frame
	return false


func _wait_for_warmup(timeout_s: float) -> bool:
	var deadline_usec: int = Time.get_ticks_usec() + int(timeout_s * 1000000.0)
	while Time.get_ticks_usec() < deadline_usec:
		var scene: Node = get_tree().current_scene
		if scene == null or not scene.has_method("is_warming") or not bool(scene.call("is_warming")):
			return true
		await get_tree().process_frame
	return false


func _begin_segment(index: int) -> void:
	_segment = index
	if _probe != null and _probe.has_method("mark_segment"):
		_probe.call("mark_segment", index)
	_segments.append({
		"segment": index, "name": SEGMENT_NAMES[index], "started_ms": Time.get_ticks_msec(), "frames": 0,
		"video_mem_peak_bytes": 0, "texture_mem_peak_bytes": 0,
		"draw_calls_peak": 0, "primitives_peak": 0, "objects_peak": 0,
	})


func _peak(segment: Dictionary, key: String, value: float) -> void:
	segment[key] = maxi(int(segment[key]), int(value))


func _warmup_stats() -> Dictionary:
	var scene: Node = get_tree().current_scene
	var stats: Variant = scene.get("warmup_stats") if scene != null else null
	return stats if stats is Dictionary else {}


func _step(label: String, ok: bool) -> void:
	_steps.append({"step": label, "ok": ok, "at_ms": Time.get_ticks_msec()})


func _finish(exit_code: int) -> void:
	_release_all()
	set_process(false)
	var report: Dictionary = {
		"schema_version": SCHEMA_VERSION,
		"session_id": _session_id,
		"exit_code": exit_code,
		"engine": str(Engine.get_version_info()["string"]),
		"rendering_method": RenderingServer.get_current_rendering_method(),
		"rendering_driver": RenderingServer.get_current_rendering_driver_name(),
		"adapter_vendor": RenderingServer.get_video_adapter_vendor(),
		"adapter_name": RenderingServer.get_video_adapter_name(),
		"adapter_api_version": RenderingServer.get_video_adapter_api_version(),
		"window_mode": DisplayServer.window_get_mode(),
		"vsync_mode": DisplayServer.window_get_vsync_mode(),
		"viewport_size": [int(get_viewport().get_visible_rect().size.x), int(get_viewport().get_visible_rect().size.y)],
		"screen_refresh_hz": DisplayServer.screen_get_refresh_rate(),
		"segments": _segments,
		"steps": _steps,
		"shader_warmup": _warmup_stats(),
		"real_input_events": _input_log,
	}
	var file: FileAccess = FileAccess.open("user://qa56/%s_qa140.json" % _session_id, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "  ", false) + "\n")
		file.close()
	print("QA140_SCENARIO_DONE exit=%d adapter=%s method=%s" % [
		exit_code, report["adapter_name"], report["rendering_method"]])
	get_tree().quit(exit_code)
