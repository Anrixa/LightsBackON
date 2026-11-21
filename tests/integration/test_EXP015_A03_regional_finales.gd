extends "res://tests/test_case.gd"
## EXP015 A03: actual host-owned finale decision replays, 25 regions x 2 forks.
## Source/headless only: no human/controller, real grid solver or release claim.
const Atlas := preload("res://scripts/world/dispatch_atlas.gd")
const Ledger := preload("res://scripts/progression/expedition_ledger.gd")
const Network := preload("res://scripts/gameplay/expedition_regional_network.gd")
const Finale := preload("res://scripts/gameplay/expedition_regional_finales.gd")
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
	_root = "user://exp015_a03_" + str(Time.get_ticks_usec()) + "_" + str(randi())


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
		"Test-only source-authored restoration fixture required: " + level_id)


func _profile(atlas: Dictionary, region: int, mode: String,
		account: String, stage: int = 8) -> Dictionary:
	var profile: Dictionary = Ledger.new_profile(account)
	for previous: int in range(region):
		for slot: int in SPINE:
			_restore(profile, atlas, previous * 8 + slot)
	var base: int = region * 8
	_restore(profile, atlas, base + 1)
	_restore(profile, atlas, base + (3 if mode == "critical_first" else 2))
	if stage >= 7:
		_restore(profile, atlas, base + 4)
		_restore(profile, atlas, base + (6 if mode == "critical_first" else 5))
	if stage >= 8:
		_restore(profile, atlas, base + 7)
	return profile


func _context(atlas: Dictionary, book: Dictionary, region: int, mode: String) -> Dictionary:
	var target: String = "LV_%03d" % (region * 8 + 8)
	var profile: Dictionary = _profile(atlas, region, mode,
		"a03_r%02d_%s" % [region + 1, mode])
	var regional: Network = Network.new()
	var configured: Dictionary = regional.configure(atlas, profile, target)
	assert_true(bool(configured.get("ok", false)), str(configured))
	if not bool(configured.get("ok", false)):
		return {}
	var selected: Dictionary = regional.select_strategy(mode)
	assert_true(bool(selected.get("ok", false)), str(selected))
	if not bool(selected.get("ok", false)):
		return {}
	var finale: Finale = Finale.new()
	var source: Dictionary = Finale.entry_for(book, target)
	var started: Dictionary = finale.configure(source, regional)
	assert_true(bool(started.get("ok", false)), str(started))
	if not bool(started.get("ok", false)):
		return {}
	return {"regional": regional, "finale": finale, "source": source}


func _send(host: Runtime, seq: int, board: String, action: String,
		peer: int = 1) -> Dictionary:
	return host.receive(peer, JSON.stringify({
		"session": host.session_id(), "seq": seq, "type": "operate_worksite",
		"entity": board, "payload": {"action": action}
	}).to_utf8_buffer())


func _start(region: int, mode: String, account: String, stage: int,
		incident: bool, cascade: bool, finale: bool) -> Dictionary:
	var atlas: Dictionary = Atlas.load_catalog()
	var profile: Dictionary = _profile(atlas, region, mode, account, stage)
	var saves: Saves = Saves.new()
	saves.configure(1, Offline.SAVE_BUILD_ID,
		ContentHash.content_revision(), ContentHash.rules_revision())
	var root: String = _root.path_join(account).path_join("slot_%d" % stage)
	var target: String = root.path_join("profiles").path_join(account).path_join(
		Ledger.PROFILE_FILE)
	var written: Dictionary = saves.write_record(target, Ledger.KIND_PROFILE,
		account, profile, STAMP)
	assert_true(bool(written.get("ok", false)), str(written))
	var host: Runtime = Runtime.new()
	var started: Dictionary = host.start("LV_%03d" % (region * 8 + stage),
		Callable(self, "_position_for"), Callable(), account, true, root,
		true, true, true, true, true,
		true, true, true, true, true,
		true, true, true, true, true,
		incident, cascade, finale)
	return {"host": host, "reply": started}


