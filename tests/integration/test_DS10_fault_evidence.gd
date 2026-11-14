extends "res://tests/test_case.gd"
## DS10: presentation-only evidence follows the same accepted host records as
## the tablet. Synthetic states below test rendering branches; the meter and
## ping tests also drive the real offline host to verify authoritative inputs.

const Scene := preload("res://scenes/world/alder_street.tscn")
const Offline := preload("res://scripts/gameplay/offline_c01_session.gd")
const Dressing := preload("res://scripts/world/street_dressing.gd")
const StreetLook := preload("res://scripts/world/street_look.gd")
const District := preload("res://scripts/world/district_builder.gd")
const FaultEvidence := preload("res://scripts/world/fault_evidence_presentation.gd")
const UiText := preload("res://scripts/ui/ui_text.gd")
const Grid := preload("res://scripts/simulation/power_grid.gd")

var _tree: SceneTree
var _holder: Node3D
var _world: Node3D
var _eyes: Camera3D
var _fx: RefCounted
var _session: RefCounted


func before_each() -> void:
	_tree = Engine.get_main_loop() as SceneTree
	_holder = Node3D.new()
	_tree.root.add_child(_holder)
	_world = Scene.instantiate() as Node3D
	_world.name = "District"
	_holder.add_child(_world)
	var district: Dictionary = District.load_district()
	var look: Dictionary = StreetLook.load_look()
	StreetLook.skin_world(_world, look, district)
	Dressing.new().build(_world, district, look, Dressing.load_dressing())
	_eyes = Camera3D.new()
	_holder.add_child(_eyes)
	_fx = FaultEvidence.new()
	_fx.setup(_world, _eyes)
	_session = Offline.new()
	var errors: Array[Dictionary] = _session.setup(
		func(_player: String, _target: String) -> bool: return true,
		func(_player: String) -> Vector3i: return Vector3i(450, 100, 1500))
	assert_eq(errors, [] as Array[Dictionary])


func after_each() -> void:
	_fx = null
	_session = null
	_tree.root.remove_child(_holder)
	_holder.free()
	_holder = null


func _apply(tool: String = "meter", panel: String = "PANEL_JW") -> void:
	var readings: Dictionary = _session.meter.readings(panel, _session.grid)
	_fx.apply(_session.host_state(), tool, panel, readings)


func test_DS10_cabinet_overlays_leave_gameplay_collision_untouched() -> void:
	for id: String in ["CABINET_JW", "CABINET_JE"]:
		var cabinet: Node3D = _world.get_node("Dressing/Cabinet_" + id) as Node3D
		assert_true(cabinet.get_node_or_null("DS10DoorHinge") is Node3D)
		assert_true(cabinet.get_node_or_null("DS10Interior") is Node3D)
		assert_eq(cabinet.find_children("*", "CollisionObject3D", true, false).size(), 0)
		assert_eq(cabinet.find_children("*", "CollisionShape3D", true, false).size(), 0)
	assert_true(_eyes.get_node_or_null("DS10Meter/Reading") is Label3D)


func test_DS10_cabinets_follow_repair_stage_and_isolator_without_repair_mutation() -> void:
	var source: Dictionary = _session.host_state()
	var saved: String = Grid.serialize(source)
	_fx.apply(source, "screwdriver", "PANEL_JW", {})
	assert_false(_fx.cabinet_open("R_JW_FUSE"), "the default locked door is closed")
	assert_false(_fx.cabinet_open("R_JE_TRUNK"))
	var fixture: Dictionary = source.duplicate(true)
	var repairs: Dictionary = (fixture["repairs"] as Dictionary)["repairs"]
	repairs["R_JW_FUSE"] = {"state": "opened", "lock_owner": "P1"}
	var nodes: Dictionary = (fixture["grid"] as Dictionary)["nodes"]
	var west: Dictionary = nodes["JW"]
	west["isolated"] = true
	_fx.apply(fixture, "meter", "PANEL_JW", {})
	assert_true(_fx.cabinet_open("R_JW_FUSE"), "the door opens only after the host reports opened")
	assert_false(_fx.cabinet_open("R_JE_TRUNK"), "other repair stays closed")
	var west_holder: Node3D = _world.get_node("Dressing/Cabinet_CABINET_JW") as Node3D
	assert_true((west_holder.get_node("DS10Interior/FuseCarrier") as MeshInstance3D).visible)
	assert_true(absf((west_holder.get_node("IsolatorHandle") as Node3D).rotation.z) > 0.2)
	repairs["R_JW_FUSE"] = {"state": "component_removed", "lock_owner": "P1"}
	_fx.apply(fixture, "meter", "PANEL_JW", {})
	assert_false((west_holder.get_node("DS10Interior/FuseCarrier") as MeshInstance3D).visible)
	repairs["R_JW_FUSE"] = {"state": "replacement_installed", "lock_owner": "P1"}
	_fx.apply(fixture, "meter", "PANEL_JW", {})
	assert_true((west_holder.get_node("DS10Interior/FuseCarrier") as MeshInstance3D).visible)
	repairs["R_JW_FUSE"] = {"state": "restored", "lock_owner": ""}
	_fx.apply(fixture, "meter", "PANEL_JW", {})
	assert_false(_fx.cabinet_open("R_JW_FUSE"), "closed/tested/restored states never leave the door open")
	assert_eq(Grid.serialize(_session.host_state()), saved, "presentation cannot mutate host state")


