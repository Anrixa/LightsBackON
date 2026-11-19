extends "res://tests/test_case.gd"
## EXP06 source-engineering gates. No physical/controller route is certified.
## Test-only player coordinates are supplied by the trusted host fixture;
## every field action still enters through SessionHost.receive().

const Atlas := preload("res://scripts/world/dispatch_atlas.gd")
const Mechanics := preload("res://scripts/gameplay/expedition_bespoke_mechanics.gd")
const Runtime := preload("res://scripts/gameplay/expedition_host_session.gd")

var _server_position: Vector3 = Vector3(26.0, 0.90, 26.0)
var _seq: int = 0


func before_each() -> void:
	_server_position = Vector3(26.0, 0.90, 26.0)
	_seq = 0


func _position(_player_id: String) -> Vector3:
	return _server_position


func _session(id: String) -> Runtime:
	var session: Runtime = Runtime.new()
	var started: Dictionary = session.start(id, Callable(self, "_position"),
		Callable(), "", false, "", true)
	assert_true(bool(started.get("ok", false)), "%s %s" % [id, str(started)])
	return session


func _stand(session: Runtime, entity: String) -> void:
	var pos: Vector3 = session.definition_snapshot()["positions"][entity]
	_server_position = Vector3(pos.x, 0.90, pos.z)


func _wire(session: Runtime, seq: int, kind: String, entity: String,
		payload: Dictionary = {}) -> Dictionary:
	var bytes: PackedByteArray = JSON.stringify({
		"session": session.session_id(), "seq": seq,
		"type": kind, "entity": entity, "payload": payload
	}).to_utf8_buffer()
	return session.receive(1, bytes)


func _action(session: Runtime, kind: String, entity: String,
		payload: Dictionary = {}) -> Dictionary:
	# Environmental lockouts are deterministic fixed host ticks, never
	# client-supplied weather/time. Wait without mutating a network sequence.
	for t: int in range(200):
		var gate: Dictionary = session.bespoke.preflight(kind, entity)
		if bool(gate.get("ok", false)):
			break
		session.tick_host()
	_seq += 1
	var reply: Dictionary = _wire(session, _seq, kind, entity, payload)
	assert_true(bool(reply.get("ok", false)),
		"%s %s seq=%d reply=%s" % [kind, entity, _seq, str(reply)])
	return reply


func _restore_west(session: Runtime) -> void:
	_stand(session, "R_WEST")
	_action(session, "request_lock", "R_WEST")
	var steps: Array[String] = [
		"diagnose", "isolate", "open", "remove",
		"install", "close", "test", "restore"
	]
	var tools: Dictionary = {
		"open": "screwdriver", "remove": "puller",
		"install": "puller", "close": "screwdriver", "test": "meter"
	}
	var equipped: String = ""
	for step: String in steps:
		var needed: String = str(tools.get(step, ""))
		if needed != "" and needed != equipped:
			_action(session, "equip", "", {"tool": needed})
			equipped = needed
		_action(session, "repair_step", "R_WEST", {"step": step})


func _inspect_west(session: Runtime) -> void:
	_stand(session, "PANEL_WEST")
	_action(session, "inspect", "PANEL_WEST")


func _east(session: Runtime, enabled: bool) -> void:
	_stand(session, "SW_EAST")
	_action(session, "toggle_switch", "SW_EAST", {"value": enabled})


func _spur(session: Runtime, enabled: bool) -> void:
	_stand(session, "SW_GRID_SPUR")
	_action(session, "toggle_switch", "SW_GRID_SPUR", {"value": enabled})


