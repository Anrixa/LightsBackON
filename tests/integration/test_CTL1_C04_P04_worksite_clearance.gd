extends "res://tests/test_case.gd"
## CT-L1/C04 P04: station geometry, visibility and source-bound staging.
## Source/headless probes are not walked human/controller playability evidence.

const Preview := preload("res://scenes/mission/c04_sign_spur_preview.tscn")
const C01 := preload("res://scenes/mission/mission_root.tscn")
const C03 := preload("res://scenes/mission/c03_roof_preview.tscn")
const AlderWorld := preload("res://scenes/world/alder_street.tscn")
const SpurView := preload("res://scripts/world/c04_sign_spur_view.gd")
const Offline := preload("res://scripts/gameplay/offline_c01_session.gd")
const Controller := preload("res://scripts/actors/first_person_controller.gd")
const Grid := preload("res://scripts/simulation/power_grid.gd")

var _holder: Node3D


func before_each() -> void:
	_holder = Node3D.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(_holder)


func after_each() -> void:
	_holder.get_parent().remove_child(_holder)
	_holder.free()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _preview() -> Node3D:
	var scene: Node3D = Preview.instantiate()
	_holder.add_child(scene)
	return scene


func _definition(filename: String) -> Dictionary:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(
		Offline.C04_CONTRACT.path_join(filename)))
	return data if data is Dictionary else {}


func test_CTL1_C04_P04_all_authorized_stations_have_noncolliding_worksite_plates() -> void:
	var scene: Node3D = _preview()
	var view: SpurView = scene.get("_sign_spur_view") as SpurView
	assert_true(view != null)
	var markers: Node3D = scene.get_node("District/Markers") as Node3D
	assert_eq(view.get_node("C04ControlStations").get_child_count(), 8)
	for id: String in [
		"PANEL_JW", "SW_JW_BREAKER", "PANEL_JE", "SW_JE_BREAKER",
		"PANEL_SPUR", "SW_SPUR_BREAKER", "SW_EAST_SIGN", "SW_SIGN"
	]:
		var station: Node3D = view.get_node_or_null("C04ControlStations/" + id) as Node3D
		assert_true(station != null, "C04 physical plate: " + id)
		if station == null:
			continue
		assert_eq(station.position, (markers.get_node(id) as Marker3D).position,
			"visual/interaction anchor must agree: " + id)
		assert_true(station.get_node_or_null("Plate") is MeshInstance3D, id)
		assert_true(station.get_node_or_null("State") is Label3D, id)
		assert_eq(station.find_children("*", "CollisionObject3D", true, false).size(), 0,
			"visual plate cannot block the player: " + id)
		assert_eq(station.find_children("*", "CollisionShape3D", true, false).size(), 0,
			"visual plate cannot alter physics: " + id)
	var west: Label3D = view.get_node("C04ControlStations/PANEL_JW/State") as Label3D
	var east: Label3D = view.get_node("C04ControlStations/PANEL_JE/State") as Label3D
	assert_true(west.text.contains("WORKSITE"))
	assert_true(east.text.contains("WORKSITE"))
	assert_false(west.text.contains("SUPPLIED"), "repair site label is not a power assertion")


func test_CTL1_C04_P04_inherited_switch_plates_follow_host_only() -> void:
	var scene: Node3D = _preview()
	var view: SpurView = scene.get("_sign_spur_view") as SpurView
	var session: Offline = scene.get("session") as Offline
	var before: String = Grid.serialize(session.host_state())
	var west: Label3D = view.get_node("C04ControlStations/SW_JW_BREAKER/State") as Label3D
	var east: Label3D = view.get_node("C04ControlStations/SW_JE_BREAKER/State") as Label3D
	var sign: Label3D = view.get_node("C04ControlStations/SW_SIGN/State") as Label3D
	var state: Dictionary = session.host_state()
	state["grid"]["nodes"]["JW"]["tripped"] = true
	state["grid"]["nodes"]["JE"]["tripped"] = false
	state["grid"]["nodes"]["SIGN"]["enabled"] = true
	view.apply_host(state)
	assert_true(west.text.ends_with("TRIPPED"))
	assert_true(east.text.ends_with("RESET"))
	assert_true(sign.text.ends_with("ENABLED"))
	state["grid"]["nodes"]["JW"]["tripped"] = "forged"
	state["grid"]["nodes"]["SIGN"]["enabled"] = 1
	view.apply_host(state)
	assert_true(west.text.ends_with("UNKNOWN"))
	assert_true(sign.text.ends_with("UNKNOWN"))
	assert_eq(Grid.serialize(session.host_state()), before,
		"presentation cannot change the authoritative switch state")


