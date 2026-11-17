extends "res://tests/test_case.gd"
## CT-L1/C03 P03: real preview scene, camera target selection, physics line of
## sight and host-command route probes. Position staging is a test fixture:
## it does NOT certify a continuous human/controller walk or rendered framerate.

const Preview := preload("res://scenes/mission/c03_roof_preview.tscn")
const C01 := preload("res://scenes/mission/mission_root.tscn")
const Offline := preload("res://scripts/gameplay/offline_c01_session.gd")
const Controller := preload("res://scripts/actors/first_person_controller.gd")
const Ladder := preload("res://scripts/world/c03_fixed_ladder_view.gd")
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


func _stand(scene: Node3D, at: Vector3) -> void:
	var player: Controller = scene.get("player") as Controller
	player.global_position = at
	player.velocity = Vector3.ZERO


func _aim(scene: Node3D, id: String) -> void:
	var session: Offline = scene.get("session") as Offline
	var player: Controller = scene.get("player") as Controller
	var target: Vector3 = session.entity_position(id)
	assert_ne(target, Vector3.INF, "physical target must exist: " + id)
	if target == Vector3.INF:
		return
	assert_true(bool(scene.call("_in_range", Offline.PLAYER_ID, id)),
		"real physics visibility/range: " + id)
	player.camera.look_at(target, Vector3.UP)
	scene.call("_update_target")
	assert_eq(str(scene.get("_target")), id, "center-ray target priority: " + id)


func _host_ok(session: Offline, kind: String, entity: String,
		payload: Dictionary = {}) -> void:
	var reply: Dictionary = session.command(kind, entity, payload)
	assert_true(bool(reply.get("ok", false)), "%s %s: %s" % [kind, entity, str(reply)])


func _repair(session: Offline, repair: String, panel: String,
		remove_tool: String, install_tool: String) -> void:
	_host_ok(session, "request_lock", repair)
	_host_ok(session, "inspect", panel)
	_host_ok(session, "repair_step", repair, {"step": "diagnose"})
	_host_ok(session, "repair_step", repair, {"step": "isolate"})
	assert_true(bool(session.set_tool("screwdriver").get("ok", false)))
	_host_ok(session, "repair_step", repair, {"step": "open"})
	assert_true(bool(session.set_tool(remove_tool).get("ok", false)))
	_host_ok(session, "repair_step", repair, {"step": "remove"})
	assert_true(bool(session.set_tool(install_tool).get("ok", false)))
	_host_ok(session, "repair_step", repair, {"step": "install"})
	_host_ok(session, "repair_step", repair, {"step": "close"})
	assert_true(bool(session.set_tool("meter").get("ok", false)))
	_host_ok(session, "repair_step", repair, {"step": "test"})
	_host_ok(session, "repair_step", repair, {"step": "restore"})


func test_CTL1_C03_P03_inherited_switches_are_not_live_C03_aim_targets() -> void:
	var scene: Node3D = _preview()
	var session: Offline = scene.get("session") as Offline
	var switches: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
		Offline.C03_CONTRACT.path_join("switches.json")))
	var allowed: Dictionary = {}
	for record: Dictionary in switches["switches"]:
		allowed[str(record["id"])] = true
	var visible: Dictionary = {}
	for target: Dictionary in session.targets():
		var id: String = str(target["id"])
		visible[id] = true
		if id.begins_with("SW_"):
			assert_true(allowed.has(id), "foreign switch in C03 camera candidates: " + id)
	for id: String in allowed:
		assert_true(visible.has(id), "missing authorized physical switch: " + id)
	for foreign: String in ["SW_SIGN", "SW_JE_BREAKER"]:
		assert_false(visible.has(foreign), foreign)
		assert_eq(session.radius_for(foreign), 0.0)
		assert_eq(session.entity_position(foreign), Vector3.INF)
		assert_eq(session.prompt_for(foreign, "meter"), {})
	var before: String = Grid.serialize(session.host_state())
	var denied: Dictionary = session.command("toggle_switch", "SW_SIGN", {"value": true})
	assert_false(bool(denied.get("ok", false)))
	assert_eq(Grid.serialize(session.host_state()), before)
	assert_false(bool(scene.get("_save_enabled")))

	# C01 contract owns those inherited switches and must retain them.
	var original: Node3D = C01.instantiate()
	_holder.add_child(original)
	var c01: Offline = original.get("session") as Offline
	var c01_switches: Array[String] = []
	for target: Dictionary in c01.targets():
		if str(target["id"]).begins_with("SW_"):
			c01_switches.append(str(target["id"]))
	assert_true(c01_switches.has("SW_SIGN"))
	assert_true(c01_switches.has("SW_JE_BREAKER"))
	assert_true(c01.entity_position("SW_SIGN") != Vector3.INF)


func test_CTL1_C03_P03_both_ladder_landings_are_clear_and_supported() -> void:
	var scene: Node3D = _preview()
	var player: Controller = scene.get("player") as Controller
	var ladder: Ladder = scene.get("_ladder_view") as Ladder
	for endpoint: String in ["LADDER_WEST", "LADDER_WEST_RETURN"]:
		assert_true(ladder.can_transfer(player, endpoint),
			"landing must have capsule clearance AND a real supporting floor: " + endpoint)
	# A technically empty capsule volume in the air is not a landing.
	var destinations: Dictionary = (ladder.get("_arrivals") as Dictionary).duplicate()
	destinations["LADDER_WEST"] = Vector3(21.0, 30.0, 44.3)
	ladder.set("_arrivals", destinations)
	assert_false(ladder.can_transfer(player, "LADDER_WEST"))
	assert_false(ladder.transfer(player, "LADDER_WEST"))


