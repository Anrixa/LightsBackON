extends "res://tests/test_case.gd"
## EXP011 host authority, source pins, capacity and recoverable service latches.

const Atlas := preload("res://scripts/world/dispatch_atlas.gd")
const Logistics := preload("res://scripts/gameplay/expedition_emergency_logistics.gd")
const Balancing := preload("res://scripts/gameplay/expedition_critical_loads.gd")
const Runtime := preload("res://scripts/gameplay/expedition_host_session.gd")

var _pos: Vector3 = Vector3(26.0, 0.90, 26.0)


func before_each() -> void:
	_pos = Vector3(26.0, 0.90, 26.0)


func _position(_id: String) -> Vector3:
	return _pos


func _stand(run: Runtime, id: String) -> void:
	var p: Vector3 = run.definition_snapshot()["positions"][id]
	_pos = Vector3(p.x, 0.90, p.z)


func _wire(run: Runtime, seq: int, kind: String, id: String,
		payload: Dictionary = {}, peer: int = 1) -> Dictionary:
	return run.receive(peer, JSON.stringify({"session": run.session_id(),
		"seq": seq, "type": kind, "entity": id, "payload": payload}).to_utf8_buffer())


func _facts() -> Dictionary:
	return {"logistics_solved": true, "consequences_solved": true,
		"faults_solved": true, "west_restored": true,
		"east_on": true, "hazard_active": false}


func _stabilize(machine: Balancing, service: Dictionary) -> void:
	var id: String = str(service["id"])
	assert_true(machine.operate(id, "energize", _facts())["ok"])
	for t: int in range(int(service["dwell_ticks"]) - 1):
		machine.advance(_facts())
	assert_eq(machine.snapshot()["circuits"][id]["status"], "warming")
	machine.advance(_facts())
	assert_eq(machine.snapshot()["circuits"][id]["status"], "stable")
	assert_true(machine.operate(id, "shed", _facts())["ok"])
	assert_eq(machine.snapshot()["circuits"][id]["status"], "latched")


func test_EXP011_all_200_critical_service_boards_and_recovery() -> void:
	var audit: Dictionary = Balancing.inspect(Atlas.load_catalog(),
		Logistics.load_book(), Balancing.load_book())
	assert_true(bool(audit["ok"]), str(audit))
	assert_eq(audit["levels"], 200)
	assert_eq(audit["circuits"], 600)
	assert_eq(audit["targets"], 1000)
	assert_eq(audit["modes"], 3)
	for entry: Dictionary in Balancing.load_book()["entries"]:
		var machine: Balancing = Balancing.new()
		assert_true(machine.configure(entry)["ok"])
		assert_eq(machine.target_ids().size(), 5)
		var before: String = JSON.stringify(machine.snapshot())
		for t: int in range(5):
			machine.advance(_facts())
		assert_eq(JSON.stringify(machine.snapshot()), before)
		assert_false(machine.operate(str(entry["board"]), "open",
			{"logistics_solved": false})["ok"])
		assert_true(machine.operate(str(entry["board"]), "open", _facts())["ok"])
		for service: Dictionary in entry["services"]:
			_stabilize(machine, service)
		assert_eq(machine.snapshot()["used_pu"], 0)
		assert_false(machine.operate(str(entry["console"]), "certify",
			{"logistics_solved": false})["ok"])
		assert_true(machine.operate(str(entry["console"]), "certify", _facts())["ok"])
		assert_true(machine.solved())
		var frozen: String = JSON.stringify(machine.snapshot())
		for t: int in range(6):
			machine.advance(_facts())
		assert_eq(JSON.stringify(machine.snapshot()), frozen)
		var unsafe: Dictionary = _facts()
		unsafe["east_on"] = false
		machine.advance(unsafe)
		assert_false(machine.solved())
		assert_eq(machine.snapshot()["reopens"], 1)
		assert_eq(machine.snapshot()["used_pu"], 0)
		for service: Dictionary in entry["services"]:
			var id: String = str(service["id"])
			assert_eq(machine.snapshot()["circuits"][id]["status"], "recheck")
			assert_true(machine.operate(id, "recheck", _facts())["ok"])
			assert_false(machine.operate(id, "recheck", _facts())["ok"])
		assert_true(machine.operate(str(entry["console"]), "certify", _facts())["ok"])
		assert_true(machine.solved())


