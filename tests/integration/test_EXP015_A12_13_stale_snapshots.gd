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



## A12.14 checks every original region with an obsolete transport owner and
## verifies that the current dispatcher and non-A09 legacy retain normal hooks.
func test_EXP015_A12_14_all_25_regions_block_obsolete_host_lifecycle() -> void:
	var atlas: Dictionary = Atlas.load_catalog()
	var qualified: int = 0
	for region: int in range(25):
		Network.clear_host_memory_for_test()
		var account: String = "a12_14_%02d" % region
		var profile: Dictionary = _profile(atlas, region, account)
		var prior_ctx: Dictionary = _start(region, profile, "prior_lifecycle")
		if prior_ctx.is_empty():
			continue
		var prior: Runtime = prior_ctx["session"]
		var old_manifest: Dictionary = prior.host.snapshot()["manifest"]
		var original_member: String = prior.host.member(1)
		assert_false(original_member.is_empty())
		var current_ctx: Dictionary = _start(region, profile, "current_lifecycle")
		if current_ctx.is_empty():
			continue
		var current: Runtime = current_ctx["session"]
		var revision_before: int = prior.host.revision
		var hash_before: String = prior.host.state_hash()
		var denied: Dictionary = prior.host.admit(2, "PEER_2",
			int(old_manifest["protocol_version"]),
			str(old_manifest["content_revision"]), [] as Array[String])
		assert_eq(str(denied.get("code", "")),
			"EXP015_A12_14_STALE_HOST_LIFECYCLE")
		denied = prior.host.confirm_synced(1, prior.host.revision)
		assert_eq(str(denied.get("code", "")),
			"EXP015_A12_14_STALE_HOST_LIFECYCLE")
		denied = prior.host.begin_after_briefing()
		assert_eq(str(denied.get("code", "")),
			"EXP015_A12_14_STALE_HOST_LIFECYCLE")
		assert_eq(prior.host.set_in_zone(original_member, "ZONE_EXTRACT", true), [])
		assert_eq(prior.host.remove(1), [])
		assert_eq(prior.host.member(1), original_member,
			"obsolete teardown cannot rewrite previous host membership")
		assert_eq(prior.host.revision, revision_before)
		assert_eq(prior.host.state_hash(), hash_before,
			"old authority remains a stable stale marker")
		var current_manifest: Dictionary = current.host.snapshot()["manifest"]
		var live_join: Dictionary = current.host.admit(2, "PEER_2",
			int(current_manifest["protocol_version"]),
			str(current_manifest["content_revision"]), [] as Array[String])
		assert_true(bool(live_join.get("ok", false)), str(live_join))
		assert_true(bool(current.host.confirm_synced(2,
			current.host.revision).get("ok", false)))
		current.host.remove(2)
		assert_eq(current.host.member(2), "")
		qualified += 1
		print("EXP015_A12_14 region=%02d old_transport=DENIED current=PASS" %
			[region + 1])
	assert_eq(qualified, 25)


func test_EXP015_A12_14_non_regional_transport_lifecycle_unchanged() -> void:
	var legacy: Runtime = Runtime.new()
	var started: Dictionary = legacy.start("LV_001", Callable(self, "_position_for"))
	assert_true(bool(started.get("ok", false)), str(started))
	if not bool(started.get("ok", false)):
		return
	assert_true(legacy.regional_network == null)
	var manifest: Dictionary = legacy.host.snapshot()["manifest"]
	var join: Dictionary = legacy.host.admit(2, "PEER_2",
		int(manifest["protocol_version"]),
		str(manifest["content_revision"]), [] as Array[String])
	assert_true(bool(join.get("ok", false)), str(join))
	assert_true(bool(legacy.host.confirm_synced(2,
		legacy.host.revision).get("ok", false)))
	legacy.host.remove(2)
	assert_eq(legacy.host.member(2), "")



## A12.15 hostile reuse of host setup methods and cached command replies.
func _a12_15_permit_all(_player: String, _kind: String,
		_entity: String, _payload: Dictionary) -> Dictionary:
	return {"ok": true}


func _a12_15_bypass_epoch() -> bool:
	return true


