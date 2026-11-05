extends Node
## QA56 opt-in local frame-interval logger for exported Windows builds.
## It is not a GPU-present timestamp or end-to-end input-latency measurement.
## No network, personal identifiers, or telemetry upload. Disabled by default.

const FLUSH_EVERY_FRAMES: int = 240

var _log: FileAccess
var _started_usec: int = 0
var _last_usec: int = 0
var _segment: int = 0
var _pending: Array[String] = []


static func valid_session_id(value: String) -> bool:
	if value.length() != 32:
		return false
	for index: int in range(value.length()):
		if not "0123456789abcdef".contains(value.substr(index, 1).to_lower()):
			return false
	return true


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)
	set_process_input(false)


func configure(session_id: String) -> bool:
	if not valid_session_id(session_id):
		return false
	var directory: String = ProjectSettings.globalize_path("user://qa56")
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		push_warning("QA56: failed to create local capture directory")
		return false
	_log = FileAccess.open("user://qa56/%s.csv" % session_id, FileAccess.WRITE)
	if _log == null:
		push_warning("QA56: failed to open local capture")
		return false
	_log.store_line("elapsed_ms,frame_ms,scene,segment")
	_started_usec = Time.get_ticks_usec()
	_last_usec = 0
	set_process(true)
	set_process_input(true)
	print("QA56_CAPTURE_STARTED session=%s path=user://qa56/%s.csv" % [session_id, session_id])
	return true


func _process(_delta: float) -> void:
	if _log == null:
		return
	var now_usec: int = Time.get_ticks_usec()
	if _last_usec != 0:
		var scene: Node = get_tree().current_scene
		var scene_name: String = "Transition"
		if scene != null:
			# Only the authored scene category is recorded, not file paths.
			if scene.name == "MainMenu":
				scene_name = "MainMenu"
			elif scene.name == "MissionRoot":
				scene_name = "MissionRoot"
			else:
				scene_name = "Other"
		var elapsed_ms: float = float(now_usec - _started_usec) / 1000.0
		var interval_ms: float = float(now_usec - _last_usec) / 1000.0
		_pending.append("%.3f,%.3f,%s,%d" % [
			elapsed_ms, interval_ms, scene_name, _segment
		])
		if _pending.size() >= FLUSH_EVERY_FRAMES:
			_flush()
	_last_usec = now_usec


func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key: InputEventKey = event as InputEventKey
		if key.pressed and not key.echo and key.physical_keycode == KEY_F9:
			_segment += 1
			print("QA56_SEGMENT=%d" % _segment)


func _notification(what: int) -> void:
	if what == NOTIFICATION_EXIT_TREE or what == NOTIFICATION_PREDELETE:
		_flush()


func _flush() -> void:
	if _log == null or _pending.is_empty():
		return
	for line: String in _pending:
		_log.store_line(line)
	_pending.clear()
	_log.flush()
