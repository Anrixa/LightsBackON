extends "res://tests/test_case.gd"
## CT-L1/C04 P02: actual C04 preview scene + host-bound repair and control checks.
## Stations are staged test positions, NOT a continuous player/controller route.
## No visual, GPU, Steam, saved-campaign or human-playability qualification.

const Preview := preload("res://scenes/mission/c04_sign_spur_preview.tscn")
const C01 := preload("res://scenes/mission/mission_root.tscn")
const AlderWorld := preload("res://scenes/world/alder_street.tscn")
const Offline := preload("res://scripts/gameplay/offline_c01_session.gd")
const Controller := preload("res://scripts/actors/first_person_controller.gd")
const SpurView := preload("res://scripts/world/c04_sign_spur_view.gd")
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


func _aim(scene: Node3D, target: String) -> void:
	var session: Offline = scene.get("session") as Offline
	var player: Controller = scene.get("player") as Controller
	var point: Vector3 = session.entity_position(target)
	assert_ne(point, Vector3.INF, "authored C04 marker exists: " + target)
	if point == Vector3.INF:
		return
	assert_true(bool(scene.call("_in_range", Offline.PLAYER_ID, target)),
		"real scene ray/range permits C04 station: " + target)
	player.camera.look_at(point, Vector3.UP)
	scene.call("_update_target")
	assert_eq(str(scene.get("_target")), target, "real C04 camera selects station: " + target)


func _host_ok(session: Offline, kind: String, entity: String,
		payload: Dictionary = {}) -> void:
	var reply: Dictionary = session.command(kind, entity, payload)
	assert_true(bool(reply.get("ok", false)),
		"C04 host %s %s payload=%s => %s" % [kind, entity, str(payload), str(reply)])


func _repair(session: Offline, repair: String, panel: String,
		remove_tool: String, install_tool: String) -> void:
	# Every command passes through the genuine SessionHost and the scene's
	# distance/occlusion callback. No direct grid or repair state edits.
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


func test_CTL1_C04_P02_repair_id_uses_actual_street_panel_not_c01_basement() -> void:
	var scene: Node3D = _preview()
	var session: Offline = scene.get("session") as Offline
	assert_true(session != null)
	assert_eq(session.entity_position("R_JE_TRUNK"), session.entity_position("PANEL_JE"),
		"host range and authored C04 panel must resolve to the same location")
	assert_ne(session.entity_position("R_JE_TRUNK"), session.entity_position("TRUNK_JE"))
	assert_true(scene.get_node_or_null("District/Markers/PANEL_JE") is Marker3D)
	_stand(scene, Vector3(72.6, 0.9, 26.1))
	assert_true(bool(scene.call("_in_range", Offline.PLAYER_ID, "R_JE_TRUNK")),
		"repair ID is reachable from the C04 JE street worksite")
	assert_eq(str(session.action_for("PANEL_JE", "meter").get("kind", "")), "inspect")
	assert_false(bool(scene.get("_save_enabled")))
	assert_eq(scene.get("_store"), null)

	# Old production content remains anchored to the exposed basement worksite.
	var original: Node3D = C01.instantiate()
	_holder.add_child(original)
	var c01: Offline = original.get("session") as Offline
	assert_true(c01 != null)
	assert_eq(c01.entity_position("R_JE_TRUNK"), c01.entity_position("TRUNK_JE"))
	assert_ne(c01.entity_position("R_JE_TRUNK"), c01.entity_position("PANEL_JE"))
	assert_true(original.get("_store") != null)


func test_CTL1_C04_P02_host_denies_repair_from_wrong_worksite_then_accepts_je() -> void:
	var scene: Node3D = _preview()
	var session: Offline = scene.get("session") as Offline
	_stand(scene, Vector3(29.6, 0.9, 25.9))
	var initial: String = Grid.serialize(session.grid.canonical_state())
	var denied: Dictionary = session.command("request_lock", "R_JE_TRUNK")
	assert_false(bool(denied.get("ok", false)), "no remote repair through an unrelated cabinet")
	assert_eq(Grid.serialize(session.grid.canonical_state()), initial)

	_stand(scene, Vector3(72.6, 0.9, 26.1))
	assert_true(bool(scene.call("_in_range", Offline.PLAYER_ID, "R_JE_TRUNK")))
	_repair(session, "R_JE_TRUNK", "PANEL_JE", "cutter", "crimper")
	assert_true(bool(session.grid.canonical_state()["edges"]["E_GRID_JE"]["healthy"]))
	assert_eq(session.interaction.repair_state("R_JE_TRUNK"), "restored")


func test_CTL1_C04_P02_preview_aim_and_authorized_controls_are_scene_bound() -> void:
	var scene: Node3D = _preview()
	var session: Offline = scene.get("session") as Offline
	_stand(scene, Vector3(72.6, 0.9, 26.1))
	_aim(scene, "PANEL_JE")
	_stand(scene, Vector3(60.2, 0.9, 37.9))
	_aim(scene, "PANEL_SPUR")
	_aim(scene, "SW_SPUR_BREAKER")
	_stand(scene, Vector3(66.9, 0.9, 38.8))
	_aim(scene, "SW_EAST_SIGN")
	_stand(scene, Vector3(64.6, 0.9, 40.2))
	_aim(scene, "SW_SIGN")

	# A C03 beacon switch is never a C04 action, even if a client forges a
	# host command or manually supplies the old target ID.
	assert_eq(session.action_for("SW_BEACON", "meter"), {})
	assert_eq(session.radius_for("SW_BEACON"), 0.0)
	assert_eq(session.entity_position("SW_BEACON"), Vector3.INF)
	var before: String = Grid.serialize(session.grid.canonical_state())
	var forged: Dictionary = session.command("toggle_switch", "SW_BEACON", {"value": true})
	assert_false(bool(forged.get("ok", false)))
	assert_eq(Grid.serialize(session.grid.canonical_state()), before)


