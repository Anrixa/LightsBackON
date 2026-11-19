extends "res://tests/test_case.gd"
## EXP012 source-pinned dual-route work orders, finite calibration cells,
## host dedupe/range/peer barriers and recoverable supply rechecks.
## Source/headless assertions only. Physical access, controller and GPU held.

const Atlas := preload("res://scripts/world/dispatch_atlas.gd")
const Balancing := preload("res://scripts/gameplay/expedition_critical_loads.gd")
const Worksite := preload("res://scripts/gameplay/expedition_worksite_orders.gd")
const Runtime := preload("res://scripts/gameplay/expedition_host_session.gd")

var _pos: Vector3 = Vector3(25.0, 0.90, 25.0)


func before_each() -> void:
	_pos = Vector3(25.0, 0.90, 25.0)


func _position(_id: String) -> Vector3:
	return _pos


func _stand(run: Runtime, id: String) -> void:
	var point: Vector3 = run.definition_snapshot()["positions"][id]
	_pos = Vector3(point.x, 0.90, point.z)


func _wire(run: Runtime, seq: int, kind: String, target: String,
		payload: Dictionary = {}, peer: int = 1) -> Dictionary:
	return run.receive(peer, JSON.stringify({"session": run.session_id(),
		"seq": seq, "type": kind, "entity": target, "payload": payload}).to_utf8_buffer())


func _facts() -> Dictionary:
	return {"balancing_solved": true, "logistics_solved": true,
		"consequences_solved": true, "faults_solved": true,
		"east_on": true, "west_restored": true, "hazard_active": false,
		"investigation_solved": true, "routing_solved": true,
		"repair_solved": true, "discovery_solved": true}


func _solve(machine: Worksite, entry: Dictionary, route: String) -> void:
	var facts: Dictionary = _facts()
	assert_true(machine.operate(str(entry["board"]), "open", facts)["ok"])
	assert_true(machine.operate(str(entry["decision"]), route, facts)["ok"])
	var count: int = 0
	while count < 3:
		var progress: bool = false
		var state: Dictionary = machine.snapshot()["states"]
		for i: int in range(3):
			var cp: Dictionary = entry["checkpoints"][i]
			var id: String = str(cp["id"])
			if state[id]["status"] != "pending":
				continue
			var ready: bool = true
			for parent: Variant in entry["routes"][route][i]:
				if state[str(parent)]["status"] != "latched":
					ready = false
			if not ready:
				continue
			var response: Dictionary = machine.operate(id, "precision", facts)
			assert_true(bool(response.get("ok", false)), str(response))
			if not response.get("ok", false):
				return
			for tick: int in range(int(cp["precision_ticks"])):
				machine.advance(facts)
			assert_eq(machine.snapshot()["states"][id]["status"], "stable")
			assert_true(machine.operate(id, "confirm", facts)["ok"])
			assert_eq(machine.snapshot()["states"][id]["status"], "latched")
			count += 1
			progress = true
			break
		assert_true(progress, "Route must always have an available source-bound checkpoint")
		if not progress:
			return
	assert_true(machine.operate(str(entry["console"]), "certify", facts)["ok"])
	assert_true(machine.solved())
	assert_eq(machine.snapshot()["active_crews"], 0)


func test_EXP012_all_200_worksites_two_distinct_routes_and_rechecks() -> void:
	var atlas: Dictionary = Atlas.load_catalog()
	var book: Dictionary = Worksite.load_book()
	var audit: Dictionary = Worksite.inspect(atlas, Balancing.load_book(), book)
	assert_true(audit["ok"], str(audit))
	assert_eq(audit["levels"], 200)
	assert_eq(audit["targets"], 1400)
	assert_eq(audit["task_bindings"], 1000)
	assert_eq(audit["alternative_routes"], 400)
	for entry: Dictionary in book["entries"]:
		for route: String in ["priority", "resilience"]:
			var machine: Worksite = Worksite.new()
			assert_true(machine.configure(entry)["ok"])
			assert_eq(machine.target_ids().size(), 7)
			assert_false(machine.operate(str(entry["board"]), "open",
				{"balancing_solved": false})["ok"])
			_solve(machine, entry, route)
			var frozen: String = JSON.stringify(machine.snapshot())
			machine.advance(_facts())
			assert_eq(JSON.stringify(machine.snapshot()), frozen)
			var unsafe: Dictionary = _facts()
			unsafe["east_on"] = false
			machine.advance(unsafe)
			assert_false(machine.solved())
			assert_eq(machine.snapshot()["reopens"], 1)
			for cp: Dictionary in entry["checkpoints"]:
				var id: String = str(cp["id"])
				assert_eq(machine.snapshot()["states"][id]["status"], "recheck")
				assert_true(machine.operate(id, "recheck", _facts())["ok"])
				assert_false(machine.operate(id, "recheck", _facts())["ok"])
			assert_true(machine.operate(str(entry["console"]), "certify", _facts())["ok"])
			assert_true(machine.solved())


