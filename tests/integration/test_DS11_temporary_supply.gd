extends "res://tests/test_case.gd"
## DS11: generator tradeoff is a projection of real host state, not another
## timer or authority. Synthetic host replies exercise the refused-tie UI,
## while source/load/protection cases drive a real isolated offline C01 host.

const Scene := preload("res://scenes/world/alder_street.tscn")
const Offline := preload("res://scripts/gameplay/offline_c01_session.gd")
const Dressing := preload("res://scripts/world/street_dressing.gd")
const StreetLook := preload("res://scripts/world/street_look.gd")
const District := preload("res://scripts/world/district_builder.gd")
const GeneratorTradeoff := preload("res://scripts/world/generator_tradeoff_presentation.gd")
const FieldHud := preload("res://scripts/ui/field_hud.gd")
const UiText := preload("res://scripts/ui/ui_text.gd")
const Grid := preload("res://scripts/simulation/power_grid.gd")

var _tree: SceneTree
var _holder: Node3D
var _world: Node3D
var _fx: GeneratorTradeoff
var _session: Offline


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
	_fx = GeneratorTradeoff.new()
	_fx.setup(_world)
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


func _command(action: String, extra: Dictionary = {}) -> Dictionary:
	var payload: Dictionary = {"action": action}
	payload.merge(extra)
	return _session.command("place_item", "GEN_PORTABLE", payload)


func _prepare_generator() -> void:
	assert_true(bool(_command("pickup").get("ok", false)))
	assert_true(bool(_command("place", {"anchor": "PAD_PUMP"}).get("ok", false)))


func _start_pump_only() -> void:
	_prepare_generator()
	assert_true(bool(_command("connect", {"route": "E_TEMP_PUMP"}).get("ok", false)))
	assert_true(bool(_command("start").get("ok", false)))


func test_DS11_visuals_add_no_collision_or_relocate_any_world_marker() -> void:
	var overlay: Node3D = _world.get_node("DS11TemporarySupply") as Node3D
	assert_true(overlay.get_node_or_null("PortableGenerator") is Node3D)
	assert_true(overlay.get_node_or_null("GeneratorPadMarkings") is Node3D)
	assert_eq(overlay.find_children("*", "CollisionObject3D", true, false).size(), 0)
	assert_eq(overlay.find_children("*", "CollisionShape3D", true, false).size(), 0)
	assert_true(_fx.ring_count() == 16, "the visible overload dial is composed of authored progress segments")
	assert_true(_fx.warning_sound() != null)
	assert_true(_fx.warning_sound().stream is AudioStreamWAV, "warning is project-generated PCM, not imported audio")


func test_DS11_visuals_follow_the_accepted_generator_anchor() -> void:
	var start: Dictionary = _fx.apply(_session.host_state())
	assert_eq(start["anchor"], "VAN_BAY")
	assert_false(bool(start["visible"]), "van storage is not an on-pad HUD alert")
	var body: Node3D = _world.get_node("DS11TemporarySupply/PortableGenerator") as Node3D
	assert_true(body.visible, "generator is physically present at the van")
	_prepare_generator()
	var view: Dictionary = _fx.apply(_session.host_state())
	assert_true(bool(view["on_pad"]))
	assert_true(bool(view["visible"]))
	assert_eq(body.position, Vector3(62.5, 0.0, 16.0), "generator matches the authored equipment pad")
	assert_false(_fx.cable_visible("E_TEMP_PUMP"))
	assert_false(_fx.cable_visible("E_TEMP_PUB"))


func test_DS11_pump_route_is_visible_only_when_the_real_host_connects_it() -> void:
	_prepare_generator()
	var baseline: String = Grid.serialize(_session.host_state())
	_fx.apply(_session.host_state())
	assert_false(_fx.cable_visible("E_TEMP_PUMP"))
	assert_false(_fx.cable_visible("E_TEMP_PUB"))
	assert_eq(Grid.serialize(_session.host_state()), baseline)
	assert_true(bool(_command("connect", {"route": "E_TEMP_PUMP"}).get("ok", false)))
	var view: Dictionary = _fx.apply(_session.host_state())
	assert_true(_fx.cable_visible("E_TEMP_PUMP"))
	assert_false(_fx.cable_visible("E_TEMP_PUB"))
	assert_true(bool((view["routes"] as Dictionary)["E_TEMP_PUMP"]))
	assert_true(bool(_command("disconnect", {"route": "E_TEMP_PUMP"}).get("ok", false)))
	_fx.apply(_session.host_state())
	assert_false(_fx.cable_visible("E_TEMP_PUMP"), "disconnect from host removes the rendered cable")


func test_DS11_valid_pump_supply_reads_four_of_six_not_a_fake_maximum() -> void:
	_start_pump_only()
	var view: Dictionary = _fx.apply(_session.host_state())
	assert_eq(view["load"], 4)
	assert_eq(view["capacity"], 6)
	assert_true(bool(view["online"]))
	assert_false(bool(view["warning"]))
	assert_eq(view["trip_ticks"], 0)
	assert_true(_fx.cable_visible("E_TEMP_PUMP"))
	assert_eq((_world.get_node("DS11TemporarySupply/PortableGenerator/LoadReadout") as Label3D).text,
		UiText.tf("world.generator.gauge", [4, 6]) + "\n" + UiText.t("world.generator.running"))


