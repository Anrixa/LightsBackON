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


func test_QA105_sparse_coordinate_overflow_is_rejected_before_layout() -> void:
	var case: Dictionary = _opened()
	var original: Dictionary = case["snapshot"]
	for axis: String in ["row", "col"]:
		for value: int in [64, 1000000000]:
			var invalid: Dictionary = original.duplicate(true)
			invalid["nodes"]["TEMP"][axis] = value
			_rejects(case, invalid)
	var valid: Dictionary = original.duplicate(true)
	(case["tablet"] as PanelContainer).show_data(valid, case["objectives"])
	assert_eq((case["tablet"] as PanelContainer).get("_view"), valid,
		"bounded authored coordinates still produce an accessible map")
	_finish(case)


func test_QA106_caller_mutation_cannot_bypass_validated_snapshot() -> void:
	var case: Dictionary = _opened()
	var tablet: PanelContainer = case["tablet"]
	var incoming: Dictionary = (case["snapshot"] as Dictionary).duplicate(true)
	var incoming_objectives: Array = (case["objectives"] as Array).duplicate(true)
	var context: Array[String] = ["district.alder_street", "contract.c01"]
	tablet.show_data(incoming, incoming_objectives, context)
	Fixture.settle(tablet)
	assert_eq(str(tablet.selected), "TEMP", "valid live refresh retains selected node")
	assert_true((tablet.get("_pending_tablet_requests") as Dictionary).has(int(case["pending"]["seq"])))

	# Mutate every caller-owned input *after* the tablet accepted it. None of
	# these unsafe changes passed validation and none may enter the live view.
	(incoming["order"] as Array).clear()
	incoming["nodes"]["TEMP"]["name_key"] = "node.c01.unlocalized"
	incoming["edges"][0]["to"] = "GHOST"
	(incoming_objectives[0] as Dictionary)["text_key"] = "objective.unknown"
	context[0] = "tablet.title"
	assert_eq(tablet.get("_view"), case["snapshot"], "caller cannot rewrite validated map records")
	assert_eq(tablet.get("_objectives"), case["objectives"], "objective list owns its copy")
	var accepted_context: Array[String] = ["district.alder_street", "contract.c01"]
	assert_eq(tablet.get("_context"), accepted_context, "header context owns its copy")
	assert_true((tablet.map.nodes as Dictionary).has("TEMP"), "live controls retain their validated IDs")
	assert_true((tablet.get("_pending_tablet_requests") as Dictionary).has(int(case["pending"]["seq"])),
		"in-flight Ping is not invalidated by a caller-side mutation")
	_finish(case)


func test_QA107_header_context_must_use_district_and_contract_keys() -> void:
	var case: Dictionary = _opened()
	var tablet: PanelContainer = case["tablet"]
	var original: Dictionary = case["snapshot"]
	var expected: Array[String] = ["district.alder_street", "contract.c01"]
	var wrong_contexts: Array = [
		["contract.c01", "district.alder_street"],
		["tablet.title", "contract.c01"],
		["district.alder_street", "tablet.title"],
		["district.alder_street", "objective.c01.extract"]
	]
	for wrong: Array in wrong_contexts:
		var typed: Array[String] = []
		typed.assign(wrong)
		tablet.show_data(original.duplicate(true), (case["objectives"] as Array).duplicate(true), typed)
		assert_eq(tablet.get("_view"), original, "a wrong-category header must not replace the map")
		assert_eq(tablet.get("_context"), expected, "header must retain the prior district and contract")
		assert_eq(str(tablet.selected), "TEMP")
		assert_eq((Engine.get_main_loop() as SceneTree).root.gui_get_focus_owner(), case["focus"])
		assert_true((tablet.get("_pending_tablet_requests") as Dictionary).has(int(case["pending"]["seq"])))

	var valid: Dictionary = original.duplicate(true)
	tablet.show_data(valid, (case["objectives"] as Array).duplicate(true), expected)
	assert_eq(tablet.get("_view"), valid, "a correctly typed localized header remains accepted")
	assert_eq(tablet.get("_context"), expected)
	_finish(case)


