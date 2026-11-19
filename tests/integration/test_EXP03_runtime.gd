extends "res://tests/test_case.gd"
## EXP03: real G01/G03/G04/G05/F03/V02 host envelopes against all 200
## unique dispatch contracts. Host-owned positions are staged in these tests;
## nobody has walked a route and no rewards/saves are issued.

const Atlas := preload("res://scripts/world/dispatch_atlas.gd")
const Plan := preload("res://scripts/world/expedition_layout_plan.gd")
const Factory := preload("res://scripts/gameplay/expedition_contract_factory.gd")
const Runtime := preload("res://scripts/gameplay/expedition_host_session.gd")
const Grid := preload("res://scripts/simulation/power_grid.gd")

var _server_position: Vector3 = Vector3(26.0, 0.90, 26.0)


func before_each() -> void:
	_server_position = Vector3(26.0, 0.90, 26.0)


func _position(_player_id: String) -> Vector3:
	return _server_position


func _session(level_id: String) -> Runtime:
	var runtime: Runtime = Runtime.new()
	var result: Dictionary = runtime.start(level_id, Callable(self, "_position"))
	assert_true(bool(result.get("ok", false)), "%s: %s" % [level_id, result])
	return runtime


func _stand(runtime: Runtime, entity: String) -> void:
	var positions: Dictionary = runtime.definition_snapshot()["positions"]
	var location: Vector3 = positions[entity]
	_server_position = Vector3(location.x, 0.90, location.z)


func _send(runtime: Runtime, seq: int, action: String, entity: String,
		payload: Dictionary = {}, peer_id: int = 1) -> Dictionary:
	var msg: Dictionary = {"session": runtime.session_id(), "seq": seq,
		"type": action, "entity": entity, "payload": payload}
	return runtime.receive(peer_id, JSON.stringify(msg).to_utf8_buffer())


func _must(runtime: Runtime, seq: int, kind: String, entity: String,
		payload: Dictionary = {}) -> void:
	var result: Dictionary = _send(runtime, seq, kind, entity, payload)
	assert_true(bool(result.get("ok", false)), "seq=%d %s %s => %s" %
		[seq, kind, entity, str(result)])


## The original repair service requires a lock, meter evidence, correct tool
## selection and all eight in-order steps. These are actual host envelopes.
func _restore_west(runtime: Runtime, first_seq: int) -> int:
	_stand(runtime, "R_WEST")
	var seq: int = first_seq
	_must(runtime, seq, "request_lock", "R_WEST")
	seq += 1
	var steps: Array[String] = [
		"diagnose", "isolate", "open", "remove",
		"install", "close", "test", "restore"
	]
	var tools: Dictionary = {
		"open": "screwdriver", "remove": "puller",
		"install": "puller", "close": "screwdriver", "test": "meter"
	}
	var last_tool: String = ""
	for step: String in steps:
		var tool: String = str(tools.get(step, ""))
		if tool != "" and tool != last_tool:
			_must(runtime, seq, "equip", "", {"tool": tool})
			seq += 1
			last_tool = tool
		_must(runtime, seq, "repair_step", "R_WEST", {"step": step})
		seq += 1
	return seq


func _complete(runtime: Runtime, include_optional: bool) -> void:
	_stand(runtime, "PANEL_WEST")
	_must(runtime, 1, "inspect", "PANEL_WEST")
	_stand(runtime, "SW_EAST")
	_must(runtime, 2, "toggle_switch", "SW_EAST", {"value": true})
	var seq: int = _restore_west(runtime, 3)
	if include_optional:
		_stand(runtime, "PANEL_SPUR")
		_must(runtime, seq, "inspect", "PANEL_SPUR")
		seq += 1
		_must(runtime, seq, "toggle_switch", "SW_GRID_SPUR", {"value": true})
		seq += 1
		_must(runtime, seq, "toggle_switch", "SW_SIGN", {"value": true})
		seq += 1
	var board: Dictionary = runtime.task_board()
	assert_eq(int(board["required_completed"]), 3)
	assert_eq(bool(board["optional_completed"]), include_optional)
	var verify_ticks: int = int(runtime.definition_snapshot()["verification_ticks"])
	for i: int in range(verify_ticks + 1):
		var tick: Dictionary = runtime.tick_host()
		assert_true(bool(tick["ok"]))
	assert_true(runtime.mission.verified(), "real mission director verifies sustained grid supply")
	assert_false(runtime.completed(), "verification is not automatic extraction")
	_stand(runtime, "ZONE_EXTRACT")
	runtime.tick_host()  # host observes its own avatar before an extraction request
	_must(runtime, seq, "request_extract", "ZONE_EXTRACT", {"action": "start"})
	for i: int in range(50):
		runtime.tick_host()
	assert_true(runtime.completed(), "50 host ticks, crew in zone, supplies and repairs valid")
	board = runtime.task_board()
	assert_eq(int(board["required_completed"]), 4)
	assert_true(bool(board["mission_completed"]))
	assert_eq(str(board["not_certified"]), "NO_PHYSICAL_PLAYABILITY_OR_REWARD_PROMOTION")


