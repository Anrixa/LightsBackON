extends RefCounted
## EXP021 A02: original procedural spatial audio for the 200 host-bound scenes.
## A host response is the only source of command-success cues. Ambient storm is
## cosmetic; restoration crossfade uses validated host/PowerGrid snapshots.
## No third-party recordings, audio downloads, music samples or external rights.

const Art := preload("res://scripts/world/exp021_environment_art.gd")
const QUALIFICATION: String = "HEADLESS_SOURCE_AUDIO_ONLY_PHYSICAL_STEAM_RELEASE_HELD"
const SAMPLE_RATE: int = 22050
const LOADS: Array[String] = ["LOAD_A", "LOAD_B", "LOAD_C"]
const TOOLS: Array[String] = ["meter", "screwdriver", "puller", "cutter", "crimper"]
const ACCEPTED_COMMANDS: Array[String] = [
	"inspect", "repair_step", "toggle_switch", "operate_worksite",
	"verify_mission", "request_lock", "release_lock", "ping"
]

var _world: Node3D
var _root: Node3D
var _storm: AudioStreamPlayer
var _recovery: AudioStreamPlayer
var _tool: AudioStreamPlayer3D
var _tool_samples: Dictionary = {}
var _last_host_revision: int = -1
var _last_grid_tick: int = -1
var _level_id: String = ""
var _event_count: int = 0
var _last_tool: String = ""
var _storm_target_db: float = -14.0
var _recovery_target_db: float = -75.0
var _verified: bool = false


static func inspect(plan: Dictionary) -> Dictionary:
	var art: Dictionary = Art.inspect(plan)
	if not bool(art.get("ok", false)):
		return {"ok": false, "code": "EXP021_A02_SOURCE_REJECTED"}
	var stations: Variant = plan.get("stations")
	if not stations is Array or stations.size() != 5:
		return {"ok": false, "code": "EXP021_A02_MISSING_STATIONS"}
	for i: int in range(5):
		var station: Dictionary = stations[i]
		if station.get("id") != "JOB_%03d_%d" % [int(plan["serial"]), i + 1] or \
				not station.get("position") is Vector3 or \
				not (station["position"] as Vector3).is_finite():
			return {"ok": false, "code": "EXP021_A02_SOURCE_POSITION_DRIFT"}
	return {"ok": true, "level_id": str(art["level_id"]),
		"region_id": str(art["region_id"]),
		"signature": (str(art["source_signature"]) + "|audio_v1").sha256_text(),
		"qualification": QUALIFICATION, "authority": "READ_ONLY_HOST_AUDIO"}


static func _wave(kind: String, looped: bool = false) -> AudioStreamWAV:
	var frames: int = 22050 if looped else 3308
	var pcm: PackedByteArray = PackedByteArray()
	pcm.resize(frames * 2)
	var low_noise: float = 0.0
	for i: int in range(frames):
		var phase: float = float(i) / float(frames)
		var t: float = float(i) / float(SAMPLE_RATE)
		var noise: float = float(((i * 1103515245 + 12345) >> 9) & 65535) / 32767.5 - 1.0
		low_noise = low_noise * 0.86 + noise * 0.14
		var sound: float = 0.0
		match kind:
			"storm":
				sound = 0.30 * low_noise + 0.08 * noise
			"recovery":
				sound = 0.10 * sin(TAU * 110.0 * t) + \
					0.07 * sin(TAU * 220.0 * t)
			"meter":
				sound = 0.27 * sin(TAU * 880.0 * t) * \
					(1.0 if phase < 0.26 or (phase > 0.40 and phase < 0.67) else 0.0)
			"screwdriver":
				sound = 0.18 * sin(TAU * (135.0 + phase * 190.0) * t) + 0.08 * low_noise
			"puller":
				sound = (0.31 * low_noise + 0.17 * sin(TAU * 80.0 * t)) * pow(1.0 - phase, 2.0)
			"cutter":
				sound = (0.31 * low_noise + 0.09 * noise) * pow(1.0 - phase, 1.4)
			"crimper":
				sound = (0.29 * noise + 0.13 * sin(TAU * 105.0 * t)) * pow(1.0 - phase, 2.2)
			_:
				sound = 0.24 * sin(TAU * 520.0 * t) * (1.0 - phase)
		var edge: float = minf(1.0, minf(phase, 1.0 - phase) * 60.0)
		var envelope: float = 1.0 if looped else pow(1.0 - phase, 0.8)
		pcm.encode_s16(i * 2, roundi(clampf(sound * edge * envelope, -1.0, 1.0) * 32767.0))
	var stream: AudioStreamWAV = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.data = pcm
	if looped:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = frames
	return stream


