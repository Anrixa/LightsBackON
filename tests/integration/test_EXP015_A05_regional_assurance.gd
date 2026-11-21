extends "res://tests/test_case.gd"
## A05 exact original 25-region A09 feeder and reserve evidence.
const Atlas := preload("res://scripts/world/dispatch_atlas.gd")
const Ledger := preload("res://scripts/progression/expedition_ledger.gd")
const Network := preload("res://scripts/gameplay/expedition_regional_network.gd")
const Finale := preload("res://scripts/gameplay/expedition_regional_finales.gd")
const Aftercare := preload("res://scripts/gameplay/expedition_regional_aftercare.gd")
const Assurance := preload("res://scripts/gameplay/expedition_regional_assurance.gd")
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
	_root = "user://exp015_a05_" + str(Time.get_ticks_usec()) + "_" + str(randi())


func after_each() -> void:
	Network.clear_host_memory_for_test()


func _position_for(_player: String) -> Vector3:
	return _position


func _restore(profile: Dictionary, atlas: Dictionary, n: int) -> void:
	var level_id: String = "LV_%03d" % n
	var level: Dictionary = Atlas.find_level(atlas, level_id)
	var receipt: Dictionary = Ledger.make_receipt(str(profile["account_key"]),
		level_id, str(level["tasks"][4]["id"]), "restoration")
	assert_true(bool(Ledger.apply_receipt(profile, receipt, atlas).get("applied", false)),
		"Source-authored EXP04 restoration fixture, never an actual played mission")


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
	var level_id: String = "LV_%03d" % (region * 8 + 8)
	var profile: Dictionary = _profile(atlas, region, mode,
		"a05_context_%02d_%s" % [region + 1, mode])
	var network: Network = Network.new()
	var network_gate: Dictionary = network.configure(atlas, profile, level_id)
	assert_true(bool(network_gate.get("ok", false)), str(network_gate))
	if not bool(network_gate.get("ok", false)):
		return {}
	assert_true(bool(network.select_strategy(mode).get("ok", false)))
	var finale: Finale = Finale.new()
	assert_true(bool(finale.configure(
		Finale.entry_for(Finale.load_book(), level_id), network).get("ok", false)))
	var aftercare: Aftercare = Aftercare.new()
	assert_true(bool(aftercare.configure(
		Aftercare.entry_for(Aftercare.load_book(), level_id),
		network, finale).get("ok", false)))
	var assurance: Assurance = Assurance.new()
	var configured: Dictionary = assurance.configure(
		Assurance.entry_for(Assurance.load_book(), level_id), network, aftercare)
	assert_true(bool(configured.get("ok", false)), str(configured))
	if not bool(configured.get("ok", false)):
		return {}
	return {"network": network, "finale": finale,
		"aftercare": aftercare, "assurance": assurance}


func _prepare(finale: Finale, aftercare: Aftercare, mode: String) -> void:
	for action: String in ["finale_assess",
		"finale_critical_verified" if mode == "critical_first" else
			"finale_critical_contingency",
		"finale_buffer" if mode == "critical_first" else "finale_managed",
		"finale_verify", "finale_signoff"]:
		var result: Dictionary = finale.operate(action)
		assert_true(bool(result.get("ok", false)), str(result) + " " + action)
	for action: String in ["aftercare_assess", "aftercare_trip", "aftercare_managed",
		"aftercare_clear", "aftercare_release", "aftercare_reset",
		"aftercare_verify", "aftercare_signoff"]:
		var response: Dictionary = aftercare.operate(action)
		assert_true(bool(response.get("ok", false)), str(response) + " " + action)


func _send(host: Runtime, seq: int, board: String, action: String,
		peer: int = 1) -> Dictionary:
	return host.receive(peer, JSON.stringify({
		"session": host.session_id(), "seq": seq, "type": "operate_worksite",
		"entity": board, "payload": {"action": action}
	}).to_utf8_buffer())


func _start_host(region: int, mode: String, account: String,
		with_assurance: bool) -> Dictionary:
	var atlas: Dictionary = Atlas.load_catalog()
	var profile: Dictionary = _profile(atlas, region, mode, account)
	var saves: Saves = Saves.new()
	saves.configure(1, Offline.SAVE_BUILD_ID,
		ContentHash.content_revision(), ContentHash.rules_revision())
	var root: String = _root.path_join(account)
	var path: String = root.path_join("profiles").path_join(account).path_join(
		Ledger.PROFILE_FILE)
	assert_true(bool(saves.write_record(path, Ledger.KIND_PROFILE,
		account, profile, STAMP).get("ok", false)))
	var host: Runtime = Runtime.new()
	var ready: Dictionary = host.start("LV_%03d" % (region * 8 + 8),
		Callable(self, "_position_for"), Callable(), account, true, root,
		true, true, true, true, true,
		true, true, true, true, true,
		true, true, true, true, true,
		true, true, true, true, with_assurance)
	return {"host": host, "ready": ready}