func test_EXP03_all_200_distinct_contracts_replay_through_real_host_to_completion() -> void:
	var data: Dictionary = Atlas.load_catalog()
	var successes: int = 0
	var seen: Dictionary = {}
	for level: Dictionary in data["levels"]:
		var level_id: String = str(level["id"])
		var runtime: Runtime = _session(level_id)
		assert_true(runtime.grid != null and runtime.host != null and runtime.mission != null)
		var bindings: Dictionary = runtime.definition_snapshot()["bindings"]
		assert_eq(bindings.size(), 5)
		for task: Dictionary in level["tasks"]:
			assert_true(bindings.has(str(task["id"])))
			seen[str(task["id"])] = true
		_complete(runtime, false)
		successes += 1
	assert_eq(successes, 200)
	assert_eq(seen.size(), 1000)
	print("EXP03_HOST_REPLAY PASS levels=%d task_bindings=%d verified_host_completions=%d" %
		[successes, seen.size(), successes])


func test_EXP03_optional_discovery_and_safe_sign_supply_remain_independently_optional() -> void:
	var runtime: Runtime = _session("LV_001")
	_complete(runtime, true)
	var result: Dictionary = runtime.mission.results()
	assert_true((result["optional_services"] as Array).has("SIGN"))
	assert_true(bool(runtime.task_board()["optional_completed"]))
	assert_true(int(result["stars"]) >= 2)
	assert_true(runtime.definition_snapshot().get("not_certified", "").contains("NO_WALKED_ROUTE"))


func test_EXP03_early_extract_and_forged_peer_and_remote_target_are_refused() -> void:
	var runtime: Runtime = _session("LV_013")
	var state_before: String = runtime.state_hash()
	assert_false(bool(_send(runtime, 1, "request_extract", "ZONE_EXTRACT",
		{"action": "start"}).get("ok", true)))
	assert_false(bool(_send(runtime, 2, "inspect", "PANEL_WEST", {}, 77).get("ok", true)))
	assert_false(bool(_send(runtime, 3, "inspect", "PANEL_WEST").get("ok", true)),
		"source-only stage location cannot be bypassed from the tile center")
	assert_false(bool(_send(runtime, 4, "inspect", "JOB_013_1").get("ok", true)),
		"atlas task IDs cannot become host meter panel IDs")
	assert_eq(runtime.state_hash(), state_before)
	assert_eq(int(runtime.task_board()["required_completed"]), 0)


func test_EXP03_duplicate_wire_sequence_is_deduped_without_duplicate_progress() -> void:
	var runtime: Runtime = _session("LV_047")
	_stand(runtime, "PANEL_WEST")
	var first: Dictionary = _send(runtime, 1, "inspect", "PANEL_WEST")
	assert_true(bool(first["ok"]))
	var original: String = runtime.state_hash()
	var replay: Dictionary = _send(runtime, 1, "toggle_switch", "SW_EAST", {"value": true})
	assert_true(bool(replay.get("duplicate", false)))
	assert_eq(runtime.state_hash(), original)
	assert_eq(int(runtime.task_board()["required_completed"]), 1)
	assert_false(bool(runtime.grid.canonical_state()["edges"]["E_GRID_EAST"]["enabled"]))


func test_EXP03_west_work_order_and_meter_first_are_enforced_by_original_repair_service() -> void:
	var runtime: Runtime = _session("LV_088")
	_stand(runtime, "R_WEST")
	var result: Dictionary = _send(runtime, 1, "request_lock", "R_WEST")
	assert_true(bool(result["ok"]))
	result = _send(runtime, 2, "repair_step", "R_WEST", {"step": "install"})
	assert_false(bool(result["ok"]))
	result = _send(runtime, 3, "repair_step", "R_WEST", {"step": "diagnose"})
	assert_false(bool(result["ok"]), "meter-first diagnosis is a hard host gate")
	_stand(runtime, "PANEL_WEST")
	_must(runtime, 4, "inspect", "PANEL_WEST")
	_stand(runtime, "R_WEST")
	_must(runtime, 5, "repair_step", "R_WEST", {"step": "diagnose"})
	result = _send(runtime, 6, "repair_step", "R_WEST", {"step": "open"})
	assert_false(bool(result["ok"]))
	assert_eq(str(runtime.interaction.repair_state("R_WEST")), "diagnosed")