func test_CTL1_C04_P02_staged_repairs_safe_sign_bonus_and_extraction() -> void:
	var scene: Node3D = _preview()
	var session: Offline = scene.get("session") as Offline
	# Retain actionable evidence in CI. No fake zone/position bypass.
	session.action_replied.connect(func(envelope: Dictionary, reply: Dictionary) -> void:
		var kind: String = str(envelope.get("type", ""))
		if ["repair_step", "toggle_switch", "request_extract"].has(kind):
			print("C04_P02_HOST kind=%s entity=%s payload=%s ok=%s code=%s" % [
				kind, str(envelope.get("entity", "")), str(envelope.get("payload", {})),
				str(reply.get("ok", false)), str(reply.get("code", ""))])
	)
	_stand(scene, Vector3(72.6, 0.9, 26.1))
	_repair(session, "R_JE_TRUNK", "PANEL_JE", "cutter", "crimper")
	_stand(scene, Vector3(29.6, 0.9, 25.9))
	_repair(session, "R_JW_FUSE", "PANEL_JW", "puller", "puller")
	_stand(scene, Vector3(60.2, 0.9, 37.9))
	_repair(session, "R_SIGN_SPUR", "PANEL_SPUR", "cutter", "crimper")
	var installed: Dictionary = session.grid.canonical_state()
	assert_true(bool(installed["edges"]["E_GRID_SPUR"]["enabled"]),
		"host-installed, isolated 4 PU source spur")
	assert_eq(int(installed["edges"]["E_GRID_SPUR"]["capacity"]), 4)
	assert_false(bool(installed["nodes"]["SIGN"]["enabled"]))

	_stand(scene, Vector3(64.6, 0.9, 40.2))
	_host_ok(session, "toggle_switch", "SW_SIGN", {"value": true})
	for i: int in 99:
		session.tick_once()
	assert_false(session.mission.is_latched("LATCH_SIGN_SUPPLY"))
	session.tick_once()
	assert_true(session.mission.is_latched("LATCH_SIGN_SUPPLY"),
		"only 100 valid GRID-origin ticks grant the optional sign")
	assert_true(session.mission.verified(), "five required services qualify independently")
	assert_eq(int(session.grid.canonical_state()["nodes"]["GRID"]["load"]), 23)
	assert_eq(int(session.grid.canonical_state()["edges"]["E_GRID_SPUR"]["flow"]), 3)

	# The alternate JE sign route remains dangerous and is refused before
	# changing the successfully restored grid state.
	_stand(scene, Vector3(66.9, 0.9, 38.8))
	var before: String = Grid.serialize(session.grid.canonical_state())
	var rejected: Dictionary = session.command("toggle_switch", "SW_EAST_SIGN", {"value": false})
	assert_false(bool(rejected.get("ok", false)), "no simultaneous sign sources")
	assert_eq(Grid.serialize(session.grid.canonical_state()), before)

	_stand(scene, Vector3(8.0, 0.9, 14.4))
	var physically_inside: bool = session.inside_van((scene.get("player") as Controller).global_position)
	assert_true(physically_inside, "actual van-zone geometry is used")
	session.set_in_van_zone(physically_inside)
	assert_true(session.equipment.all_stowed(), "no portable sign cable inventory")
	_host_ok(session, "request_extract", "ZONE_VAN", {"action": "start"})
	for i: int in 50:
		session.tick_once()
	assert_true(session.completed(), "source/scene-bound host extraction finishes")
	assert_false(bool(scene.get("_save_enabled")), "C04 preview never writes C01 progress")


func test_CTL1_C04_P02_overlay_refuses_forged_station_ids_kinds_and_types() -> void:
	var district: Node3D = AlderWorld.instantiate()
	_holder.add_child(district)
	var view: SpurView = SpurView.new()
	district.add_child(view)
	var overlay: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
		Offline.C04_CONTRACT.path_join("world.json")))
	var switches: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
		Offline.C04_CONTRACT.path_join("switches.json")))
	var extra: Dictionary = overlay.duplicate(true)
	extra["markers"].append({"id": "PANEL_FORGED", "kind": "panel",
		"pos_cm": [6000, 140, 3950]})
	var wrong_kind: Dictionary = overlay.duplicate(true)
	wrong_kind["markers"][0]["kind"] = "switch"
	var bad_type: Dictionary = overlay.duplicate(true)
	bad_type["markers"][0]["pos_cm"] = "60,140,39"
	var swapped: Dictionary = switches.duplicate(true)
	swapped["switches"][0]["id"] = "SW_FORGED"
	for invalid: Dictionary in [extra, wrong_kind, bad_type]:
		assert_false(view.setup(district, invalid, switches))
		assert_false(district.has_node("Markers/PANEL_SPUR"),
			"invalid overlay leaves original district untouched")
	assert_false(view.setup(district, overlay, swapped))
	assert_false(district.has_node("Markers/PANEL_SPUR"))
	assert_eq(view.get_child_count(), 0, "no partial preview visuals on failure")
