extends "res://tests/test_case.gd"
## EXP015 A12.13 — obsolete session cannot publish live successor source.
const Atlas := preload("res://scripts/world/dispatch_atlas.gd")
const Ledger := preload("res://scripts/progression/expedition_ledger.gd")
const Network := preload("res://scripts/gameplay/expedition_regional_network.gd")
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
	_root = "user://exp015_a12_10_" + str(Time.get_ticks_usec()) + "_" + str(randi())
	_position = Vector3.ZERO


func after_each() -> void:
	Network.clear_host_memory_for_test()


func _position_for(_player: String) -> Vector3:
	return _position


func _restore(atlas: Dictionary, profile: Dictionary, index: int) -> void:
	var site: String = "LV_%03d" % index
	var level: Dictionary = Atlas.find_level(atlas, site)
	var receipt: Dictionary = Ledger.make_receipt(str(profile["account_key"]),
		site, str(level["tasks"][4]["id"]), "restoration")
	assert_true(bool(Ledger.apply_receipt(profile, receipt, atlas).get("applied", false)),
		"host-only EXP04 fixture receipt rejected")


func _profile(atlas: Dictionary, region: int, account: String) -> Dictionary:
	var profile: Dictionary = Ledger.new_profile(account)
	for prior: int in range(region):
		for slot: int in PRIOR:
			_restore(atlas, profile, 8 * prior + slot)
	for slot: int in CURRENT:
		_restore(atlas, profile, 8 * region + slot)
	return profile


func _save(profile: Dictionary, account: String, stage: String) -> String:
	var storage: Saves = Saves.new()
	storage.configure(1, Offline.SAVE_BUILD_ID,
		ContentHash.content_revision(), ContentHash.rules_revision())
	var root: String = _root.path_join(account).path_join(stage)
	var path: String = root.path_join("profiles").path_join(account).path_join(
		Ledger.PROFILE_FILE)
	var result: Dictionary = storage.write_record(path, Ledger.KIND_PROFILE,
		account, profile, STAMP)
	assert_true(bool(result.get("ok", false)), str(result))
	return root


func _start(region: int, profile: Dictionary, stage: String) -> Dictionary:
	var account: String = str(profile["account_key"])
	var level: String = "LV_%03d" % (8 * region + 8)
	var session: Runtime = Runtime.new()
	var started: Dictionary = session.start(level,
		Callable(self, "_position_for"), Callable(), account, true,
		_save(profile, account, stage),
		true, true, true, true, true,
		true, true, true, true, true,
		true, true, true, true, true,
		true, true, true, true, true,
		false, false, false, true, true)
	assert_true(bool(started.get("ok", false)), str(started))
	if not bool(started.get("ok", false)):
		return {}
	assert_true(str(started["content_revision"]).begins_with("EXP015_A12_9_"))
	var board: String = str(session.worksite.definition_snapshot()["board"])
	_position = session.definition_snapshot()["positions"][board]
	return {"session": session, "board": board}


func _send(session: Runtime, seq: int, kind: String, entity: String,
		payload: Dictionary = {}, peer: int = 1,
		session_override: String = "") -> Dictionary:
	session.host.tick(seq)
	return session.receive(peer, JSON.stringify({
		"session": session.session_id() if session_override.is_empty() \
			else session_override,
		"seq": seq, "type": kind, "entity": entity, "payload": payload
	}).to_utf8_buffer())




## This original finale lacks the first-junction A01 incident. The host
## passes network acquisition first, then fails in incident recipe checking.
func _start_invalid(region: int, profile: Dictionary, stage: String) -> Dictionary:
	var account: String = str(profile["account_key"])
	var level: String = "LV_%03d" % (8 * region + 8)
	var candidate: Runtime = Runtime.new()
	var failed: Dictionary = candidate.start(level,
		Callable(self, "_position_for"), Callable(), account, true,
		_save(profile, account, stage),
		true, true, true, true, true,
		true, true, true, true, true,
		true, true, true, true, true,
		true, false, false, false, false,
		false, false, false, false, false)
	return {"runtime": candidate, "result": failed}



