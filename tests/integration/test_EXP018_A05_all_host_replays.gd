extends "res://tests/test_case.gd"
## EXP018 A05: 200 real SessionHost command replays + 400 source case routes.
## Exact host mission completion is NOT inferred from source case solutions.

const Atlas := preload("res://scripts/world/dispatch_atlas.gd")
const Runtime := preload("res://scripts/gameplay/expedition_host_session.gd")
const Cases := preload("res://scripts/gameplay/expedition_advanced_casework.gd")
const Faults := preload("res://scripts/gameplay/expedition_advanced_fault_layers.gd")
const Hazards := preload("res://scripts/gameplay/expedition_advanced_hazards.gd")
const Gear := preload("res://scripts/gameplay/expedition_advanced_equipment.gd")
const Policies := preload("res://scripts/gameplay/expedition_advanced_policies.gd")
const Discoveries := preload("res://scripts/gameplay/expedition_advanced_discoveries.gd")
const Cascades := preload("res://scripts/gameplay/expedition_advanced_cascade.gd")
const A12Replay := preload("res://tests/integration/test_EXP016_A12_full_replay.gd")

const EVIDENCE_PATH: String = "res://build/exp018-a05/host-replay-evidence.json"
var _position: Vector3 = Vector3.ZERO


func _position_for(_player: String) -> Vector3:
	return _position


func _message(session: String, seq: int, entity: String) -> PackedByteArray:
	return JSON.stringify({
		"session": session, "seq": seq, "type": "inspect",
		"entity": entity, "payload": {}
	}).to_utf8_buffer()


func _entry(books: Array[Dictionary], level: String) -> Dictionary:
	for book: Dictionary in books:
		var candidate: Dictionary = Cases.entry_for(book, level)
		if not candidate.is_empty():
			return candidate
	return {}


func _write_evidence(report: Dictionary) -> void:
	var absolute: String = ProjectSettings.globalize_path(EVIDENCE_PATH.get_base_dir())
	var status: Error = DirAccess.make_dir_recursive_absolute(absolute)
	assert_eq(status, OK, "cannot create independent replay evidence directory")
	if status != OK:
		return
	var handle: FileAccess = FileAccess.open(EVIDENCE_PATH, FileAccess.WRITE)
	assert_true(handle != null, "cannot write original source replay evidence")
	if handle != null:
		handle.store_string(JSON.stringify(report, "\t") + "\n")
		handle.flush()
		handle.close()


