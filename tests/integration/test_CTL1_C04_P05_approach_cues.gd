extends "res://tests/test_case.gd"
## CT-L1/C04 P05: source-bound, preview-only approach cues.
## Positions are staged; these tests DO NOT qualify a continuous walking route.

const Preview := preload("res://scenes/mission/c04_sign_spur_preview.tscn")
const C01 := preload("res://scenes/mission/mission_root.tscn")
const C03 := preload("res://scenes/mission/c03_roof_preview.tscn")
const AlderWorld := preload("res://scenes/world/alder_street.tscn")
const SpurView := preload("res://scripts/world/c04_sign_spur_view.gd")
const Offline := preload("res://scripts/gameplay/offline_c01_session.gd")
const Controller := preload("res://scripts/actors/first_person_controller.gd")
const Grid := preload("res://scripts/simulation/power_grid.gd")
const UiText := preload("res://scripts/ui/ui_text.gd")
const ContentHash := preload("res://scripts/network/content_hash.gd")

const GUIDES_PATH: String = "res://scenes/mission/c04_preview_approaches.json"
const EXPECTED_IDS: Array[String] = [
	"PANEL_JE", "PANEL_JW", "PANEL_SPUR", "SW_SIGN", "SW_EAST_SIGN", "ZONE_VAN"
]

var _holder: Node3D


func before_each() -> void:
	_holder = Node3D.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(_holder)


func after_each() -> void:
	_holder.get_parent().remove_child(_holder)
	_holder.free()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _content(path: String) -> Dictionary:
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return raw if raw is Dictionary else {}


func _preview() -> Node3D:
	var scene: Node3D = Preview.instantiate()
	_holder.add_child(scene)
	return scene


func test_CTL1_C04_P05_only_six_authored_noncolliding_approaches_appear() -> void:
	var scene: Node3D = _preview()
	var view: SpurView = scene.get("_sign_spur_view") as SpurView
	assert_true(view != null)
	var cues: Node3D = view.get_node("C04ApproachCues") as Node3D
	assert_eq(cues.get_child_count(), EXPECTED_IDS.size())
	var source: Dictionary = _content(GUIDES_PATH)
	for entry: Dictionary in source["approaches"]:
		var id: String = entry["id"]
		assert_true(EXPECTED_IDS.has(id), "authorized guide: " + id)
		var cue: Node3D = cues.get_node_or_null(id) as Node3D
		assert_true(cue != null, "scene guide exists: " + id)
		if cue == null:
			continue
		var coord: Array = entry["pos_cm"]
		assert_eq(cue.position,
			Vector3(float(coord[0]), float(coord[1]), float(coord[2])) / 100.0)
		assert_true(cue.get_node_or_null("GroundCue") is MeshInstance3D)
		var label: Label3D = cue.get_node_or_null("Caption") as Label3D
		assert_true(label != null)
		if label != null:
			assert_eq(label.text, UiText.t(str(entry["label_key"])))
			assert_false(label.text.contains("SUPPLIED"),
				"neutral navigation hint cannot certify electrical supply")
		assert_eq(cue.find_children("*", "CollisionObject3D", true, false).size(), 0)
		assert_eq(cue.find_children("*", "CollisionShape3D", true, false).size(), 0)
		assert_false(scene.get_node("District/Markers").has_node(id)
			and id == "ZONE_VAN", "van cue cannot register a new host target")
	assert_eq(scene.get("_store"), null)
	assert_false(bool(scene.get("_save_enabled")))


func test_CTL1_C04_P05_invalid_or_foreign_guides_fail_before_world_mutation() -> void:
	var world: Node3D = AlderWorld.instantiate()
	_holder.add_child(world)
	var view: SpurView = SpurView.new()
	world.add_child(view)
	var overlay: Dictionary = _content(Offline.C04_CONTRACT.path_join("world.json"))
	var switches: Dictionary = _content(Offline.C04_CONTRACT.path_join("switches.json"))
	var good: Dictionary = _content(GUIDES_PATH)
	var forged: Dictionary = good.duplicate(true)
	forged["approaches"][0]["id"] = "SW_BEACON"
	var duplicate: Dictionary = good.duplicate(true)
	duplicate["approaches"][0]["id"] = duplicate["approaches"][1]["id"]
	var wrong_key: Dictionary = good.duplicate(true)
	wrong_key["approaches"][0]["label_key"] = "objective.c01.extract"
	var far: Dictionary = good.duplicate(true)
	far["approaches"][0]["pos_cm"] = [7260, 6, 3300]
	var sunken: Dictionary = good.duplicate(true)
	sunken["approaches"][2]["pos_cm"] = [6020, -50, 3790]
	var missing: Dictionary = good.duplicate(true)
	missing["approaches"].pop_back()
	var bad_contract: Dictionary = good.duplicate(true)
	bad_contract["contract_id"] = "C03"
	var original_count: int = world.get_node("Markers").get_child_count()
	for invalid: Dictionary in [
		forged, duplicate, wrong_key, far, sunken, missing, bad_contract
	]:
		assert_false(view.setup(world, overlay, switches, invalid))
		assert_eq(world.get_node("Markers").get_child_count(), original_count)
		assert_eq(view.get_child_count(), 0, "invalid guidance is atomic")
	assert_false(view.setup(world, overlay, switches, {"contract_id": "C04",
		"approaches": "not-an-array"}))
	assert_false(view.setup(world, overlay, switches, 42))
	assert_eq(view.get_child_count(), 0)
	assert_true(view.setup(world, overlay, switches, good),
		"original preview-only standing positions are source-valid")
	assert_eq(view.get_node("C04ApproachCues").get_child_count(), 6)