func test_DS10_trunk_end_is_concealed_until_the_cabinet_is_open() -> void:
	var snapshot: Dictionary = _session.host_state().duplicate(true)
	var repairs: Dictionary = (snapshot["repairs"] as Dictionary)["repairs"]
	var east: Node3D = _world.get_node("Dressing/Cabinet_CABINET_JE") as Node3D
	_fx.apply(snapshot, "meter", "PANEL_JE", {})
	assert_false((east.get_node("DS10Interior") as Node3D).visible)
	repairs["R_JE_TRUNK"] = {"state": "opened", "lock_owner": "P1"}
	_fx.apply(snapshot, "meter", "PANEL_JE", {})
	assert_true((east.get_node("DS10Interior/TrunkEnd") as MeshInstance3D).visible)
	repairs["R_JE_TRUNK"] = {"state": "replacement_installed", "lock_owner": "P1"}
	_fx.apply(snapshot, "meter", "PANEL_JE", {})
	assert_false((east.get_node("DS10Interior/TrunkEnd") as MeshInstance3D).visible)


func test_DS10_meter_never_fabricates_a_reading() -> void:
	var unknown: Dictionary = _session.meter.readings("PANEL_JW", _session.grid)
	assert_false((unknown["_panel"] as Dictionary).has("tick"))
	_fx.apply(_session.host_state(), "meter", "PANEL_JW", unknown)
	assert_eq(_fx.meter_text(), UiText.t("world.meter.unmeasured"))
	var live: Node3D = _eyes.get_node("DS10Meter") as Node3D
	assert_true(live.visible)
	_fx.apply(_session.host_state(), "screwdriver", "PANEL_JW", unknown)
	assert_false(live.visible, "the meter is only visible while equipped")


func test_DS10_meter_shows_a_real_host_inspection_not_hidden_faults() -> void:
	var accepted: Dictionary = _session.interact("PANEL_JW", "meter")
	assert_true(bool(accepted.get("ok", false)))
	var known: Dictionary = _session.meter.readings("PANEL_JW", _session.grid)
	assert_true((known["_panel"] as Dictionary).has("tick"))
	_fx.apply(_session.host_state(), "meter", "PANEL_JW", known)
	assert_false(_fx.meter_text().contains("NOT MEASURED"))
	assert_true(_fx.meter_text().contains(UiText.t("world.meter.source")))
	_fx.apply(_session.host_state(), "meter", "TRUNK_JE", known)
	assert_eq(_fx.meter_text(), UiText.t("world.meter.unmeasured"),
		"an exposed trunk does not become a remote panel inspection")


func test_DS10_world_ping_only_follows_accepted_host_events() -> void:
	_fx.apply(_session.host_state(), "meter", "PANEL_JW", {})
	assert_false(_fx.ping_visible("R_JW_FUSE"))
	var ping: Dictionary = _session.command("ping", "JW", {"ping": "PING_LOOK"})
	assert_true(bool(ping.get("ok", false)))
	var ping_id: String = ""
	for event: Dictionary in ping.get("events", []):
		_fx.on_host_event(event)
		if str(event.get("type", "")) == "ping_added":
			ping_id = str((event["ping"] as Dictionary)["id"])
	assert_true(ping_id != "")
	assert_true(_fx.ping_visible("R_JW_FUSE"))
	assert_false(_fx.ping_visible("R_JE_TRUNK"))
	_fx.on_host_event({"type": "ping_removed", "ping": ping_id})
	assert_false(_fx.ping_visible("R_JW_FUSE"), "host expiration removes a visual ping")