func test_EXP018_A05_all_200_real_host_envelopes_1000_tasks_and_400_case_routes() -> void:
	var atlas: Dictionary = Atlas.load_catalog()
	var books: Array[Dictionary] = Cases.load_available_books()
	var fault_book: Dictionary = Faults.load_book()
	var hazards: Dictionary = Hazards.load_book()
	var equipment: Dictionary = Gear.load_book()
	var policies: Dictionary = Policies.load_book()
	var discoveries: Dictionary = Discoveries.load_book()
	var cascades: Dictionary = Cascades.load_book()
	var records: Array[Dictionary] = []
	var ids: Dictionary = {}
	var source_task_ids: Dictionary = {}
	var route_count: int = 0
	var recovery_routes: int = 0
	var accepted_host_intents: int = 0
	var replay_denials: int = 0
	for serial: int in range(1, 201):
		var level: Dictionary = atlas["levels"][serial - 1]
		var id: String = "LV_%03d" % serial
		assert_eq(str(level["id"]), id)
		var host: Runtime = Runtime.new()
		_position = Vector3.ZERO
		var started: Dictionary = host.start_exp016_source_qualification(
			id, Callable(self, "_position_for"))
		assert_true(bool(started.get("ok", false)), str(started))
		if not bool(started.get("ok", false)):
			continue
		assert_true(str(started["content_revision"]).begins_with("EXP016_"))
		var board: Dictionary = host.task_board()
		assert_true(bool(board.get("ok", false)))
		assert_eq(str(board["level_id"]), id)
		assert_eq((board["tasks"] as Array).size(), 5)
		var task_ids: Array[String] = []
		for task_number: int in range(5):
			var expected: String = str(level["tasks"][task_number]["id"])
			var bound: String = str(board["tasks"][task_number]["id"])
			assert_eq(bound, expected)
			assert_false(source_task_ids.has(bound), "duplicate original task ID " + bound)
			source_task_ids[bound] = true
			task_ids.append(bound)
		assert_true(host.advanced_cases != null)
		assert_true(host.authoritative_state().has("exp018_advanced_cases"))
		# Host transport checks execute before command dispatch or source debit.
		_position = host.definition_snapshot()["positions"]["PANEL_WEST"]
		var message: PackedByteArray = _message(host.session_id(), 1, "PANEL_WEST")
		var before: Dictionary = host.authoritative_state().duplicate(true)
		var unknown: Dictionary = host.receive(999, message)
		assert_eq(str(unknown.get("code", "")), "UNKNOWN_PEER")
		var foreign: Dictionary = host.receive(1,
			_message("S_FORGED_EXP018", 1, "PANEL_WEST"))
		assert_eq(str(foreign.get("code", "")), "WRONG_SESSION")
		assert_eq(host.authoritative_state(), before)
		host.host.tick(1)
		var accepted: Dictionary = host.receive(1, message)
		assert_true(bool(accepted.get("ok", false)), str(accepted))
		if bool(accepted.get("ok", false)):
			accepted_host_intents += 1
		var after: Dictionary = host.authoritative_state()
		var duplicate: Dictionary = host.receive(1, message)
		assert_true(bool(duplicate.get("duplicate", false)), str(duplicate))
		assert_eq(host.authoritative_state(), after, "exact replay mutated original host")
		if bool(duplicate.get("duplicate", false)):
			replay_denials += 1
		var source_case: Dictionary = _entry(books, id)
		assert_false(source_case.is_empty())
		var region: Dictionary = Cascades.entry_for(cascades, id)
		assert_false(region.is_empty())
		if source_case.is_empty() or region.is_empty():
			continue
		var inherited: int = 1 if (region["source_predecessors"][id] as Array).size() > 0 else 0
		for policy: String in ["priority", "resilience"]:
			# Re-execute a full nonlinear, finite resource/equipment/hazard
			# source-machine route (including adverse recovery for 25 finales).
			# This cannot replace the actual MissionDirector completion proof.
			var replay = A12Replay.new()
			var inject: bool = serial % 8 == 0 and policy == "priority"
			replay._replay(source_case, Faults.entry_for(fault_book, id),
				Hazards.entry_for(hazards, id), Gear.entry_for(equipment, id),
				Policies.entry_for(policies, id),
				Discoveries.entry_for(discoveries, id),
				policy, inherited, inject)
			assert_true(replay.failures.is_empty(),
				"source-route failure " + id + "/" + policy + ": " + str(replay.failures))
			if not replay.failures.is_empty():
				continue
			route_count += 1
			if inject:
				recovery_routes += 1
		ids[id] = true
		records.append({
			"level_id": id, "task_ids": task_ids,
			"region_id": str(level["region_id"]),
			"host_source_revision": str(started["content_revision"]),
			"host_inspect_accepted": bool(accepted.get("ok", false)),
			"host_duplicate_idempotent": bool(duplicate.get("duplicate", false)),
			"host_revision": int(host.host.revision),
			"source_case_routes_qualified": ["priority", "resilience"],
			"source_only_no_full_mission_completion": true,
		})
		if serial % 25 == 0:
			print("EXP018_A05 progress=%03d/200 host_intents=%d source_routes=%d task_ids=%d" %
				[serial, accepted_host_intents, route_count, source_task_ids.size()])
	assert_eq(ids.size(), 200)
	assert_eq(source_task_ids.size(), 1000)
	assert_eq(accepted_host_intents, 200)
	assert_eq(replay_denials, 200)
	assert_eq(route_count, 400)
	assert_eq(recovery_routes, 25)
	var status: String = "PASS" if failures.is_empty() and ids.size() == 200 and 			source_task_ids.size() == 1000 and route_count == 400 else "FAIL"
	_write_evidence({
		"phase": "EXP018_A05",
		"status": status,
		"scope": "HEADLESS_HOST_ENVELOPES_PLUS_COMPLETE_SOURCE_CASE_ROUTES",
		"full_authoritative_mission_completion": "NOT_ESTABLISHED",
		"level_count": ids.size(),
		"source_task_id_count": source_task_ids.size(),
		"host_inspect_accepted_count": accepted_host_intents,
		"host_duplicate_idempotent_count": replay_denials,
		"nonlinear_source_route_count": route_count,
		"adverse_recovery_route_count": recovery_routes,
		"original_campaign_and_saves": "UNCHANGED_HOLD",
		"records": records,
		"soft_assertion_failures": failures.duplicate(),
	})
