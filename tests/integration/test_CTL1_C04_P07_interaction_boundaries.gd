extends "res://tests/test_case.gd"
## CT-L1/C04 P07: source/headless interaction limit regression matrix.
## Temporarily staged target positions are not human/controller traversal.

const Preview := preload("res://scenes/mission/c04_sign_spur_preview.tscn")
const C01 := preload("res://scenes/mission/mission_root.tscn")
const C03 := preload("res://scenes/mission/c03_roof_preview.tscn")
const Offline := preload("res://scripts/gameplay/offline_c01_session.gd")
const Player := preload("res://scripts/actors/first_person_controller.gd")
const Grid := preload("res://scripts/simulation/power_grid.gd")
const Selector := preload("res://scripts/interaction/target_selector.gd")
const Visibility := preload("res://scripts/interaction/interaction_visibility.gd")
const Matrix := preload("res://scripts/diagnostics/c04_interaction_boundaries.gd")
const P06 := preload("res://scripts/diagnostics/c04_scene_accessibility.gd")
const ContentHash := preload("res://scripts/network/content_hash.gd")

const EXPECTED: Array[String] = [
	"PANEL_JE", "PANEL_JW", "PANEL_SPUR", "SW_EAST_SIGN",
	"SW_JE_BREAKER", "SW_JW_BREAKER", "SW_SIGN", "SW_SPUR_BREAKER"
]
const EYE_ABOVE_CENTER_M: float = 0.85
const STAGED_PLAYER_CENTER_Y_M: float = 0.90

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


## This helper is ONLY for a discrete host range test and never advances the
## character along a path. It preserves the existing P04/P06 headless ceiling.
func _stage_at_distance(scene: Node3D, entity: String, distance_m: float) -> void:
	var session: Offline = scene.get("session") as Offline
	var player: Player = scene.get("player") as Player
	var target: Vector3 = session.entity_position(entity)
	var front: Vector3 = Matrix.FRONT[entity]
	var dy: float = STAGED_PLAYER_CENTER_Y_M + EYE_ABOVE_CENTER_M - target.y
	var horizontal_m: float = sqrt(maxf(0.0, distance_m * distance_m - dy * dy))
	player.global_position = Vector3(target.x + front.x * horizontal_m,
		STAGED_PLAYER_CENTER_Y_M, target.z + front.z * horizontal_m)
	player.velocity = Vector3.ZERO


func test_CTL1_C04_P07_all_eight_source_boundaries_pass_conservative_headless_matrix() -> void:
	var scene: Node3D = _preview()
	var matrix: Dictionary = Matrix.inspect(scene)
	print("C04_P07_MATRIX ok=%s cases=%d failures=%s qualification=%s" % [
		str(matrix.get("ok")), int(matrix.get("cases_checked", -1)),
		str(matrix.get("failures", [])), str(matrix.get("not_certified", ""))])
	assert_true(bool(matrix["ok"]), str(matrix["failures"]))
	assert_eq(str(matrix["contract_id"]), "C04")
	assert_eq(str(matrix["code"]), "SOURCE_HEADLESS_ONLY")
	assert_eq(str(matrix["not_certified"]), "NO_CONTINUOUS_ROUTE_OR_HUMAN_CONTROLLER_TEST")
	assert_eq(int(matrix["cases_checked"]), 8)
	var ids: Array[String] = []
	for entry: Dictionary in matrix["cases"]:
		ids.append(str(entry["id"]))
		for gate: String in [
			"ok", "in_range_clear", "out_of_range_denied", "aimed_inside",
			"aimed_outside_denied", "facing_away_denied"
		]:
			assert_true(bool(entry[gate]), "%s: %s" % [entry["id"], gate])
		assert_eq(float(entry["margin_m"]), Matrix.EDGE_MARGIN_M)
		assert_true(float(entry["edge_m"]) > 2.30)
	assert_eq(ids, EXPECTED)


