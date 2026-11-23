extends "res://tests/test_case.gd"
## CT-L1/C04 P01: headless preview source and host-snapshot checks only.
## No controller, route traversal, GPU or human playability certification.

const Preview := preload("res://scenes/mission/c04_sign_spur_preview.tscn")
const C01 := preload("res://scenes/mission/mission_root.tscn")
const C03 := preload("res://scenes/mission/c03_roof_preview.tscn")
const AlderWorld := preload("res://scenes/world/alder_street.tscn")
const Offline := preload("res://scripts/gameplay/offline_c01_session.gd")
const SignSpur := preload("res://scripts/world/c04_sign_spur_view.gd")
const Grid := preload("res://scripts/simulation/power_grid.gd")
const UiText := preload("res://scripts/ui/ui_text.gd")

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


func test_CTL1_C04_P01_c04_preview_is_separate_unsaved_host_session() -> void:
	var scene: Node3D = _preview()
	var session: Offline = scene.get("session") as Offline
	assert_true(session != null, "C04 preview boots the real host-local command stack")
	assert_eq(str(scene.get("contract_id")), "C04")
	assert_eq(session.hud_view(1, "", "meter")["contract_key"], "contract.c04")
	assert_false(bool(scene.get("_save_enabled")))
	assert_eq(scene.get("_store"), null, "C04 must never initialize C01 checkpoint writer")
	assert_false((scene.get("onboarding") as Control).visible)
	assert_true(scene.get_node_or_null("District/C04SignSpur") is SignSpur)
	assert_eq(str(session.mission.objectives()[0]["text_key"]), "objective.c04.restore_east")
	assert_true(session.host_state()["grid"]["nodes"].has("SPUR"))


func test_CTL1_C04_P01_authorized_switches_and_spur_panel_have_world_markers() -> void:
	var scene: Node3D = _preview()
	var session: Offline = scene.get("session") as Offline
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
		Offline.C04_CONTRACT.path_join("switches.json")))
	assert_eq(config["switches"].size(), 5)
	var targets: Dictionary = {}
	for target: Dictionary in session.targets():
		targets[str(target["id"])] = true
	for sw: Dictionary in config["switches"]:
		var id: String = str(sw["id"])
		assert_true(targets.has(id), "authorized scene target: " + id)
		assert_true(scene.get_node_or_null("District/Markers/" + id) is Marker3D, id)
		assert_true(session.radius_for(id) > 0.0, id)
		var action: Dictionary = session.action_for(id, "meter")
		assert_eq(str(action.get("kind", "")), "toggle_switch", id)
		assert_true((action.get("payload", {}) as Dictionary).get("value") is bool, id)
	assert_true(targets.has("PANEL_SPUR"))
	assert_true(scene.get_node_or_null("District/Markers/PANEL_SPUR") is Marker3D)
	assert_eq(session.action_for("PANEL_SPUR", "meter")["kind"], "inspect")
	assert_eq(session.radius_for("SW_BEACON"), 0.0, "C03-only control must stay unavailable")
	assert_eq(session.entity_position("SW_BEACON"), Vector3.INF)
	assert_eq(session.action_for("SW_EAST_SIGN", "meter")["payload"]["value"], false)
	assert_eq(session.action_for("SW_SIGN", "meter")["payload"]["value"], true)


func test_CTL1_C04_P01_sign_and_feeder_status_come_only_from_host() -> void:
	var scene: Node3D = _preview()
	var session: Offline = scene.get("session") as Offline
	var view: SignSpur = scene.get("_sign_spur_view") as SignSpur
	view.apply_host(session.host_state())
	var feeder: Label3D = view.get_node("C04ControlStations/PANEL_SPUR/State") as Label3D
	var isolation: Label3D = view.get_node("C04ControlStations/SW_EAST_SIGN/State") as Label3D
	var sign: Label3D = view.get_node("C04SignSupply") as Label3D
	assert_true(feeder.text.ends_with("NOT INSTALLED"))
	assert_true(isolation.text.ends_with("ISOLATED"))
	assert_true(sign.text.ends_with("UNSUPPLIED"))
	assert_true(view.get_node_or_null("C04DedicatedConduit/Segment_00") is MeshInstance3D)
	var before: String = Grid.serialize(session.host_state())
	var staged: Dictionary = session.host_state()
	staged["grid"]["edges"]["E_GRID_SPUR"]["enabled"] = true
	staged["grid"]["nodes"]["SIGN"]["supplied"] = true
	view.apply_host(staged)
	assert_true(feeder.text.ends_with("INSTALLED"))
	assert_true(sign.text.ends_with("SUPPLIED"))
	assert_eq(Grid.serialize(session.host_state()), before, "preview may not mutate host state")
	view.apply_host({"grid": {"nodes": {}, "edges": {}}})
	assert_true(feeder.text.ends_with("UNKNOWN"))
	assert_true(sign.text.ends_with("UNKNOWN"))