func setup(world: Node3D, plan: Dictionary) -> Dictionary:
	var audit: Dictionary = inspect(plan)
	if not bool(audit.get("ok", false)) or world == null or \
			str(world.get_meta("source_level_id", "")) != str(audit.get("level_id", "")) or \
			world.get_node_or_null("EXP021_A02_SpatialAudio") != null:
		return {"ok": false, "code": "EXP021_A02_BINDING_REJECTED"}
	_world = world
	_level_id = str(audit["level_id"])
	_root = Node3D.new()
	_root.name = "EXP021_A02_SpatialAudio"
	_root.set_meta("source_level_id", _level_id)
	_root.set_meta("source_signature", audit["signature"])
	_root.set_meta("qualification", QUALIFICATION)
	_root.set_meta("read_only", true)
	world.add_child(_root)
	_storm = AudioStreamPlayer.new()
	_storm.name = "StormBed"
	_storm.stream = _wave("storm", true)
	_storm.volume_db = _storm_target_db
	_root.add_child(_storm)
	_recovery = AudioStreamPlayer.new()
	_recovery.name = "RecoveryBed"
	_recovery.stream = _wave("recovery", true)
	_recovery.volume_db = _recovery_target_db
	_root.add_child(_recovery)
	_tool = AudioStreamPlayer3D.new()
	_tool.name = "AcceptedToolCue3D"
	_tool.unit_size = 1.0
	_tool.max_distance = 18.0
	_tool.volume_db = -10.0
	_root.add_child(_tool)
	for kind: String in TOOLS:
		_tool_samples[kind] = _wave(kind)
	_tool_samples["confirmation"] = _wave("confirmation")
	if DisplayServer.get_name() != "headless":
		_storm.play()
		_recovery.play()
	return {"ok": true, "level_id": _level_id, "qualification": QUALIFICATION,
		"source_audio_streams": _tool_samples.size() + 2}


## Validate *before* changing targets; corrupt or stale payloads are inert.
func reflect(board: Dictionary, grid: Dictionary) -> Dictionary:
	if _root == null or str(board.get("level_id", "")) != _level_id or \
			typeof(board.get("host_revision")) != TYPE_INT or \
			int(board["host_revision"]) < _last_host_revision or \
			typeof(board.get("mission_verified")) != TYPE_BOOL or \
			typeof(grid.get("tick")) != TYPE_INT or \
			int(grid["tick"]) < _last_grid_tick or \
			not grid.get("nodes") is Dictionary:
		return {"ok": false, "code": "EXP021_A02_STALE_OR_INVALID_HOST"}
	var nodes: Dictionary = grid["nodes"]
	if not nodes.get("GRID") is Dictionary or \
			typeof(nodes["GRID"].get("online")) != TYPE_BOOL:
		return {"ok": false, "code": "EXP021_A02_BAD_GRID_SOURCE"}
	var supplied: int = 0
	for load: String in LOADS:
		if not nodes.get(load) is Dictionary or \
				typeof(nodes[load].get("supplied")) != TYPE_BOOL:
			return {"ok": false, "code": "EXP021_A02_BAD_CONSUMER"}
		if bool(nodes[load]["supplied"]):
			if not bool(nodes["GRID"]["online"]):
				return {"ok": false, "code": "EXP021_A02_IMPOSSIBLE_SUPPLY"}
			supplied += 1
	_verified = bool(board["mission_verified"]) and supplied == LOADS.size()
	_storm_target_db = -37.0 if _verified else -14.0
	_recovery_target_db = -17.0 if _verified else -75.0
	_last_host_revision = int(board["host_revision"])
	_last_grid_tick = int(grid["tick"])
	return {"ok": true, "verified": _verified, "supplied": supplied,
		"authority": "READ_ONLY_HOST_AUDIO"}


func advance(delta: float) -> void:
	if _root == null:
		return
	_storm.volume_db = move_toward(_storm.volume_db, _storm_target_db, maxf(0.0, delta) * 12.0)
	_recovery.volume_db = move_toward(_recovery.volume_db, _recovery_target_db, maxf(0.0, delta) * 16.0)


## Call only with the direct SessionHost response to one transmitted command.
## Denied commands, malformed replies and unrecognized tools produce no cue.
func play_confirmed_command(reply: Dictionary, kind: String,
		tool: String, global_position: Vector3) -> bool:
	if _root == null or reply.get("ok") != true or \
			not ACCEPTED_COMMANDS.has(kind) or not TOOLS.has(tool) or \
			not global_position.is_finite():
		return false
	_tool.stream = _tool_samples[tool] if kind == "repair_step" else _tool_samples["confirmation"]
	# Detached headless fixtures have no global transform; only live stage
	# nodes use global_position. Both paths preserve the accepted host cue.
	if _tool.is_inside_tree():
		_tool.global_position = global_position
	else:
		_tool.position = global_position
	_last_tool = tool if kind == "repair_step" else "confirmation"
	_event_count += 1
	if DisplayServer.get_name() != "headless":
		_tool.play()
	return true


func event_count() -> int:
	return _event_count


func last_cue() -> String:
	return _last_tool


func is_verified() -> bool:
	return _verified


func audio_root() -> Node3D:
	return _root
