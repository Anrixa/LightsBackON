extends "res://tests/test_case.gd"
## DS04 exercises the production C01 host and the live MissionRoot presentation.
## These deterministic checks do not claim rendered GPU photosensitivity approval.

const Offline := preload("res://scripts/gameplay/offline_c01_session.gd")

var _scene: Node3D
var _tree: SceneTree


func before_each() -> void:
	_tree = Engine.get_main_loop() as SceneTree
	_scene = (load("res://scenes/mission/mission_root.tscn") as PackedScene).instantiate()
	_tree.root.add_child(_scene)


func after_each() -> void:
	if _scene != null and is_instance_valid(_scene):
		_tree.root.remove_child(_scene)
		_scene.free()
	_scene = null
	_tree.root.get_viewport().gui_release_focus()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func test_DS04_cascade_and_sign_follow_authoritative_restoration() -> void:
	var fx: RefCounted = _scene.get("_world_fx")
	fx.call("set_reduce_flashes", false)
	var count: int = int(fx.call("window_count", "APT_W"))
	assert_true(count > 1, "Alder Street must have several pane markers for cascade")
	assert_true(str(fx.call("state_label_of", "APT_W")).contains("NO POWER"),
		"dark status is explicitly readable, not inferred from pane color")
	var host: Offline = _host()
	_restore_west(host)
	var before: Dictionary = host.grid.canonical_state()
	assert_true(bool(before["nodes"]["APT_W"]["supplied"]))
	fx.call("apply", host.host_state(), false)
	assert_eq(fx.call("state_of", "APT_W"), "grid")
	assert_true(str(fx.call("state_label_of", "APT_W")).contains("GRID POWER"))
	assert_eq(float(fx.call("pane_energy_of", "APT_W", 0)), 0.0,
		"status is immediate but the animation starts without an artificial flash")
	fx.call("advance", 0.11)
	var first: float = float(fx.call("pane_energy_of", "APT_W", 0))
	var last: float = float(fx.call("pane_energy_of", "APT_W", count - 1))
	assert_true(first > 0.0 and first > last,
		"each authored window gets a delayed, monotone restoration phase")
	assert_true(last >= 0.0)
	fx.call("advance", 3.0)
	assert_false(bool(fx.call("is_transitioning", "APT_W")))
	for i: int in range(count):
		assert_true(is_equal_approx(float(fx.call("pane_energy_of", "APT_W", i)), 0.55))
	assert_eq(host.grid.canonical_state(), before,
		"visual work must never modify the authoritative power graph")


func test_DS04_preferences_rebase_each_window_without_light_jumps() -> void:
	var fx: RefCounted = _scene.get("_world_fx")
	fx.call("set_reduce_flashes", false)
	var host: Offline = _host()
	_restore_west(host)
	fx.call("apply", host.host_state(), false)
	fx.call("advance", 0.24)
	var count: int = int(fx.call("window_count", "APT_W"))
	var before: Array[float] = []
	for i: int in range(count):
		before.append(float(fx.call("pane_energy_of", "APT_W", i)))
	var lamp_before: float = float(fx.call("light_energy_of", "APT_W"))
	fx.call("set_reduce_flashes", true)
	assert_true(bool(fx.call("reduce_flashes_enabled")))
	assert_true(is_equal_approx(float(fx.call("light_energy_of", "APT_W")), lamp_before))
	for i: int in range(count):
		assert_true(is_equal_approx(float(fx.call("pane_energy_of", "APT_W", i)), before[i]),
			"no pane is allowed to jump when the setting changes")
	fx.call("advance", 0.20)
	for i: int in range(count):
		var next: float = float(fx.call("pane_energy_of", "APT_W", i))
		assert_true(next >= before[i] and next <= 0.55,
			"flashes-off transitions must be bounded and monotonically rising")
	assert_true(float(fx.call("light_energy_of", "APT_W")) >= lamp_before)
	fx.call("advance", 3.0)
	assert_false(bool(fx.call("is_transitioning", "APT_W")))


func test_DS04_power_loss_interrupts_fade_without_false_grid_status() -> void:
	var fx: RefCounted = _scene.get("_world_fx")
	fx.call("set_reduce_flashes", true)
	var host: Offline = _host()
	_restore_west(host)
	fx.call("apply", host.host_state(), false)
	fx.call("advance", 0.50)
	var before: float = float(fx.call("pane_energy_of", "APT_W", 0))
	var dark: Offline = _host()
	fx.call("apply", dark.host_state(), false)
	assert_eq(fx.call("state_of", "APT_W"), "dark")
	assert_true(str(fx.call("state_label_of", "APT_W")).contains("NO POWER"))
	assert_true(is_equal_approx(float(fx.call("pane_energy_of", "APT_W", 0)), before),
		"the loss-of-supply fade starts from the actually displayed brightness")
	fx.call("advance", 0.20)
	var dimmed: float = float(fx.call("pane_energy_of", "APT_W", 0))
	assert_true(dimmed >= 0.0 and dimmed <= before)
	fx.call("advance", 3.0)
	assert_true(is_equal_approx(float(fx.call("pane_energy_of", "APT_W", 0)), 0.0))
	assert_eq(fx.call("state_of", "PUB"), "dark")
	assert_true(bool(fx.call("flood_visible")),
		"flood props still require the host drain latch")


func _host() -> Offline:
	var host: Offline = Offline.new()
	var errors: Array[Dictionary] = host.setup(
		func(_player: String, _entity: String) -> bool: return true,
		func(_player: String) -> Vector3i: return Vector3i(450, 90, 1500))
	assert_true(errors.is_empty(), "use the real offline C01 host")
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
	assert_true(bool(host.grid.canonical_state()["nodes"]["APT_W"]["supplied"]))