func test_EXP011_mode_specific_interlock_capacity_and_early_shed() -> void:
	var interlock: Dictionary = Balancing.load_book()["entries"][2]
	var machine: Balancing = Balancing.new()
	assert_true(machine.configure(interlock)["ok"])
	assert_true(machine.operate(str(interlock["board"]), "open", _facts())["ok"])
	var a: Dictionary = interlock["services"][0]
	var b: Dictionary = interlock["services"][1]
	var c: Dictionary = interlock["services"][2]
	assert_false(machine.operate(str(c["id"]), "energize", _facts())["ok"])
	assert_true(machine.operate(str(a["id"]), "energize", _facts())["ok"])
	assert_eq(machine.operate(str(b["id"]), "energize", _facts())["code"],
		"EXP011_CROSS_FEED_INTERLOCK")
	assert_true(machine.operate(str(a["id"]), "shed", _facts())["ok"])
	assert_eq(machine.snapshot()["aborts"], 1)
	assert_eq(machine.snapshot()["used_pu"], 0)
	_stabilize(machine, a)
	_stabilize(machine, b)
	_stabilize(machine, c)
	assert_true(machine.operate(str(interlock["console"]), "certify", _facts())["ok"])
	var triage: Dictionary = Balancing.load_book()["entries"][1].duplicate(true)
	# This is an isolated, intentionally mutated internal machine fixture; the
	# EXP011 source inspector rejects it before the production host can start.
	triage["services"][0]["demand_pu"] = 5
	triage["services"][1]["demand_pu"] = 3
	var capacity: Balancing = Balancing.new()
	assert_true(capacity.configure(triage)["ok"])
	assert_true(capacity.operate(str(triage["board"]), "open", _facts())["ok"])
	assert_true(capacity.operate(str(triage["services"][0]["id"]), "energize", _facts())["ok"])
	assert_eq(capacity.operate(str(triage["services"][1]["id"]), "energize", _facts())["code"],
		"EXP011_CAPACITY_EXCEEDED")
	assert_eq(capacity.snapshot()["used_pu"], 5)


func test_EXP011_host_rejects_disabled_foreign_and_replayed_operations() -> void:
	var invalid: Runtime = Runtime.new()
	assert_eq(invalid.start("LV_001", Callable(self, "_position"),
		Callable(), "", false, "", true, true, true, true, false, true)["code"],
		"EXP011_REQUIRES_EXP010")
	var old: Runtime = Runtime.new()
	assert_true(old.start("LV_001", Callable(self, "_position"))["ok"])
	var old_hash: String = old.host.state_hash()
	assert_false(_wire(old, 1, "operate_balance", "LB_001_BOARD",
		{"action": "open"})["ok"])
	assert_eq(old.host.state_hash(), old_hash)
	var run: Runtime = Runtime.new()
	var begun: Dictionary = run.start("LV_001", Callable(self, "_position"),
		Callable(), "", false, "", true, true, true, true, true, true)
	assert_true(begun["ok"], str(begun))
	if not begun["ok"]:
		return
	assert_true(run.host.authoritative_state().has("exp011_critical_loads"))
	var board: Dictionary = run.balancing.definition_snapshot()
	_stand(run, str(board["board"]))
	var original: String = run.host.state_hash()
	assert_false(_wire(run, 1, "operate_balance", str(board["board"]),
		{"action": "open"}, 998)["ok"])
	assert_eq(run.host.state_hash(), original)
	assert_false(_wire(run, 1, "operate_balance", str(board["board"]),
		{"action": "open", "capacity_pu": 999.0})["ok"])
	assert_eq(run.host.state_hash(), original)
	assert_true(_wire(run, 1, "operate_balance", str(board["board"]),
		{"action": "open"}).get("duplicate", false))
	assert_eq(run.host.state_hash(), original)
	_stand(run, "ZONE_EXTRACT")
	assert_eq(_wire(run, 2, "operate_balance", str(board["board"]),
		{"action": "open"}).get("code"), "NOT_IN_RANGE")
	assert_eq(run.host.state_hash(), original)


func test_EXP011_spliced_source_is_not_admitted() -> void:
	var catalog: Dictionary = Atlas.load_catalog()
	var book: Dictionary = Balancing.load_book()
	var manifest: Dictionary = Logistics.load_book()["entries"][0]
	assert_true(Balancing.entry_for(book, catalog["levels"][0], manifest).has("load_key"))
	var spliced: Dictionary = book.duplicate(true)
	spliced["entries"][0]["logistics_key"] = "forged"
	assert_true(Balancing.entry_for(spliced, catalog["levels"][0], manifest).is_empty())
	assert_false(Balancing.inspect(catalog, Logistics.load_book(), spliced)["ok"])