func test_EXP03_optional_unsafe_west_shortcut_overloads_and_trips_original_protection() -> void:
	var runtime: Runtime = _session("LV_191")
	_stand(runtime, "PANEL_WEST")
	_must(runtime, 1, "inspect", "PANEL_WEST")
	_stand(runtime, "SW_EAST")
	_must(runtime, 2, "toggle_switch", "SW_EAST", {"value": true})
	var seq: int = _restore_west(runtime, 3)
	_stand(runtime, "SW_WEST_SPUR")
	_must(runtime, seq, "toggle_switch", "SW_WEST_SPUR", {"value": true})
	_must(runtime, seq + 1, "toggle_switch", "SW_SIGN", {"value": true})
	var state: Dictionary = runtime.grid.canonical_state()
	assert_true(bool(state["edges"]["E_GRID_WEST"]["overloaded"]))
	for i: int in range(15):
		runtime.tick_host()
	assert_true(bool(runtime.grid.canonical_state()["nodes"]["WEST"]["tripped"]))
	assert_false(runtime.mission.verified())
	assert_false(runtime.completed())


func test_EXP03_two_simultaneous_sign_routes_refused_atomically_by_grid() -> void:
	var runtime: Runtime = _session("LV_090")
	_stand(runtime, "PANEL_WEST")
	_must(runtime, 1, "inspect", "PANEL_WEST")
	_stand(runtime, "SW_EAST")
	_must(runtime, 2, "toggle_switch", "SW_EAST", {"value": true})
	var seq: int = _restore_west(runtime, 3)
	_stand(runtime, "SW_GRID_SPUR")
	_must(runtime, seq, "toggle_switch", "SW_GRID_SPUR", {"value": true})
	_must(runtime, seq + 1, "toggle_switch", "SW_SIGN", {"value": true})
	_stand(runtime, "SW_WEST_SPUR")
	var before: String = runtime.state_hash()
	var result: Dictionary = _send(runtime, seq + 2, "toggle_switch",
		"SW_WEST_SPUR", {"value": true})
	assert_false(bool(result["ok"]), "two energized sign routes must be refused")
	assert_eq(str(result.get("grid_code", "")), "DUAL_SUPPLY")
	assert_eq(runtime.state_hash(), before, "no partial mutation on rejected route")
	assert_false(bool(runtime.grid.canonical_state()["edges"]["E_WEST_SPUR"]["enabled"]))


func test_EXP03_factory_rejects_forged_task_bindings_and_capacity_mutation() -> void:
	var atlas: Dictionary = Atlas.load_catalog()
	var level: Dictionary = (atlas["levels"] as Array)[0]
	var site: Dictionary = Atlas.find_location(atlas, str(level["location_id"]))
	var plan: Dictionary = Plan.make_plan(level, site)
	assert_true(bool(Factory.build(level, plan)["ok"]))
	var bad: Dictionary = plan.duplicate(true)
	((bad["stations"] as Array)[2] as Dictionary)["id"] = "FORGED"
	assert_eq(str(Factory.build(level, bad)["code"]), "UNTRUSTED_TASK_MAPPING")
	bad = plan.duplicate(true)
	(bad["puzzle"] as Dictionary)["source_capacity_pu"] = 999
	assert_eq(str(Factory.build(level, bad)["code"]), "BAD_CAPACITY")
	assert_eq(str(Factory.build(level, {"ok": true, "code": "HOST_AUTHORIZED"})["code"]),
		"INVALID_SOURCE_PLAN")


func test_EXP03_source_only_runtime_cannot_award_credits_or_modify_campaign_saves() -> void:
	var runtime: Runtime = _session("LV_200")
	assert_false(runtime.task_board().has("credits"))
	assert_false(runtime.definition_snapshot().has("profile"))
	assert_false(runtime.definition_snapshot().has("reward_receipt"))
	assert_true(runtime.authoritative_state().has("mission"))
	assert_false(runtime.authoritative_state().has("expedition_loot"))
	assert_false(runtime.authoritative_state().has("player_reward"))
	assert_false(runtime.completed())
