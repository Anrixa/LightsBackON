extends "res://tests/test_case.gd"
## A04 live integration tests use the real MissionRoot, player, panel, local
## profile writer, onboarding adapter and world lighting. Headless CI is not
## a substitute for the separate UX01 controller/hardware acceptance.

const Offline := preload("res://scripts/gameplay/offline_c01_session.gd")
const Persistence := preload("res://scripts/persistence/offline_persistence.gd")
const Settings := preload("res://scripts/ui/accessibility_settings.gd")

var _scene: Node3D
var _tree: SceneTree
var _original: Dictionary = {}


func before_each() -> void:
	_tree = Engine.get_main_loop() as SceneTree
	_scene = (load("res://scenes/mission/mission_root.tscn") as PackedScene).instantiate()
	_tree.root.add_child(_scene)
	_original = (_scene.get("settings") as RefCounted).call("snapshot")


func after_each() -> void:
	if _scene != null and is_instance_valid(_scene):
		# The active profile belongs to CI's user://test_runtime sandbox.
		# Restore preferences so unrelated V07 tests cannot inherit toggles.
		if DisplayServer.get_name() == "headless":
			var model: RefCounted = _scene.get("settings")
			model.call("restore_snapshot", _original)
			_scene.call("_settings_changed", model.call("snapshot"), true)
		_tree.root.remove_child(_scene)
		_scene.free()
	_scene = null
	_tree.root.get_viewport().gui_release_focus()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func test_A04_active_mission_toggle_controls_actual_camera_without_blocking_look() -> void:
	var actor: CharacterBody3D = _scene.get("player")
	var camera: Camera3D = actor.get("camera")
	var panel: PanelContainer = _scene.get("accessibility")
	var motion: CheckBox = panel.get("motion_toggle")
	motion.set_pressed(true)
	assert_eq(float(actor.call("camera_motion_offset_y")), 0.0)
	var pitch: float = camera.rotation.x
	actor.call("_pitch", 0.12)
	assert_true(camera.rotation.x > pitch, "reduced motion never blocks the essential pitch control")
	motion.set_pressed(false)
	assert_false(bool((_scene.get("settings") as RefCounted).call("value", "reduce_camera_motion")))
	# A cosmetic displacement is removed immediately when the toggle changes.
	camera.position.y += 0.03
	motion.set_pressed(true)
	assert_eq(float(actor.call("camera_motion_offset_y")), 0.0)
	assert_true(is_equal_approx(camera.position.y, float(
		JSON.parse_string(FileAccess.get_file_as_string("res://content/world/kit_dimensions.json"))["camera_height_cm"])
		/ 100.0 - float(JSON.parse_string(FileAccess.get_file_as_string(
			"res://content/world/kit_dimensions.json"))["player_height_cm"]) / 200.0))
	assert_true(bool(actor.get("enabled")), "accessibility changes do not disable movement")
	assert_true(camera.rotation.x > pitch, "look rotation persists across cosmetic reset")


func test_A04_live_restoration_fade_is_monotone_and_rebases_mid_mission() -> void:
	var host: Offline = _fresh_production_host()
	var fx: RefCounted = _scene.get("_world_fx")
	var panel: PanelContainer = _scene.get("accessibility")
	var flashes: CheckBox = panel.get("flash_toggle")
	flashes.set_pressed(false)
	assert_false(bool(fx.call("reduce_flashes_enabled")))
	_restore_west(host)
	fx.call("apply", host.host_state(), false)
	assert_eq(fx.call("state_of", "APT_W"), "grid")
	assert_true(bool(fx.call("is_transitioning", "APT_W")))
	fx.call("advance", 0.21)
	var before: float = float(fx.call("light_energy_of", "APT_W"))
	assert_true(before > 0.0 and before < 0.55)
	flashes.set_pressed(true)
	assert_true(bool(fx.call("reduce_flashes_enabled")))
	assert_true(is_equal_approx(float(fx.call("light_energy_of", "APT_W")), before),
		"toggle mid-fade cannot cause a brightness spike")
	fx.call("advance", 0.21)
	var after: float = float(fx.call("light_energy_of", "APT_W"))
	assert_true(after >= before and after < 0.55, "reduced transition remains monotone and slower")
	fx.call("advance", 2.0)
	assert_false(bool(fx.call("is_transitioning", "APT_W")))
	assert_true(is_equal_approx(float(fx.call("light_energy_of", "APT_W")), 0.55))
	assert_eq(fx.call("state_of", "APT_W"), "grid",
		"essential restored/unpowered state remains readable with reduced flashes")
	assert_eq(fx.call("state_of", "PUB"), "dark", "other services cannot light before host supply")
	assert_true(bool(fx.call("flood_visible")), "pump latch is still controlled by host state")


