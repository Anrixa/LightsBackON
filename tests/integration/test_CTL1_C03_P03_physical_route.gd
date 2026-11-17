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
const Selector := preload("res://scripts/interaction/target_selector.gd")

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
	# Trace every gameplay-relevant host reply in failing CI, not just the final
	# assertion. No state is fabricated or directly edited by this observer.
	session.action_replied.connect(func(envelope: Dictionary, reply: Dictionary) -> void:
		var kind: String = str(envelope.get("type", ""))
		if ["use_ladder", "place_item", "toggle_switch", "request_extract"].has(kind):
			print("C03_P03_HOST kind=%s entity=%s payload=%s ok=%s code=%s duplicate=%s" %
				[kind, str(envelope.get("entity", "")), str(envelope.get("payload", {})),
				str(reply.get("ok", false)), str(reply.get("code", "")),
				str(reply.get("duplicate", false))])
	)

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
	assert_false(bool(session.grid.canonical_state()["edges"]["E_GRID_JE"]["healthy"]),
		"source contract leaves the broken direct-east feeder enabled but unhealthy")
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
	print("C03_P03_GEN_STATE %s" % str(session.equipment.canonical_state()))
	print("C03_P03_GEN_GRID %s" % str(session.grid.canonical_state()["nodes"]["GEN"]))
	assert_true(bool(session.grid.canonical_state()["nodes"]["GEN"]["online"]),
		"generator must be online after explicit preview start")
	assert_true(bool(session.grid.canonical_state()["edges"]["E_TEMP_ROOF_LIGHT"]["enabled"]))
	assert_false(bool(session.grid.canonical_state()["edges"]["E_TEMP_PUMP"]["enabled"]))

	_stand(scene, Vector3(21.0, 0.9, 40.2))
	_aim(scene, "LADDER_WEST")
	scene.call("_interact")
	print("C03_P03_SECOND_ASCENT pos=%s target=%s state=%s" % [str(player.global_position),
		str(scene.get("_target")), str(session.mission.canonical_state().get("ladder_access", {}))])
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


## The existing V01 movement probe walks an actual CharacterBody3D through
## a 50 cm collision grid with gravity and move_and_slide. Run it on both
## C03's inherited ground and isolated 8 m roof. This verifies physical
## corridors, not actual player input or controller camera manipulation.
const DistrictProbe := preload("res://tests/support/district_probe.gd")


func _closest_connected_cell(probe: DistrictProbe, parent: PackedInt32Array,
		point: Vector3, floor_m: float) -> int:
	var center: int = probe.cell_of(point)
	var ci: int = center % probe.nx
	var cj: int = center / probe.nx
	var best: int = -1
	var distance: float = INF
	for dj: int in range(-4, 5):
		for di: int in range(-4, 5):
			var x: int = ci + di
			var z: int = cj + dj
			if x < 0 or z < 0 or x >= probe.nx or z >= probe.nz:
				continue
			var idx: int = x + z * probe.nx
			if parent[idx] < 0:
				continue
			var feet: Vector3 = probe.feet(idx)
			if absf(feet.y - floor_m) > 0.25:
				continue
			var horizontal: float = Vector2(feet.x - point.x, feet.z - point.z).length()
			if horizontal < distance and horizontal <= 2.0:
				best = idx
				distance = horizontal
	return best


func _walk_connected_stations(probe: DistrictProbe, session: Offline,
		start: Vector3, floor_m: float, stations: Array[String]) -> void:
	var current: int = probe.cell_of(start)
	assert_true(probe.standable(current), "actual walkable start: " + str(start))
	if not probe.standable(current):
		return
	var movement: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
		"res://content/movement.json"))
	var speed: float = float(movement["walk_mm_s"]) / 1000.0
	for id: String in stations:
		var reach: PackedInt32Array = probe.search(current)
		var goal: int = _closest_connected_cell(probe, reach,
			session.entity_position(id), floor_m)
		assert_true(goal >= 0, "collision-connected corridor to " + id)
		if goal < 0:
			return
		var waypoints: Array[Vector3] = probe.path_to(reach, goal)
		assert_false(waypoints.is_empty(), "no walkable path to " + id)
		if waypoints.is_empty():
			return
		var arrival: Vector3 = probe.walk(waypoints, speed)
		assert_true(arrival.distance_to(probe.feet(goal)) <= 0.3,
			"body must physically walk to %s; end=%s blocker=%s" % [
				id, str(arrival), probe.last_blocker])
		current = goal


