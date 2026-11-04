extends "res://tests/test_case.gd"
## V01 offline-first continuation: production scene and real host-local command pathway.
## These are automated smoke/logic checks, not real controller or Steam acceptance.

const Offline := preload("res://scripts/gameplay/offline_c01_session.gd")
const Transport := preload("res://scripts/network/transport_adapter.gd")
const Restoration := preload("res://scripts/world/restoration_presentation.gd")
const C01: String = "res://content/contracts/c01_alder_street"
var _session: Offline


func before_each() -> void:
	_session = Offline.new()
	var failures: Array[Dictionary] = _session.setup(
		func(_player: String, _target: String) -> bool: return true,
		func(_player: String) -> Vector3i: return Vector3i(450, 100, 1500))
	assert_eq(failures, [] as Array[Dictionary], "offline production services load the C01 authored data")


func after_each() -> void:
	_session = null


func test_V01_offline_uses_real_authoritative_host_and_starts_unmeasured() -> void:
	var state: Dictionary = _session.host_state()
	assert_true(state.has("grid") and state.has("repairs") and state.has("mission"))
	assert_eq(state["crew"], ["P1"])
	var measured: Dictionary = _session.meter.readings("PANEL_JW", _session.grid)
	assert_false(measured["_panel"].has("tick"), "unknown is not a zero meter reading")
	assert_eq(str(_session.action_for("PANEL_JW", "meter")["kind"]), "inspect")
	assert_true(_session.interact("PANEL_JW", "meter")["ok"])
	assert_true(_session.meter.readings("PANEL_JW", _session.grid)["_panel"].has("tick"))
	assert_eq(str(_session.action_for("PANEL_JW", "meter")["kind"]), "request_lock")
	assert_true(_session.interact("PANEL_JW", "meter")["ok"])
	assert_eq(str(_session.action_for("PANEL_JW", "meter")["payload"]["step"]), "diagnose")
	assert_true(_session.interact("PANEL_JW", "meter")["ok"])
	assert_eq(_session.interaction.repair_state("R_JW_FUSE"), "diagnosed")
	assert_eq(str(_session.action_for("PANEL_JW", "meter")["payload"]["step"]), "isolate")
	assert_true(_session.interact("PANEL_JW", "meter")["ok"])
	assert_true(_session.grid.canonical_state()["nodes"]["JW"]["isolated"])


func test_V01_offline_gen_pump_requires_actual_state_transitions() -> void:
	var nodes: Dictionary = _session.grid.canonical_state()["nodes"]
	assert_false(bool(nodes["GEN"]["online"]))
	assert_eq(str(_session.action_for("GEN_PORTABLE", "meter")["payload"]["action"]), "pickup")
	assert_true(_session.interact("GEN_PORTABLE", "meter")["ok"])
	assert_eq(_session.equipment.carrier_of("GEN_PORTABLE"), "P1")
	assert_eq(str(_session.action_for("PAD_PUMP", "meter")["payload"]["anchor"]), "PAD_PUMP")
	assert_true(_session.interact("PAD_PUMP", "meter")["ok"])
	assert_eq(str(_session.action_for("GEN_PORTABLE", "meter")["payload"]["action"]), "connect")
	assert_true(_session.interact("GEN_PORTABLE", "meter")["ok"])
	assert_eq(str(_session.action_for("GEN_PORTABLE", "meter")["payload"]["action"]), "start")
	assert_true(_session.interact("GEN_PORTABLE", "meter")["ok"])
	for _i: int in 120:
		_session.tick_once()
	assert_true(_session.mission.is_latched("LATCH_PUMP_DRAIN"), "120 live ticks power the pump")
	assert_eq(str(_session.action_for("GEN_PORTABLE", "meter")["payload"]["action"]), "stop")
	assert_true(_session.interact("GEN_PORTABLE", "meter")["ok"])
	assert_eq(str(_session.action_for("GEN_PORTABLE", "meter")["payload"]["action"]), "disconnect")
	assert_true(_session.interact("GEN_PORTABLE", "meter")["ok"])
	assert_eq(str(_session.action_for("GEN_PORTABLE", "meter")["payload"]["action"]), "pickup")