## QA108-QA127: deliberately corrupted but previously well-typed read-only
## snapshots. Each test preserves focus, selection and a pending authenticated
## host Ping when the replacement is rejected. No authority is moved into UI.

func _rejects_objectives(case: Dictionary, invalid: Array) -> void:
	var tablet: PanelContainer = case["tablet"]
	tablet.show_data((case["snapshot"] as Dictionary).duplicate(true), invalid)
	assert_eq(tablet.get("_view"), case["snapshot"], "malformed objectives cannot replace the current map")
	assert_eq(tablet.get("_objectives"), case["objectives"], "last valid objective list is retained")
	assert_eq(str(tablet.selected), "TEMP")
	assert_eq((Engine.get_main_loop() as SceneTree).root.gui_get_focus_owner(), case["focus"])
	assert_true((tablet.get("_pending_tablet_requests") as Dictionary).has(int(case["pending"]["seq"])))


func _replace_node_id(view: Dictionary, old_id: String, new_id: String) -> void:
	var node: Dictionary = view["nodes"][old_id]
	(view["nodes"] as Dictionary).erase(old_id)
	node["id"] = new_id
	view["nodes"][new_id] = node
	var index: int = (view["order"] as Array).find(old_id)
	(view["order"] as Array)[index] = new_id


func test_QA108_empty_node_id_refused() -> void:
	var case: Dictionary = _opened()
	var invalid: Dictionary = (case["snapshot"] as Dictionary).duplicate(true)
	_replace_node_id(invalid, "TEMP", "")
	_rejects(case, invalid)
	_finish(case)


func test_QA109_node_path_separator_refused() -> void:
	var case: Dictionary = _opened()
	var invalid: Dictionary = (case["snapshot"] as Dictionary).duplicate(true)
	_replace_node_id(invalid, "TEMP", "INJECTED/Node")
	_rejects(case, invalid)
	_finish(case)


func test_QA110_node_name_must_be_localized_node_key() -> void:
	var case: Dictionary = _opened()
	var invalid: Dictionary = (case["snapshot"] as Dictionary).duplicate(true)
	invalid["nodes"]["TEMP"]["name_key"] = "tablet.title"
	_rejects(case, invalid)
	_finish(case)


func test_QA111_access_key_must_describe_access() -> void:
	var case: Dictionary = _opened()
	var invalid: Dictionary = (case["snapshot"] as Dictionary).duplicate(true)
	invalid["nodes"]["TEMP"]["access_key"] = "tablet.title"
	_rejects(case, invalid)
	_finish(case)


func test_QA112_objective_chip_cannot_masquerade_as_power_status() -> void:
	var case: Dictionary = _opened()
	var invalid: Dictionary = (case["snapshot"] as Dictionary).duplicate(true)
	invalid["nodes"]["TEMP"]["status_group"] = "objectives"
	invalid["nodes"]["TEMP"]["status_state"] = "done"
	_rejects(case, invalid)
	_finish(case)


func test_QA113_measured_flag_must_be_boolean() -> void:
	var case: Dictionary = _opened()
	var invalid: Dictionary = (case["snapshot"] as Dictionary).duplicate(true)
	invalid["nodes"]["TEMP"]["measured"] = "false"
	_rejects(case, invalid)
	_finish(case)


func test_QA114_reinspect_flag_must_be_boolean() -> void:
	var case: Dictionary = _opened()
	var invalid: Dictionary = (case["snapshot"] as Dictionary).duplicate(true)
	invalid["nodes"]["TEMP"]["needs_reinspect"] = 1
	_rejects(case, invalid)
	_finish(case)


func test_QA115_source_detail_must_be_text() -> void:
	var case: Dictionary = _opened()
	var invalid: Dictionary = (case["snapshot"] as Dictionary).duplicate(true)
	invalid["nodes"]["TEMP"]["source_text"] = {"forged": "line"}
	_rejects(case, invalid)
	_finish(case)