func test_CTL1_C03_P03_actual_capsule_walks_ground_and_roof_corridors() -> void:
	# Do not mount another full C03 scene on top of the physics probe: duplicate
	# colliders would invalidate body-walk evidence. The standalone host only
	# supplies the selected contract's authored marker positions.
	var session: Offline = Offline.new()
	var errors: Array[Dictionary] = session.setup(
		func(_player: String, _target: String) -> bool: return true,
		func(_player: String) -> Vector3i: return Vector3i.ZERO,
		Offline.C03_CONTRACT)
	assert_eq(errors, [] as Array[Dictionary])
	if not errors.is_empty():
		return
	var world: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
		"res://content/world/alder_street.json"))
	var overlay: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
		Offline.C03_CONTRACT.path_join("world.json")))
	var roof_arrival: Vector3 = Vector3.INF
	for transition: Dictionary in overlay["transitions"]:
		if str(transition["id"]) == "LADDER_WEST":
			var cm: Array = transition["arrival_cm"]
			roof_arrival = Vector3(float(cm[0]), float(cm[1]), float(cm[2])) / 100.0
	assert_ne(roof_arrival, Vector3.INF, "authored C03 west ladder arrival")
	if roof_arrival == Vector3.INF:
		return
	var dimensions: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
		"res://content/world/kit_dimensions.json"))
	var geometry: String = str(world["scene"])

	# Lower world: the same original Alder Street collision that C03 inherits.
	# The ordered stations reflect the twice-used ladder and GEN pad route.
	var ground: DistrictProbe = DistrictProbe.new(geometry, dimensions, world["envelope_cm"])
	ground.build_grid()
	_walk_connected_stations(ground, session, session.entity_position("SPAWN_1"),
		0.0, ["PANEL_JW", "SW_JW_BREAKER", "SW_ACCESS_LIGHT", "SW_CROSSFEED",
			"LADDER_WEST", "VAN_BAY", "PAD_PUMP", "LADDER_WEST",
			"PAD_PUMP", "VAN_BAY"])
	ground.free_scene()

	# Roof world: take the supporting APT_W 8 m top, never a ground-floor
	# phantom route through the building. P01/P03 host tests own the ladder
	# transitions that join these distinct walking surfaces.
	var roof: DistrictProbe = DistrictProbe.new(geometry, dimensions, world["envelope_cm"])
	roof.build_grid(12.0)
	_walk_connected_stations(roof, session, roof_arrival,
		8.0, ["PANEL_ROOF", "SW_ROOF_FEED", "SW_ROOF_BREAKER", "SW_BEACON",
			"LADDER_WEST_RETURN"])
	roof.free_scene()


func test_CTL1_C03_P03_ladder_inside_sphere_is_only_selected_when_aimed() -> void:
	var eye: Vector3 = Vector3(21.0, 9.99, 44.3)
	var roof_panel: Vector3 = Vector3(22.1, 9.70, 45.9)
	var ladder_return: Vector3 = Vector3(21.0, 9.65, 44.5)
	var candidates: Array[Dictionary] = [
		{"id": "LADDER_WEST_RETURN", "position": ladder_return, "radius": 0.48},
		{"id": "PANEL_ROOF", "position": roof_panel, "radius": 0.48},
	]
	assert_true(eye.distance_to(ladder_return) < 0.48,
		"regression fixture must actually put camera inside ladder assist radius")
	var toward_panel: Vector3 = (roof_panel - eye).normalized()
	assert_eq(Selector.select(eye, toward_panel, candidates, 2.3, 6.0), "PANEL_ROOF",
		"overlapping ladder aim sphere must not steal roof panel center ray")
	var toward_ladder: Vector3 = (ladder_return - eye).normalized()
	assert_eq(Selector.select(eye, toward_ladder, candidates, 2.3, 6.0), "LADDER_WEST_RETURN",
		"looking directly at nearby return ladder must still select it")