func test_CTL1_C04_P01_invalid_overlay_and_forged_controls_fail_without_partial_nodes() -> void:
	var scene: Node3D = AlderWorld.instantiate()
	_holder.add_child(scene)
	var view: SignSpur = SignSpur.new()
	scene.add_child(view)
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
		Offline.C04_CONTRACT.path_join("world.json")))
	var switches: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
		Offline.C04_CONTRACT.path_join("switches.json")))
	var missing: Dictionary = data.duplicate(true)
	var kept: Array = []
	for rec: Dictionary in missing["markers"]:
		if str(rec["id"]) != "SW_EAST_SIGN":
			kept.append(rec)
	missing["markers"] = kept
	assert_false(view.setup(scene, missing, switches))
	assert_false(scene.has_node("Markers/PANEL_SPUR"), "validation must precede any mutation")
	var duplicate: Dictionary = switches.duplicate(true)
	duplicate["switches"].append(duplicate["switches"][0].duplicate(true))
	assert_false(view.setup(scene, data, duplicate))
	assert_false(scene.has_node("Markers/PANEL_SPUR"))
	var bad_conduit: Dictionary = data.duplicate(true)
	bad_conduit["conduit_cm"] = [[0, 0, 0], [999999, 0, 0]]
	assert_false(view.setup(scene, bad_conduit, switches))
	assert_false(scene.has_node("Markers/PANEL_SPUR"))
	var fractional: Dictionary = data.duplicate(true)
	fractional["markers"][0]["pos_cm"][0] = 6020.5
	assert_false(view.setup(scene, fractional, switches), "fractional centimeter coordinates are not accepted")
	assert_false(scene.has_node("Markers/PANEL_SPUR"))


func test_CTL1_C04_P01_c01_and_c03_contracts_remain_isolated() -> void:
	var c03: Node3D = C03.instantiate()
	_holder.add_child(c03)
	var c03_session: Offline = c03.get("session") as Offline
	assert_true(c03_session != null)
	assert_false(c03_session.host_state()["grid"]["nodes"].has("SPUR"))
	assert_eq(c03.get("_sign_spur_view"), null)
	assert_eq(c03.get("_store"), null)
	var c01: Node3D = C01.instantiate()
	_holder.add_child(c01)
	var c01_session: Offline = c01.get("session") as Offline
	assert_true(c01_session != null)
	assert_eq(c01_session.hud_view(1, "", "meter")["contract_key"], "contract.c01")
	assert_true(c01.get("_store") != null, "the production C01 save path remains present")
	assert_eq(c01.get("_sign_spur_view"), null)
	assert_false(c01_session.host_state()["grid"]["nodes"].has("SPUR"))


func test_CTL1_C04_P01_menu_text_and_immutable_source_boundaries() -> void:
	assert_true(UiText.t("offline.menu.c04_preview").contains("NOT SAVED"), "the menu says the preview is unsaved")
	assert_true(UiText.t("offline.c04.unsaved_notice").contains("not saved")
		or UiText.t("offline.c04.unsaved_notice").contains("no progress is saved"))
	assert_true(UiText.t("offline.loading.c04_briefing").contains("4 PU"))
	var preview_resource: Node3D = Preview.instantiate()
	assert_eq(preview_resource.get("contract_id"), "C04")
	preview_resource.free()
	var world: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
		Offline.C04_CONTRACT.path_join("world.json")))
	assert_eq(world.get("contract_id"), "C04")
	assert_eq(world["markers"].size(), 3)
	assert_eq(world["conduit_cm"].size(), 5)
