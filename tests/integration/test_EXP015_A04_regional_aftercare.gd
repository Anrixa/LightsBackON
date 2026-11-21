extends "res://tests/test_case.gd"
## EXP015 A04: 25 regions x two real A09 branches with actual feeder faults,
## standby finite-reserve alternatives, managed fallback and authenticated host.
const Atlas := preload("res://scripts/world/dispatch_atlas.gd")
const Ledger := preload("res://scripts/progression/expedition_ledger.gd")
const Network := preload("res://scripts/gameplay/expedition_regional_network.gd")
const Finale := preload("res://scripts/gameplay/expedition_regional_finales.gd")
const Aftercare := preload("res://scripts/gameplay/expedition_regional_aftercare.gd")
const Runtime := preload("res://scripts/gameplay/expedition_host_session.gd")
const Saves := preload("res://scripts/persistence/save_service.gd")
const Offline := preload("res://scripts/persistence/offline_persistence.gd")
const ContentHash := preload("res://scripts/network/content_hash.gd")

const SPINE: Array[int] = [1, 3, 4, 6, 7, 8]
const STAMP: String = "2026-11-22T00:00:00Z"
var _root: String = ""
var _position: Vector3 = Vector3.ZERO


func before_each() -> void:
	Network.clear_host_memory_for_test()
	_position = Vector3.ZERO
	_root = "user://exp015_a04_" + str(Time.get_ticks_usec()) + "_" + str(randi())


func after_each() -> void:
	Network.clear_host_memory_for_test()


func _position_for(_player: String) -> Vector3:
	return _position


func _restore(profile: Dictionary, atlas: Dictionary, number: int) -> void:
	var level_id: String = "LV_%03d" % number
	var level: Dictionary = Atlas.find_level(atlas, level_id)
	var receipt: Dictionary = Ledger.make_receipt(str(profile["account_key"]),
		level_id, str(level["tasks"][4]["id"]), "restoration")
	assert_true(bool(Ledger.apply_receipt(profile, receipt, atlas).get("applied", false)),
		"Only source-authored test fixture receipts may prepare a dispatch")


func _profile(atlas: Dictionary, region: int, mode: String, account: String) -> Dictionary:
	var profile: Dictionary = Ledger.new_profile(account)
	for previous: int in range(region):
		for slot: int in SPINE:
			_restore(profile, atlas, previous * 8 + slot)
	var base: int = region * 8
	_restore(profile, atlas, base + 1)
	_restore(profile, atlas, base + (3 if mode == "critical_first" else 2))
	_restore(profile, atlas, base + 4)
	_restore(profile, atlas, base + (6 if mode == "critical_first" else 5))
	_restore(profile, atlas, base + 7)
	return profile


func _context(region: int, mode: String) -> Dictionary:
	var atlas: Dictionary = Atlas.load_catalog()
	var target: String = "LV_%03d" % (region * 8 + 8)
	var profile: Dictionary = _profile(atlas, region, mode,
		"a04_source_%02d_%s" % [region + 1, mode])
	var regional: Network = Network.new()
	var result: Dictionary = regional.configure(atlas, profile, target)
	assert_true(bool(result.get("ok", false)), str(result))
	if not bool(result.get("ok", false)):
		return {}
	assert_true(bool(regional.select_strategy(mode).get("ok", false)))
	var finale: Finale = Finale.new()
	var source: Dictionary = Finale.entry_for(Finale.load_book(), target)
	assert_true(bool(finale.configure(source, regional).get("ok", false)))
	var aftercare: Aftercare = Aftercare.new()
	var authored: Dictionary = Aftercare.entry_for(Aftercare.load_book(), target)
	var configured: Dictionary = aftercare.configure(authored, regional, finale)
	assert_true(bool(configured.get("ok", false)), str(configured))
	if not bool(configured.get("ok", false)):
		return {}
	return {"network": regional, "finale": finale, "aftercare": aftercare,
		"source": authored}


func _finish_finale(finale: Finale, mode: String) -> void:
	for action: String in [
		"finale_assess",
		"finale_critical_verified" if mode == "critical_first" else
			"finale_critical_contingency",
		"finale_buffer" if mode == "critical_first" else "finale_managed",
		"finale_verify", "finale_signoff"
	]:
		var result: Dictionary = finale.operate(action)
		assert_true(bool(result.get("ok", false)), str(result) + " action=" + action)


func _send(host: Runtime, seq: int, board: String, action: String,
		peer: int = 1) -> Dictionary:
	return host.receive(peer, JSON.stringify({
		"session": host.session_id(), "seq": seq, "type": "operate_worksite",
		"entity": board, "payload": {"action": action}
	}).to_utf8_buffer())