func test_QA116_worker_detail_must_be_text() -> void:
	var case: Dictionary = _opened()
	var invalid: Dictionary = (case["snapshot"] as Dictionary).duplicate(true)
	invalid["nodes"]["TEMP"]["worker_text"] = 9000
	_rejects(case, invalid)
	_finish(case)


func test_QA117_source_detail_length_is_bounded() -> void:
	var case: Dictionary = _opened()
	var invalid: Dictionary = (case["snapshot"] as Dictionary).duplicate(true)
	invalid["nodes"]["TEMP"]["source_text"] = "x".repeat(2049)
	_rejects(case, invalid)
	_finish(case)


func test_QA118_worker_detail_length_is_bounded() -> void:
	var case: Dictionary = _opened()
	var invalid: Dictionary = (case["snapshot"] as Dictionary).duplicate(true)
	invalid["nodes"]["TEMP"]["worker_text"] = "x".repeat(2049)
	_rejects(case, invalid)
	_finish(case)


func test_QA119_node_evidence_row_count_is_bounded() -> void:
	var case: Dictionary = _opened()
	var invalid: Dictionary = (case["snapshot"] as Dictionary).duplicate(true)
	var oversized: Array[String] = []
	for i: int in 33:
		oversized.append("reading_%d" % i)
	invalid["nodes"]["TEMP"]["lines"] = oversized
	_rejects(case, invalid)
	_finish(case)


func test_QA120_node_evidence_line_length_is_bounded() -> void:
	var case: Dictionary = _opened()
	var invalid: Dictionary = (case["snapshot"] as Dictionary).duplicate(true)
	invalid["nodes"]["TEMP"]["lines"] = ["x".repeat(2049)]
	_rejects(case, invalid)
	_finish(case)


func test_QA121_node_findings_count_is_bounded() -> void:
	var case: Dictionary = _opened()
	var invalid: Dictionary = (case["snapshot"] as Dictionary).duplicate(true)
	var findings: Array[Dictionary] = []
	for i: int in 17:
		findings.append({"code": "FEED_OPEN"})
	invalid["nodes"]["TEMP"]["findings"] = findings
	_rejects(case, invalid)
	_finish(case)


func test_QA122_edge_identifier_cannot_contain_path_syntax() -> void:
	var case: Dictionary = _opened()
	var invalid: Dictionary = (case["snapshot"] as Dictionary).duplicate(true)
	invalid["edges"][0]["id"] = "EDGE/FOREIGN"
	_rejects(case, invalid)
	_finish(case)


func test_QA123_edge_fanout_limit_prevents_unbounded_map_build() -> void:
	var case: Dictionary = _opened()
	var invalid: Dictionary = (case["snapshot"] as Dictionary).duplicate(true)
	for i: int in 513:
		(invalid["edges"] as Array).append({"id": "QA_EDGE_%d" % i, "from": "GRID", "to": "TEMP", "style": "unknown"})
	_rejects(case, invalid)
	_finish(case)


func test_QA124_node_limit_prevents_unbounded_control_trees() -> void:
	var case: Dictionary = _opened()
	var invalid: Dictionary = (case["snapshot"] as Dictionary).duplicate(true)
	for i: int in 129:
		var nid: String = "QA_NODE_%d" % i
		var node: Dictionary = (invalid["nodes"]["TEMP"] as Dictionary).duplicate(true)
		node["id"] = nid
		node["col"] = i % 64
		node["row"] = 10 + i / 64
		invalid["nodes"][nid] = node
		(invalid["order"] as Array).append(nid)
	_rejects(case, invalid)
	_finish(case)


func test_QA125_missing_or_malformed_objective_id_refused() -> void:
	var case: Dictionary = _opened()
	for malformed: Variant in [null, 123, "BAD/ID", ""]:
		var invalid: Array = (case["objectives"] as Array).duplicate(true)
		if malformed == null:
			(invalid[0] as Dictionary).erase("id")
		else:
			invalid[0]["id"] = malformed
		_rejects_objectives(case, invalid)
	_finish(case)


func test_QA126_duplicate_objective_id_refused() -> void:
	var case: Dictionary = _opened()
	var invalid: Array = (case["objectives"] as Array).duplicate(true)
	invalid.append((invalid[0] as Dictionary).duplicate(true))
	_rejects_objectives(case, invalid)
	_finish(case)


