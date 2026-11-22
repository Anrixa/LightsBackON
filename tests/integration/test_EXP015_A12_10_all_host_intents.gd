extends "res://tests/test_case.gd"
## EXP015 A12.10 — authenticated ingress rejects EVERY stale host intent,
## not merely worksite and extraction. Legacy C01–C12 paths remain opt-out.
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
const ORDINARY: Array[String] = [
	"inspect", "toggle_switch", "recover_self", "collect_lore",
	"operate_device", "operate_fault", "operate_consequence",
	"operate_logistics", "operate_balance", "repair_step",
	"use_ladder", "use_route", "request_lock", "release"
]
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


func test_EXP015_A12_10_25_regions_all_authenticated_stale_intents_denied() -> void:
	var atlas: Dictionary = Atlas.load_catalog()
	var qualified: int = 0
	for region: int in range(25):
		Network.clear_host_memory_for_test()
		var account: String = "a12_10_%02d" % region
		var profile: Dictionary = _profile(atlas, region, account)
		var original: Dictionary = _start(region, profile, "old")
		if original.is_empty():
			continue
		var old: Runtime = original["session"]
		var network: Network = old.regional_network
		var current_ctx: Dictionary = _start(region, profile, "new")
		if current_ctx.is_empty():
			continue
		var current: Runtime = current_ctx["session"]
		assert_true(current.regional_network == network)
		assert_eq(network.current_dispatch_epoch(), 2)
		var before: Dictionary = network.snapshot()
		# A foreign peer or forged session is still refused by SessionHost
		# BEFORE the new guard. Security checks must not be weakened.
		assert_eq(str(_send(old, 1, "inspect", "PANEL_WEST",
			{}, 999).get("code", "")), "UNKNOWN_PEER")
		assert_eq(str(_send(old, 1, "inspect", "PANEL_WEST",
			{}, 1, "WRONG_SESSION").get("code", "")), "WRONG_SESSION")
		var seq: int = 1
		for kind: String in ORDINARY:
			var denied: Dictionary = _send(old, seq, kind, "PANEL_WEST")
			assert_eq(str(denied.get("code", "")),
				"EXP015_A12_10_STALE_HOST_INTENT",
				"authenticated stale " + kind + " passed on region " + str(region))
			assert_false(bool(denied.get("ok", false)))
			seq += 1
		var worksite: Dictionary = _send(old, seq, "operate_worksite",
			str(original["board"]), {"action": "regional_critical"})
		assert_eq(str(worksite.get("code", "")),
			"EXP015_A12_9_STALE_HOST_DISPATCH")
		seq += 1
		var extraction: Dictionary = _send(old, seq, "request_extract", "")
		assert_eq(str(extraction.get("code", "")),
			"EXP015_A12_9_STALE_HOST_DISPATCH")
		seq += 1
		var anchor: Dictionary = _send(old, seq, "operate_worksite",
			str(original["board"]), {"action": "anchor_audit"})
		assert_eq(str(anchor.get("code", "")), "ANCHOR_DISPATCH_CONTEXT_EXPIRED")
		# Dedupe replays only a refusal, never produces source side effects.
		var duplicate: Dictionary = _send(old, seq, "operate_worksite",
			str(original["board"]), {"action": "anchor_audit"})
		assert_true(bool(duplicate.get("duplicate", false)))
		assert_eq(str(duplicate.get("code", "")), "ANCHOR_DISPATCH_CONTEXT_EXPIRED")
		assert_eq(network.snapshot(), before)
		assert_eq(network.current_dispatch_epoch(), 2)
		assert_eq(old.pending_rewards(account).size(), 0)
		assert_eq(current.pending_rewards(account).size(), 0)
		# An actually current authenticated intent must still operate.
		var valid: Dictionary = _send(current, 1, "operate_worksite",
			str(current_ctx["board"]), {"action": "regional_critical"})
		assert_true(bool(valid.get("ok", false)), str(valid))
		assert_eq(int(network.snapshot()["reserve_pu"]),
			int(before["reserve_pu"]) - 2)
		qualified += 1
		print("EXP015_A12_10 region=%02d stale_intent_guard=PASS" % [region + 1])
	assert_eq(qualified, 25)