func test_CTL1_C04_P05_cue_text_never_mutates_power_or_mission_authority() -> void:
	var scene: Node3D = _preview()
	var view: SpurView = scene.get("_sign_spur_view") as SpurView
	var session: Offline = scene.get("session") as Offline
	var original: String = Grid.serialize(session.host_state())
	var guides: Node3D = view.get_node("C04ApproachCues") as Node3D
	var captions: Dictionary = {}
	for cue: Node in guides.get_children():
		captions[str(cue.name)] = (cue.get_node("Caption") as Label3D).text
	var fake: Dictionary = session.host_state()
	fake["grid"]["nodes"]["SIGN"]["supplied"] = true
	fake["mission"]["latched"]["LATCH_SIGN_SUPPLY"] = 123
	view.apply_host(fake)
	assert_eq(Grid.serialize(session.host_state()), original)
	for cue: Node in guides.get_children():
		assert_eq((cue.get_node("Caption") as Label3D).text, captions[str(cue.name)],
			"guidance cannot claim verified power or reward")
	assert_eq(session.action_for("C04ApproachCues", "meter"), {})
	assert_eq(session.radius_for("C04ApproachCues"), 0.0)


func test_CTL1_C04_P05_authored_approach_sites_are_staged_not_walked() -> void:
	var scene: Node3D = _preview()
	var player: Controller = scene.get("player") as Controller
	var session: Offline = scene.get("session") as Offline
	var source: Dictionary = _content(GUIDES_PATH)
	var verified: int = 0
	for entry: Dictionary in source["approaches"]:
		var id: String = entry["id"]
		var cm: Array = entry["pos_cm"]
		player.global_position = Vector3(float(cm[0]), 90.0, float(cm[2])) / 100.0
		player.velocity = Vector3.ZERO
		if id == "ZONE_VAN":
			assert_true(session.inside_van(player.global_position),
				"authored van guide lies within the existing host extraction zone")
		else:
			assert_true(bool(scene.call("_in_range", Offline.PLAYER_ID, id)),
				"staged physics range at authored C04 approach: " + id)
			player.camera.look_at(session.entity_position(id), Vector3.UP)
			scene.call("_update_target")
			assert_eq(str(scene.get("_target")), id,
				"staged first-person target, not a continuous route: " + id)
		verified += 1
	assert_eq(verified, 6)
	assert_false(bool(scene.get("_save_enabled")))


func test_CTL1_C04_P05_legacy_scenes_keep_no_approach_cues() -> void:
	var c01: Node3D = C01.instantiate()
	_holder.add_child(c01)
	assert_true(c01.get_node_or_null("District/C04SignSpur") == null)
	assert_true(c01.get_node_or_null("District/C04ApproachCues") == null)
	assert_true(c01.get("_store") != null)
	var c03: Node3D = C03.instantiate()
	_holder.add_child(c03)
	assert_true(c03.get_node_or_null("District/C04SignSpur") == null)
	assert_true(c03.get_node_or_null("District/C04ApproachCues") == null)
	assert_true(c03.get("_store") == null)
	for entry: Dictionary in _content(GUIDES_PATH)["approaches"]:
		assert_true(UiText.has(str(entry["label_key"])))


func test_CTL1_C04_P05_guide_file_never_changes_rules_revision_classification() -> void:
	assert_true(FileAccess.file_exists(GUIDES_PATH))
	assert_false(GUIDES_PATH.begins_with(ContentHash.ROOT.trim_suffix("/") + "/"),
		"the P05 visual guide must stay outside hashed content rules")
	assert_true(ContentHash.presentation_paths().has("content/ui/strings/en.json"),
		"new localized captions must remain presentation-only")
	assert_false(ContentHash.presentation_paths().has(
		"content/world/c04_preview_approaches.json"),
		"there must be no stale compatibility exception for an obsolete guide file")


func test_CTL1_C04_P05_both_export_presets_package_preview_json() -> void:
	# Future additive exports may include further unreferenced, source-owned
	# JSON files. Enforce membership rather than freezing the entire CSV text.
	var presets: String = FileAccess.get_file_as_string("res://export_presets.cfg")
	var checked: int = 0
	for line: String in presets.split("\n"):
		if not line.begins_with('include_filter="'):
			continue
		var value: String = line.trim_prefix('include_filter="').trim_suffix('"')
		var included: PackedStringArray = value.split(",")
		assert_true(included.has("build_manifest.json"),
			"the build provenance manifest must be packaged")
		assert_true(included.has("scenes/mission/c04_preview_approaches.json"),
			"C04's otherwise unreferenced approach JSON must survive both exports")
		checked += 1
	assert_eq(checked, 2, "check both release and internal Windows presets")
