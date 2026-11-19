extends "res://tests/test_case.gd"
## EXP08: source/headless authority checks; no human/controller certification.
const Atlas := preload("res://scripts/world/dispatch_atlas.gd")
const Graph := preload("res://scripts/gameplay/expedition_device_graph.gd")
const Faults := preload("res://scripts/gameplay/expedition_fault_diagnostics.gd")
const Runtime := preload("res://scripts/gameplay/expedition_host_session.gd")

var _pos: Vector3 = Vector3(26.0, 0.90, 26.0)
var _seq: int = 0

func before_each() -> void:
	_pos = Vector3(26.0, 0.90, 26.0)
	_seq = 0

func _position(_id: String) -> Vector3:
	return _pos

func _stand(run: Runtime, id: String) -> void:
	var target: Vector3 = run.definition_snapshot()["positions"][id]
	_pos = Vector3(target.x, 0.90, target.z)

func _wire(run: Runtime, seq: int, kind: String, id: String,
		payload: Dictionary = {}, peer: int = 1) -> Dictionary:
	return run.receive(peer, JSON.stringify({
		"session": run.session_id(), "seq": seq, "type": kind,
		"entity": id, "payload": payload}).to_utf8_buffer())

func _command(run: Runtime, kind: String, id: String, payload: Dictionary = {}) -> Dictionary:
	if _seq > 0 and _seq % 8 == 0:
		for t: int in range(11):
			run.tick_host()
	for t: int in range(300):
		if bool(run.bespoke.preflight(kind, id).get("ok", false)):
			break
		run.tick_host()
	_seq += 1
	var answer: Dictionary = _wire(run, _seq, kind, id, payload)
	assert_true(bool(answer.get("ok", false)), "%s %s seq=%d %s" % [
		kind, id, _seq, str(answer)])
	return answer

func _solve_devices(run: Runtime) -> void:
	_stand(run, "PANEL_WEST")
	_command(run, "inspect", "PANEL_WEST")
	_stand(run, "SW_EAST")
	_command(run, "toggle_switch", "SW_EAST", {"value": true})
	_stand(run, "R_WEST")
	_command(run, "request_lock", "R_WEST")
	var needed: Dictionary = {
		"open": "screwdriver", "remove": "puller",
		"install": "puller", "close": "screwdriver", "test": "meter"}
	var tool: String = ""
	for step: String in ["diagnose", "isolate", "open", "remove",
			"install", "close", "test", "restore"]:
		var target_tool: String = str(needed.get(step, ""))
		if target_tool != "" and target_tool != tool:
			_command(run, "equip", "", {"tool": target_tool})
			tool = target_tool
		_command(run, "repair_step", "R_WEST", {"step": step})
	for node: Dictionary in run.devices.definition_snapshot()["nodes"]:
		_stand(run, str(node["id"]))
		for t: int in range(300):
			if not (bool(node.get("hazard_sensitive", false)) and run.bespoke.hazard_active()):
				break
			run.tick_host()
		_command(run, "operate_device", str(node["id"]), {"action": str(node["action"])})
	assert_true(run.devices.solved())

func test_EXP08_all_200_source_profiles_solve_both_alternative_paths() -> void:
	var audit: Dictionary = Faults.inspect(Atlas.load_catalog(), Graph.load_book(), Faults.load_book())
	assert_true(bool(audit.get("ok", false)), str(audit))
	assert_eq(audit.get("levels"), 200)
	assert_eq(audit.get("fault_families"), 8)
	for profile: Dictionary in Faults.load_book()["entries"]:
		for mode: String in ["isolate", "reroute"]:
			var f: Faults = Faults.new()
			assert_true(f.configure(profile).get("ok", false))
			var facts: Dictionary = {
				"west_inspected": true, "east_on": true, "west_restored": true,
				"spur_on": mode == "reroute", "devices_solved": true,
				"hazard_active": false}
			assert_false(f.solved())
			assert_true(f.operate(str(profile["probe_a"]), "scan", facts)["ok"])
			assert_true(f.operate(str(profile["probe_b"]), "scan", facts)["ok"])
			assert_true(f.operate(str(profile["console"]), mode, facts)["ok"])
			assert_true(f.operate(str(profile["console"]), "stabilize", facts)["ok"])
			var duration: int = int(profile["hold_ticks"]) + (
				int(profile["alternate_extra_ticks"]) if mode == "reroute" else 0)
			for t: int in range(duration):
				f.advance(facts)
			assert_eq(f.snapshot()["phase"], "verified")
			assert_true(f.operate(str(profile["console"]), "certify", facts)["ok"])
			assert_true(f.solved())

