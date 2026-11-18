extends "res://tests/test_case.gd"
## CT-L1/C04 P06: no walking/collider movement. Diagnostic probes sample
## virtual capsules and sight rays in the genuine C04 scene's physics world.

const Preview := preload("res://scenes/mission/c04_sign_spur_preview.tscn")
const C01 := preload("res://scenes/mission/mission_root.tscn")
const C03 := preload("res://scenes/mission/c03_roof_preview.tscn")
const Offline := preload("res://scripts/gameplay/offline_c01_session.gd")
const Controller := preload("res://scripts/actors/first_person_controller.gd")
const Grid := preload("res://scripts/simulation/power_grid.gd")
const Visibility := preload("res://scripts/interaction/interaction_visibility.gd")
const TargetSelector := preload("res://scripts/interaction/target_selector.gd")
const Audit := preload("res://scripts/diagnostics/c04_scene_accessibility.gd")
const ContentHash := preload("res://scripts/network/content_hash.gd")

const WORKSITES: Array[String] = [
	"PANEL_JE", "PANEL_JW", "PANEL_SPUR", "SW_EAST_SIGN", "SW_JE_BREAKER",
	"SW_JW_BREAKER", "SW_SIGN", "SW_SPUR_BREAKER"
]

var _holder: Node3D


func before_each() -> void:
	_holder = Node3D.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(_holder)


func after_each() -> void:
	_holder.get_parent().remove_child(_holder)
	_holder.free()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _scene() -> Node3D:
	var scene: Node3D = Preview.instantiate()
	_holder.add_child(scene)
	return scene


func test_CTL1_C04_P06_eight_scene_worksites_are_visible_and_capsule_clear_at_staged_positions() -> void:
	var scene: Node3D = _scene()
	var report: Dictionary = Audit.inspect(scene)
	print("C04_P06_AUDIT ok=%s contract=%s sites=%d van=%s cabinet=%s failures=%s" %
		[str(report.get("ok")), str(report.get("contract_id")),
		(report.get("sites", []) as Array).size(), str(report.get("van_inside_zone")),
		str(report.get("cabinet_negative")), str(report.get("failures"))])
	assert_true(bool(report["ok"]), str(report["failures"]))
	assert_eq(str(report["code"]), "SOURCE_HEADLESS_ONLY")
	assert_eq(str(report["not_certified"]), "NO_CONTINUOUS_ROUTE_OR_HUMAN_CONTROLLER_TEST")
	var sites: Array = report["sites"]
	assert_eq(sites.size(), 8)
	var ids: Array[String] = []
	for site: Dictionary in sites:
		ids.append(str(site["id"]))
		assert_true(bool(site["ok"]), str(site))
		assert_true(bool(site["marker_aligned"]), str(site))
		assert_true(bool(site["capsule_clear"]), str(site))
		assert_eq(site["capsule_blockers"], [] as Array[String], str(site))
		assert_true(bool(site["ray_clear"]), str(site))
		assert_eq(str(site["selected"]), str(site["id"]))
		assert_true(float(site["eye_distance_m"]) < float(site["interaction_limit_m"]))
	assert_eq(ids, WORKSITES)


func test_CTL1_C04_P06_van_zone_uses_real_scene_without_new_extraction_authority() -> void:
	var scene: Node3D = _scene()
	var session: Offline = scene.get("session") as Offline
	var before: String = Grid.serialize(session.host_state())
	var report: Dictionary = Audit.inspect(scene)
	assert_true(bool(report["van_capsule_clear"]))
	assert_true(bool(report["van_inside_zone"]))
	assert_eq(session.action_for("C04ApproachCues", "meter"), {})
	assert_eq(session.radius_for("C04ApproachCues"), 0.0)
	assert_eq(session.entity_position("C04ApproachCues"), Vector3.INF)
	assert_eq(Grid.serialize(session.host_state()), before,
		"virtual van/capsule checks cannot certify extraction or edit host state")
	assert_false(bool(scene.get("_save_enabled")))
	assert_true(scene.get("_store") == null)


func test_CTL1_C04_P06_real_cabinet_occludes_nearby_backside_host_target() -> void:
	var scene: Node3D = _scene()
	var session: Offline = scene.get("session") as Offline
	var player: Controller = scene.get("player") as Controller
	var report: Dictionary = Audit.inspect(scene)
	var cabinet: Dictionary = report["cabinet_negative"]
	assert_true(bool(cabinet["within_range"]),
		"negative sightline must be within normal range, not a distant rejection")
	assert_true(bool(cabinet["denied"]))
	assert_eq(str(cabinet["first_collider"]), "CABINET_JW")
	var behind: Vector3 = Vector3(29.6, 1.79, 22.8)
	var target: Vector3 = session.entity_position("PANEL_JW")
	assert_false(Visibility.can_reach(scene.get_world_3d().direct_space_state, behind, target,
		2.30, session.radius_for("PANEL_JW"), [player.get_rid()] as Array[RID]),
		"nominally in-range ray must not traverse the real cabinet")