func test_QA127_objective_namespace_and_count_boundaries() -> void:
	var case: Dictionary = _opened()
	var wrong_label: Array = (case["objectives"] as Array).duplicate(true)
	wrong_label[0]["text_key"] = "tablet.title"
	_rejects_objectives(case, wrong_label)
	var too_many: Array = (case["objectives"] as Array).duplicate(true)
	for i: int in 385:
		var objective: Dictionary = (too_many[0] as Dictionary).duplicate(true)
		objective["id"] = "QA_OBJECTIVE_%d" % i
		too_many.append(objective)
	_rejects_objectives(case, too_many)
	# Legitimate host-built C01 snapshots still rebuild with all controls.
	var valid: Dictionary = (case["snapshot"] as Dictionary).duplicate(true)
	var tablet: PanelContainer = case["tablet"]
	tablet.show_data(valid, (case["objectives"] as Array).duplicate(true))
	assert_eq(tablet.get("_view"), valid, "the production snapshot remains accepted")
	assert_true((tablet.map.nodes as Dictionary).has("TEMP"), "active tablet nodes remain navigable")
	_finish(case)


## QA128-QA132: the snapshot is well-typed but semantically misleading,
## or a real refusal arrives with a foreign (otherwise localized) key.

func test_QA128_panel_target_identifiers_cannot_escape_inspect_namespace() -> void:
	var case: Dictionary = _opened()
	for malformed: String in ["PANEL/FOREIGN", "PANEL WITH SPACE", "P".repeat(129)]:
		var invalid: Dictionary = (case["snapshot"] as Dictionary).duplicate(true)
		invalid["nodes"]["TEMP"]["panel"] = malformed
		_rejects(case, invalid)
	var valid: Dictionary = (case["snapshot"] as Dictionary).duplicate(true)
	(case["tablet"] as PanelContainer).show_data(valid, case["objectives"])
	assert_eq((case["tablet"] as PanelContainer).get("_view"), valid)
	_finish(case)


func test_QA129_status_chip_must_match_power_node_kind() -> void:
	var case: Dictionary = _opened()
	var consumer: Dictionary = (case["snapshot"] as Dictionary).duplicate(true)
	consumer["nodes"]["PUMP"]["status_group"] = "findings"
	consumer["nodes"]["PUMP"]["status_state"] = "NO_SOURCE"
	_rejects(case, consumer)
	var source: Dictionary = (case["snapshot"] as Dictionary).duplicate(true)
	source["nodes"]["GEN"]["status_group"] = "other"
	source["nodes"]["GEN"]["status_state"] = "unknown"
	_rejects(case, source)
	var dark_source: Dictionary = (case["snapshot"] as Dictionary).duplicate(true)
	dark_source["nodes"]["GRID"]["status_group"] = "supply"
	dark_source["nodes"]["GRID"]["status_state"] = "dark"
	_rejects(case, dark_source)
	_finish(case)


func test_QA130_uninspected_junction_must_not_claim_supply_or_fault() -> void:
	var case: Dictionary = _opened()
	assert_false(bool(case["snapshot"]["nodes"]["TEMP"]["measured"]))
	var invented_supply: Dictionary = (case["snapshot"] as Dictionary).duplicate(true)
	invented_supply["nodes"]["TEMP"]["status_group"] = "supply"
	invented_supply["nodes"]["TEMP"]["status_state"] = "restored"
	_rejects(case, invented_supply)
	var invented_fault: Dictionary = (case["snapshot"] as Dictionary).duplicate(true)
	invented_fault["nodes"]["TEMP"]["status_group"] = "findings"
	invented_fault["nodes"]["TEMP"]["status_state"] = "FEED_OPEN"
	invented_fault["nodes"]["TEMP"]["findings"] = [{"code": "FEED_OPEN"}]
	_rejects(case, invented_fault)
	_finish(case)