func test_EXP015_A12_15_25_regions_reject_rebound_guards_and_cached_success() -> void:
	var atlas: Dictionary = Atlas.load_catalog()
	var qualified: int = 0
	for region: int in range(25):
		Network.clear_host_memory_for_test()
		var account: String = "a12_15_%02d" % region
		var profile: Dictionary = _profile(atlas, region, account)
		var old_ctx: Dictionary = _start(region, profile, "replay_old")
		if old_ctx.is_empty():
			continue
		var old: Runtime = old_ctx["session"]
		var old_board: String = str(old_ctx["board"])
		var first_command: Dictionary = {
			"session": old.session_id(), "seq": 1,
			"type": "operate_worksite", "entity": old_board,
			"payload": {"action": "regional_critical"}
		}
		old.host.tick(1)
		var initial: Dictionary = old.receive(1,
			JSON.stringify(first_command).to_utf8_buffer())
		assert_true(bool(initial.get("ok", false)),
			"original accepted action required before preemption: " + str(initial))
		var network: Network = old.regional_network
		var reserve_after_first: int = int(network.snapshot()["reserve_pu"])
		var successor_ctx: Dictionary = _start(region, profile, "replay_new")
		if successor_ctx.is_empty():
			continue
		var successor: Runtime = successor_ctx["session"]
		assert_true(successor.regional_network == network)
		var stale_revision: int = old.host.revision
		var stale_hash: String = old.host.state_hash()
		# Public setup methods cannot transform an old owner into a new one.
		old.host.set_expedition_tick_authority(Callable())
		old.host.set_expedition_tick_authority(
			Callable(self, "_a12_15_bypass_epoch"))
		old.host.set_expedition_intent_guard(Callable())
		old.host.set_expedition_intent_guard(
			Callable(self, "_a12_15_permit_all"))
		assert_eq(str(old.host.snapshot().get("code", "")),
			"EXP015_A12_13_STALE_HOST_SNAPSHOT")
		assert_eq(old.host.tick(2), [])
		var replayed: Dictionary = old.receive(1,
			JSON.stringify(first_command).to_utf8_buffer())
		assert_eq(str(replayed.get("code", "")),
			"EXP015_A12_15_STALE_REPLAY")
		assert_false(bool(replayed.get("ok", false)),
			"old successful reply must not resurface after replacement")
		var fresh_command: Dictionary = first_command.duplicate(true)
		fresh_command["seq"] = 2
		var denied: Dictionary = old.receive(1,
			JSON.stringify(fresh_command).to_utf8_buffer())
		assert_eq(str(denied.get("code", "")),
			"EXP015_A12_9_STALE_HOST_DISPATCH")
		assert_eq(old.host.revision, stale_revision)
		assert_eq(old.host.state_hash(), stale_hash)
		assert_eq(int(network.snapshot()["reserve_pu"]), reserve_after_first,
			"no stale replay may charge finite original reserve")
		var live: Dictionary = successor.host.snapshot()
		assert_true(live.has("manifest"), str(live))
		qualified += 1
		print("EXP015_A12_15 region=%02d bind_once=PASS replay=DENIED" %
			[region + 1])
	assert_eq(qualified, 25)


func test_EXP015_A12_15_legacy_duplicate_reply_remains_idempotent() -> void:
	var legacy: Runtime = Runtime.new()
	var started: Dictionary = legacy.start("LV_001",
		Callable(self, "_position_for"))
	assert_true(bool(started.get("ok", false)), str(started))
	if not bool(started.get("ok", false)):
		return
	assert_true(legacy.regional_network == null)
	_position = legacy.definition_snapshot()["positions"]["PANEL_WEST"]
	legacy.host.tick(1)
	var intent: Dictionary = {"session": legacy.session_id(), "seq": 1,
		"type": "inspect", "entity": "PANEL_WEST", "payload": {}}
	var raw: PackedByteArray = JSON.stringify(intent).to_utf8_buffer()
	var first: Dictionary = legacy.receive(1, raw)
	assert_true(bool(first.get("ok", false)), str(first))
	var replayed: Dictionary = legacy.receive(1, raw)
	assert_true(bool(replayed.get("ok", false)), str(replayed))
	assert_true(bool(replayed.get("duplicate", false)),
		"legacy clients must still receive exact replay acknowledgements")
