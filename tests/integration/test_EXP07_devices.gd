extends "res://tests/test_case.gd"
## EXP07 authoritative regression. Coordinates are TEST-ONLY server-owned stations.
## No physical traversal, actual controller, renderer or release qualification.
const Atlas := preload("res://scripts/world/dispatch_atlas.gd")
const Graph := preload("res://scripts/gameplay/expedition_device_graph.gd")
const Encounters := preload("res://scripts/gameplay/expedition_bespoke_mechanics.gd")
const Runtime := preload("res://scripts/gameplay/expedition_host_session.gd")

var _position_on_host: Vector3 = Vector3(26.0, 0.90, 26.0)
var _seq: int = 0


func before_each() -> void:
	_position_on_host = Vector3(26.0, 0.90, 26.0)
	_seq = 0


func _position(_player_id: String) -> Vector3:
	return _position_on_host


func _start(id: String) -> Runtime:
	var run: Runtime = Runtime.new()
	var result: Dictionary = run.start(id, Callable(self, "_position"),
		Callable(), "", false, "", true, true)
	assert_true(bool(result.get("ok", false)), "%s: %s" % [id, str(result)])
	return run


func _stand(run: Runtime, entity: String) -> void:
	var pos: Vector3 = run.definition_snapshot()["positions"][entity]
	_position_on_host = Vector3(pos.x, 0.90, pos.z)


func _wire(run: Runtime, seq: int, kind: String, entity: String,
		payload: Dictionary = {}) -> Dictionary:
	return run.receive(1, JSON.stringify({"session": run.session_id(),
		"seq": seq, "type": kind, "entity": entity,
		"payload": payload}).to_utf8_buffer())


func _command(run: Runtime, kind: String, entity: String,
		payload: Dictionary = {}) -> Dictionary:
	for tick: int in range(200):
		var safe: bool = bool(run.bespoke.preflight(kind, entity).get("ok", false))
		if kind == "operate_device" and run.devices != null and \
				bool(run.devices.device_definition(entity).get("hazard_sensitive", false)):
			safe = safe and not run.bespoke.hazard_active()
		if safe:
			break
		run.tick_host()
	_seq += 1
	var result: Dictionary = _wire(run, _seq, kind, entity, payload)
	assert_true(bool(result.get("ok", false)),
		"%s %s seq=%d %s" % [kind, entity, _seq, str(result)])
	return result


func _device(run: Runtime, node: Dictionary, action: String = "") -> Dictionary:
	var id: String = str(node["id"])
	_stand(run, id)
	return _command(run, "operate_device", id,
		{"action": str(node["action"]) if action == "" else action})


func _repair(run: Runtime) -> void:
	_stand(run, "R_WEST")
	_command(run, "request_lock", "R_WEST")
	var tools: Dictionary = {
		"open": "screwdriver", "remove": "puller", "install": "puller",
		"close": "screwdriver", "test": "meter"}
	var equipped: String = ""
	for step: String in [
			"diagnose", "isolate", "open", "remove",
			"install", "close", "test", "restore"]:
		var needed: String = str(tools.get(step, ""))
		if needed != "" and needed != equipped:
			_command(run, "equip", "", {"tool": needed})
			equipped = needed
		_command(run, "repair_step", "R_WEST", {"step": step})


func test_EXP07_all_200_graphs_are_source_bound_and_load_in_real_host() -> void:
	var atlas: Dictionary = Atlas.load_catalog()
	var encounters: Dictionary = Encounters.load_book()
	var book: Dictionary = Graph.load_book()
	var audit: Dictionary = Graph.inspect(atlas, encounters, book)
	assert_true(bool(audit.get("ok", false)), str(audit))
	assert_eq(audit.get("levels"), 200)
	assert_true(int(audit.get("operations", 0)) >= 20)
	var count: int = 0
	for level: Dictionary in atlas["levels"]:
		var run: Runtime = _start(str(level["id"]))
		assert_true(run.devices != null, str(level["id"]))
		if run.devices != null:
			var ids: Array[String] = run.devices.device_ids()
			count += ids.size()
			for id: String in ids:
				assert_true(run.definition_snapshot()["positions"].has(id),
					"physical marker and host reach for " + id)
			assert_false(run.devices.solved(), "cannot pre-solve " + str(level["id"]))
	assert_eq(count, 1100)