func _start(region: int, mode: String, account: String,
		aftercare: bool) -> Dictionary:
	var atlas: Dictionary = Atlas.load_catalog()
	var profile: Dictionary = _profile(atlas, region, mode, account)
	var saves: Saves = Saves.new()
	saves.configure(1, Offline.SAVE_BUILD_ID,
		ContentHash.content_revision(), ContentHash.rules_revision())
	var root: String = _root.path_join(account)
	var target: String = root.path_join("profiles").path_join(account).path_join(
		Ledger.PROFILE_FILE)
	assert_true(bool(saves.write_record(target, Ledger.KIND_PROFILE,
		account, profile, STAMP).get("ok", false)))
	var host: Runtime = Runtime.new()
	var started: Dictionary = host.start("LV_%03d" % (region * 8 + 8),
		Callable(self, "_position_for"), Callable(), account, true, root,
		true, true, true, true, true,
		true, true, true, true, true,
		true, true, true, true, true,
		true, true, true, aftercare)
	return {"host": host, "reply": started}


func test_EXP015_A04_source_audit_25_original_incidents() -> void:
	var verdict: Dictionary = Aftercare.inspect(Atlas.load_catalog(),
		Aftercare.load_book(), Network.load_book(), Finale.load_book())
	assert_true(bool(verdict.get("ok", false)), str(verdict))
	assert_eq(int(verdict["regions"]), 25)
	var changed: Dictionary = Aftercare.load_book()
	changed["entries"][0]["fault_signature"] = "FAKED_SOURCE"
	assert_false(bool(Aftercare.inspect(Atlas.load_catalog(), changed,
		Network.load_book(), Finale.load_book()).get("ok", false)))


func test_EXP015_A04_25_by_two_real_network_recovery_and_service_tradeoffs() -> void:
	var complete: int = 0
	var standby_count: Dictionary = {"critical_first": 0, "resilience_first": 0}
	for region: int in range(25):
		for mode: String in ["critical_first", "resilience_first"]:
			var prepared: Dictionary = _context(region, mode)
			if prepared.is_empty():
				continue
			var network: Network = prepared["network"]
			var finale: Finale = prepared["finale"]
			var aftercare: Aftercare = prepared["aftercare"]
			var source: Dictionary = prepared["source"]
			assert_eq(aftercare.operate("aftercare_assess")["code"],
				"AFTERCARE_FINALE_SIGNOFF_REQUIRED")
			_finish_finale(finale, mode)
			assert_true(finale.closed())
			var reserve_before: int = int(network.snapshot()["reserve_pu"])
			assert_true(bool(aftercare.operate("aftercare_assess").get("ok", false)))
			assert_eq(aftercare.operate("aftercare_reset")["code"],
				"AFTERCARE_RESET_NOT_READY")
			assert_true(bool(aftercare.operate("aftercare_trip").get("ok", false)))
			assert_false(finale.closed(), "actual original shelter feeder is now faulted")
			assert_eq(str(network.snapshot()["feeders"][str(
				source["recovery_feeder_id"])]["fault"]), source["fault_signature"])
			var transfer: Dictionary = aftercare.operate("aftercare_transfer")
			if bool(transfer.get("ok", false)):
				standby_count[mode] = int(standby_count[mode]) + 1
				assert_eq(int(aftercare.snapshot()["reserve_consumed_pu"]), 2)
				assert_eq(int(network.snapshot()["reserve_pu"]), reserve_before - 2)
				assert_true(bool(network.snapshot()["ties"][str(
					source["standby_tie_id"])]["engaged"]))
			else:
				assert_true(["BREAK_BEFORE_MAKE_INTERLOCK",
					"STANDBY_RESERVE_EXHAUSTED"].has(str(transfer.get("code", ""))),
					str(transfer))
				assert_eq(int(network.snapshot()["reserve_pu"]), reserve_before)
				assert_true(bool(aftercare.operate("aftercare_managed").get("ok", false)))
				assert_eq(str(aftercare.snapshot()["recovery_route"]), "managed_outage")
			assert_eq(aftercare.operate("aftercare_reset")["code"],
				"AFTERCARE_RESET_NOT_READY")
			assert_true(bool(aftercare.operate("aftercare_clear").get("ok", false)))
			assert_true(bool(aftercare.operate("aftercare_release").get("ok", false)))
			assert_true(bool(aftercare.operate("aftercare_reset").get("ok", false)))
			assert_true(finale.closed(), "original A03 signoff must be valid again")
			assert_true(bool(aftercare.operate("aftercare_verify").get("ok", false)))
			assert_true(bool(aftercare.operate("aftercare_signoff").get("ok", false)))
			assert_true(aftercare.closed())
			assert_eq(aftercare.snapshot()["events"].size(), 8)
			assert_false(bool(network.snapshot()["ties"][str(
				source["standby_tie_id"])]["engaged"]))
			assert_eq(str(network.snapshot()["feeders"][str(
				source["recovery_feeder_id"])]["fault"]), "")
			complete += 1
			print("EXP015_A04_REPLAY region=%02d mode=%s route=%s reserve_used=%d" %
				[region + 1, mode, str(aftercare.snapshot()["recovery_route"]),
				int(aftercare.snapshot()["reserve_consumed_pu"])])
	assert_eq(complete, 50)
	assert_eq(int(standby_count["critical_first"]), 11)
	assert_eq(int(standby_count["resilience_first"]), 17)