func test_CTL1_C03_P03_camera_can_select_ground_and_roof_work_stations() -> void:
	var scene: Node3D = _preview()
	_stand(scene, Vector3(29.6, 0.9, 25.9))
	_aim(scene, "PANEL_JW")
	_stand(scene, Vector3(31.2, 0.9, 21.8))
	_aim(scene, "SW_ACCESS_LIGHT")
	_stand(scene, Vector3(21.0, 0.9, 40.2))
	_aim(scene, "LADDER_WEST")
	var ladder: Ladder = scene.get("_ladder_view") as Ladder
	_stand(scene, ladder.destination("LADDER_WEST"))
	_aim(scene, "PANEL_ROOF")
	_aim(scene, "SW_ROOF_FEED")
	_aim(scene, "SW_BEACON")
	_aim(scene, "LADDER_WEST_RETURN")
	_stand(scene, Vector3(8.0, 0.9, 14.4))
	_aim(scene, "GEN_PORTABLE")
	_stand(scene, Vector3(62.5, 0.9, 17.6))
	# The actual PUMP pad is reused as C03's provisional generator socket.
	# Its walkable connection still needs a hands-on scene route review.
	var session: Offline = scene.get("session") as Offline
	assert_true(bool(scene.call("_in_range", Offline.PLAYER_ID, "PAD_PUMP")))


func test_CTL1_C03_P03_station_staged_host_route_reaches_extraction() -> void:
	var scene: Node3D = _preview()
	var session: Offline = scene.get("session") as Offline
	var player: Controller = scene.get("player") as Controller
	var ladder: Ladder = scene.get("_ladder_view") as Ladder

	# Initial west fuse is repaired through the real scene-bound host range callback.
	_stand(scene, Vector3(29.6, 0.9, 25.9))
	_repair(session, "R_JW_FUSE", "PANEL_JW", "puller", "puller")
	for i: int in 50:
		session.tick_once()
	assert_true(session.mission.is_latched("LATCH_LADDER_LIGHT"))
	_stand(scene, Vector3(21.0, 0.9, 40.2))
	_aim(scene, "LADDER_WEST")
	scene.call("_interact")
	assert_eq(player.global_position, ladder.destination("LADDER_WEST"),
		"only an accepted host ladder reply can change physical location")

	# Complete the rooftop repair from a genuinely visible, nearby station.
	_aim(scene, "PANEL_ROOF")
	_repair(session, "R_ROOF_SPLICE", "PANEL_ROOF", "cutter", "crimper")
	_aim(scene, "SW_ROOF_FEED")
	scene.call("_interact")
	assert_true(bool(session.grid.canonical_state()["edges"]["E_GRID_ROOF"]["enabled"]))
	assert_false(bool(session.grid.canonical_state()["edges"]["E_GRID_JE"]["enabled"]))
	_aim(scene, "LADDER_WEST_RETURN")
	scene.call("_interact")
	assert_eq(player.global_position, ladder.destination("LADDER_WEST_RETURN"))

	# Reuse the authenticated C03 temporary-light generator route, never C01 pump.
	_stand(scene, Vector3(8.0, 0.9, 14.4))
	_aim(scene, "GEN_PORTABLE")
	scene.call("_interact")  # pickup
	_stand(scene, Vector3(62.5, 0.9, 17.6))
	_aim(scene, "PAD_PUMP")
	scene.call("_interact")  # place
	_aim(scene, "GEN_PORTABLE")
	scene.call("_interact")  # connect
	scene.call("_interact")  # start
	assert_true(bool(session.grid.canonical_state()["nodes"]["GEN"]["online"]))
	assert_true(bool(session.grid.canonical_state()["edges"]["E_TEMP_ROOF_LIGHT"]["enabled"]))
	assert_false(bool(session.grid.canonical_state()["edges"]["E_TEMP_PUMP"]["enabled"]))

	_stand(scene, Vector3(21.0, 0.9, 40.2))
	_aim(scene, "LADDER_WEST")
	scene.call("_interact")
	assert_eq(player.global_position, ladder.destination("LADDER_WEST"))
	_aim(scene, "SW_BEACON")
	scene.call("_interact")
	for i: int in 100:
		session.tick_once()
	assert_true(session.mission.is_latched("LATCH_ROOF_WORK_LIGHT"))
	assert_true(session.mission.verified(), "real host must verify all required GRID loads")
	_aim(scene, "LADDER_WEST_RETURN")
	scene.call("_interact")
	assert_eq(player.global_position, ladder.destination("LADDER_WEST_RETURN"))

	_stand(scene, Vector3(62.5, 0.9, 17.6))
	_aim(scene, "GEN_PORTABLE")
	scene.call("_interact")  # stop
	scene.call("_interact")  # disconnect
	scene.call("_interact")  # pickup
	_stand(scene, Vector3(8.0, 0.9, 14.4))
	_aim(scene, "VAN_BAY")
	scene.call("_interact")  # stow
	assert_true(session.equipment.all_stowed())
	session.set_in_van_zone(true)
	_host_ok(session, "request_extract", "ZONE_VAN", {"action": "start"})
	for i: int in 50:
		session.tick_once()
	assert_true(session.completed(), "C03 must reach the real host extraction finale")
	assert_false(bool(scene.get("_save_enabled")), "C03 remains unsaved development preview")
