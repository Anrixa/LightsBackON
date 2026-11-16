extends "res://tests/test_case.gd"
## DS12: real host-driven recovery is legible without audio and without
## flashes/camera motion. The fake host states below are avoided: we drive
## valid C01 grid/equipment mutations through an isolated Offline session.

const Scene := preload("res://scenes/world/alder_street.tscn")
const MissionScene := preload("res://scenes/mission/mission_root.tscn")
const Offline := preload("res://scripts/gameplay/offline_c01_session.gd")
const Dressing := preload("res://scripts/world/street_dressing.gd")
const StreetLook := preload("res://scripts/world/street_look.gd")
const District := preload("res://scripts/world/district_builder.gd")
const RecoveryPayoff := preload("res://scripts/world/recovery_payoff_presentation.gd")
const Soundscape := preload("res://scripts/world/storm_soundscape.gd")
const Grid := preload("res://scripts/simulation/power_grid.gd")

var _tree: SceneTree
var _holder: Node3D
var _world: Node3D
var _fx: RecoveryPayoff
var _session: Offline


func before_each() -> void:
	_tree = Engine.get_main_loop() as SceneTree
	_holder = Node3D.new()
	_tree.root.add_child(_holder)
	_world = Scene.instantiate() as Node3D
	_world.name = "District"
	_holder.add_child(_world)
	var district: Dictionary = District.load_district()
	var look: Dictionary = StreetLook.load_look()
	StreetLook.skin_world(_world, look, district)
	Dressing.new().build(_world, district, look, Dressing.load_dressing())
	_fx = RecoveryPayoff.new()
	_fx.setup(_world)
	_session = Offline.new()
	var errors: Array[Dictionary] = _session.setup(
		func(_player: String, _target: String) -> bool: return true,
		func(_player: String) -> Vector3i: return Vector3i(450, 100, 1500))
	assert_eq(errors, [] as Array[Dictionary])


func after_each() -> void:
	_fx = null
	_session = null
	_tree.root.remove_child(_holder)
	_holder.free()
	_holder = null
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _restore_west() -> void:
	var a: Dictionary = _session.grid.apply({"op": "set", "id": "JW", "field": "failed", "value": false})
	assert_true(bool(a.get("ok", false)))
	var b: Dictionary = _session.grid.apply({"op": "set", "id": "JW", "field": "tripped", "value": false})
	assert_true(bool(b.get("ok", false)))


func _generator(action: String, extra: Dictionary = {}) -> Dictionary:
	var payload: Dictionary = {"action": action}
	payload.merge(extra)
	return _session.command("place_item", "GEN_PORTABLE", payload)


func test_DS12_recovery_dressing_is_visual_only_and_has_no_collision() -> void:
	var holder: Node3D = _world.get_node("DS12RecoveryPayoff") as Node3D
	assert_eq(holder.find_children("*", "CollisionObject3D", true, false).size(), 0)
	assert_eq(holder.find_children("*", "CollisionShape3D", true, false).size(), 0)
	for id: String in ["APT_W", "MARKET", "PUB", "APT_E", "WORKSHOP"]:
		var fascia: Node3D = _world.get_node("Dressing/Fascia_" + id) as Node3D
		assert_true(fascia.get_node_or_null("DS12Sign") is Node3D)
		assert_true(fascia.get_node_or_null("DS12Sign/DS12VentRotor") is Node3D)
		assert_true(holder.get_node_or_null("DS12Spill_" + id) is MeshInstance3D)
	assert_eq(_fx.active_transitions(), 0)


func test_DS12_initial_dark_street_has_no_fake_light_or_restore_audio() -> void:
	var frozen: String = Grid.serialize(_session.host_state())
	_fx.apply(_session.host_state())
	for id: String in ["APT_W", "MARKET", "PUB", "APT_E", "WORKSHOP"]:
		assert_eq(_fx.state_of(id), "dark")
		assert_eq(_fx.sign_intensity(id), 0.0)
		assert_eq(_fx.spill_intensity(id), 0.0)
	assert_eq(_fx.soundscape().restored_count(), 0)
	assert_eq(Grid.serialize(_session.host_state()), frozen)


func test_DS12_windows_first_then_neon_then_spill_per_valid_recovery() -> void:
	_fx.set_reduce_flashes(false)
	_fx.apply(_session.host_state())
	_restore_west()
	_fx.apply(_session.host_state())
	assert_eq(_fx.state_of("APT_W"), "grid")
	assert_eq(_fx.state_of("MARKET"), "grid")
	assert_eq(_fx.state_of("PUB"), "dark")
	assert_eq(_fx.sign_intensity("APT_W"), 0.0, "sign has not lit before window cascade")
	_fx.advance(1.00)
	assert_true(_fx.sign_intensity("APT_W") > 0.0, "neon comes after the window's initial delay")
	assert_eq(_fx.spill_intensity("APT_W"), 0.0, "pavement light comes last")
	_fx.advance(2.00)
	assert_eq(_fx.sign_intensity("APT_W"), 1.0)
	assert_eq(_fx.spill_intensity("APT_W"), 1.0)
	assert_eq(_fx.sign_intensity("PUB"), 0.0)
	assert_eq(_fx.soundscape().restored_count(), 2)