func test_QA131_measured_junction_primary_finding_must_match_evidence() -> void:
	var case: Dictionary = _opened()
	assert_true(bool(case["snapshot"]["nodes"]["JE"]["measured"]))
	var hidden_findings: Dictionary = (case["snapshot"] as Dictionary).duplicate(true)
	hidden_findings["nodes"]["JE"]["status_group"] = "supply"
	hidden_findings["nodes"]["JE"]["status_state"] = "dark"
	hidden_findings["nodes"]["JE"]["findings"] = [{"code": "FEED_OPEN"}]
	_rejects(case, hidden_findings)
	var invented_banner: Dictionary = (case["snapshot"] as Dictionary).duplicate(true)
	invented_banner["nodes"]["JE"]["status_group"] = "findings"
	invented_banner["nodes"]["JE"]["status_state"] = "FEED_OPEN"
	invented_banner["nodes"]["JE"]["findings"] = []
	_rejects(case, invented_banner)
	_finish(case)


func test_QA132_refusal_uses_only_known_host_reason_namespace() -> void:
	var case: Dictionary = _opened()
	var tablet: PanelContainer = case["tablet"]
	tablet.on_reply(case["pending"], {"ok": false, "key": "tablet.title"})
	var outcome: String = str(tablet.get("_status_text"))
	assert_true(outcome.contains(UiText.t("network.refused.generic")),
		"a known but unrelated UI translation cannot become a host refusal")
	assert_false(outcome.contains(UiText.t("tablet.title")))
	tablet.close()
	var known: Dictionary = _opened()
	var known_tablet: PanelContainer = known["tablet"]
	known_tablet.on_reply(known["pending"], {"ok": false, "key": "network.refused.not_in_range"})
	assert_true(str(known_tablet.get("_status_text")).contains(UiText.t("network.refused.not_in_range")),
		"valid host-command refusal remains specific")
	known_tablet.close()

## QA133-QA137: node/edge semantic invariants needed for truthful C01
## controller traversal and inspection. Host-built views remain valid.

func test_QA133_directed_edges_never_start_at_consumers_or_end_at_sources() -> void:
	var case: Dictionary = _opened()
	var original: Dictionary = case["snapshot"]
	var wrong_feeder: Dictionary = original.duplicate(true)
	wrong_feeder["edges"][0]["from"] = "PUMP"
	_rejects(case, wrong_feeder)
	var wrong_source: Dictionary = original.duplicate(true)
	wrong_source["edges"][0]["to"] = "GEN"
	_rejects(case, wrong_source)
	var valid: Dictionary = original.duplicate(true)
	(case["tablet"] as PanelContainer).show_data(valid, case["objectives"])
	assert_eq((case["tablet"] as PanelContainer).get("_view"), valid)
	_finish(case)


func test_QA134_non_meter_nodes_cannot_invent_diagnostic_findings() -> void:
	var case: Dictionary = _opened()
	for nid: String in ["GRID", "PUMP"]:
		var invalid: Dictionary = (case["snapshot"] as Dictionary).duplicate(true)
		invalid["nodes"][nid]["findings"] = [{"code": "FEED_OPEN"}]
		_rejects(case, invalid)
	_finish(case)


func test_QA135_uninspected_junction_cannot_claim_numeric_evidence() -> void:
	var case: Dictionary = _opened()
	assert_false(bool(case["snapshot"]["nodes"]["TEMP"]["measured"]))
	for lines: Array in [["Load: 999 PU"], [UiText.t("tablet.unknown_measure"), "Load: 999 PU"], []]:
		var invalid: Dictionary = (case["snapshot"] as Dictionary).duplicate(true)
		invalid["nodes"]["TEMP"]["lines"] = lines
		_rejects(case, invalid)
	_finish(case)


func test_QA136_measured_junction_requires_inspectable_panel_id() -> void:
	var case: Dictionary = _opened()
	assert_true(bool(case["snapshot"]["nodes"]["JE"]["measured"]))
	var invalid: Dictionary = (case["snapshot"] as Dictionary).duplicate(true)
	invalid["nodes"]["JE"]["panel"] = ""
	_rejects(case, invalid)
	_finish(case)