func test_CTL1_C04_P07_real_host_callback_obeys_near_far_boundary_for_each_target() -> void:
	var scene: Node3D = _preview()
	var session: Offline = scene.get("session") as Offline
	var before: String = Grid.serialize(session.host_state())
	for id: String in EXPECTED:
		var edge_m: float = 2.30 + session.radius_for(id)
		_stage_at_distance(scene, id, edge_m - 0.05)
		assert_true(bool(scene.call("_in_range", Offline.PLAYER_ID, id)),
			"actual host range and collision callback accepts safe front boundary: " + id)
		_stage_at_distance(scene, id, edge_m + 0.10)
		assert_false(bool(scene.call("_in_range", Offline.PLAYER_ID, id)),
			"actual host callback denies 10 cm outside range: " + id)
		assert_false(bool(scene.call("_in_range", "FORGED_PLAYER", id)),
			"peer identity cannot bypass distance: " + id)
	assert_eq(Grid.serialize(session.host_state()), before)
	assert_false(bool(scene.get("_save_enabled")))


func test_CTL1_C04_P07_all_eight_face_away_and_outside_rays_fail_selector() -> void:
	var scene: Node3D = _preview()
	var session: Offline = scene.get("session") as Offline
	for id: String in EXPECTED:
		var target: Vector3 = session.entity_position(id)
		var radius: float = session.radius_for(id)
		var direction: Vector3 = Matrix.FRONT[id]
		var inside: Vector3 = target + direction * (2.30 + radius - 0.05)
		var outside: Vector3 = target + direction * (2.30 + radius + 0.05)
		var candidates: Array[Dictionary] = [
			{"id": id, "position": target, "radius": radius}
		]
		assert_eq(Selector.select(inside, inside.direction_to(target),
			candidates, 2.30, 6.0), id, id)
		assert_eq(Selector.select(outside, outside.direction_to(target),
			candidates, 2.30, 6.0), "", id)
		assert_eq(Selector.select(inside, -inside.direction_to(target),
			candidates, 2.30, 6.0), "", id)


func test_CTL1_C04_P07_both_real_cabinets_block_short_rear_side_sightlines() -> void:
	var scene: Node3D = _preview()
	var session: Offline = scene.get("session") as Offline
	var player: Player = scene.get("player") as Player
	var space: PhysicsDirectSpaceState3D = scene.get_world_3d().direct_space_state
	for item: Dictionary in [
		{"id": "PANEL_JW", "blocker": "CABINET_JW", "x": 29.6},
		{"id": "PANEL_JE", "blocker": "CABINET_JE", "x": 72.6}
	]:
		var id: String = item["id"]
		var target: Vector3 = session.entity_position(id)
		var origin: Vector3 = Vector3(float(item["x"]), 1.79, 22.8)
		var radius: float = session.radius_for(id)
		assert_true(origin.distance_to(target) < 2.30 + radius)
		var ray: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
			origin, target, 1, [player.get_rid()] as Array[RID])
		var collision: Dictionary = space.intersect_ray(ray)
		var blocker: Node = collision.get("collider") as Node
		assert_true(blocker != null, "real physics first hit: " + id)
		if blocker != null:
			assert_eq(str(blocker.name), str(item["blocker"]))
		assert_false(Visibility.can_reach(space, origin, target, 2.30, radius,
			[player.get_rid()] as Array[RID]), id)


func test_CTL1_C04_P07_repair_id_and_panel_target_share_single_host_range_boundary() -> void:
	var scene: Node3D = _preview()
	var session: Offline = scene.get("session") as Offline
	for pair: Dictionary in [
		{"panel": "PANEL_JW", "repair": "R_JW_FUSE"},
		{"panel": "PANEL_JE", "repair": "R_JE_TRUNK"},
		{"panel": "PANEL_SPUR", "repair": "R_SIGN_SPUR"}
	]:
		var panel: String = pair["panel"]
		var repair: String = pair["repair"]
		assert_eq(session.entity_position(repair), session.entity_position(panel))
		assert_eq(session.radius_for(repair), session.radius_for(panel))
		_stage_at_distance(scene, panel, 2.30 + session.radius_for(panel) - 0.08)
		assert_eq(scene.call("_in_range", Offline.PLAYER_ID, repair),
			scene.call("_in_range", Offline.PLAYER_ID, panel),
			"repair ID must not have a separate physical authorization path")
		_stage_at_distance(scene, panel, 2.30 + session.radius_for(panel) + 0.10)
		assert_false(bool(scene.call("_in_range", Offline.PLAYER_ID, repair)), repair)