func test_A04_live_hints_are_reachable_with_captured_pointer_and_respect_toggle() -> void:
	var guide: PanelContainer = _scene.get("onboarding")
	var panel: PanelContainer = _scene.get("accessibility")
	(panel.get("hints_toggle") as CheckBox).set_pressed(true)
	assert_eq(guide.get("guide").call("step_id"), "MOVE")
	_scene.call("_on_player_moved")
	assert_eq(guide.get("guide").call("step_id"), "MEASURE")
	var rejected: Dictionary = {"ok": false, "message": "out of reach"}
	_scene.call("_on_action_replied", {"type": "inspect", "payload": {}}, rejected)
	assert_eq(guide.get("guide").call("step_id"), "MEASURE", "rejected gameplay cannot advance hints")
	var input: InputEventAction = InputEventAction.new()
	input.action = "onboarding_hint"
	input.pressed = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_scene.call("_unhandled_input", input)
	assert_true(not (guide.get("hint") as Label).text.is_empty(),
		"H and D-pad action works without focusing the visible tutorial button")
	(panel.get("hints_toggle") as CheckBox).set_pressed(false)
	assert_eq((guide.get("hint") as Label).text, "", "disabling hints clears the active hint immediately")
	_scene.call("_unhandled_input", input)
	assert_eq((guide.get("hint") as Label).text, "", "hints disabled blocks new hints")
	assert_true(not (guide.get("instruction") as Label).text.is_empty(),
		"essential tutorial instruction remains visible when optional hints are off")


func test_A04_live_settings_survive_scene_recreation_using_same_local_profile() -> void:
	var panel: PanelContainer = _scene.get("accessibility")
	var motion: CheckBox = panel.get("motion_toggle")
	var flashes: CheckBox = panel.get("flash_toggle")
	motion.set_pressed(false)
	flashes.set_pressed(false)
	var want: Dictionary = (_scene.get("settings") as RefCounted).call("snapshot")
	_tree.root.remove_child(_scene)
	_scene.free()
	_scene = (load("res://scenes/mission/mission_root.tscn") as PackedScene).instantiate()
	_tree.root.add_child(_scene)
	var loaded: RefCounted = _scene.get("settings")
	assert_eq(loaded.call("snapshot"), want, "new live scene reloads G06 profile instead of using defaults")
	assert_false(bool((_scene.get("_world_fx") as RefCounted).call("reduce_flashes_enabled")))
	assert_false(bool((_scene.get("accessibility") as PanelContainer).get("motion_toggle").button_pressed))
	assert_false(bool((_scene.get("accessibility") as PanelContainer).get("flash_toggle").button_pressed))
	assert_true(bool((_scene.get("player") as Node).get("enabled")))


func test_A04_onboarding_layout_stays_bounded_at_150_percent() -> void:
	var model: RefCounted = _scene.get("settings")
	model.call("set_value", "ui_scale_percent", 150)
	_scene.call("_settings_changed", model.call("snapshot"), false)
	var guide: PanelContainer = _scene.get("onboarding")
	assert_true(guide.theme != null)
	for size: Vector2 in [Vector2(960, 540), Vector2(1280, 720), Vector2(1920, 1080)]:
		_scene.call("_layout_onboarding", size)
		var width: float = guide.offset_right - guide.offset_left
		var height: float = guide.offset_bottom - guide.offset_top
		assert_true(width > 0.0 and width <= size.x, "tutorial width fits the viewport")
		assert_true(height > 0.0 and guide.offset_bottom < size.y * 0.60,
			"tutorial stays clear of the center reticle")
	_scene.call("_layout_onboarding", _scene.get_viewport().get_visible_rect().size)


func _fresh_production_host() -> Offline:
	var host: Offline = Offline.new()
	var errors: Array[Dictionary] = host.setup(
		func(_player: String, _entity: String) -> bool: return true,
		func(_player: String) -> Vector3i: return Vector3i(450, 90, 1500))
	assert_true(errors.is_empty(), "use the production offline C01 host")
	return host


func _restore_west(host: Offline) -> void:
	assert_true(host.command("inspect", "PANEL_JW")["ok"])
	assert_true(host.command("request_lock", "R_JW_FUSE")["ok"])
	for spec: Array in [["", "diagnose"], ["", "isolate"], ["screwdriver", "open"],
			["puller", "remove"], ["puller", "install"], ["", "close"],
			["meter", "test"], ["", "restore"]]:
		assert_true(host.command("equip", "", {"tool": str(spec[0])})["ok"])
		assert_true(host.command("repair_step", "R_JW_FUSE", {"step": str(spec[1])})["ok"])
		host.tick_once()
	assert_true(bool(host.grid.canonical_state()["nodes"]["APT_W"]["supplied"]),
		"visual target is derived from an actually restored authoritative branch")
