extends "res://tests/test_case.gd"
## EXP015 A12.11 — prevent superseded original regional host ticks and
## new reward accrual, preserving legitimate preemption-era receipt drain.
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



func test_EXP015_A12_11_25_regions_stale_tick_reward_and_receipt_continuity() -> void:
	var atlas: Dictionary = Atlas.load_catalog()
	var qualified: int = 0
	for region: int in range(25):
		Network.clear_host_memory_for_test()
		var account: String = "a12_11_%02d" % region
		var profile: Dictionary = _profile(atlas, region, account)
		var old_ctx: Dictionary = _start(region, profile, "old")
		if old_ctx.is_empty():
			continue
		var old: Runtime = old_ctx["session"]
		var network: Network = old.regional_network
		# Use an actual authenticated inspection to earn a genuine original
		# EXP04 task receipt BEFORE the next dispatch takes over.
		_position = old.definition_snapshot()["positions"]["PANEL_WEST"]
		var inspected: Dictionary = _send(old, 1, "inspect", "PANEL_WEST")
		assert_true(bool(inspected.get("ok", false)), str(inspected))
		var earned: Array[Dictionary] = old.pending_rewards(account)
		assert_true(earned.size() > 0, "valid preemption receipt was not issued")
		var warm: Dictionary = old.tick_host()
		assert_true(bool(warm.get("ok", false)), str(warm))
		var old_ticks: int = old._tick
		var old_hash: String = old.state_hash()
		var new_ctx: Dictionary = _start(region, profile, "new")
		if new_ctx.is_empty():
			continue
		var current: Runtime = new_ctx["session"]
		assert_true(current.regional_network == network)
		assert_eq(network.current_dispatch_epoch(), 2)
		var source_before: Dictionary = network.snapshot()
		# All three host-only paths must refuse obsolete lifecycle changes.
		for attempt: int in range(3):
			var denied: Dictionary = old.tick_host()
			assert_false(bool(denied.get("ok", false)))
			assert_eq(str(denied.get("code", "")),
				"EXP015_A12_11_STALE_HOST_LIFECYCLE")
		assert_eq(old._tick, old_ticks)
		var events: Array[Dictionary] = old.host.tick(100)
		assert_eq(events.size(), 0, "direct old SessionHost.tick advanced the world")
		assert_eq(old.state_hash(), old_hash)
		assert_eq(network.snapshot(), source_before)
		# A test-local forged completion cannot accrue a new reward, even
		# if a stale callback tries to execute the reward/progress path.
		old._completed[str(old._tasks[3]["id"])] = true
		old._issue_task_rewards()
		old._update_progress()
		assert_eq(old.pending_rewards(account), earned,
			"preemption must not mint or remove pending receipts")
		# Previously earned receipts remain available for exactly-once
		# delivery and acknowledgement; they must not be discarded.
		old.ack_reward(account, str(earned[0]["receipt_key"]))
		assert_eq(old.pending_rewards(account).size(), earned.size() - 1)
		assert_eq(network.snapshot(), source_before)
		var fresh_tick: Dictionary = current.tick_host()
		assert_true(bool(fresh_tick.get("ok", false)), str(fresh_tick))
		var restored: Dictionary = _send(current, 1, "operate_worksite",
			str(new_ctx["board"]), {"action": "regional_critical"})
		assert_true(bool(restored.get("ok", false)), str(restored))
		assert_eq(int(network.snapshot()["reserve_pu"]),
			int(source_before["reserve_pu"]) - 2)
		qualified += 1
		print("EXP015_A12_11 region=%02d old_tick=FENCED earned_receipt=PRESERVED fresh_host=PASS" %
			[region + 1])
	assert_eq(qualified, 25)


func test_EXP015_A12_11_session_without_A09_keeps_host_tick_authority() -> void:
	var session: Runtime = Runtime.new()
	var started: Dictionary = session.start("LV_001",
		Callable(self, "_position_for"))
	assert_true(bool(started.get("ok", false)), str(started))
	if not bool(started.get("ok", false)):
		return
	assert_true(session.regional_network == null)
	var ticked: Dictionary = session.tick_host()
	assert_true(bool(ticked.get("ok", false)), str(ticked))
	assert_eq(int(ticked.get("tick", 0)), 1)
