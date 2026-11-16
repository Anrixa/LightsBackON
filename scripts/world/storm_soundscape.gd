extends RefCounted
## DS12 original procedural rain/thunder, generator/vent hum and recovery cue.
## All electrical audio levels are driven by authenticated host supply states.
## Weather is a non-gameplay ambient loop; no lightning flashes or licensed files.
## Headless CI constructs the streams but never opens an audio output.

const RestorationPresentation := preload("res://scripts/world/restoration_presentation.gd")

var _config: Dictionary = {}
var _root: Node3D
var _rain: AudioStreamPlayer
var _thunder: AudioStreamPlayer
var _generator: AudioStreamPlayer3D
var _music: AudioStreamPlayer
var _stinger: AudioStreamPlayer
var _vent_sounds: Dictionary = {}
var _last_states: Dictionary = {}
var _started: bool = false
var _thunder_elapsed_s: float = 0.0
var _restored_count: int = 0


func setup(world: Node3D, config: Dictionary) -> void:
	_config = config.duplicate(true)
	_last_states.clear()
	_vent_sounds.clear()
	_started = false
	_thunder_elapsed_s = 0.0
	_restored_count = 0
	_root = Node3D.new()
	_root.name = "DS12Soundscape"
	world.add_child(_root)
	_rain = _ambient("RainBed", "rain", true, float(config["rain_db"]))
	_thunder = _ambient("DistantThunder", "thunder", false, float(config["thunder_db"]))
	_music = _ambient("MusicBed", "music", true, -80.0)
	_stinger = _ambient("RestorationStinger", "stinger", false, float(config["stinger_db"]))
	var generator: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
	generator.name = "GeneratorHum"
	generator.stream = _wave("generator", true)
	generator.volume_db = -80.0
	generator.unit_size = 1.0
	generator.max_distance = 16.0
	_root.add_child(generator)
	var coords: Array = config["reference_generator_cm"]
	generator.position = Vector3(float(coords[0]), float(coords[1]), float(coords[2])) / 100.0
	_generator = generator
	var shared_hum: AudioStreamWAV = _wave("building", true)
	for service: String in RestorationPresentation.SERVICES:
		var holder: Node3D = world.get_node_or_null(NodePath("Dressing/Fascia_" + service)) as Node3D
		if holder == null:
			continue
		var vent: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
		vent.name = "DS12VentHum"
		vent.stream = shared_hum
		vent.volume_db = -80.0
		vent.unit_size = 1.0
		vent.max_distance = 14.0
		holder.add_child(vent)
		_vent_sounds[service] = vent
	if DisplayServer.get_name() != "headless":
		_rain.play()
		_music.play()
		_generator.play()
		for node: AudioStreamPlayer3D in _vent_sounds.values():
			node.play()


func _ambient(name: String, tone: String, repeat: bool, db: float) -> AudioStreamPlayer:
	var node: AudioStreamPlayer = AudioStreamPlayer.new()
	node.name = name
	node.stream = _wave(tone, repeat)
	node.volume_db = db
	_root.add_child(node)
	return node


## Original sample construction; no encoded media or downloadable asset.
## Frequencies are original simple waveforms, not copies of an existing song.
func _wave(kind: String, repeat: bool) -> AudioStreamWAV:
	var rate: int = int(_config["sample_rate"])
	var duration_ms: int = int(_config["loop_ms"] if repeat else _config["stinger_ms"])
	var frames: int = maxi(16, rate * duration_ms / 1000)
	var data: PackedByteArray = PackedByteArray()
	data.resize(frames * 2)
	var noise_memory: float = 0.0
	for i: int in frames:
		var t: float = float(i) / float(rate)
		var phase: float = float(i) / float(frames)
		var noise: float = float(((i * 1103515245 + 12345) >> 8) & 65535) / 32767.5 - 1.0
		noise_memory = noise_memory * 0.92 + noise * 0.08
		var sound: float = 0.0
		match kind:
			"rain":
				sound = 0.52 * noise_memory + 0.12 * noise
			"thunder":
				sound = 0.25 * sin(TAU * 37.0 * t) + noise_memory * 0.28
			"generator":
				sound = 0.34 * sin(TAU * 92.0 * t) + 0.12 * sin(TAU * 184.0 * t)
			"building":
				sound = 0.23 * sin(TAU * 74.0 * t) + 0.1 * sin(TAU * 148.0 * t)
			"music":
				sound = 0.10 * (sin(TAU * 110.0 * t) +
					0.7 * sin(TAU * 164.0 * t) + 0.7 * sin(TAU * 220.0 * t))
			"stinger":
				sound = 0.21 * (sin(TAU * 293.0 * t) + 0.62 * sin(TAU * 440.0 * t))
		# Smooth sample boundaries (and soften the transients of non-loop cues).
		var edge: float = minf(1.0, minf(phase, 1.0 - phase) * 100.0)
		var envelope: float = edge if repeat else edge * pow(1.0 - phase, 1.4)
		var value: int = roundi(clampf(sound * envelope, -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 2, value)
	var wav: AudioStreamWAV = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo = false
	wav.data = data
	if repeat:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = frames
	return wav


## Called with states computed from the actual host snapshot. On a checkpoint
## restore, initial grid lights do not fabricate five simultaneous stingers.
func apply(states: Dictionary, generator_online: bool) -> void:
	var count: int = 0
	var newly_restored: bool = false
	for service: String in RestorationPresentation.SERVICES:
		var status: String = str(states.get(service, "dark"))
		if status == "grid":
			count += 1
		if _started and status == "grid" and str(_last_states.get(service, "")) != "grid":
			newly_restored = true
		if _vent_sounds.has(service):
			(_vent_sounds[service] as AudioStreamPlayer3D).volume_db = float(_config["building_db"]) if status == "grid" else -80.0
		_last_states[service] = status
	_restored_count = count
	_generator.volume_db = float(_config["generator_db"]) if generator_online else -80.0
	_music.volume_db = lerpf(-80.0, float(_config["music_db_at_full_restoration"]),
		float(count) / float(maxi(1, RestorationPresentation.SERVICES.size())))
	if newly_restored and DisplayServer.get_name() != "headless":
		_stinger.play()
	_started = true


## Weather clock is local presentation only. Thunder has sound but no flash.
func advance(delta: float) -> void:
	if _root == null:
		return
	_thunder_elapsed_s += maxf(0.0, delta)
	var interval: float = float(_config["distant_thunder_interval_seconds"])
	if _thunder_elapsed_s >= interval:
		_thunder_elapsed_s = fmod(_thunder_elapsed_s, interval)
		if DisplayServer.get_name() != "headless":
			_thunder.play()


func restored_count() -> int:
	return _restored_count


func vent_volume(service: String) -> float:
	if not _vent_sounds.has(service):
		return -80.0
	return (_vent_sounds[service] as AudioStreamPlayer3D).volume_db


func music_volume() -> float:
	return _music.volume_db


func generator_volume() -> float:
	return _generator.volume_db


func sample_bytes(kind: String) -> int:
	match kind:
		"rain": return (_rain.stream as AudioStreamWAV).data.size()
		"thunder": return (_thunder.stream as AudioStreamWAV).data.size()
		"music": return (_music.stream as AudioStreamWAV).data.size()
		"stinger": return (_stinger.stream as AudioStreamWAV).data.size()
		"generator": return (_generator.stream as AudioStreamWAV).data.size()
	return 0
