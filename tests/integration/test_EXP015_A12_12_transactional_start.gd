extends "res://tests/test_case.gd"
## EXP015 A12.12 — failed session startup cannot preempt the original network.
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


func test_EXP015_A12_12_25_regions_late_failure_preserves_live_owner() -> void:
	var atlas: Dictionary = Atlas.load_catalog()
	var passed: int = 0
	for region: int in range(25):
		Network.clear_host_memory_for_test()
		var account: String = "a12_12_%02d" % region
		var profile: Dictionary = _profile(atlas, region, account)
		var started: Dictionary = _start(region, profile, "live")
		if started.is_empty():
			continue
		var live: Runtime = started["session"]
		var network: Network = live.regional_network
		var before: Dictionary = network.snapshot()
		var epoch: int = network.current_dispatch_epoch()
		assert_eq(epoch, 1)
		# This verified new restoration receipt would be applied by
		# refresh_receipts() during the failed takeover.
		var expanded: Dictionary = profile.duplicate(true)
		_restore(atlas, expanded, 8 * region + 5)
		var denied: Dictionary = _start_invalid(region, expanded, "aborted")
		assert_eq(str(denied["result"].get("code", "")),
			"EXP015_SITE_NOT_AUTHORED")
		assert_true(denied["runtime"].regional_network == null)
		assert_true(live.regional_network == network)
		assert_eq(network.current_dispatch_epoch(), epoch)
		assert_eq(network.snapshot(), before,
			"failed startup changed original receipt, epoch or source state")
		assert_true(live._regional_dispatch_current())
		_position = live.definition_snapshot()["positions"][str(started["board"])]
		var live_action: Dictionary = _send(live, 1, "operate_worksite",
			str(started["board"]), {"action": "regional_critical"})
		assert_true(bool(live_action.get("ok", false)), str(live_action))
		assert_eq(int(network.snapshot()["reserve_pu"]),
			int(before["reserve_pu"]) - 2)
		passed += 1
		print("EXP015_A12_12 region=%02d failed_preempt=ROLLED_BACK live_host=PASS" %
			[region + 1])
	assert_eq(passed, 25)


func test_EXP015_A12_12_failed_first_registration_does_not_orphan_network() -> void:
	var atlas: Dictionary = Atlas.load_catalog()
	var account: String = "a12_12_first"
	var profile: Dictionary = _profile(atlas, 0, account)
	var rejected: Dictionary = _start_invalid(0, profile, "failed")
	assert_eq(str(rejected["result"].get("code", "")), "EXP015_SITE_NOT_AUTHORED")
	assert_true(rejected["runtime"].regional_network == null)
	var first: Dictionary = Network.acquire(atlas, profile, "LV_008")
	assert_true(bool(first.get("ok", false)), str(first))
	if not bool(first.get("ok", false)):
		return
	assert_false(bool(first.get("reused", true)), "aborted host left source registered")
	assert_eq(first["network"].current_dispatch_epoch(), 1)
	var next: Dictionary = Network.acquire(atlas, profile, "LV_008")
	assert_true(bool(next.get("reused", false)))
	assert_eq(first["network"].current_dispatch_epoch(), 2)