func test_DS11_overload_ring_uses_exact_host_ticks_and_never_predicts_trip() -> void:
	_start_pump_only()
	assert_true(bool(_command("connect", {"route": "E_TEMP_PUB"}).get("ok", false)))
	var initial: Dictionary = _fx.apply(_session.host_state())
	assert_eq(initial["load"], 8)
	assert_eq(initial["capacity"], 6)
	assert_true(bool(initial["overloaded"]))
	assert_false(bool(initial["warning"]), "before the first host tick do not invent a timer")
	for _i: int in 7:
		_session.tick_once()
	var mid: Dictionary = _fx.apply(_session.host_state())
	assert_eq(mid["trip_ticks"], 7)
	assert_eq(mid["trip_total"], 15)
	assert_true(bool(mid["warning"]))
	assert_eq(mid["trip_percent"], 46)
	assert_false(bool(mid["tripped"]))
	for _i: int in 7:
		_session.tick_once()
	var before_trip: Dictionary = _fx.apply(_session.host_state())
	assert_eq(before_trip["trip_ticks"], 14)
	assert_true(bool(before_trip["warning"]))
	assert_false(bool(before_trip["tripped"]))
	_session.tick_once()
	var after: Dictionary = _fx.apply(_session.host_state())
	assert_true(bool(after["tripped"]))
	assert_false(bool(after["warning"]), "protection event replaces the warning")
	assert_false(bool((_session.host_state()["grid"]["nodes"]["TEMP"] as Dictionary).get("energized", false)))


func test_DS11_trip_display_does_not_mutate_authoritative_grid_or_save_causes() -> void:
	_start_pump_only()
	var before: String = Grid.serialize(_session.host_state())
	var causes: String = Grid.serialize(_session.grid.causes())
	for _i: int in 6:
		_fx.apply(_session.host_state())
		_fx.advance(0.4)
	assert_eq(Grid.serialize(_session.host_state()), before)
	assert_eq(Grid.serialize(_session.grid.causes()), causes,
		"UI wall-clock advancement cannot tick or change any host causes")


func test_DS11_host_refused_dual_supply_highlights_actual_tie_only() -> void:
	_prepare_generator()
	_fx.apply(_session.host_state())
	var rejected: Dictionary = {"ok": false, "code": "GRID_REFUSED", "grid_code": "DUAL_SUPPLY",
		"ids": ["PUB", "E_TEMP_PUB", "E_JE_PUB", "GEN_PORTABLE"]}
	_fx.on_host_refusal(rejected)
	assert_true(_fx.refusal_active())
	var label: Label3D = _world.get_node("DS11TemporarySupply/GeneratorPadMarkings/RoutePlate") as Label3D
	assert_eq(label.text, UiText.t("world.generator.dual_refused"))
	assert_false(_fx.cable_visible("E_TEMP_PUB"), "refusal does not invent an accepted route")
	_fx.advance(5.0)
	assert_false(_fx.refusal_active())
	assert_eq(label.text, UiText.t("world.generator.route_plate"))
	_fx.on_host_refusal({"ok": false, "code": "GRID_REFUSED", "grid_code": "CYCLE",
		"ids": ["E_TEMP_PUB", "E_JE_PUB"]})
	assert_false(_fx.refusal_active(), "only the host-proven conflict receives the dual-supply highlight")


func test_DS11_real_host_refuses_pub_second_route_without_switching_cables() -> void:
	# Preparation simulates an already-repaired east trunk (the repair sequence
	# is covered by G04). The actual SessionHost still adjudicates the tie.
	_start_pump_only()
	var opened: Dictionary = _session.grid.apply({
		"op": "set", "id": "E_GRID_JE", "field": "healthy", "value": true})
	assert_true(bool(opened.get("ok", false)))
	var source: Dictionary = _session.host_state()
	assert_true(bool((source["grid"]["nodes"]["PUB"] as Dictionary)["supplied"]))
	var refused: Dictionary = _command("connect", {"route": "E_TEMP_PUB"})
	assert_false(bool(refused.get("ok", true)), "grid and generator may not both feed the pub")
	assert_eq(refused.get("code"), "GRID_REFUSED")
	assert_eq(refused.get("grid_code"), "DUAL_SUPPLY")
	assert_false(bool((_session.host_state()["grid"]["edges"]["E_TEMP_PUB"] as Dictionary)["enabled"]))
	_fx.apply(_session.host_state())
	_fx.on_host_refusal(refused)
	assert_true(_fx.refusal_active())
	assert_false(_fx.cable_visible("E_TEMP_PUB"))
	assert_true(_fx.cable_visible("E_TEMP_PUMP"))


func test_DS11_hud_exposes_host_numbers_without_color_or_audio_dependency() -> void:
	_start_pump_only()
	var overlay: FieldHud = FieldHud.new()
	_holder.add_child(overlay)
	overlay.apply(_session.hud_view(1, "", "meter"))
	var view: Dictionary = _fx.apply(_session.host_state())
	overlay.set_generator_tradeoff(view)
	var label: Label = overlay.find_child("GeneratorLoadStatus", true, false) as Label
	assert_true(label != null)
	assert_true(label.text.contains("4 / 6 PU"))
	var bar: ProgressBar = overlay.find_child("GeneratorTripProgress", true, false) as ProgressBar
	assert_true(bar != null)
	assert_eq(int(bar.value), 0)
	assert_true(bar.mouse_filter == Control.MOUSE_FILTER_IGNORE)
	_command("connect", {"route": "E_TEMP_PUB"})
	for _i: int in 4:
		_session.tick_once()
	overlay.set_generator_tradeoff(_fx.apply(_session.host_state()))
	assert_true(label.text.contains("8 / 6 PU"))
	assert_true(label.text.contains(UiText.t("world.generator.warning")))
	assert_true(int(bar.value) > 0, "accessible HUD contains the exact host-counter fraction")
	assert_true((overlay.find_child("GeneratorTripLabel", true, false) as Label).text.contains("4 / 15"))
