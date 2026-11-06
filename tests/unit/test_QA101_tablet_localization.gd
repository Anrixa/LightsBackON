extends "res://tests/test_case.gd"
## QA101: malformed localized text references must not replace an active S07
## read-only tablet, disclose internal keys, or invalidate a pending Ping.

const Fixture := preload("res://tests/support/ui_fixture.gd")
const Runner := preload("res://tests/support/solution_runner.gd")
const NetworkTablet := preload("res://scripts/ui/network_tablet.gd")
const IntentOutbox := preload("res://scripts/ui/intent_outbox.gd")
const UiText := preload("res://scripts/ui/ui_text.gd")

var _owned: Array[Node] = []


func after_each() -> void:
	UiText.set_locale(UiText.LOCALE_EN)
	for node: Node in _owned:
		if is_instance_valid(node):
			node.get_parent().remove_child(node)
			node.free()
	_owned.clear()


func test_QA101_unknown_tablet_localization_does_not_break_visit() -> void:
	UiText.set_locale(UiText.LOCALE_EN)
	var ctx: Dictionary = Fixture.mid_shift()
	assert_eq(ctx["errors"], [] as Array, "C01 host fixture has no errors")
	assert_eq(ctx["failures"], [] as Array[String], "C01 setup is a valid partial solution")

	var frame: Control = Control.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(frame)
	_owned.append(frame)
	frame.size = Vector2(1280, 720)
	var tablet: PanelContainer = NetworkTablet.new()
	frame.add_child(tablet)
	tablet.size = frame.size
	tablet.ui_scale_percent = 150

	var sent: Array[Dictionary] = []
	var outbox: RefCounted = IntentOutbox.new(Runner.SESSION, func(_bytes: PackedByteArray) -> Dictionary:
		return {})
	outbox.sent.connect(func(envelope: Dictionary) -> void:
		sent.append(envelope))
	tablet.setup(outbox)
	var source: Dictionary = Fixture.tablet_view(ctx)
	var objectives: Array = ctx["mission"].objectives()
	tablet.show_data(source, objectives)
	Fixture.settle(tablet)
	tablet.open()
	tablet.select("TEMP")
	(tablet.map.nodes["TEMP"] as Control).grab_focus()
	tablet.ping_selected()
	assert_eq(sent.size(), 1, "Ping is sent before testing a delayed snapshot")
	var pending: Dictionary = sent[0].duplicate(true)
	var original_view: Dictionary = tablet.get("_view")
	var original_objectives: Array = tablet.get("_objectives")
	var focus_before: Control = (Engine.get_main_loop() as SceneTree).root.gui_get_focus_owner()

	var missing_name: Dictionary = original_view.duplicate(true)
	missing_name["nodes"]["TEMP"]["name_key"] = "node.c01.unknown"
	var empty_name: Dictionary = original_view.duplicate(true)
	empty_name["nodes"]["TEMP"]["name_key"] = ""
	var missing_access: Dictionary = original_view.duplicate(true)
	missing_access["nodes"]["TEMP"]["access_key"] = "access.unknown"
	var wrong_access_type: Dictionary = original_view.duplicate(true)
	wrong_access_type["nodes"]["TEMP"]["access_key"] = 99
	for invalid: Dictionary in [missing_name, empty_name, missing_access, wrong_access_type]:
		tablet.show_data(invalid, original_objectives.duplicate(true))
		assert_eq(tablet.get("_view"), original_view,
			"unknown node/access label cannot replace the valid read-only snapshot")
		assert_eq(str(tablet.selected), "TEMP")
		assert_eq((Engine.get_main_loop() as SceneTree).root.gui_get_focus_owner(), focus_before)
		assert_true((tablet.get("_pending_tablet_requests") as Dictionary).has(int(pending["seq"])),
			"a rejected refresh does not consume an outstanding Ping")

	var invalid_objectives: Array = original_objectives.duplicate(true)
	assert_true(not invalid_objectives.is_empty(), "fixture must contain a real objective")
	(invalid_objectives[0] as Dictionary)["text_key"] = "objective.c01.unknown"
	tablet.show_data(original_view.duplicate(true), invalid_objectives)
	assert_eq(tablet.get("_objectives"), original_objectives,
		"missing objective translation cannot enter the Objectives tab")
	assert_eq(tablet.get("_view"), original_view)
	assert_eq((Engine.get_main_loop() as SceneTree).root.gui_get_focus_owner(), focus_before)
	assert_true((tablet.get("_pending_tablet_requests") as Dictionary).has(int(pending["seq"])))

	tablet.on_reply(pending, {"ok": true})
	assert_true(str(tablet.get("_status_text")) != "",
		"an authentic delayed acknowledgment still works after rejected refreshes")

	# A valid optional access restriction still renders after the new gate.
	var valid: Dictionary = original_view.duplicate(true)
	valid["nodes"]["TEMP"]["access_key"] = "access.pump_house_drained"
	assert_true(UiText.has("access.pump_house_drained"))
	tablet.show_data(valid, original_objectives.duplicate(true))
	assert_eq(tablet.get("_view"), valid, "registered localization keys remain valid")
	assert_eq(str(tablet.selected), "TEMP")
	tablet.close()
