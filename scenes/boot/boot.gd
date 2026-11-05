extends Node
## Boot scene (F01 placeholder). Logs the build identity so an exported build can be matched to its manifest.
## Windowed solo builds enter the main menu. Headless CI keeps the reproducible boot log and save-soak hooks.

const SaveSoak := preload("res://scripts/persistence/save_soak.gd")
const QA56FrameProbe := preload("res://scripts/diagnostics/qa56_frame_probe.gd")
const MANIFEST_PATH: String = "res://build_manifest.json"
const MENU_PATH: String = "res://scenes/menu/main_menu.tscn"


func _ready() -> void:
	print("Lights Back On boot | engine %s | build %s" % [Engine.get_version_info()["string"], _build_id()])
	_start_qa56_capture_if_requested()
	var mode: String = SaveSoak.requested_mode(OS.get_cmdline_user_args())
	if mode != "":
		_run_save_soak(mode)
	elif DisplayServer.get_name() != "headless":
		# The exported headless smoke retains the same boot line; only a real
		# windowed launch enters the playable offline-first main menu.
		get_tree().call_deferred("change_scene_to_file", MENU_PATH)


## G06 kill test hooks (internal builds only; see save_soak.gd).
func _run_save_soak(mode: String) -> void:
	if not SaveSoak.allowed():
		print("save soak is not available in this build")
		return
	var soak: SaveSoak = SaveSoak.new()
	soak.name = "SaveSoak"
	soak.setup(_build_id())
	add_child(soak)
	if mode == SaveSoak.ARG_VERIFY:
		get_tree().quit(soak.verify())
	else:
		soak.start_soak()


func _build_id() -> String:
	if not FileAccess.file_exists(MANIFEST_PATH):
		return "unmanifested-dev"
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	if parsed is Dictionary and (parsed as Dictionary).has("build_id"):
		return str((parsed as Dictionary)["build_id"])
	return "manifest-unreadable"


## Opt-in physical Windows export profiling. Not started by normal gameplay or CI.
## A session ID is caller-generated and contains no account/device identifiers.
func _start_qa56_capture_if_requested() -> void:
	if OS.get_name() != "Windows" or DisplayServer.get_name() == "headless":
		return
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if not args.has("--qa56-capture"):
		return
	var session_id: String = ""
	for arg: String in args:
		if arg.begins_with("--qa56-id="):
			session_id = arg.trim_prefix("--qa56-id=")
			break
	if not QA56FrameProbe.valid_session_id(session_id):
		push_warning("QA56: invalid or missing session ID; capture disabled")
		return
	var probe := QA56FrameProbe.new()
	probe.name = "QA56FrameProbe"
	get_tree().root.add_child(probe)
	if not probe.configure(session_id):
		probe.queue_free()