func test_EXP015_A03_all_25_source_bindings_refuse_forged_finale_feeders() -> void:
	var atlas: Dictionary = Atlas.load_catalog()
	var original: Dictionary = Finale.load_book()
	var regional: Dictionary = Network.load_book()
	assert_eq(Finale.inspect(atlas, original, regional)["regions"], 25)
	for i: int in range(25):
		assert_eq(str(original["entries"][i]["finale_site_id"]),
			"LV_%03d" % ((i + 1) * 8))
		var forged: Dictionary = original.duplicate(true)
		forged["entries"][i]["critical_feeder_id"] = "FORGED_FEEDER"
		assert_eq(Finale.inspect(atlas, forged, regional)["code"],
			"FINALE_FEEDER_PROVENANCE_MISMATCH")
	var bad: Dictionary = original.duplicate(true)
	bad["entries"][5]["risk_closeout_protocol"] = "COSMETIC_ONLY"
	assert_eq(Finale.inspect(atlas, bad, regional)["code"],
		"FINALE_RISK_PROTOCOL_MISMATCH")
	bad = original.duplicate(true)
	bad["entries"][12]["finale_site_id"] = "LV_999"
	assert_eq(Finale.inspect(atlas, bad, regional)["code"],
		"FINALE_ORIGINAL_SITE_SOURCE_MISMATCH")


func test_EXP015_A03_all_50_actual_host_network_strategies_close_with_distinct_debt() -> void:
	var atlas: Dictionary = Atlas.load_catalog()
	var book: Dictionary = Finale.load_book()
	var finalized: int = 0
	var critical_ready: int = 0
	var resilience_ready: int = 0
	for region: int in range(25):
		for mode: String in ["critical_first", "resilience_first"]:
			var context: Dictionary = _context(atlas, book, region, mode)
			if context.is_empty():
				continue
			var finale: Finale = context["finale"]
			var network: Network = context["regional"]
			var source: Dictionary = context["source"]
			var before: Dictionary = network.snapshot()
			assert_eq(finale.operate("finale_buffer")["code"],
				"FINALE_SHELTER_PRECONDITION_INVALID")
			assert_eq(finale.operate("finale_signoff")["code"],
				"FINALE_RESTORATION_NOT_VERIFIED")
			assert_true(bool(finale.operate("finale_assess").get("ok", false)))
			var live: bool = bool(before["sites"][str(source["critical_service_site"])]["energized"])
			var ready: bool = bool(before["site_conditions"]["supply_ready"])
			assert_eq(live, mode == "critical_first")
			if live:
				assert_eq(finale.operate("finale_critical_contingency")["code"],
					"FINALE_CONTINGENCY_NOT_REQUIRED")
				assert_true(bool(finale.operate("finale_critical_verified").get("ok", false)))
				assert_eq(int(finale.snapshot()["critical_contingency_pressure"]), 0)
			else:
				assert_eq(finale.operate("finale_critical_verified")["code"],
					"FINALE_CRITICAL_ENERGIZATION_MISSING")
				assert_true(bool(finale.operate("finale_critical_contingency").get("ok", false)))
				assert_eq(int(finale.snapshot()["critical_contingency_pressure"]),
					int(source["critical_dark_pressure_pu"]))
			var shelter_action: String = "finale_buffer" if mode == "critical_first" else "finale_managed"
			assert_true(bool(finale.operate(shelter_action).get("ok", false)))
			assert_true(network.site_prepared())
			assert_eq(int(finale.snapshot()["reserve_consumed"]),
				(0 if ready else 2) if mode == "critical_first" else 0)
			assert_eq(int(finale.snapshot()["shelter_service_pressure"]),
				(0 if ready else 2) if mode == "resilience_first" else 0)
			assert_eq(int(network.snapshot()["reserve_pu"]),
				int(before["reserve_pu"]) - int(finale.snapshot()["reserve_consumed"]))
			assert_eq(finale.operate("finale_signoff")["code"],
				"FINALE_RESTORATION_NOT_VERIFIED")
			assert_true(bool(finale.operate("finale_verify").get("ok", false)))
			assert_true(bool(finale.operate("finale_signoff").get("ok", false)))
			assert_true(finale.closed())
			assert_eq(finale.snapshot()["events"].size(), 5)
			assert_eq(finale.operate("finale_signoff")["code"],
				"FINALE_RESTORATION_NOT_VERIFIED")
			critical_ready += int(ready) if mode == "critical_first" else 0
			resilience_ready += int(ready) if mode == "resilience_first" else 0
			finalized += 1
			print("EXP015_A03_CLOSEOUT region=%02d mode=%s shelter_ready=%s reserve_spent=%d critical_debt=%d" %
				[region + 1, mode, str(ready),
				int(finale.snapshot()["reserve_consumed"]),
				int(finale.snapshot()["critical_contingency_pressure"])])
	assert_eq(finalized, 50)
	assert_eq(critical_ready, 7)
	assert_eq(resilience_ready, 12)