func test_EXP015_A05_25_source_bound_critical_feeder_definitions() -> void:
	var verdict: Dictionary = Assurance.inspect(Atlas.load_catalog(),
		Assurance.load_book(), Network.load_book(), Aftercare.load_book())
	assert_true(bool(verdict.get("ok", false)), str(verdict))
	assert_eq(int(verdict["regions"]), 25)
	var changed: Dictionary = Assurance.load_book()
	changed["entries"][13]["critical_feeder_id"] = "FAKE"
	assert_false(bool(Assurance.inspect(Atlas.load_catalog(),
		changed, Network.load_book(), Aftercare.load_book()).get("ok", false)))


func test_EXP015_A05_actual_50_critical_and_original_recharge_routes() -> void:
	var total: int = 0
	var viable: Dictionary = {"critical_first": 0, "resilience_first": 0}
	for region: int in range(25):
		for mode: String in ["critical_first", "resilience_first"]:
			var context: Dictionary = _context(region, mode)
			if context.is_empty():
				continue
			var network: Network = context["network"]
			var finale: Finale = context["finale"]
			var aftercare: Aftercare = context["aftercare"]
			var assurance: Assurance = context["assurance"]
			assert_eq(assurance.operate("assurance_assess")["code"],
				"ASSURANCE_AFTERCARE_SIGNOFF_REQUIRED")
			_prepare(finale, aftercare, mode)
			assert_true(aftercare.closed())
			var before: int = int(network.snapshot()["reserve_pu"])
			assert_true(bool(assurance.operate("assurance_assess").get("ok", false)))
			assert_eq(bool(assurance.snapshot()["critical_originally_live"]),
				mode == "critical_first")
			assert_eq(assurance.operate("assurance_trip")["code"],
				"ASSURANCE_FAULT_NOT_AUTHORIZED")
			var recharge: Dictionary = assurance.operate("assurance_recharge")
			if bool(recharge.get("ok", false)):
				viable[mode] = int(viable[mode]) + 1
				assert_true(int(network.snapshot()["reserve_pu"]) >= before)
				assert_true(int(assurance.snapshot()["reserve_recovered_pu"]) > 0)
			else:
				assert_eq(str(recharge.get("code", "")), "RESERVE_RECHARGE_DENIED")
				assert_eq(int(network.snapshot()["reserve_pu"]), before)
				assert_true(bool(assurance.operate("assurance_conserve").get("ok", false)))
			assert_true(bool(assurance.operate("assurance_trip").get("ok", false)))
			assert_false(aftercare.closed(), "critical feeder trip invalidates A03/A04 live proof")
			assert_false(assurance.closed())
			if mode == "critical_first":
				assert_true(bool(assurance.operate("assurance_priority").get("ok", false)))
				assert_eq(int(assurance.snapshot()["managed_pressure_pu"]), 0)
			else:
				assert_eq(assurance.operate("assurance_priority")["code"],
					"ASSURANCE_PRIORITY_REQUIRES_LIVE_CRITICAL")
				assert_true(bool(assurance.operate("assurance_managed").get("ok", false)))
				assert_true(int(assurance.snapshot()["managed_pressure_pu"]) >= 2)
			assert_eq(assurance.operate("assurance_reset")["code"],
				"ASSURANCE_RESET_NOT_READY")
			assert_true(bool(assurance.operate("assurance_clear").get("ok", false)))
			assert_true(bool(assurance.operate("assurance_reset").get("ok", false)))
			assert_true(aftercare.closed())
			assert_true(bool(assurance.operate("assurance_verify").get("ok", false)))
			assert_true(bool(assurance.operate("assurance_signoff").get("ok", false)))
			assert_true(assurance.closed())
			assert_eq(assurance.snapshot()["events"].size(), 8)
			total += 1
			print("EXP015_A05_REPLAY region=%02d mode=%s reserve_policy=%s service=%s" %
				[region + 1, mode, str(assurance.snapshot()["reserve_policy"]),
				str(assurance.snapshot()["service_policy"])])
	assert_eq(total, 50)
	assert_eq(int(viable["critical_first"]), 3)
	assert_eq(int(viable["resilience_first"]), 0)