func test_V01_production_session_replays_known_solution_with_no_fake_grid_edits() -> void:
	var trace: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(C01.path_join("solution.json")))
	var failures: Array[String] = []
	var index: int = 0
	for step: Dictionary in trace["steps"]:
		index += 1
		if step.has("note"):
			continue
		if step.has("ticks"):
			for _tick: int in int(step["ticks"]):
				_session.tick_once()
			continue
		if step.has("zone"):
			_session.set_in_van_zone(bool(step["inside"]))
			continue
		var reply: Dictionary = _session.command(str(step["intent"]), str(step["entity"]), step.get("payload", {}))
		var expected: String = str(step.get("expect", "ok"))
		var got: String = "ok" if reply.get("ok", false) else str(reply.get("code", ""))
		if got != expected:
			failures.append("step %d expected %s, got %s" % [index, expected, got])
		for _tick: int in int(trace["pace_ticks_per_command"]):
			_session.tick_once()
	assert_eq(failures, [] as Array[String], "production solo adapter matches the C01 host trace")
	assert_true(_session.completed(), "mission completion is earned through host command validation")
	assert_true(_session.mission.results()["stars"] >= 1, "completion results come from the mission service")


func test_V01_offline_does_not_activate_unqualified_steam() -> void:
	assert_eq(Transport.create_host(Transport.MODE_STEAM, 0)["code"], "STEAM_NOT_QUALIFIED")
	assert_eq(Transport.create_client(Transport.MODE_STEAM, "", 0)["code"], "STEAM_NOT_QUALIFIED")
	assert_eq(_session.host_state()["crew"], ["P1"])


func test_V01_authored_targets_map_to_real_markers() -> void:
	var entities: Array[Dictionary] = _session.targets()
	var ids: Array[String] = []
	for record: Dictionary in entities:
		ids.append(str(record["id"]))
		assert_false((record["position"] as Vector3) == Vector3.INF)
	assert_true(ids.has("GEN_PORTABLE") and ids.has("PANEL_JW") and ids.has("PANEL_JE") and ids.has("TRUNK_JE"))
	assert_true(ids.has("SW_SIGN"))
	assert_false(ids.has("PAD_PUMP"), "pad is only selectable while carrying")
	assert_true(_session.inside_van(Vector3(4.5, 1.0, 15.0)))
	assert_false(_session.inside_van(Vector3(60.0, 1.0, 30.0)))



func test_V01_je_meter_and_basement_trunk_are_different_physical_actions() -> void:
	assert_eq(_session.entity_position("R_JE_TRUNK"), _session.entity_position("TRUNK_JE"),
		"host validates the east repair at the drained basement work point")
	assert_ne(_session.entity_position("TRUNK_JE"), _session.entity_position("PANEL_JE"),
		"measuring JE is not the same location as the exposed cable")
	var blocked: Dictionary = _session.action_for("TRUNK_JE", "meter")
	assert_true(blocked.has("blocked"), "the basement work point cannot diagnose an unseen JE fault")
	assert_eq(_session.interact("TRUNK_JE", "meter")["code"], "SELECT_TOOL",
		"a shortcut through the basement cannot provide a fake meter reading")
	assert_eq(_session.action_for("PANEL_JE", "meter")["kind"], "inspect")
	assert_true(_session.interact("PANEL_JE", "meter")["ok"])
	assert_eq(_session.action_for("PANEL_JE", "meter")["kind"], "inspect",
		"the cabinet remains a meter target, never a remote repair button")
	assert_eq(_session.action_for("TRUNK_JE", "meter")["entity"], "R_JE_TRUNK")
	assert_eq(_session.interact("TRUNK_JE", "meter")["code"], "NO_ACCESS",
		"the basement is not safe to repair until the pump has drained it")