func test_QA137_tablet_focus_catalog_preserves_spatial_order() -> void:
	var case: Dictionary = _opened()
	var original: Dictionary = case["snapshot"]
	for swap_pair: Array in [[0, 1], [1, 2]]:
		var invalid: Dictionary = original.duplicate(true)
		var order: Array = invalid["order"] as Array
		var first: Variant = order[swap_pair[0]]
		order[swap_pair[0]] = order[swap_pair[1]]
		order[swap_pair[1]] = first
		_rejects(case, invalid)
	var valid: Dictionary = original.duplicate(true)
	(case["tablet"] as PanelContainer).show_data(valid, case["objectives"])
	assert_eq((case["tablet"] as PanelContainer).get("_view"), valid)
	_finish(case)

## PERF21: authoritatively identical 10 Hz snapshots should not rebuild the
## entire network map or invalidate its focus/pending inspection response.
func test_PERF21_unchanged_host_snapshot_keeps_widget_identity_and_focus() -> void:
	var case: Dictionary = _opened()
	var tablet: PanelContainer = case["tablet"]
	var original_map: Container = tablet.map
	var original_detail: ScrollContainer = tablet.detail_scroll
	for _i: int in 12:
		tablet.show_data((case["snapshot"] as Dictionary).duplicate(true),
			(case["objectives"] as Array).duplicate(true))
		assert_eq(tablet.map, original_map,
			"repeated equal host state must not churn the live network map")
		assert_eq(tablet.detail_scroll, original_detail)
	assert_eq((Engine.get_main_loop() as SceneTree).root.gui_get_focus_owner(), case["focus"])
	assert_true((tablet.get("_pending_tablet_requests") as Dictionary).has(int(case["pending"]["seq"])))
	_finish(case)


func test_PERF21_changed_objective_renders_and_retains_pending_request() -> void:
	var case: Dictionary = _opened()
	var tablet: PanelContainer = case["tablet"]
	var previous_map: Container = tablet.map
	var changed: Array = (case["objectives"] as Array).duplicate(true)
	changed[0]["status"] = "active" if changed[0]["status"] == "done" else "done"
	tablet.show_data((case["snapshot"] as Dictionary).duplicate(true), changed)
	assert_true(tablet.map != previous_map,
		"a real host objective transition still rebuilds the visible tablet")
	assert_eq(tablet.get("_objectives"), changed)
	assert_true((tablet.get("_pending_tablet_requests") as Dictionary).has(int(case["pending"]["seq"])),
		"visual updates cannot drop the host acknowledgment correlation")
	_finish(case)


func test_PERF21_pseudolocale_change_rejects_stale_text_then_repaints() -> void:
	var case: Dictionary = _opened()
	var tablet: PanelContainer = case["tablet"]
	var previous_map: Container = tablet.map
	UiText.set_locale(UiText.LOCALE_PSEUDO)
	# Measured/unknown lines are already localized by the actual presenter.
	# The old English-only payload is no longer valid under the new locale;
	# never bypass the evidence validator just to force a visual rebuild.
	tablet.show_data((case["snapshot"] as Dictionary).duplicate(true),
		(case["objectives"] as Array).duplicate(true))
	assert_eq(tablet.map, previous_map,
		"stale differently localized evidence stays rejected without losing focus")
	var refreshed: Dictionary = Fixture.mid_shift()
	assert_eq(refreshed["errors"], [] as Array)
	assert_eq(refreshed["failures"], [] as Array[String])
	tablet.show_data(Fixture.tablet_view(refreshed), refreshed["mission"].objectives())
	assert_true(tablet.map != previous_map,
		"freshly localized presenter data rebuilds even with unchanged gameplay")
	assert_eq(str(tablet.get("_rendered_locale")), UiText.LOCALE_PSEUDO)
	UiText.set_locale(UiText.LOCALE_EN)
	tablet.show_data((case["snapshot"] as Dictionary).duplicate(true),
		(case["objectives"] as Array).duplicate(true))
	assert_eq(str(tablet.get("_rendered_locale")), UiText.LOCALE_EN)
	_finish(case)