func test_DS12_generator_power_is_temporary_and_cannot_fake_grid_neon() -> void:
	_fx.apply(_session.host_state())
	assert_true(bool(_generator("pickup").get("ok", false)))
	assert_true(bool(_generator("place", {"anchor": "PAD_PUMP"}).get("ok", false)))
	assert_true(bool(_generator("connect", {"route": "E_TEMP_PUB"}).get("ok", false)))
	assert_true(bool(_generator("start").get("ok", false)))
	_fx.apply(_session.host_state())
	_fx.advance(5.0)
	assert_eq(_fx.state_of("PUB"), "temporary")
	assert_eq(_fx.sign_intensity("PUB"), 0.0, "temporary is not credited as a grid restoration")
	assert_eq(_fx.spill_intensity("PUB"), 0.0)
	assert_eq(_fx.soundscape().restored_count(), 0)
	assert_true(_fx.soundscape().generator_volume() > -70.0)


func test_DS12_interrupted_restore_fades_from_actual_rendered_level() -> void:
	_fx.set_reduce_flashes(false)
	_fx.apply(_session.host_state())
	_restore_west()
	_fx.apply(_session.host_state())
	_fx.advance(1.7)
	var seen: float = _fx.sign_intensity("APT_W")
	assert_true(seen > 0.0)
	var off: Dictionary = _session.grid.apply({"op": "set", "id": "JW", "field": "tripped", "value": true})
	assert_true(bool(off.get("ok", false)))
	_fx.apply(_session.host_state())
	assert_eq(_fx.state_of("APT_W"), "dark")
	assert_eq(_fx.sign_intensity("APT_W"), seen, "no artificial jump at interruption")
	_fx.advance(2.2)
	assert_eq(_fx.sign_intensity("APT_W"), 0.0)
	assert_eq(_fx.spill_intensity("APT_W"), 0.0)


func test_DS12_reduce_flashes_rebases_without_a_brightness_jump() -> void:
	_fx.set_reduce_flashes(false)
	_fx.apply(_session.host_state())
	_restore_west()
	_fx.apply(_session.host_state())
	_fx.advance(1.5)
	var sign_before: float = _fx.sign_intensity("MARKET")
	var spill_before: float = _fx.spill_intensity("MARKET")
	_fx.set_reduce_flashes(true)
	assert_eq(_fx.sign_intensity("MARKET"), sign_before)
	assert_eq(_fx.spill_intensity("MARKET"), spill_before)
	_fx.advance(0.3)
	assert_true(_fx.sign_intensity("MARKET") >= sign_before)
	assert_true(_fx.spill_intensity("MARKET") >= spill_before)
	assert_true(_fx.sign_intensity("MARKET") <= 1.0)


func test_DS12_reduce_motion_freezes_rotor_without_losing_supply_feedback() -> void:
	_fx.apply(_session.host_state())
	_restore_west()
	_fx.apply(_session.host_state())
	_fx.advance(5.0)
	var rotor: Node3D = _world.get_node("Dressing/Fascia_APT_W/DS12Sign/DS12VentRotor") as Node3D
	_fx.set_reduce_motion(true)
	var angle: float = rotor.rotation.z
	_fx.advance(0.5)
	assert_eq(rotor.rotation.z, angle)
	assert_eq(_fx.state_of("APT_W"), "grid")
	_fx.set_reduce_motion(false)
	_fx.advance(0.5)
	assert_true(rotor.rotation.z != angle, "normal ventilation has the authored rotating fan")


func test_DS12_soundscape_uses_only_original_samples_and_grid_power() -> void:
	var sound: Soundscape = _fx.soundscape()
	for family: String in ["rain", "thunder", "generator", "music", "stinger"]:
		assert_true(sound.sample_bytes(family) > 0, "generated WAV has samples: " + family)
	assert_eq(sound.vent_volume("PUB"), -80.0)
	assert_eq(sound.generator_volume(), -80.0)
	_fx.apply(_session.host_state())
	var before: float = sound.music_volume()
	_restore_west()
	_fx.apply(_session.host_state())
	assert_true(sound.music_volume() > before, "more verified grid restoration opens the original music bed")
	assert_true(sound.vent_volume("APT_W") > sound.vent_volume("PUB"))
	assert_eq(sound.restored_count(), 2)


func test_DS12_cosmetic_frame_clock_cannot_change_grid_or_save_causes() -> void:
	_fx.apply(_session.host_state())
	_restore_west()
	_fx.apply(_session.host_state())
	var frozen: String = Grid.serialize(_session.host_state())
	var causes: String = Grid.serialize(_session.grid.causes())
	for i: int in 7:
		_fx.advance(0.55)
		if i == 2:
			_fx.set_reduce_flashes(false)
			_fx.set_reduce_motion(true)
	assert_eq(Grid.serialize(_session.host_state()), frozen)
	assert_eq(Grid.serialize(_session.grid.causes()), causes)


func test_DS12_results_uses_a_static_camera_over_the_real_street() -> void:
	var mission: Node = MissionScene.instantiate()
	_holder.add_child(mission)
	var result_view: SubViewportContainer = mission.find_child("ResultsStreetPreview", true, false) as SubViewportContainer
	assert_true(result_view != null)
	assert_eq(result_view.focus_mode, Control.FOCUS_NONE)
	var viewport: SubViewport = result_view.get_node("ResultsLiveWorld") as SubViewport
	assert_true(viewport.world_3d == mission.get_world_3d(), "no separate fake-world render")
	var camera: Camera3D = viewport.get_node("StaticStreetCamera") as Camera3D
	assert_true(camera.current)
	var player: Node = mission.get("player")
	var camera_before: Transform3D = (player.get("camera") as Camera3D).global_transform
	assert_true(camera.global_position != Vector3.ZERO)
	assert_eq((player.get("camera") as Camera3D).global_transform, camera_before,
		"result preview must not move the current player camera, even without Reduce Motion")
