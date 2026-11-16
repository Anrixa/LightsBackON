extends "res://tests/test_case.gd"
## C03-P01 physical solo preview. These are headless scene and host/raycast
## integration checks, not real controller, GPU, human or Steam qualification.

const Preview := preload("res://scenes/mission/c03_roof_preview.tscn")
const C01 := preload("res://scenes/mission/mission_root.tscn")
const Offline := preload("res://scripts/gameplay/offline_c01_session.gd")
const Controller := preload("res://scripts/actors/first_person_controller.gd")
const Ladder := preload("res://scripts/world/c03_fixed_ladder_view.gd")
const Grid := preload("res://scripts/simulation/power_grid.gd")
const UiText := preload("res://scripts/ui/ui_text.gd")
const LoadingCard := preload("res://scripts/ui/loading_card.gd")

var _tree: SceneTree
var _holder: Node3D


func before_each() -> void:
	_tree = Engine.get_main_loop() as SceneTree
	_holder = Node3D.new()
	_tree.root.add_child(_holder)


func after_each() -> void:
	_tree.root.remove_child(_holder)
	_holder.free()
	_holder = null
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _preview() -> Node3D:
	var scene: Node3D = Preview.instantiate() as Node3D
	_holder.add_child(scene)
	return scene


func test_CTL1_C03_P01_explicit_preview_does_not_initialize_C01_save_writer() -> void:
	var scene: Node3D = _preview()
	var session: Offline = scene.get("session") as Offline
	assert_true(session != null, "C03 scene must actually boot the host stack")
	assert_eq(str(scene.get("contract_id")), "C03")
	assert_false(bool(scene.get("_save_enabled")))
	assert_eq(scene.get("_store"), null, "preview never touches the C01 save coordinator")
	assert_true(session.host_state()["grid"]["nodes"].has("ROOF_BEACON"))
	assert_eq(session.hud_view(1, "", "meter")["contract_key"], "contract.c03")
	assert_eq(str(session.mission.objectives()[0]["text_key"]), "objective.c03.reach_roof")
	assert_false((scene.get("onboarding") as Control).visible)
	assert_true(scene.get_node_or_null("District/C03RoofRoute") is Ladder)


func test_CTL1_C03_P01_world_markers_correspond_to_authorized_host_targets() -> void:
	var scene: Node3D = _preview()
	var session: Offline = scene.get("session") as Offline
	var ids: Array[String] = []
	for rec: Dictionary in session.targets():
		ids.append(str(rec["id"]))
		assert_false((rec["position"] as Vector3) == Vector3.INF)
	for id: String in ["LADDER_WEST", "LADDER_WEST_RETURN", "PANEL_ROOF", "SW_BEACON", "SW_CROSSFEED"]:
		assert_true(ids.has(id), id)
		assert_true(scene.get_node_or_null("District/Markers/" + id) is Marker3D)
	assert_eq(session.action_for("LADDER_WEST", "meter")["kind"], "use_ladder")
	assert_eq(session.action_for("LADDER_WEST_RETURN", "meter")["kind"], "use_ladder")
	assert_eq(session.action_for("PANEL_ROOF", "meter")["kind"], "inspect")
	assert_true(session.radius_for("LADDER_WEST") > 0.0)


func test_CTL1_C03_P01_actual_host_position_refuses_a_distant_ladder_request() -> void:
	var scene: Node3D = _preview()
	var session: Offline = scene.get("session") as Offline
	var player: Controller = scene.get("player") as Controller
	assert_true(player.global_position.distance_to(session.entity_position("LADDER_WEST")) > 10.0)
	var before: String = Grid.serialize(session.host_state())
	var denied: Dictionary = session.command("use_ladder", "LADDER_WEST", {})
	assert_eq(denied.get("code"), "NOT_IN_RANGE")
	assert_eq(Grid.serialize(session.host_state()), before,
		"no rejected remote use can change a grid, repair, or mission receipt")
	assert_false(session.mission.canonical_state()["ladder_access"].has("LADDER_WEST"))


