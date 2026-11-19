extends "res://tests/test_case.gd"
## EXP010: all 200 source profiles, finite-stock simulation and SessionHost gates.
const Atlas := preload("res://scripts/world/dispatch_atlas.gd")
const Chains := preload("res://scripts/gameplay/expedition_consequences.gd")
const Logistics := preload("res://scripts/gameplay/expedition_emergency_logistics.gd")
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
	return {"consequences_solved": true, "faults_solved": true,
		"west_restored": true, "east_on": true, "hazard_active": false}


func _deliver(machine: Logistics, entry: Dictionary, job_index: int,
		route: String, facts: Dictionary) -> void:
	var job: Dictionary = entry["jobs"][job_index]
	var action: String = "dispatch_" + ("a" if job_index == 0 else "b") + "_" + route
	assert_true(machine.operate(str(entry["depot"]), action, facts)["ok"])
	assert_false(machine.operate(str(entry["depot"]), action, facts)["ok"])
	var ticks: int = 6 if route == "direct" else 14
	for t: int in range(ticks - 1):
		machine.advance(facts)
	assert_eq(machine.snapshot()["jobs"][str(job["id"])]["status"], "transit")
	machine.advance(facts)
	assert_eq(machine.snapshot()["jobs"][str(job["id"])]["status"], "arrived")
	assert_true(machine.operate(str(job["id"]), "receive", facts)["ok"])


func test_EXP010_200_source_pins_and_deterministic_finite_inventory() -> void:
	var audit: Dictionary = Logistics.inspect(Atlas.load_catalog(), Chains.load_book(),
		Logistics.load_book())
	assert_true(bool(audit["ok"]), str(audit))
	assert_eq(audit["levels"], 200)
	assert_eq(audit["jobs"], 400)
	assert_eq(audit["targets"], 800)
	assert_eq(audit["patterns"], 3)
	for entry: Dictionary in Logistics.load_book()["entries"]:
		var machine: Logistics = Logistics.new()
		assert_true(machine.configure(entry)["ok"])
		assert_eq(machine.target_ids().size(), 4)
		var dormant: String = JSON.stringify(machine.snapshot())
		for t: int in range(20):
			machine.advance(_facts())
		assert_eq(JSON.stringify(machine.snapshot()), dormant)
		assert_true(machine.operate(str(entry["depot"]), "manifest", _facts())["ok"])
		var a_route: String = "relay" if entry["pattern"] == "crossdock" else "direct"
		var b_route: String = "direct" if a_route == "relay" else "relay"
		_deliver(machine, entry, 0, a_route, _facts())
		_deliver(machine, entry, 1, b_route, _facts())
		assert_eq(machine.snapshot()["stock"], {"spares": 0, "fuel": 0})
		assert_false(machine.operate(str(entry["console"]), "certify",
			{"consequences_solved": false})["ok"])
		assert_true(machine.operate(str(entry["console"]), "certify", _facts())["ok"])
		assert_true(machine.solved())
		var frozen: String = JSON.stringify(machine.snapshot())
		for t: int in range(20):
			machine.advance(_facts())
		assert_eq(JSON.stringify(machine.snapshot()), frozen)
		# Reopening must not mint more material or demand impossible new stock.
		var unsafe: Dictionary = _facts()
		unsafe["east_on"] = false
		machine.advance(unsafe)
		assert_false(machine.solved())
		assert_eq(machine.snapshot()["stock"], {"spares": 0, "fuel": 0})
		for job: Dictionary in entry["jobs"]:
			assert_eq(machine.snapshot()["jobs"][str(job["id"])]["status"], "recheck")
			assert_true(machine.operate(str(job["id"]), "recheck", _facts())["ok"])
		assert_true(machine.operate(str(entry["console"]), "certify", _facts())["ok"])
		assert_true(machine.solved())