func test_EXP07_live_host_rejects_forgery_remote_and_duplicate_while_preserving_state() -> void:
	var run: Runtime = _start("LV_001")
	var nodes: Array = run.devices.definition_snapshot()["nodes"]
	var first: Dictionary = nodes[0]
	_stand(run, str(first["id"]))
	var wrong_peer: Dictionary = _wire(run, 1, "operate_device", str(first["id"]),
		{"action": str(first["action"])})
	# First command from a different transport peer must never acquire authority.
	var hostile: Dictionary = run.receive(999, JSON.stringify({"session": run.session_id(),
		"seq": 1, "type": "operate_device", "entity": first["id"],
		"payload": {"action": first["action"]}}).to_utf8_buffer())
	assert_false(bool(hostile.get("ok", false)))
	assert_true(bool(wrong_peer.get("ok", false)), str(wrong_peer))
	var before: String = run.host.state_hash()
	var duplicate: Dictionary = _wire(run, 1, "operate_device", str(first["id"]),
		{"action": str(first["action"])})
	assert_true(bool(duplicate.get("duplicate", false)))
	assert_eq(run.host.state_hash(), before)
	_stand(run, "ZONE_EXTRACT")
	var too_far: Dictionary = _wire(run, 2, "operate_device", str(nodes[1]["id"]),
		{"action": str(nodes[1]["action"])})
	assert_false(bool(too_far.get("ok", false)))
	assert_eq(run.host.state_hash(), before)
	_stand(run, str(nodes[1]["id"]))
	var forged_action: Dictionary = _wire(run, 3, "operate_device", str(nodes[1]["id"]),
		{"action": "grant_credits"})
	assert_false(bool(forged_action.get("ok", false)))
	assert_eq(run.host.state_hash(), before)
	var fake_level: Dictionary = _wire(run, 4, "operate_device", "DV_999_A",
		{"action": "trace"})
	assert_false(bool(fake_level.get("ok", false)))
	assert_eq(run.host.state_hash(), before)


func test_EXP07_genuine_fault_reset_and_host_evidence_requirements() -> void:
	var run: Runtime = _start("LV_001")
	var nodes: Array = run.devices.definition_snapshot()["nodes"]
	var fault: Dictionary = nodes[2]
	_stand(run, str(fault["id"]))
	var jammed: Dictionary = _command(run, "operate_device", str(fault["id"]),
		{"action": str(fault["action"])})
	assert_eq(jammed.get("device_state"), "jammed")
	assert_eq(run.devices.status_for(str(fault["id"])), "jammed")
	_seq += 1
	var early_reset: Dictionary = _wire(run, _seq, "operate_device", str(fault["id"]),
		{"action": "reset"})
	assert_false(bool(early_reset.get("ok", false)), str(early_reset))
	_device(run, nodes[0])
	_device(run, nodes[1])
	_device(run, fault, "reset")
	assert_eq(run.devices.status_for(str(fault["id"])), "idle")
	_device(run, fault)
	_stand(run, str(nodes[3]["id"]))
	_seq += 1
	var missing_east: Dictionary = _wire(run, _seq, "operate_device", str(nodes[3]["id"]),
		{"action": str(nodes[3]["action"])})
	assert_eq(missing_east.get("code"), "HOST_EVIDENCE_REQUIRED")
	_stand(run, "SW_EAST")
	_command(run, "toggle_switch", "SW_EAST", {"value": true})
	_device(run, nodes[3])
	_stand(run, str(nodes[4]["id"]))
	_seq += 1
	var missing_repair: Dictionary = _wire(run, _seq, "operate_device", str(nodes[4]["id"]),
		{"action": str(nodes[4]["action"])})
	assert_eq(missing_repair.get("code"), "HOST_EVIDENCE_REQUIRED")
	_repair(run)
	_device(run, nodes[4])
	assert_true(run.devices.solved())
	assert_eq(run.devices.snapshot()["faults"], 1)
	assert_eq(run.devices.snapshot()["resets"], 1)


func test_EXP07_extraction_denied_by_graph_even_after_EXP06_puzzle_solved() -> void:
	var run: Runtime = _start("LV_001")
	_stand(run, "PANEL_WEST")
	_command(run, "inspect", "PANEL_WEST")
	_stand(run, "SW_GRID_SPUR")
	_command(run, "toggle_switch", "SW_GRID_SPUR", {"value": true})
	_command(run, "toggle_switch", "SW_GRID_SPUR", {"value": false})
	_stand(run, "SW_EAST")
	_command(run, "toggle_switch", "SW_EAST", {"value": true})
	_repair(run)
	assert_true(run.bespoke.solved(), "EXP06 puzzle should be solved first")
	_stand(run, "ZONE_EXTRACT")
	_seq += 1
	var forbidden: Dictionary = _wire(run, _seq, "request_extract",
		"ZONE_EXTRACT", {"action": "start"})
	assert_eq(forbidden.get("code"), "EXP07_DEVICES_INCOMPLETE")
	assert_false(run.devices.solved())
	var nodes: Array = run.devices.definition_snapshot()["nodes"]
	for node: Dictionary in nodes:
		_device(run, node)
	assert_true(run.devices.solved(), "All five authentic host operations completed")
	_stand(run, "ZONE_EXTRACT")
	_seq += 1
	var afterward: Dictionary = _wire(run, _seq, "request_extract",
		"ZONE_EXTRACT", {"action": "start"})
	assert_ne(afterward.get("code", ""), "EXP07_DEVICES_INCOMPLETE")


func test_EXP07_disabled_legacy_session_refuses_device_intent_without_revision_change() -> void:
	var run: Runtime = Runtime.new()
	var initialized: Dictionary = run.start("LV_001", Callable(self, "_position"),
		Callable(), "", false, "", true)
	assert_true(bool(initialized.get("ok", false)), str(initialized))
	assert_true(run.devices == null)
	var prior: String = run.host.state_hash()
	_seq += 1
	var denied: Dictionary = _wire(run, _seq, "operate_device", "DV_001_A", {"action": "trace"})
	assert_false(bool(denied.get("ok", false)))
	assert_eq(run.host.state_hash(), prior)