func test_EXP08_interruption_spare_exhaustion_and_isolation_recovery() -> void:
	var p: Dictionary = Faults.load_book()["entries"][0]
	var f: Faults = Faults.new()
	assert_true(f.configure(p)["ok"])
	var facts: Dictionary = {
		"west_inspected": true, "east_on": true, "west_restored": true,
		"spur_on": true, "devices_solved": true, "hazard_active": false}
	assert_false(f.operate(str(p["console"]), "reroute", facts)["ok"])
	assert_true(f.operate(str(p["probe_a"]), "scan", facts)["ok"])
	assert_true(f.operate(str(p["probe_b"]), "scan", facts)["ok"])
	assert_true(f.operate(str(p["console"]), "reroute", facts)["ok"])
	assert_true(f.operate(str(p["console"]), "stabilize", facts)["ok"])
	f.advance(facts)
	facts["east_on"] = false
	f.advance(facts)
	assert_eq(f.snapshot()["phase"], "faulted")
	assert_eq(f.snapshot()["faults"], 1)
	assert_eq(f.snapshot()["spares"], 0)
	assert_false(f.operate(str(p["console"]), "certify", facts)["ok"])
	assert_true(f.operate(str(p["console"]), "reset", facts)["ok"])
	assert_false(f.operate(str(p["console"]), "reroute", facts)["ok"])
	facts["east_on"] = true
	facts["spur_on"] = false
	assert_true(f.operate(str(p["console"]), "isolate", facts)["ok"])
	assert_true(f.operate(str(p["console"]), "stabilize", facts)["ok"])
	for t: int in range(int(p["hold_ticks"])):
		f.advance(facts)
	assert_true(f.operate(str(p["console"]), "certify", facts)["ok"])
	assert_true(f.solved())
	assert_eq(f.snapshot()["resets"], 1)

func test_EXP08_live_host_denies_peer_replay_remote_and_early_extraction() -> void:
	var run: Runtime = Runtime.new()
	var start: Dictionary = run.start("LV_001", Callable(self, "_position"),
		Callable(), "", false, "", true, true, true)
	assert_true(bool(start.get("ok", false)), str(start))
	if not bool(start.get("ok", false)):
		return
	var p: Dictionary = run.faults.definition_snapshot()
	_stand(run, str(p["probe_a"]))
	var initial_hash: String = run.host.state_hash()
	assert_false(bool(_wire(run, 1, "operate_fault", str(p["probe_a"]),
		{"action": "scan"}, 998).get("ok", false)))
	assert_eq(run.host.state_hash(), initial_hash)
	assert_eq(_wire(run, 1, "operate_fault", str(p["probe_a"]),
		{"action": "scan"}).get("code"), "EXP08_DEVICES_REQUIRED")
	assert_true(bool(_wire(run, 1, "operate_fault", str(p["probe_a"]),
		{"action": "scan"}).get("duplicate", false)))
	assert_eq(run.host.state_hash(), initial_hash)
	_seq = 1
	_solve_devices(run)
	_stand(run, "ZONE_EXTRACT")
	_seq += 1
	assert_eq(_wire(run, _seq, "request_extract", "ZONE_EXTRACT",
		{"action": "start"}).get("code"), "EXP08_FAULTS_INCOMPLETE")
	_stand(run, str(p["probe_a"]))
	_command(run, "operate_fault", str(p["probe_a"]), {"action": "scan"})
	_stand(run, str(p["probe_b"]))
	_command(run, "operate_fault", str(p["probe_b"]), {"action": "scan"})
	_stand(run, "ZONE_EXTRACT")
	_seq += 1
	assert_eq(_wire(run, _seq, "operate_fault", str(p["console"]),
		{"action": "isolate"}).get("code"), "NOT_IN_RANGE")
	_stand(run, str(p["console"]))
	_command(run, "operate_fault", str(p["console"]), {"action": "isolate"})
	# Schedule the host hold at a source-defined safe window with enough ticks
	# remaining, without a client-selected clock or fabricated hazard flag.
	var hazard: Dictionary = run.bespoke.definition_snapshot()["hazard"]
	var period: int = int(hazard["period_ticks"])
	var active: int = int(hazard["active_ticks"])
	var offset: int = int(hazard["phase_offset"])
	for t: int in range(2 * period):
		var phase: int = (int(run.bespoke.snapshot()["tick"]) + offset) % period
		if phase >= active and period - phase > int(p["hold_ticks"]) + 2:
			break
		run.tick_host()
	_command(run, "operate_fault", str(p["console"]), {"action": "stabilize"})
	var before: String = run.host.state_hash()
	for t: int in range(int(p["hold_ticks"])):
		run.tick_host()
	assert_ne(run.host.state_hash(), before)
	assert_eq(run.faults.snapshot()["phase"], "verified")
	_command(run, "operate_fault", str(p["console"]), {"action": "certify"})
	assert_true(run.faults.solved())
	assert_true(run.host.authoritative_state().has("exp08_faults"))
	_stand(run, "ZONE_EXTRACT")
	_seq += 1
	var after: Dictionary = _wire(run, _seq, "request_extract",
		"ZONE_EXTRACT", {"action": "start"})
	assert_ne(after.get("code", ""), "EXP08_FAULTS_INCOMPLETE")

func test_EXP08_disabled_legacy_host_retains_hash_and_denies_fault_intent() -> void:
	var dependency: Runtime = Runtime.new()
	var denied: Dictionary = dependency.start("LV_001", Callable(self, "_position"),
		Callable(), "", false, "", false, false, true)
	assert_eq(denied.get("code"), "EXP08_REQUIRES_EXP07")
	var legacy: Runtime = Runtime.new()
	assert_true(legacy.start("LV_001", Callable(self, "_position"))["ok"])
	var old_hash: String = legacy.host.state_hash()
	assert_false(_wire(legacy, 1, "operate_fault", "FD_001_A",
		{"action": "scan"}).get("ok", false))
	assert_eq(legacy.host.state_hash(), old_hash)