func test_EXP012_finite_rapid_cells_crew_capacity_and_recoverable_abort() -> void:
	# REG_02 has one crew and three calibration cells; priority is a fork.
	var entry: Dictionary = Worksite.load_book()["entries"][8]
	var machine: Worksite = Worksite.new()
	assert_true(machine.configure(entry)["ok"])
	assert_true(machine.operate(str(entry["board"]), "open", _facts())["ok"])
	assert_true(machine.operate(str(entry["decision"]), "priority", _facts())["ok"])
	var first: String = str(entry["checkpoints"][0]["id"])
	var second: String = str(entry["checkpoints"][1]["id"])
	assert_true(machine.operate(first, "rapid", _facts())["ok"])
	assert_eq(machine.operate(second, "precision", _facts())["code"],
		"EXP012_CREW_CAPACITY")
	assert_false(machine.operate(str(entry["decision"]), "resilience", _facts())["ok"])
	assert_true(machine.operate(first, "confirm", _facts())["ok"])
	assert_eq(machine.snapshot()["aborts"], 1)
	assert_eq(machine.snapshot()["states"][first]["status"], "pending")
	assert_eq(machine.snapshot()["cells_left"], int(entry["cell_budget"]) - 1)
	assert_true(machine.operate(first, "precision", _facts())["ok"])
	for t: int in range(int(entry["checkpoints"][0]["precision_ticks"])):
		machine.advance(_facts())
	assert_true(machine.operate(first, "confirm", _facts())["ok"])
	assert_true(machine.operate(second, "rapid", _facts())["ok"])
	assert_eq(machine.snapshot()["cells_left"], int(entry["cell_budget"]) - 2)
	var unsafe: Dictionary = _facts()
	unsafe["hazard_active"] = true
	machine.advance(unsafe)
	assert_eq(machine.snapshot()["states"][first]["status"], "recheck")
	assert_eq(machine.snapshot()["states"][second]["status"], "pending")
	assert_eq(machine.snapshot()["cells_left"], int(entry["cell_budget"]) - 2)
	assert_true(machine.operate(first, "recheck", _facts())["ok"])


func test_EXP012_discovery_is_optional_and_never_authorizes_forged_evidence() -> void:
	var entry: Dictionary = Worksite.load_book()["entries"][0]
	var machine: Worksite = Worksite.new()
	assert_true(machine.configure(entry)["ok"])
	var facts: Dictionary = _facts()
	facts["investigation_solved"] = false
	assert_eq(machine.operate(str(entry["board"]), "open", facts)["code"],
		"EXP012_SOURCE_EVIDENCE_REQUIRED")
	assert_true(machine.operate(str(entry["board"]), "open", _facts())["ok"])
	facts = _facts()
	facts["discovery_solved"] = false
	assert_eq(machine.operate(str(entry["optional_target"]), "log", facts)["code"],
		"EXP012_DISCOVERY_EVIDENCE_REQUIRED")
	assert_false(machine.snapshot()["optional_logged"])
	assert_true(machine.operate(str(entry["optional_target"]), "log", _facts())["ok"])
	assert_false(machine.operate(str(entry["optional_target"]), "log", _facts())["ok"])


func test_EXP012_host_legacy_opt_out_forgery_dedupe_and_range() -> void:
	var wrong: Runtime = Runtime.new()
	assert_eq(wrong.start("LV_001", Callable(self, "_position"),
		Callable(), "", false, "", true, true, true, true, true, false, true)["code"],
		"EXP012_REQUIRES_EXP011")
	var old: Runtime = Runtime.new()
	assert_true(old.start("LV_001", Callable(self, "_position"))["ok"])
	var old_hash: String = old.host.state_hash()
	assert_false(_wire(old, 1, "operate_worksite", "WO_001_BOARD",
		{"action": "open"})["ok"])
	assert_eq(old.host.state_hash(), old_hash)
	var run: Runtime = Runtime.new()
	var begun: Dictionary = run.start("LV_001", Callable(self, "_position"),
		Callable(), "", false, "", true, true, true, true, true, true, true)
	assert_true(begun["ok"], str(begun))
	if not begun["ok"]:
		return
	assert_true(run.host.authoritative_state().has("exp012_worksite_orders"))
	var entry: Dictionary = run.worksite.definition_snapshot()
	_stand(run, str(entry["board"]))
	var untouched: String = run.host.state_hash()
	assert_false(_wire(run, 1, "operate_worksite", str(entry["board"]),
		{"action": "open"}, 899)["ok"])
	assert_eq(run.host.state_hash(), untouched)
	assert_false(_wire(run, 1, "operate_worksite", str(entry["board"]),
		{"action": "open", "cells_left": 999})["ok"])
	assert_eq(run.host.state_hash(), untouched)
	assert_true(_wire(run, 1, "operate_worksite", str(entry["board"]),
		{"action": "open"}).get("duplicate", false))
	assert_eq(run.host.state_hash(), untouched)
	_stand(run, "ZONE_EXTRACT")
	assert_eq(_wire(run, 2, "operate_worksite", str(entry["board"]),
		{"action": "open"}).get("code"), "NOT_IN_RANGE")
	assert_eq(run.host.state_hash(), untouched)
	assert_eq(run._bespoke_guard(Runtime.PLAYER_ID, "request_extract",
		"ZONE_EXTRACT", {}).get("code"), "EXP07_DEVICES_INCOMPLETE")


func test_EXP012_spliced_book_rejected_at_source_boundary() -> void:
	var atlas: Dictionary = Atlas.load_catalog()
	var book: Dictionary = Worksite.load_book()
	var load: Dictionary = Balancing.load_book()["entries"][0]
	assert_true(Worksite.entry_for(book, atlas["levels"][0], load).has("encounter_key"))
	var mutated: Dictionary = book.duplicate(true)
	mutated["entries"][0]["task_ids"][0] = "JOB_FAKED"
	assert_true(Worksite.entry_for(mutated, atlas["levels"][0], load).is_empty())
	assert_false(Worksite.inspect(atlas, Balancing.load_book(), mutated)["ok"])
