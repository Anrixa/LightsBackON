extends "res://tests/test_case.gd"
## EXP009 source/headless propagation and SessionHost authority regression.
const Atlas := preload("res://scripts/world/dispatch_atlas.gd")
const Faults := preload("res://scripts/gameplay/expedition_fault_diagnostics.gd")
const Chains := preload("res://scripts/gameplay/expedition_consequences.gd")
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
	return {"west_inspected": true, "devices_solved": true,
		"west_restored": true, "east_on": true, "spur_on": false,
		"hazard_active": false, "fault_phase": "route", "faults_solved": false}


func test_EXP009_source_pins_and_all_200_clean_cascades() -> void:
	var audit: Dictionary = Chains.inspect(Atlas.load_catalog(), Faults.load_book(), Chains.load_book())
	assert_true(bool(audit.get("ok", false)), str(audit))
	assert_eq(audit.get("levels"), 200)
	assert_eq(audit.get("nodes"), 600)
	assert_eq(audit.get("topologies"), 2)
	for chain: Dictionary in Chains.load_book()["entries"]:
		var machine: Chains = Chains.new()
		assert_true(machine.configure(chain)["ok"])
		var facts: Dictionary = _facts()
		machine.advance(facts)
		for node: Dictionary in chain["nodes"]:
			var id: String = str(node["id"])
			assert_eq(machine.snapshot()["states"][id]["status"], "at_risk")
			assert_true(machine.operate(id, "survey", facts)["ok"])
			assert_true(machine.operate(id, "isolate", facts)["ok"])
		assert_false(machine.operate(str(chain["console"]), "certify", facts)["ok"])
		facts["faults_solved"] = true
		assert_true(machine.operate(str(chain["console"]), "certify", facts)["ok"])
		assert_true(machine.solved())
		assert_eq(machine.snapshot()["failures"], 0)


func test_EXP009_failure_propagation_and_three_stage_recovery() -> void:
	for chain: Dictionary in [Chains.load_book()["entries"][0],
			Chains.load_book()["entries"][1]]:
		var machine: Chains = Chains.new()
		assert_true(machine.configure(chain)["ok"])
		var facts: Dictionary = _facts()
		facts["east_on"] = false
		facts["fault_phase"] = "faulted"
		for t: int in range(180):
			machine.advance(facts)
		var report: Dictionary = machine.snapshot()
		assert_eq(report["failures"], 3)
		for node: Dictionary in chain["nodes"]:
			assert_eq(report["states"][node["id"]]["status"], "failed")
		facts["east_on"] = true
		facts["fault_phase"] = "complete"
		facts["faults_solved"] = true
		for node: Dictionary in chain["nodes"]:
			var id: String = str(node["id"])
			assert_false(machine.operate(id, "repair", facts)["ok"])
			assert_true(machine.operate(id, "survey", facts)["ok"])
			assert_true(machine.operate(id, "repair", facts)["ok"])
		assert_eq(machine.snapshot()["recoveries"], 3)
		assert_true(machine.operate(str(chain["console"]), "certify", facts)["ok"])
		assert_true(machine.solved())
		# A certified field operation becomes unsafe again on host supply loss.
		facts["east_on"] = false
		machine.advance(facts)
		assert_false(machine.solved())
		assert_eq(machine.snapshot()["reopens"], 1)
		facts["east_on"] = true
		var root: String = str(chain["nodes"][0]["id"])
		assert_true(machine.operate(root, "isolate", facts)["ok"])
		assert_true(machine.operate(str(chain["console"]), "certify", facts)["ok"])
		assert_true(machine.solved())


func test_EXP009_finite_diversion_and_interlocks() -> void:
	var chain: Dictionary = Chains.load_book()["entries"][0]
	var machine: Chains = Chains.new()
	assert_true(machine.configure(chain)["ok"])
	var facts: Dictionary = _facts()
	var root: String = str(chain["nodes"][0]["id"])
	assert_false(machine.operate(root, "survey", facts)["ok"])
	machine.advance(facts)
	assert_false(machine.operate(root, "divert", facts)["ok"])
	assert_true(machine.operate(root, "survey", facts)["ok"])
	assert_false(machine.operate(root, "divert", facts)["ok"])
	facts["spur_on"] = true
	assert_true(machine.operate(root, "divert", facts)["ok"])
	assert_eq(machine.snapshot()["reserve"], 0)
	for node: Dictionary in chain["nodes"].slice(1):
		var id: String = str(node["id"])
		assert_true(machine.operate(id, "survey", facts)["ok"])
		assert_false(machine.operate(id, "divert", facts)["ok"])
		facts["spur_on"] = false
		assert_true(machine.operate(id, "isolate", facts)["ok"])
	facts["faults_solved"] = true
	assert_true(machine.operate(str(chain["console"]), "certify", facts)["ok"])
	assert_eq(machine.snapshot()["diversions"], 1)
	assert_true(machine.solved())


func test_EXP009_real_host_refuses_peer_forgery_range_and_legacy_intents() -> void:
	var inactive: Runtime = Runtime.new()
	assert_eq(inactive.start("LV_001", Callable(self, "_position"),
		Callable(), "", false, "", true, true, false, true)["code"],
		"EXP009_REQUIRES_EXP08")
	var old: Runtime = Runtime.new()
	assert_true(old.start("LV_001", Callable(self, "_position"))["ok"])
	var old_hash: String = old.host.state_hash()
	assert_false(_wire(old, 1, "operate_consequence", "FC_001_0",
		{"action": "survey"})["ok"])
	assert_eq(old.host.state_hash(), old_hash)
	var run: Runtime = Runtime.new()
	var begun: Dictionary = run.start("LV_001", Callable(self, "_position"),
		Callable(), "", false, "", true, true, true, true)
	assert_true(begun["ok"], str(begun))
	if not bool(begun["ok"]):
		return
	assert_true(run.host.authoritative_state().has("exp009_consequences"))
	var chain: Dictionary = run.consequences.definition_snapshot()
	_stand(run, str(chain["nodes"][0]["id"]))
	var original: String = run.host.state_hash()
	assert_false(_wire(run, 1, "operate_consequence", str(chain["nodes"][0]["id"]),
		{"action": "survey"}, 998)["ok"])
	assert_eq(run.host.state_hash(), original)
	var denied: Dictionary = _wire(run, 1, "operate_consequence",
		str(chain["nodes"][0]["id"]), {"action": "survey", "exposure": 0.0})
	assert_false(denied["ok"])
	assert_eq(run.host.state_hash(), original)
	assert_true(_wire(run, 1, "operate_consequence",
		str(chain["nodes"][0]["id"]), {"action": "survey"}).get("duplicate", false))
	assert_eq(run.host.state_hash(), original)
	_stand(run, "ZONE_EXTRACT")
	assert_eq(_wire(run, 2, "operate_consequence",
		str(chain["nodes"][0]["id"]), {"action": "survey"}).get("code"),
		"NOT_IN_RANGE")
	assert_eq(run.host.state_hash(), original)