func test_CTL1_C04_P07_unauthorized_switches_cues_and_foreign_ids_are_not_targets() -> void:
	var scene: Node3D = _preview()
	var session: Offline = scene.get("session") as Offline
	var visible: Dictionary = {}
	for target: Dictionary in session.targets():
		visible[str(target["id"])] = true
	for id: String in EXPECTED:
		assert_true(visible.has(id), "original C04 authorized station: " + id)
	for illegal: String in [
		"SW_BEACON", "SW_ROOF", "SW_PUMP", "PANEL_UNKNOWN",
		"C04ApproachCues", "C04ControlStations"
	]:
		assert_false(visible.has(illegal))
		assert_eq(session.entity_position(illegal), Vector3.INF)
		assert_eq(session.radius_for(illegal), 0.0)
		assert_false(bool(scene.call("_in_range", Offline.PLAYER_ID, illegal)))


func test_CTL1_C04_P07_matrix_is_deterministic_read_only_and_non_save() -> void:
	var scene: Node3D = _preview()
	var session: Offline = scene.get("session") as Offline
	var player: Player = scene.get("player") as Player
	var before: String = Grid.serialize(session.host_state())
	var transform: Transform3D = player.global_transform
	var aim: Transform3D = player.camera.global_transform
	var marker_count: int = scene.get_node("District/Markers").get_child_count()
	var p06: Dictionary = P06.inspect(scene)
	var first: Dictionary = Matrix.inspect(scene)
	var second: Dictionary = Matrix.inspect(scene)
	assert_true(bool(p06["ok"]))
	assert_true(bool(first["ok"]), str(first["failures"]))
	assert_eq(first, second, "stable readback with no random or wall-clock inputs")
	assert_eq(Grid.serialize(session.host_state()), before)
	assert_eq(player.global_transform, transform)
	assert_eq(player.camera.global_transform, aim)
	assert_eq(scene.get_node("District/Markers").get_child_count(), marker_count)
	assert_true(scene.get("_store") == null)
	assert_false(bool(scene.get("_save_enabled")))


func test_CTL1_C04_P07_c01_c03_cannot_be_promoted_by_c04_audit() -> void:
	var c01: Node3D = C01.instantiate()
	_holder.add_child(c01)
	var c03: Node3D = C03.instantiate()
	_holder.add_child(c03)
	for scene: Node3D in [c01, c03]:
		var report: Dictionary = Matrix.inspect(scene)
		assert_false(bool(report["ok"]))
		assert_eq(str(report["code"]), "NOT_C04")
		assert_eq(report["cases"], [] as Array)
		assert_true(scene.get_node_or_null("District/C04SignSpur") == null)
	assert_true(c01.get("_store") != null)
	assert_true(c03.get("_store") == null)


func test_CTL1_C04_P07_evidence_ledger_and_rules_revision_are_separate() -> void:
	assert_true(FileAccess.file_exists("res://docs/evidence/CTL1-C04-P01-P07-LEDGER.md"))
	for phase: int in range(1, 8):
		var doc: String = "res://docs/evidence/CTL1-C04-P%02d.md" % phase
		assert_true(FileAccess.file_exists(doc), doc)
	assert_true(Matrix.INTERACTION_PATH.begins_with("res://content/"))
	assert_false(P06.GUIDES_PATH.begins_with(ContentHash.ROOT.trim_suffix("/") + "/"))
	assert_eq(ContentHash.presentation_paths().has("content/ui/strings/en.json"), true)
	assert_eq(Matrix.FRONT.size(), 8)