func test_EXP015_A03_attested_state_revokes_if_actual_feeder_changes() -> void:
	var context: Dictionary = _context(
		Atlas.load_catalog(), Finale.load_book(), 0, "critical_first")
	assert_false(context.is_empty())
	if context.is_empty():
		return
	var finale: Finale = context["finale"]
	var network: Network = context["regional"]
	var source: Dictionary = context["source"]
	for action: String in [
		"finale_assess", "finale_critical_verified", "finale_buffer",
		"finale_verify", "finale_signoff"
	]:
		assert_true(bool(finale.operate(action).get("ok", false)), action)
	assert_true(finale.closed())
	assert_true(finale.protects_original_action("regional_buffer"))
	assert_true(finale.protects_original_action("regional_managed"))
	assert_true(finale.protects_original_action(
		"regional_isolate:" + str(source["critical_feeder_id"]) + ":spoof"))
	assert_true(finale.protects_original_action(
		"regional_release:" + str(source["shelter_standby_tie_id"])))
	assert_false(finale.protects_original_action("regional_recharge"))
	assert_false(finale.protects_original_action("regional_isolate:OTHER_FEEDER"))
	assert_true(bool(network.host_transition("isolate_feeder",
		str(source["shelter_feeder_id"])).get("ok", false)))
	assert_false(finale.closed(), "attested seal must not survive unsafe feeder state")
	assert_true(bool(network.host_transition("reset_feeder",
		str(source["shelter_feeder_id"])).get("ok", false)))
	assert_true(finale.closed(), "safe network repair should restore proof validity")


