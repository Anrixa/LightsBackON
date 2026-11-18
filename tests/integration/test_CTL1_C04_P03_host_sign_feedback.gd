extends "res://tests/test_case.gd"
## CT-L1/C04 P03: source/headless UI and host-projection regressions only.
## No physical human/controller playability, route traversal, GPU or Steam tests.

const Preview := preload("res://scenes/mission/c04_sign_spur_preview.tscn")
const C01 := preload("res://scenes/mission/mission_root.tscn")
const C03 := preload("res://scenes/mission/c03_roof_preview.tscn")
const AlderWorld := preload("res://scenes/world/alder_street.tscn")
const Offline := preload("res://scripts/gameplay/offline_c01_session.gd")
const SpurView := preload("res://scripts/world/c04_sign_spur_view.gd")
const UiText := preload("res://scripts/ui/ui_text.gd")
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


func test_CTL1_C04_P03_tablet_contract_identity_in_all_three_scenes() -> void:
	var c04: Node3D = _preview()
	assert_eq(c04.call("_tablet_breadcrumbs"), ["district.alder_street", "contract.c04"])
	assert_false(bool(c04.get("_save_enabled")), "C04 presentation must remain unsaved")
	assert_eq(c04.get("_store"), null)
	var c03: Node3D = C03.instantiate()
	_holder.add_child(c03)
	assert_eq(c03.call("_tablet_breadcrumbs"), ["district.alder_street", "contract.c03"])
	var c01: Node3D = C01.instantiate()
	_holder.add_child(c01)
	assert_eq(c01.call("_tablet_breadcrumbs"), ["district.alder_street", "contract.c01"])


func test_CTL1_C04_P03_host_latch_and_verification_feedback_are_contract_specific() -> void:
	var scene: Node3D = _preview()
	var session: Offline = scene.get("session") as Offline
	var message: Label = scene.get("_status") as Label
	var before: String = Grid.serialize(session.host_state())
	# An event-presentation test does not alter or impersonate the host mission.
	scene.call("_on_mission_event", {"type": "latch", "id": "LATCH_SIGN_SUPPLY"})
	assert_eq(message.text, UiText.t("offline.c04.sign_bonus_latched"))
	assert_false(message.text.contains("Pump house drained"))
	scene.call("_on_mission_event", {"type": "verified"})
	assert_eq(message.text, UiText.t("offline.c04.required_verified"))
	assert_eq(Grid.serialize(session.host_state()), before, "UI feedback cannot grant a latch")
	var c01: Node3D = C01.instantiate()
	_holder.add_child(c01)
	var legacy: Label = c01.get("_status") as Label
	c01.call("_on_mission_event", {"type": "latch", "id": Offline.PUMP_LATCH})
	assert_eq(legacy.text, UiText.t("offline.status.drain"), "C01 drainage messaging preserved")


func test_CTL1_C04_P03_bonus_reads_mission_latch_not_sign_power() -> void:
	var scene: Node3D = _preview()
	var view: SpurView = scene.get("_sign_spur_view") as SpurView
	var session: Offline = scene.get("session") as Offline
	var badge: Label3D = view.get_node("C04SignBonus") as Label3D
	var supplied: Label3D = view.get_node("C04SignSupply") as Label3D
	var before: String = Grid.serialize(session.host_state())
	var pending: Dictionary = session.host_state()
	pending["grid"]["nodes"]["SIGN"]["supplied"] = true
	view.apply_host(pending)
	assert_true(supplied.text.ends_with("SUPPLIED"))
	assert_true(badge.text.ends_with(UiText.t("offline.c04.sign_bonus_pending")),
		"Instant supply never implies the 100-tick host bonus")
	pending["mission"]["latched"]["LATCH_SIGN_SUPPLY"] = 101
	view.apply_host(pending)
	assert_true(badge.text.ends_with(UiText.t("offline.c04.sign_bonus_verified")))
	pending["grid"]["nodes"]["SIGN"]["supplied"] = false
	view.apply_host(pending)
	assert_true(supplied.text.ends_with("UNSUPPLIED"))
	assert_true(badge.text.ends_with(UiText.t("offline.c04.sign_bonus_verified")),
		"A host-earned durable bonus is not erased by later loss of supply")
	assert_eq(Grid.serialize(session.host_state()), before, "presentation does not mutate live host")


func test_CTL1_C04_P03_malformed_host_views_never_fake_power_or_bonus() -> void:
	var scene: Node3D = _preview()
	var view: SpurView = scene.get("_sign_spur_view") as SpurView
	var badge: Label3D = view.get_node("C04SignBonus") as Label3D
	var supplied: Label3D = view.get_node("C04SignSupply") as Label3D
	var spur: Label3D = view.get_node("C04ControlStations/PANEL_SPUR/State") as Label3D
	var isolator: Label3D = view.get_node("C04ControlStations/SW_EAST_SIGN/State") as Label3D
	for bad: Dictionary in [
		{},
		{"grid": "BAD", "mission": "BAD"},
		{"grid": {"nodes": [], "edges": "BAD"}, "mission": {"latched": []}},
		{"grid": {"nodes": {"SIGN": {"supplied": "yes"}}, "edges": {"E_GRID_SPUR": {"enabled": 1}}},
			"mission": {"latched": {"LATCH_SIGN_SUPPLY": "forged"}}}
	]:
		view.apply_host(bad)
		assert_true(supplied.text.ends_with("UNKNOWN"))
		assert_true(spur.text.ends_with("UNKNOWN"))
		assert_true(isolator.text.ends_with("UNKNOWN"))
		assert_true(badge.text.ends_with("UNKNOWN"))


func test_CTL1_C04_P03_wrong_binding_refused_before_scene_mutation() -> void:
	var world: Node3D = AlderWorld.instantiate()
	_holder.add_child(world)
	var view: SpurView = SpurView.new()
	world.add_child(view)
	var overlay: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
		Offline.C04_CONTRACT.path_join("world.json")))
	var controls: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
		Offline.C04_CONTRACT.path_join("switches.json")))
	var wrong_target: Dictionary = controls.duplicate(true)
	wrong_target["switches"][0]["target"] = "JW"
	var wrong_field: Dictionary = controls.duplicate(true)
	wrong_field["switches"][1]["field"] = "enabled"
	for forged: Dictionary in [wrong_target, wrong_field]:
		assert_false(view.setup(world, overlay, forged),
			"C04 overlay cannot relabel a switch to a different host operation")
		assert_false(world.has_node("Markers/PANEL_SPUR"))
		assert_eq(view.get_child_count(), 0)
	assert_true(view.setup(world, overlay, controls), "unchanged original contract accepted")
	assert_true(world.has_node("Markers/PANEL_SPUR"))