func _solve_family(session: Runtime, family: String) -> void:
	_inspect_west(session)
	match family:
		"fault_trace":
			var minimum: int = int(session.bespoke.definition_snapshot()["puzzle"]["min_gap_ticks"])
			for t: int in range(minimum + 1):
				session.tick_host()
			_inspect_west(session)
			_east(session, true)
			_restore_west(session)
		"feeder_pulse":
			_east(session, true)
			_east(session, false)
			_east(session, true)
			_restore_west(session)
		"post_repair_audit":
			_east(session, true)
			_restore_west(session)
			_inspect_west(session)
		"stability_hold":
			_east(session, true)
			_restore_west(session)
			var hold: int = int(session.bespoke.definition_snapshot()["puzzle"]["hold_ticks"])
			for t: int in range(hold + 1):
				session.tick_host()
		"spur_isolation":
			_spur(session, true)
			_spur(session, false)
			_east(session, true)
			_restore_west(session)
		"load_rebalance":
			_east(session, true)
			_restore_west(session)
			_east(session, false)
			_east(session, true)
		"relay_coincidence":
			_east(session, true)
			_inspect_west(session)
			_restore_west(session)
		"circuit_pair":
			_east(session, true)
			_inspect_west(session)
			_restore_west(session)
			_inspect_west(session)


func test_EXP06_all_200_encounters_pin_atlas_and_cover_eight_real_mechanic_families() -> void:
	var atlas: Dictionary = Atlas.load_catalog()
	var book: Dictionary = Mechanics.load_book()
	var inspection: Dictionary = Mechanics.inspect(atlas, book)
	assert_true(bool(inspection.get("ok", false)), str(inspection))
	assert_eq(int(inspection["levels"]), 200)
	assert_eq(int(inspection["families"]), 8)
	assert_eq(int(inspection["hazards"]), 8)
	assert_eq(int(inspection["unique_encounters"]), 200)
	var keys: Dictionary = {}
	for level: Dictionary in atlas["levels"]:
		var location: Dictionary = Atlas.find_location(atlas, str(level["location_id"]))
		var entry: Dictionary = Mechanics.entry_for(book, level, location)
		assert_false(entry.is_empty(), str(level["id"]))
		keys[entry["encounter_key"]] = true
	assert_eq(keys.size(), 200)
	print("EXP06_AUTHORING PASS configurations=200 families=8 hazards=8 unique=200")


func test_EXP06_rejects_foreign_or_tampered_source_and_invalid_hazard_parameters() -> void:
	var atlas: Dictionary = Atlas.load_catalog()
	var book: Dictionary = Mechanics.load_book()
	var forged: Dictionary = book.duplicate(true)
	(forged["entries"][0] as Dictionary)["source_puzzle_identity"] = "forged-by-client"
	assert_false(bool(Mechanics.inspect(atlas, forged)["ok"]))
	var first: Dictionary = (atlas["levels"] as Array)[0]
	var location: Dictionary = Atlas.find_location(atlas, str(first["location_id"]))
	assert_true(Mechanics.entry_for(forged, first, location).is_empty())
	forged = book.duplicate(true)
	(forged["entries"][0]["hazard"] as Dictionary)["active_ticks"] = 999
	assert_false(bool(Mechanics.inspect(atlas, forged)["ok"]))
	forged = book.duplicate(true)
	(forged["entries"][0] as Dictionary)["encounter_key"] = forged["entries"][1]["encounter_key"]
	assert_false(bool(Mechanics.inspect(atlas, forged)["ok"]))
	forged = book.duplicate(true)
	(forged["entries"][0] as Dictionary)["puzzle"]["family"] = "client_awards_points"
	assert_false(bool(Mechanics.inspect(atlas, forged)["ok"]))