func test_CTL1_C04_P04_displaced_sunken_and_overlapping_stations_refuse_atomically() -> void:
	var world: Node3D = AlderWorld.instantiate()
	_holder.add_child(world)
	var view: SpurView = SpurView.new()
	world.add_child(view)
	var overlay: Dictionary = _definition("world.json")
	var switches: Dictionary = _definition("switches.json")
	var base_count: int = (world.get_node("Markers") as Node3D).get_child_count()
	var far: Dictionary = overlay.duplicate(true)
	far["markers"][0]["pos_cm"][0] = 6320
	var sunk: Dictionary = overlay.duplicate(true)
	sunk["markers"][1]["pos_cm"][1] = -180
	var overlap: Dictionary = overlay.duplicate(true)
	overlap["markers"][0]["pos_cm"][0] = 6040
	overlap["markers"][1]["pos_cm"][0] = 6080
	for invalid: Dictionary in [far, sunk, overlap]:
		assert_false(view.setup(world, invalid, switches),
			"source curb alignment/spacing must be checked before mutation")
		assert_eq((world.get_node("Markers") as Node3D).get_child_count(), base_count)
		assert_eq(view.get_child_count(), 0, "failed preflight cannot add preview art")
	var inherited: Marker3D = world.get_node("Markers/SW_JW_BREAKER") as Marker3D
	var original: Vector3 = inherited.position
	inherited.position.x += 2.0
	assert_false(view.setup(world, overlay, switches),
		"relocated inherited switch must not be silently re-labeled")
	inherited.position = original
	assert_false(world.has_node("Markers/PANEL_SPUR"))
	assert_true(view.setup(world, overlay, switches),
		"source-original markers pass conservative geometry preflight")
	assert_true(world.has_node("Markers/PANEL_SPUR"))
	assert_eq(view.get_node("C04ControlStations").get_child_count(), 8)


func test_CTL1_C04_P04_staged_access_uses_real_scene_range_and_ray_not_route_claim() -> void:
	var scene: Node3D = _preview()
	var session: Offline = scene.get("session") as Offline
	var player: Controller = scene.get("player") as Controller
	for site: Dictionary in [
		{"id": "PANEL_JW", "stand": Vector3(29.6, 0.9, 25.9)},
		{"id": "SW_JW_BREAKER", "stand": Vector3(30.4, 0.9, 25.9)},
		{"id": "PANEL_JE", "stand": Vector3(72.6, 0.9, 26.1)},
		{"id": "SW_JE_BREAKER", "stand": Vector3(73.4, 0.9, 26.1)},
		{"id": "PANEL_SPUR", "stand": Vector3(60.2, 0.9, 37.9)},
		{"id": "SW_SPUR_BREAKER", "stand": Vector3(60.2, 0.9, 37.9)},
		{"id": "SW_EAST_SIGN", "stand": Vector3(66.9, 0.9, 38.8)},
		{"id": "SW_SIGN", "stand": Vector3(64.6, 0.9, 40.2)}
	]:
		var id: String = site["id"]
		player.global_position = site["stand"]
		player.velocity = Vector3.ZERO
		assert_true(bool(scene.call("_in_range", Offline.PLAYER_ID, id)),
			"staged scene/range check: " + id)
		player.camera.look_at(session.entity_position(id), Vector3.UP)
		scene.call("_update_target")
		assert_eq(str(scene.get("_target")), id, "staged reticle selects: " + id)
	assert_false(bool(scene.get("_save_enabled")))
	assert_eq(scene.get("_store"), null)


func test_CTL1_C04_P04_c01_c03_world_and_saves_remain_untouched() -> void:
	var c01: Node3D = C01.instantiate()
	_holder.add_child(c01)
	assert_true(c01.get_node_or_null("District/C04SignSpur") == null,
		"C01 cannot instantiate the C04 preview view")
	assert_true(c01.get("_store") != null)
	var c03: Node3D = C03.instantiate()
	_holder.add_child(c03)
	assert_true(c03.get_node_or_null("District/C04SignSpur") == null,
		"C03 cannot instantiate the C04 preview view")
	assert_eq(c03.get("_store"), null)
	assert_true(c03.get_node_or_null("District/Markers/PANEL_SPUR") == null,
		"C03 cannot inherit C04-only panel markers")