func test_EXP015_A03_authenticated_host_actions_and_extraction_hold() -> void:
	for region: int in [0, 9, 24]:
		for mode: String in ["critical_first", "resilience_first"]:
			var account: String = "a03_host_%02d_%s" % [region + 1, mode]
			var opened: Dictionary = _start(region, mode, account, 8, true, true, true)
			assert_true(bool(opened["reply"].get("ok", false)), str(opened["reply"]))
			if not bool(opened["reply"].get("ok", false)):
				continue
			var host: Runtime = opened["host"]
			var result: Dictionary = opened["reply"]
			assert_true(bool(result["regional_finale_active"]))
			assert_false(bool(result["incident_response_active"]))
			assert_false(bool(result["service_cascade_active"]))
			assert_true(str(result["content_revision"]).begins_with("EXP015_A03_"))
			var board: String = str(host.worksite.definition_snapshot()["board"])
			_position = host.definition_snapshot()["positions"][board]
			var before: Dictionary = host.regional_finale.snapshot()
			assert_false(bool(_send(host, 1, board, "finale_assess", 999).get("ok", false)))
			assert_eq(host.regional_finale.snapshot(), before)
			assert_eq(_send(host, 1, board, "finale_assess")["code"],
				"FINALE_STRATEGY_REQUIRED")
			assert_true(bool(_send(host, 2, board,
				"regional_critical" if mode == "critical_first" else "regional_resilience").get("ok", false)))
			assert_eq(_send(host, 3, board, "regional_managed")["code"],
				"EXP015_A03_PROTECTED_NETWORK_ASSET")
			assert_true(bool(_send(host, 4, board, "finale_assess").get("ok", false)))
			assert_true(bool(_send(host, 5, board,
				"finale_critical_verified" if mode == "critical_first" else
				"finale_critical_contingency").get("ok", false)))
			assert_true(bool(_send(host, 6, board,
				"finale_buffer" if mode == "critical_first" else "finale_managed").get("ok", false)))
			assert_eq(str(host._bespoke_guard(Runtime.PLAYER_ID,
				"request_extract", "ZONE_EXTRACT", {}).get("code", "")),
				"EXP015_A03_FINALE_NOT_SIGNED_OFF")
			assert_false(host.completed())
			assert_eq(host.pending_rewards(account).size(), 0)
			assert_true(bool(_send(host, 7, board, "finale_verify").get("ok", false)))
			assert_true(bool(_send(host, 8, board, "finale_signoff").get("ok", false)))
			assert_true(host.regional_finale.closed())
			assert_true(bool(_send(host, 8, board, "finale_signoff").get("duplicate", false)))
			assert_eq(host.regional_finale.snapshot()["events"].size(), 5)
			var original: Dictionary = host.regional_network.snapshot()
			var original_feeder: String = str(host.regional_finale.definition_snapshot()["shelter_feeder_id"])
			assert_eq(str(_send(host, 9, board,
				"regional_isolate:" + original_feeder + ":suffix").get("code", "")),
				"EXP015_A03_PROTECTED_NETWORK_ASSET")
			assert_eq(host.regional_network.snapshot(), original)
			assert_true(host.authoritative_state().has("exp015_regional_finale"))
			assert_eq(str(host.task_board()["regional_finale"]["phase"]), "signed_off")
			assert_ne(str(host._bespoke_guard(Runtime.PLAYER_ID,
				"request_extract", "ZONE_EXTRACT", {}).get("code", "")),
				"EXP015_A03_FINALE_NOT_SIGNED_OFF")
			assert_false(host.completed(), "finale signoff never substitutes mission extraction")
			assert_eq(host.pending_rewards(account).size(), 0)
			print("EXP015_A03_AUTH_HOST region=%02d mode=%s approved=5 rewards=0" %
				[region + 1, mode])


func test_EXP015_A03_three_flags_coexist_at_the_original_three_junctions() -> void:
	for stage: int in [4, 7, 8]:
		Network.clear_host_memory_for_test()
		var opened: Dictionary = _start(0, "resilience_first",
			"a03_coexist_%02d" % stage, stage, true, true, true)
		assert_true(bool(opened["reply"].get("ok", false)), str(opened["reply"]))
		if not bool(opened["reply"].get("ok", false)):
			continue
		assert_eq(bool(opened["reply"]["incident_response_active"]), stage == 4)
		assert_eq(bool(opened["reply"]["service_cascade_active"]), stage == 7)
		assert_eq(bool(opened["reply"]["regional_finale_active"]), stage == 8)
		var expected: String = ("EXP015_A01_" if stage == 4 else
			"EXP015_A02_" if stage == 7 else "EXP015_A03_")
		assert_true(str(opened["reply"]["content_revision"]).begins_with(expected))
	var legacy: Dictionary = _start(0, "critical_first",
		"a03_legacy", 8, false, false, false)
	assert_true(bool(legacy["reply"].get("ok", false)), str(legacy["reply"]))
	if bool(legacy["reply"].get("ok", false)):
		assert_false(bool(legacy["reply"]["regional_finale_active"]))
		assert_true(str(legacy["reply"]["content_revision"]).begins_with("EXP014_A09_"))
		assert_false(legacy["host"].task_board().has("regional_finale"))
	var denied: Runtime = Runtime.new()
	var gate: Dictionary = denied.start("LV_008", Callable(self, "_position_for"),
		Callable(), "", false, "",
		false, false, false, false, false,
		false, false, false, false, false,
		false, false, false, false, false,
		false, false, true)
	assert_eq(str(gate.get("code", "")), "EXP015_A03_REQUIRES_A09_REGIONAL_NETWORK")