func test_EXP06_authoritative_host_extraction_is_blocked_until_puzzle_is_solved() -> void:
	var book: Dictionary = Mechanics.load_book()
	var entry: Dictionary = {}
	for candidate: Dictionary in book["entries"]:
		if candidate["puzzle"]["family"] == "post_repair_audit":
			entry = candidate
			break
	assert_false(entry.is_empty())
	var session: Runtime = _session(str(entry["level_id"]))
	_stand(session, "ZONE_EXTRACT")
	session.tick_host()
	_seq = 1
	var denied: Dictionary = _wire(session, _seq, "request_extract",
		"ZONE_EXTRACT", {"action": "start", "puzzle_solved": true})
	assert_false(bool(denied.get("ok", true)), "client declaration cannot substitute for evidence")
	assert_false(bool(session.task_board()["bespoke"]["puzzle_solved"]))
	# Same numeric seq must remain idempotent even if server-owned time changes.
	var repeated: Dictionary = _wire(session, _seq, "request_extract",
		"ZONE_EXTRACT", {"action": "start", "puzzle_solved": true})
	assert_true(bool(repeated.get("duplicate", false)), str(repeated))
	_seq = 1  # test harness action helper advances from the last wire sequence
	_solve_family(session, "post_repair_audit")
	assert_true(bool(session.task_board()["bespoke"]["puzzle_solved"]))
	assert_false(session.completed())
	var required_ticks: int = int(session.definition_snapshot()["verification_ticks"])
	for t: int in range(required_ticks + 5):
		session.tick_host()
	assert_true(session.mission.verified())
	_stand(session, "ZONE_EXTRACT")
	session.tick_host()
	_action(session, "request_extract", "ZONE_EXTRACT", {"action": "start"})
	for t: int in range(50):
		session.tick_host()
	assert_true(session.completed())
	assert_eq(int(session.task_board()["required_completed"]), 4)


func test_EXP06_each_of_eight_families_replays_using_real_host_actions() -> void:
	var book: Dictionary = Mechanics.load_book()
	var first: Dictionary = {}
	for entry: Dictionary in book["entries"]:
		var family: String = str(entry["puzzle"]["family"])
		if not first.has(family):
			first[family] = str(entry["level_id"])
	assert_eq(first.size(), 8)
	for family: String in Mechanics.FAMILIES:
		_seq = 0
		var session: Runtime = _session(str(first[family]))
		_solve_family(session, family)
		assert_true(bool(session.task_board()["bespoke"]["puzzle_solved"]),
			"%s %s" % [family, str(session.task_board()["bespoke"])])
		assert_eq(session.task_board()["bespoke"]["family"], family)
		print("EXP06_PUZZLE_HOST_REPLAY PASS %s %s" % [family, first[family]])


func test_EXP06_hazard_denies_unsafe_switches_and_preserves_host_dedupe() -> void:
	var book: Dictionary = Mechanics.load_book()
	var picked: Dictionary = {}
	for entry: Dictionary in book["entries"]:
		if entry["hazard"]["blocks"] != "repairs":
			picked = entry
			break
	assert_false(picked.is_empty())
	var session: Runtime = _session(str(picked["level_id"]))
	_stand(session, "SW_EAST")
	for t: int in range(200):
		if session.bespoke.hazard_active():
			break
		session.tick_host()
	assert_true(session.bespoke.hazard_active())
	var before: String = session.host.state_hash()
	var denied: Dictionary = _wire(session, 1, "toggle_switch", "SW_EAST", {"value": true})
	assert_eq(str(denied.get("code", "")), "EXP06_UNSAFE_HAZARD_WINDOW")
	assert_eq(session.host.state_hash(), before)
	for t: int in range(200):
		if not session.bespoke.hazard_active():
			break
		session.tick_host()
	var cached: Dictionary = _wire(session, 1, "toggle_switch", "SW_EAST", {"value": true})
	assert_true(bool(cached.get("duplicate", false)))
	assert_eq(str(cached.get("code", "")), "EXP06_UNSAFE_HAZARD_WINDOW")
	var successful: Dictionary = _wire(session, 2, "toggle_switch", "SW_EAST", {"value": true})
	assert_true(bool(successful.get("ok", false)), str(successful))
	assert_true(bool(session.grid.canonical_state()["edges"]["E_GRID_EAST"]["enabled"]))


func test_EXP06_bespoke_is_opt_in_and_original_host_contract_remains_unchanged() -> void:
	var normal: Runtime = Runtime.new()
	assert_true(bool(normal.start("LV_001", Callable(self, "_position")).get("ok", false)))
	assert_false(normal.task_board().has("bespoke"))
	assert_true(normal.bespoke == null)
	assert_eq(normal.state_hash(), normal.host.state_hash())
	var bespoke: Runtime = _session("LV_001")
	assert_true(bespoke.task_board().has("bespoke"))
	assert_ne(bespoke.state_hash(), bespoke.host.state_hash())
	assert_eq(bespoke.definition_snapshot()["level_id"], "LV_001")