func test_V01_windows_and_basement_water_follow_authoritative_state() -> void:
	var world_scene: PackedScene = load("res://scenes/world/alder_street.tscn") as PackedScene
	var world: Node3D = world_scene.instantiate()
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	tree.root.add_child(world)
	var visuals: Restoration = Restoration.new()
	visuals.setup(world)
	visuals.apply(_session.host_state(), false)
	assert_true(visuals.window_count("APT_W") > 0, "the authored kit window markers receive presentation panes")
	assert_eq(visuals.state_of("APT_W"), "dark")
	assert_true(visuals.flood_visible(), "the unpumped basement still visibly contains water")

	var steps: Array = (JSON.parse_string(FileAccess.get_file_as_string(C01.path_join("solution.json"))) as Dictionary)["steps"]
	for step: Dictionary in steps:
		if step.has("note"):
			if str(step["note"]).begins_with("2."):
				break
			continue
		if step.has("ticks") or step.has("zone"):
			continue
		var result: Dictionary = _session.command(str(step["intent"]), str(step["entity"]), step.get("payload", {}))
		assert_true(result.get("ok", false), "west restoration step accepted: %s" % str(step))
		_session.tick_once()
	visuals.apply(_session.host_state(), false)
	assert_true(_session.grid.canonical_state()["nodes"]["APT_W"]["supplied"], "west branch really energized")
	assert_eq(visuals.state_of("APT_W"), "grid", "west glass warms after the actual host repair")
	assert_eq(visuals.state_of("PUB"), "dark", "dark services never light early")
	assert_true(visuals.flood_visible(), "west restoration alone does not drain the basement")

	assert_true(_session.command("place_item", "GEN_PORTABLE", {"action": "pickup"})["ok"])
	assert_true(_session.command("place_item", "GEN_PORTABLE", {"action": "place", "anchor": "PAD_PUMP"})["ok"])
	assert_true(_session.command("place_item", "GEN_PORTABLE", {"action": "connect", "route": "E_TEMP_PUMP"})["ok"])
	assert_true(_session.command("place_item", "GEN_PORTABLE", {"action": "start"})["ok"])
	for _tick: int in 120:
		_session.tick_once()
	visuals.apply(_session.host_state(), _session.mission.is_latched("LATCH_PUMP_DRAIN"))
	assert_false(visuals.flood_visible(), "the pump latch removes flood water from presentation")
	assert_eq(visuals.state_of("APT_W"), "grid", "the west branch remains supplied")
	tree.root.remove_child(world)
	world.free()


func test_V01_windowed_game_has_actual_menu_and_mission_scenes() -> void:
	var menu_scene: PackedScene = load("res://scenes/menu/main_menu.tscn") as PackedScene
	var mission_scene: PackedScene = load("res://scenes/mission/mission_root.tscn") as PackedScene
	assert_true(menu_scene != null and mission_scene != null, "scenes import and load")
	if menu_scene == null or mission_scene == null:
		return
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var menu: Node = menu_scene.instantiate()
	tree.root.add_child(menu)
	assert_true(menu.find_child("MainMenu", true, false) == null or menu.name == "MainMenu")
	assert_true(menu.find_child("StartButton", true, false) != null or menu.get("start_button") != null,
		"solo start action is actually present")
	tree.root.remove_child(menu)
	menu.free()

	var mission_root: Node = mission_scene.instantiate()
	tree.root.add_child(mission_root)
	assert_true(mission_root.get_node_or_null("District") is Node3D, "authored Alder Street is visible")
	assert_true(mission_root.get_node_or_null("Player/BodyCollision") is CollisionShape3D, "real colliding worker")
	assert_true(mission_root.get_node_or_null("Player/Eyes") is Camera3D, "first-person camera")
	assert_true(mission_root.get_node_or_null("Interface/Screen/HUD") is Control, "V07 HUD live")
	assert_true(mission_root.get_node_or_null("Interface/Screen/NetworkTablet") is PanelContainer, "V07 tablet live")
	assert_true(mission_root.get_node_or_null("Interface/Screen/Onboarding") is PanelContainer, "A04 guidance live")
	tree.root.remove_child(mission_root)
	mission_root.free()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