func test_EXP010_recall_refunds_exactly_once_and_crossdock_enforces_route() -> void:
	var entry: Dictionary = Logistics.load_book()["entries"][2] # crossdock
	var machine: Logistics = Logistics.new()
	assert_true(machine.configure(entry)["ok"])
	assert_false(machine.operate(str(entry["depot"]), "manifest",
		{"consequences_solved": false})["ok"])
	assert_true(machine.operate(str(entry["depot"]), "manifest", _facts())["ok"])
	assert_false(machine.operate(str(entry["depot"]), "dispatch_a_direct", _facts())["ok"])
	assert_true(machine.operate(str(entry["depot"]), "dispatch_a_relay", _facts())["ok"])
	assert_eq(machine.snapshot()["stock"], {"spares": 2, "fuel": 1})
	assert_false(machine.operate(str(entry["jobs"][0]["id"]), "receive", _facts())["ok"])
	assert_true(machine.operate(str(entry["depot"]), "recall", _facts())["ok"])
	assert_eq(machine.snapshot()["stock"], {"spares": 3, "fuel": 3})
	assert_false(machine.operate(str(entry["depot"]), "recall", _facts())["ok"])
	assert_eq(machine.snapshot()["recalls"], 1)
	_deliver(machine, entry, 0, "relay", _facts())
	_deliver(machine, entry, 1, "direct", _facts())
	assert_true(machine.operate(str(entry["console"]), "certify", _facts())["ok"])


func test_EXP010_late_delivery_is_recorded_but_does_not_softlock() -> void:
	var entry: Dictionary = Logistics.load_book()["entries"][1] # triage
	var machine: Logistics = Logistics.new()
	assert_true(machine.configure(entry)["ok"])
	assert_true(machine.operate(str(entry["depot"]), "manifest", _facts())["ok"])
	# Wait beyond the critical ETA while a real host clock advances.
	for t: int in range(14):
		machine.advance(_facts())
	_deliver(machine, entry, 0, "direct", _facts())
	_deliver(machine, entry, 1, "relay", _facts())
	assert_eq(machine.snapshot()["late"], 1)
	assert_true(machine.operate(str(entry["console"]), "certify", _facts())["ok"])
	assert_true(machine.solved())


func test_EXP010_host_scope_identity_range_payload_and_replay() -> void:
	var invalid: Runtime = Runtime.new()
	assert_eq(invalid.start("LV_001", Callable(self, "_position"),
		Callable(), "", false, "", true, true, true, false, true)["code"],
		"EXP010_REQUIRES_EXP009")
	var old: Runtime = Runtime.new()
	assert_true(old.start("LV_001", Callable(self, "_position"))["ok"])
	var old_hash: String = old.host.state_hash()
	assert_false(_wire(old, 1, "operate_logistics", "LG_001_DEPOT",
		{"action": "manifest"})["ok"])
	assert_eq(old.host.state_hash(), old_hash)
	var run: Runtime = Runtime.new()
	var begun: Dictionary = run.start("LV_001", Callable(self, "_position"),
		Callable(), "", false, "", true, true, true, true, true)
	assert_true(begun["ok"], str(begun))
	if not bool(begun["ok"]):
		return
	assert_true(run.host.authoritative_state().has("exp010_logistics"))
	var manifest: Dictionary = run.logistics.definition_snapshot()
	_stand(run, str(manifest["depot"]))
	var original: String = run.host.state_hash()
	assert_false(_wire(run, 1, "operate_logistics", str(manifest["depot"]),
		{"action": "manifest"}, 998)["ok"])
	assert_eq(run.host.state_hash(), original)
	assert_false(_wire(run, 1, "operate_logistics", str(manifest["depot"]),
		{"action": "manifest", "spares": 999.0})["ok"])
	assert_eq(run.host.state_hash(), original)
	assert_true(_wire(run, 1, "operate_logistics", str(manifest["depot"]),
		{"action": "manifest"}).get("duplicate", false))
	assert_eq(run.host.state_hash(), original)
	_stand(run, "ZONE_EXTRACT")
	assert_eq(_wire(run, 2, "operate_logistics", str(manifest["depot"]),
		{"action": "manifest"}).get("code"), "NOT_IN_RANGE")
	assert_eq(run.host.state_hash(), original)


func test_EXP010_source_splice_and_permissive_policy_are_refused() -> void:
	var book: Dictionary = Logistics.load_book()
	var entry: Dictionary = book["entries"][0]
	var swapped: Dictionary = entry.duplicate(true)
	swapped["chain_key"] = "forged"
	var one: Dictionary = {"entries": [swapped]}
	var catalog: Dictionary = Atlas.load_catalog()
	assert_true(Logistics.entry_for(one, catalog["levels"][0],
		Chains.load_book()["entries"][0]).is_empty())
	assert_true(Logistics.inspect(catalog, Chains.load_book(), book)["ok"])