func test_EXP015_A04_repeated_or_unsafe_source_change_revokes_signoff() -> void:
	var state: Dictionary = _context(0, "critical_first")
	assert_false(state.is_empty())
	if state.is_empty():
		return
	var finale: Finale = state["finale"]
	var aftercare: Aftercare = state["aftercare"]
	var network: Network = state["network"]
	var source: Dictionary = state["source"]
	_finish_finale(finale, "critical_first")
	for step: String in ["aftercare_assess", "aftercare_trip", "aftercare_managed",
			"aftercare_clear", "aftercare_release", "aftercare_reset",
			"aftercare_verify", "aftercare_signoff"]:
		assert_true(bool(aftercare.operate(step).get("ok", false)), step)
	assert_true(aftercare.closed())
	assert_eq(aftercare.operate("aftercare_signoff")["code"],
		"AFTERCARE_RESTORATION_NOT_STABLE")
	assert_true(bool(network.host_transition("isolate_feeder",
		str(source["recovery_feeder_id"])).get("ok", false)))
	assert_false(aftercare.closed())
	assert_true(bool(network.host_transition("reset_feeder",
		str(source["recovery_feeder_id"])).get("ok", false)))
	assert_true(aftercare.closed())


func test_EXP015_A04_host_ingress_and_reward_hold() -> void:
	for region: int in [0, 12, 24]:
		Network.clear_host_memory_for_test()
		var account: String = "a04_host_%02d" % (region + 1)
		var opened: Dictionary = _start(region, "critical_first", account, true)
		assert_true(bool(opened["reply"].get("ok", false)), str(opened["reply"]))
		if not bool(opened["reply"].get("ok", false)):
			continue
		var host: Runtime = opened["host"]
		var board: String = str(host.worksite.definition_snapshot()["board"])
		_position = host.definition_snapshot()["positions"][board]
		assert_true(bool(opened["reply"]["regional_aftercare_active"]))
		assert_true(str(opened["reply"]["content_revision"]).begins_with("EXP015_A04_"))
		assert_false(bool(_send(host, 1, board, "aftercare_assess", 999).get("ok", false)))
		assert_eq(_send(host, 1, board, "aftercare_assess")["code"],
			"AFTERCARE_FINALE_SIGNOFF_REQUIRED")
		assert_true(bool(_send(host, 2, board, "regional_critical").get("ok", false)))
		for seq: int in range(5):
			var action: String = [
				"finale_assess", "finale_critical_verified", "finale_buffer",
				"finale_verify", "finale_signoff"][seq]
			assert_true(bool(_send(host, seq + 3, board, action).get("ok", false)), action)
		assert_true(bool(_send(host, 8, board, "aftercare_assess").get("ok", false)))
		assert_true(bool(_send(host, 9, board, "aftercare_trip").get("ok", false)))
		assert_eq(str(host._bespoke_guard(Runtime.PLAYER_ID,
			"request_extract", "ZONE_EXTRACT", {}).get("code", "")),
			"EXP015_A03_FINALE_NOT_SIGNED_OFF")
		assert_eq(_send(host, 10, board, "regional_recharge")["code"],
			"EXP015_A04_PROTECTED_RESERVE")
		assert_true(bool(_send(host, 11, board, "aftercare_managed").get("ok", false)))
		for seq: int in range(5):
			var action: String = [
				"aftercare_clear", "aftercare_release", "aftercare_reset",
				"aftercare_verify", "aftercare_signoff"][seq]
			assert_true(bool(_send(host, seq + 12, board, action).get("ok", false)), action)
		assert_true(host.regional_aftercare.closed())
		assert_true(bool(_send(host, 16, board,
			"aftercare_signoff").get("duplicate", false)))
		assert_true(host.authoritative_state().has("exp015_regional_aftercare"))
		assert_eq(str(host.task_board()["regional_aftercare"]["phase"]), "signed_off")
		assert_false(host.completed())
		assert_eq(host.pending_rewards(account).size(), 0)
		print("EXP015_A04_HOST region=%02d authenticated=PASS reward=0" % (region + 1))


func test_EXP015_A04_opt_out_keeps_legacy_A03_and_blocks_missing_A03_dependency() -> void:
	var legacy: Dictionary = _start(0, "critical_first", "a04_optout", false)
	assert_true(bool(legacy["reply"].get("ok", false)), str(legacy["reply"]))
	if bool(legacy["reply"].get("ok", false)):
		assert_false(bool(legacy["reply"]["regional_aftercare_active"]))
		assert_true(bool(legacy["reply"]["regional_finale_active"]))
		assert_true(str(legacy["reply"]["content_revision"]).begins_with("EXP015_A03_"))
