extends "res://tests/test_case.gd"
## EXP018 A03: real SessionHost + original regional source + advanced evidence.
## No synthetic client-success injection, production saves or release promotion.

const Atlas := preload("res://scripts/world/dispatch_atlas.gd")
const Ledger := preload("res://scripts/progression/expedition_ledger.gd")
const Network := preload("res://scripts/gameplay/expedition_regional_network.gd")
const Cascades := preload("res://scripts/gameplay/expedition_advanced_cascade.gd")
const Runtime := preload("res://scripts/gameplay/expedition_host_session.gd")
const Saves := preload("res://scripts/persistence/save_service.gd")
const Offline := preload("res://scripts/persistence/offline_persistence.gd")
const ContentHash := preload("res://scripts/network/content_hash.gd")

const PRIOR: Array[int] = [1, 3, 4, 6, 7, 8]
const CURRENT: Array[int] = [1, 2, 3, 4, 6, 7]
const STAMP: String = "2026-11-23T00:00:00Z"
var _root: String = ""
var _position: Vector3 = Vector3.ZERO


func before_each() -> void:
	Network.clear_host_memory_for_test()
	Cascades.reset_for_test()
	_root = "user://exp018_a03_" + str(Time.get_ticks_usec()) + "_" + str(randi())


func after_each() -> void:
	Network.clear_host_memory_for_test()
	Cascades.reset_for_test()


func _position_for(_player: String) -> Vector3:
	return _position


func _restore(atlas: Dictionary, profile: Dictionary, index: int) -> void:
	var id: String = "LV_%03d" % index
	var level: Dictionary = Atlas.find_level(atlas, id)
	var receipt: Dictionary = Ledger.make_receipt(str(profile["account_key"]),
		id, str(level["tasks"][4]["id"]), "restoration")
	assert_true(bool(Ledger.apply_receipt(profile, receipt, atlas).get("applied", false)))


func _profile(atlas: Dictionary, region: int, account: String) -> Dictionary:
	var profile: Dictionary = Ledger.new_profile(account)
	for prior: int in range(region):
		for slot: int in PRIOR:
			_restore(atlas, profile, 8 * prior + slot)
	for slot: int in CURRENT:
		_restore(atlas, profile, 8 * region + slot)
	return profile


func _save(profile: Dictionary, account: String, stage: String) -> String:
	var service: Saves = Saves.new()
	service.configure(1, Offline.SAVE_BUILD_ID,
		ContentHash.content_revision(), ContentHash.rules_revision())
	var root: String = _root.path_join(account).path_join(stage)
	var path: String = root.path_join("profiles").path_join(account).path_join(
		Ledger.PROFILE_FILE)
	var reply: Dictionary = service.write_record(path, Ledger.KIND_PROFILE,
		account, profile, STAMP)
	assert_true(bool(reply.get("ok", false)), str(reply))
	return root


func _start(region: int, profile: Dictionary, stage: String) -> Dictionary:
	var account: String = str(profile["account_key"])
	var session: Runtime = Runtime.new()
	var started: Dictionary = session.start_exp018_authenticated_finale(
		"LV_%03d" % (8 * region + 8), Callable(self, "_position_for"),
		account, _save(profile, account, stage))
	assert_true(bool(started.get("ok", false)), str(started))
	if not bool(started.get("ok", false)):
		return {}
	var board: String = str(session.worksite.definition_snapshot()["board"])
	_position = session.definition_snapshot()["positions"][board]
	return {"session": session, "board": board, "start": started}


func _send(session: Runtime, seq: int, action: String,
		entity: String) -> Dictionary:
	session.host.tick(seq)
	return session.receive(1, JSON.stringify({
		"session": session.session_id(), "seq": seq,
		"type": "operate_worksite", "entity": entity,
		"payload": {"action": action}
	}).to_utf8_buffer())


func test_EXP018_A03_25_region_finales_bind_original_resources_and_new_cases() -> void:
	var atlas: Dictionary = Atlas.load_catalog()
	var passed: int = 0
	for region: int in range(25):
		Network.clear_host_memory_for_test()
		Cascades.reset_for_test()
		var account: String = "exp018_a03_%02d" % region
		var profile: Dictionary = _profile(atlas, region, account)
		var first: Dictionary = _start(region, profile, "original")
		if first.is_empty():
			continue
		var original: Runtime = first["session"]
		var board: String = str(first["board"])
		assert_true(original.regional_network != null)
		assert_true(original.incident_response != null)
		assert_true(original.advanced_cases != null)
		assert_true(original.advanced_cascade != null)
		assert_true(str(first["start"]["content_revision"]).begins_with("EXP018_A03_"))
		var facts: Dictionary = original.authoritative_state()
		assert_true(facts.has("exp018_advanced_cases"))
		assert_true(facts.has("exp018_advanced_cascade"))
		assert_true(facts.has("exp014_regional_network"))
		assert_eq(original.task_board()["tasks"].size(), 5)
		assert_eq(str(facts["exp018_advanced_cases"]["level_id"]),
			"LV_%03d" % (8 * region + 8))
		var supply_before: int = int(original.regional_network.snapshot()["reserve_pu"])
		var malformed: Dictionary = original.receive(999,
			JSON.stringify({"session": original.session_id(), "seq": 1,
				"type": "operate_worksite", "entity": board,
				"payload": {"action": "regional_critical"}}).to_utf8_buffer())
		assert_false(bool(malformed.get("ok", false)))
		assert_eq(int(original.regional_network.snapshot()["reserve_pu"]), supply_before)
		var approved: Dictionary = _send(original, 1, "regional_critical", board)
		assert_true(bool(approved.get("ok", false)), str(approved))
		assert_eq(int(original.regional_network.snapshot()["reserve_pu"]), supply_before - 2)
		var replacement: Dictionary = _start(region, profile, "successor")
		if replacement.is_empty():
			continue
		var active: Runtime = replacement["session"]
		assert_true(active.regional_network == original.regional_network)
		var after: int = int(active.regional_network.snapshot()["reserve_pu"])
		var replay: Dictionary = _send(original, 1, "regional_critical", board)
		assert_eq(str(replay.get("code", "")), "EXP015_A12_15_STALE_REPLAY")
		assert_eq(int(active.regional_network.snapshot()["reserve_pu"]), after)
		assert_eq(str(original.authoritative_state().get("code", "")),
			"EXP015_A12_13_STALE_HOST_SNAPSHOT")
		assert_true(active.authoritative_state().has("exp018_advanced_cases"))
		passed += 1
		print("EXP018_A03 region=%02d authenticated_case=PASS finite_reserve=PASS stale=DENIED" %
			[region + 1])
	assert_eq(passed, 25)


func test_EXP018_A03_opt_in_fences_unauthenticated_or_nonfinale_requests() -> void:
	var session: Runtime = Runtime.new()
	var invalid: Dictionary = session.start_exp018_authenticated_finale(
		"LV_001", Callable(self, "_position_for"), "ACCOUNT", "user://none")
	assert_eq(str(invalid.get("code", "")), "EXP018_A03_ORIGINAL_FINALE_REQUIRED")
	var anonymous: Dictionary = session.start_exp018_authenticated_finale(
		"LV_008", Callable(self, "_position_for"), "", "user://none")
	assert_eq(str(anonymous.get("code", "")),
		"EXP018_A03_AUTHENTICATED_PROFILE_REQUIRED")