func test_CTL1_C03_P01_live_ladder_command_moves_player_only_after_host_ack() -> void:
	var scene: Node3D = _preview()
	var session: Offline = scene.get("session") as Offline
	var player: Controller = scene.get("player") as Controller
	var view: Ladder = scene.get("_ladder_view") as Ladder
	var start: Vector3 = Vector3(21.0, 1.02, 40.2)
	# Even a player already on the rooftop cannot work on the cable until
	# the host has granted a valid ladder access receipt.
	player.global_position = view.destination("LADDER_WEST")
	assert_eq(session.command("request_lock", "R_ROOF_SPLICE", {}).get("code"), "NO_ACCESS")
	player.global_position = start
	assert_true(view.destination("LADDER_WEST").y > 8.0)
	assert_true(view.can_transfer(player, "LADDER_WEST"), "authored roof clearance is needed")
	scene.set("_target", "LADDER_WEST")
	scene.call("_interact")
	assert_true(session.mission.canonical_state()["ladder_access"].has("LADDER_WEST"))
	assert_true(player.global_position.y > 8.5, "a real player body reaches the authored roof landing")
	assert_eq(player.global_position, view.destination("LADDER_WEST"))
	assert_true(view.can_transfer(player, "LADDER_WEST_RETURN"))
	scene.set("_target", "LADDER_WEST_RETURN")
	scene.call("_interact")
	assert_true(player.global_position.y < 2.0)
	assert_eq(player.global_position, view.destination("LADDER_WEST_RETURN"))


func test_CTL1_C03_P01_invalid_destination_cannot_teleport_even_with_host_fixture() -> void:
	var scene: Node3D = _preview()
	var player: Controller = scene.get("player") as Controller
	var view: Ladder = scene.get("_ladder_view") as Ladder
	var before: Vector3 = player.global_position
	assert_false(view.can_transfer(player, "INVENTED"))
	assert_false(view.transfer(player, "INVENTED"))
	assert_eq(player.global_position, before)


func test_CTL1_C03_P01_roof_beacon_is_initially_dark_and_reads_host_snapshot() -> void:
	var scene: Node3D = _preview()
	var view: Ladder = scene.get("_ladder_view") as Ladder
	var indicator: MeshInstance3D = view.get_node("RoofBeacon") as MeshInstance3D
	assert_true(indicator != null)
	var session: Offline = scene.get("session") as Offline
	view.apply_host(session.host_state())
	var off: Material = indicator.material_override
	assert_false((off as StandardMaterial3D).emission_enabled)
	# No UI status may imply restored before the actual host state changes.
	var snapshot: Dictionary = session.host_state()
	snapshot["grid"]["nodes"]["ROOF_BEACON"]["supplied"] = true
	view.apply_host(snapshot)
	assert_true((indicator.material_override as StandardMaterial3D).emission_enabled)
	view.apply_host(session.host_state())
	assert_eq(indicator.material_override, off)


func test_CTL1_C03_P01_C01_scene_and_replay_authority_are_unchanged() -> void:
	var scene: Node3D = C01.instantiate() as Node3D
	_holder.add_child(scene)
	var session: Offline = scene.get("session") as Offline
	assert_true(session != null)
	assert_eq(str(scene.get("contract_id")), "C01")
	assert_eq(session.hud_view(1, "", "meter")["contract_key"], "contract.c01")
	assert_false(session.host_state()["grid"]["nodes"].has("ROOF_BEACON"))
	assert_false(is_instance_valid(scene.get_node_or_null("District/Markers/LADDER_WEST")))
	assert_false(is_instance_valid(scene.get("_ladder_view")), "C01 has no live ladder presentation")
	assert_true(scene.get("_store") != null, "original C01 storage path remains present")


func test_CTL1_C03_P01_preview_world_contract_and_menu_copy_are_present() -> void:
	var world: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
		Offline.C03_CONTRACT.path_join("world.json")))
	var defined: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
		Offline.C03_CONTRACT.path_join("mission.json")))
	assert_eq(world.get("contract_id"), "C03")
	assert_eq(world["transitions"].size(), 2)
	assert_eq(defined["fixed_ladders"].size(), 2)
	assert_true(UiText.t("offline.menu.c03_preview").contains("NO SAVE"))
	assert_true(UiText.t("offline.c03.unsaved_notice").contains("not saved"))

func test_CTL1_C03_P01_preview_loading_briefing_is_not_C01_instruction() -> void:
	var tokens: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/ui/tokens.json"))
	var c01_card: ColorRect = LoadingCard.build(tokens, 100.0, 46, true, true)
	var c03_card: ColorRect = LoadingCard.build(tokens, 100.0, 46, true, true,
		"offline.loading.c03_briefing")
	_holder.add_child(c01_card)
	_holder.add_child(c03_card)
	var c01_label: Label = c01_card.find_child("LoadingBriefing", true, false) as Label
	var c03_label: Label = c03_card.find_child("LoadingBriefing", true, false) as Label
	assert_true(c01_label != null and c03_label != null)
	assert_eq(c01_label.text, UiText.t("offline.loading.briefing"))
	assert_eq(c03_label.text, UiText.t("offline.loading.c03_briefing"))
	assert_ne(c03_label.text, c01_label.text)
	assert_true(c03_label.text.contains("ladder"))
