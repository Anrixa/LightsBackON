extends "res://tests/test_case.gd"
## Read-only S07 snapshot boundary regression tests (QA102 onward).
## These exercise a real opened tablet at 720p / 150%, not just private validators.
## Every malformed refresh must be refused without changing visible focus or
## the correlated host acknowledgment still pending in this tablet visit.

const Fixture := preload("res://tests/support/ui_fixture.gd")
const Runner := preload("res://tests/support/solution_runner.gd")
const NetworkTablet := preload("res://scripts/ui/network_tablet.gd")
const IntentOutbox := preload("res://scripts/ui/intent_outbox.gd")
const UiText := preload("res://scripts/ui/ui_text.gd")

var _owned: Array[Node] = []


func before_each() -> void:
	UiText.set_locale(UiText.LOCALE_EN)


func after_each() -> void:
	UiText.set_locale(UiText.LOCALE_EN)
	for owner: Node in _owned:
		if is_instance_valid(owner):
			owner.get_parent().remove_child(owner)
			owner.free()
	_owned.clear()


## Build the same host-driven C01 tablet as the V07 acceptance suite.
## A Ping is left pending to detect unwanted request cancellation on rejection.
func _opened() -> Dictionary:
	var ctx: Dictionary = Fixture.mid_shift()
	assert_eq(ctx["errors"], [] as Array)
	assert_eq(ctx["failures"], [] as Array[String])
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
	outbox.sent.connect(func(env: Dictionary) -> void: sent.append(env))
	tablet.setup(outbox)
	tablet.show_data(Fixture.tablet_view(ctx), ctx["mission"].objectives())
	Fixture.settle(tablet)
	tablet.open()
	tablet.select("TEMP")
	(tablet.map.nodes["TEMP"] as Control).grab_focus()
	tablet.ping_selected()
	assert_eq(sent.size(), 1, "one outstanding Ping")
	return {"tablet": tablet, "snapshot": (tablet.get("_view") as Dictionary).duplicate(true),
		"objectives": (tablet.get("_objectives") as Array).duplicate(true),
		"pending": sent[0].duplicate(true),
		"focus": (Engine.get_main_loop() as SceneTree).root.gui_get_focus_owner()}


func _rejects(case: Dictionary, invalid: Dictionary) -> void:
	var tablet: PanelContainer = case["tablet"]
	tablet.show_data(invalid, case["objectives"])
	assert_eq(tablet.get("_view"), case["snapshot"], "rejected snapshot cannot replace the live map")
	assert_eq(str(tablet.selected), "TEMP", "node selection stays valid")
	assert_eq((Engine.get_main_loop() as SceneTree).root.gui_get_focus_owner(), case["focus"],
		"the prior controller focus must survive the rejected refresh")
	assert_true((tablet.get("_pending_tablet_requests") as Dictionary).has(int(case["pending"]["seq"])),
		"the authentic Ping remains correlated")


func _finish(case: Dictionary) -> void:
	var tablet: PanelContainer = case["tablet"]
	tablet.on_reply(case["pending"], {"ok": true})
	assert_true(str(tablet.get("_status_text")) != "", "authentic acknowledgment remains usable")
	tablet.close()


func test_QA102_invalid_node_kind_does_not_replace_active_tablet() -> void:
	var case: Dictionary = _opened()
	for invalid_kind: String in ["not_a_node", "edge", ""]:
		var invalid: Dictionary = (case["snapshot"] as Dictionary).duplicate(true)
		invalid["nodes"]["TEMP"]["kind"] = invalid_kind
		_rejects(case, invalid)
	var valid: Dictionary = (case["snapshot"] as Dictionary).duplicate(true)
	(case["tablet"] as PanelContainer).show_data(valid, case["objectives"])
	assert_eq((case["tablet"] as PanelContainer).get("_view"), valid,
		"known source, junction and consumer kinds still render")
	_finish(case)


func test_QA103_duplicate_tablet_cells_do_not_obscure_navigation() -> void:
	var case: Dictionary = _opened()
	var original: Dictionary = case["snapshot"]
	for other: String in ["GRID", "JW", "JE"]:
		var invalid: Dictionary = original.duplicate(true)
		invalid["nodes"]["TEMP"]["col"] = int(original["nodes"][other]["col"])
		invalid["nodes"]["TEMP"]["row"] = int(original["nodes"][other]["row"])
		_rejects(case, invalid)
	var valid: Dictionary = original.duplicate(true)
	(case["tablet"] as PanelContainer).show_data(valid, case["objectives"])
	assert_eq((case["tablet"] as PanelContainer).get("_view"), valid,
		"non-overlapping grid coordinates remain usable")
	_finish(case)


func test_QA104_self_loop_edge_cannot_replace_directed_tablet_map() -> void:
	var case: Dictionary = _opened()
	var original: Dictionary = case["snapshot"]
	var existing_loop: Dictionary = original.duplicate(true)
	var first: Dictionary = existing_loop["edges"][0]
	first["to"] = first["from"]
	_rejects(case, existing_loop)
	var new_loop: Dictionary = original.duplicate(true)
	(new_loop["edges"] as Array).append({"id": "SELF_LOOP", "from": "TEMP",
		"to": "TEMP", "style": "unknown"})
	_rejects(case, new_loop)
	var valid: Dictionary = original.duplicate(true)
	(case["tablet"] as PanelContainer).show_data(valid, case["objectives"])
	assert_eq((case["tablet"] as PanelContainer).get("_view"), valid,
		"valid directed edges remain accepted")
	_finish(case)