func test_CTL1_C04_P06_host_callback_rejects_backside_and_far_range_without_aim_bypass() -> void:
	var scene: Node3D = _scene()
	var player: Controller = scene.get("player") as Controller
	var session: Offline = scene.get("session") as Offline
	var original_grid: String = Grid.serialize(session.host_state())
	player.global_position = Vector3(29.6, 0.94, 22.8)
	player.velocity = Vector3.ZERO
	assert_false(bool(scene.call("_in_range", Offline.PLAYER_ID, "PANEL_JW")),
		"real host callback applies obstruction denial")
	assert_false(bool(scene.call("_in_range", Offline.PLAYER_ID, "R_JW_FUSE")),
		"repair identity must not bypass its panel's blocked line")
	player.global_position = Vector3(29.6, 0.94, 25.9)
	assert_true(bool(scene.call("_in_range", Offline.PLAYER_ID, "PANEL_JW")))
	assert_true(bool(scene.call("_in_range", Offline.PLAYER_ID, "R_JW_FUSE")))
	assert_false(bool(scene.call("_in_range", "FORGED_PLAYER", "PANEL_JW")))
	assert_false(bool(scene.call("_in_range", Offline.PLAYER_ID, "SW_BEACON")))
	player.global_position = Vector3(29.6, 0.94, 31.0)
	assert_false(bool(scene.call("_in_range", Offline.PLAYER_ID, "PANEL_JW")))
	assert_eq(Grid.serialize(session.host_state()), original_grid,
		"range probe does not trigger repairs, switching or reward state")


func test_CTL1_C04_P06_selector_facing_away_cannot_select_even_when_within_range() -> void:
	var scene: Node3D = _scene()
	var session: Offline = scene.get("session") as Offline
	var target: Vector3 = session.entity_position("PANEL_JE")
	var eye: Vector3 = Vector3(72.6, 1.79, 26.1)
	var radius: float = session.radius_for("PANEL_JE")
	var choices: Array[Dictionary] = [{"id": "PANEL_JE", "position": target, "radius": radius}]
	assert_eq(TargetSelector.select(eye, eye.direction_to(target), choices, 2.3, 6.0),
		"PANEL_JE")
	assert_eq(TargetSelector.select(eye, -eye.direction_to(target), choices, 2.3, 6.0),
		"", "a nearby host-valid target does not appear behind the reticle")
	assert_true(Visibility.can_reach(scene.get_world_3d().direct_space_state, eye, target,
		2.3, radius, [] as Array[RID]),
		"aim selection and host sight are distinct gates")


func test_CTL1_C04_P06_diagnostics_are_read_only_across_multiple_audits() -> void:
	var scene: Node3D = _scene()
	var session: Offline = scene.get("session") as Offline
	var player: Controller = scene.get("player") as Controller
	var grid_before: String = Grid.serialize(session.host_state())
	var transform_before: Transform3D = player.global_transform
	var camera_before: Transform3D = player.camera.global_transform
	var stage_before: int = (scene.get_node("District/Markers") as Node3D).get_child_count()
	var first: Dictionary = Audit.inspect(scene)
	var second: Dictionary = Audit.inspect(scene)
	assert_true(bool(first["ok"]), str(first["failures"]))
	assert_eq(first, second, "stable independent scene scans have deterministic readbacks")
	assert_eq(Grid.serialize(session.host_state()), grid_before)
	assert_eq(player.global_transform, transform_before,
		"a virtual capsule must not teleport the actual player")
	assert_eq(player.camera.global_transform, camera_before)
	assert_eq((scene.get_node("District/Markers") as Node3D).get_child_count(), stage_before)
	assert_eq(scene.get("_target"), "")


func test_CTL1_C04_P06_c01_and_c03_reject_audit_without_changing_existing_saves() -> void:
	var c01: Node3D = C01.instantiate()
	_holder.add_child(c01)
	var c03: Node3D = C03.instantiate()
	_holder.add_child(c03)
	for scene: Node3D in [c01, c03]:
		var before: Transform3D = (scene.get("player") as Controller).global_transform
		var report: Dictionary = Audit.inspect(scene)
		assert_false(bool(report["ok"]))
		assert_eq(str(report["code"]), "NOT_C04")
		assert_eq(report["sites"], [] as Array)
		assert_eq((scene.get("player") as Controller).global_transform, before)
		assert_true(scene.get_node_or_null("District/C04SignSpur") == null)
	assert_true(c01.get("_store") != null)
	assert_true(c03.get("_store") == null)


func test_CTL1_C04_P06_accessibility_probes_are_not_authoritative_content_changes() -> void:
	assert_true(FileAccess.file_exists(Audit.GUIDES_PATH))
	assert_false(Audit.GUIDES_PATH.begins_with(ContentHash.ROOT.trim_suffix("/") + "/"))
	assert_true(ContentHash.presentation_paths().has("content/ui/strings/en.json"))
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Audit.GUIDES_PATH))
	assert_eq(str(source["contract_id"]), "C04")
	assert_eq((source["approaches"] as Array).size(), 6)
	assert_eq(Audit.COMPANIONS.size(), 3)
	assert_eq(float(Audit.STAND_OFF_GROUND_M), 0.04)
	assert_eq(int(Audit.WORLD_MASK), 1)