func test_EXP015_A05_stale_critical_feeder_revokes_signoff() -> void:
	var ctx: Dictionary = _context(0, "critical_first")
	assert_false(ctx.is_empty())
	if ctx.is_empty():
		return
	var network: Network = ctx["network"]
	var assurance: Assurance = ctx["assurance"]
	_prepare(ctx["finale"], ctx["aftercare"], "critical_first")
	for action: String in ["assurance_assess", "assurance_conserve",
		"assurance_trip", "assurance_priority", "assurance_clear",
		"assurance_reset", "assurance_verify", "assurance_signoff"]:
		assert_true(bool(assurance.operate(action).get("ok", false)), action)
	assert_true(assurance.closed())
	var feeder: String = str(assurance.definition_snapshot()["critical_feeder_id"])
	assert_true(bool(network.host_transition("isolate_feeder", feeder).get("ok", false)))
	assert_false(assurance.closed())
	assert_true(bool(network.host_transition("reset_feeder", feeder).get("ok", false)))
	assert_true(assurance.closed())


func test_EXP015_A05_authenticated_host_and_no_premature_rewards() -> void:
	for region: int in [0, 9, 24]:
		Network.clear_host_memory_for_test()
		var account: String = "a05_peer_%02d" % (region + 1)
		var started: Dictionary = _start_host(region, "critical_first", account, true)
		assert_true(bool(started["ready"].get("ok", false)), str(started["ready"]))
		if not bool(started["ready"].get("ok", false)):
			continue
		var host: Runtime = started["host"]
		var board: String = str(host.worksite.definition_snapshot()["board"])
		_position = host.definition_snapshot()["positions"][board]
		assert_true(bool(started["ready"]["regional_assurance_active"]))
		assert_true(str(started["ready"]["content_revision"]).begins_with("EXP015_A05_"))
		assert_false(bool(_send(host, 1, board, "assurance_assess", 999).get("ok", false)))
		assert_eq(_send(host, 1, board, "assurance_assess")["code"],
			"ASSURANCE_AFTERCARE_SIGNOFF_REQUIRED")
		var seq: int = 2
		for action: String in ["regional_critical", "finale_assess",
			"finale_critical_verified", "finale_buffer",
			"finale_verify", "finale_signoff",
			"aftercare_assess", "aftercare_trip", "aftercare_managed",
			"aftercare_clear", "aftercare_release", "aftercare_reset",
			"aftercare_verify", "aftercare_signoff"]:
			var reply: Dictionary = _send(host, seq, board, action)
			assert_true(bool(reply.get("ok", false)), str(reply) + " " + action)
			seq += 1
		assert_eq(str(host._bespoke_guard(Runtime.PLAYER_ID,
			"request_extract", "ZONE_EXTRACT", {}).get("code", "")),
			"EXP015_A05_CRITICAL_ASSURANCE_REQUIRED")
		assert_eq(_send(host, seq, board, "regional_recharge")["code"],
			"EXP015_A05_PROTECTED_RESERVE")
		seq += 1
		for action: String in ["assurance_assess", "assurance_conserve",
			"assurance_trip", "assurance_priority", "assurance_clear",
			"assurance_reset", "assurance_verify", "assurance_signoff"]:
			var reply: Dictionary = _send(host, seq, board, action)
			assert_true(bool(reply.get("ok", false)), str(reply) + " " + action)
			seq += 1
		assert_true(host.regional_assurance.closed())
		assert_true(bool(_send(host, seq - 1, board,
			"assurance_signoff").get("duplicate", false)))
		assert_true(host.authoritative_state().has("exp015_regional_assurance"))
		assert_eq(str(host.task_board()["regional_assurance"]["phase"]), "signed_off")
		assert_false(host.completed())
		assert_eq(host.pending_rewards(account).size(), 0)
		print("EXP015_A05_HOST region=%02d envelope=PASS rewards=0" % (region + 1))


func test_EXP015_A05_opt_out_preserves_A04_wire_and_legacy() -> void:
	var started: Dictionary = _start_host(0, "critical_first", "a05_optout", false)
	assert_true(bool(started["ready"].get("ok", false)), str(started["ready"]))
	if bool(started["ready"].get("ok", false)):
		assert_false(bool(started["ready"]["regional_assurance_active"]))
		assert_true(bool(started["ready"]["regional_aftercare_active"]))
		assert_true(str(started["ready"]["content_revision"]).begins_with("EXP015_A04_"))