func test_EXP015_A12_13_25_region_stale_host_snapshots_fail_closed() -> void:
	var atlas: Dictionary = Atlas.load_catalog()
	var passed: int = 0
	for region: int in range(25):
		Network.clear_host_memory_for_test()
		var account: String = "a12_13_%02d" % region
		var profile: Dictionary = _profile(atlas, region, account)
		var original: Dictionary = _start(region, profile, "old")
		if original.is_empty():
			continue
		var old: Runtime = original["session"]
		var first_snapshot: Dictionary = old.host.snapshot()
		assert_true(first_snapshot.has("manifest"),
			"active original host must still publish its source")
		var network: Network = old.regional_network
		var current_ctx: Dictionary = _start(region, profile, "new")
		if current_ctx.is_empty():
			continue
		var current: Runtime = current_ctx["session"]
		assert_true(current.regional_network == network)
		assert_eq(network.current_dispatch_epoch(), 2)
		var before: Dictionary = network.snapshot()
		var refused: Dictionary = old.host.snapshot()
		assert_eq(str(refused.get("code", "")),
			"EXP015_A12_13_STALE_HOST_SNAPSHOT")
		assert_eq(old.host.publish(), {},
			"obsolete host must emit no newly republished delta")
		assert_eq(old.host.authoritative_state(),
			{"authority": "EXP015_A12_13_STALE_HOST_SNAPSHOT"})
		assert_eq(str(old.authoritative_state().get("code", "")),
			"EXP015_A12_13_STALE_HOST_SNAPSHOT")
		assert_eq(str(old.task_board().get("code", "")),
			"EXP015_A12_13_STALE_HOST_SNAPSHOT")
		assert_eq(str(old._worksite_snapshot().get("code", "")),
			"EXP015_A12_13_STALE_HOST_SNAPSHOT")
		var old_hash: String = old.state_hash()
		# Current authenticated host may still publish its actual source
		# and spend only the original finite reserve.
		var live: Dictionary = current.host.snapshot()
		assert_true(live.has("manifest"), str(live))
		var operated: Dictionary = _send(current, 1, "operate_worksite",
			str(current_ctx["board"]), {"action": "regional_critical"})
		assert_true(bool(operated.get("ok", false)), str(operated))
		assert_eq(int(network.snapshot()["reserve_pu"]),
			int(before["reserve_pu"]) - 2)
		assert_eq(old.state_hash(), old_hash,
			"successor source changes must not affect obsolete host hash")
		assert_eq(old.host.publish(), {})
		assert_eq(str(old.host.snapshot().get("code", "")),
			"EXP015_A12_13_STALE_HOST_SNAPSHOT")
		var current_source: Dictionary = current.authoritative_state()
		assert_true(current_source.has("exp014_regional_network"))
		assert_eq(int(current_source["exp014_regional_network"]["reserve_pu"]),
			int(before["reserve_pu"]) - 2)
		passed += 1
		print("EXP015_A12_13 region=%02d stale_replication=DENIED current=PASS" %
			[region + 1])
	assert_eq(passed, 25)


func test_EXP015_A12_13_no_A09_legacy_snapshots_still_work() -> void:
	var original: Runtime = Runtime.new()
	var started: Dictionary = original.start("LV_001",
		Callable(self, "_position_for"))
	assert_true(bool(started.get("ok", false)), str(started))
	if not bool(started.get("ok", false)):
		return
	assert_true(original.regional_network == null)
	var manifest: Dictionary = original.host.snapshot()
	assert_true(manifest.has("manifest"), str(manifest))
	var state: Dictionary = original.authoritative_state()
	assert_true(state.has("grid"))
	assert_false(state.has("authority"))
	assert_true(original.task_board().get("ok", false))
