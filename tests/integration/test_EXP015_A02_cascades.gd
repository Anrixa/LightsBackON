extends "res://tests/test_case.gd"
## EXP015 A02: 25 second-junction faults, managed recovery and real standby.
## Source/headless only: no physical, Steam, production saves or release claim.

const Atlas := preload("res://scripts/world/dispatch_atlas.gd")
const Ledger := preload("res://scripts/progression/expedition_ledger.gd")
const Regional := preload("res://scripts/gameplay/expedition_regional_network.gd")
const Cascade := preload("res://scripts/gameplay/expedition_regional_cascades.gd")
const Runtime := preload("res://scripts/gameplay/expedition_host_session.gd")
const Saves := preload("res://scripts/persistence/save_service.gd")
const Offline := preload("res://scripts/persistence/offline_persistence.gd")
const ContentHash := preload("res://scripts/network/content_hash.gd")

const SPINE: Array[int] = [1, 3, 4, 6, 7, 8]
const STAMP: String = "2026-11-22T00:00:00Z"
var _position: Vector3 = Vector3.ZERO
var _root: String = ""


func before_each() -> void:
	Regional.clear_host_memory_for_test()
	_position = Vector3.ZERO
	_root = "user://exp015_a02_" + str(Time.get_ticks_usec()) + "_" + str(randi())


func after_each() -> void:
	Regional.clear_host_memory_for_test()


func _host_position(_player: String) -> Vector3:
	return _position


func _restore(profile: Dictionary, atlas: Dictionary, index: int) -> void:
	var level_id: String = "LV_%03d" % index
	var level: Dictionary = Atlas.find_level(atlas, level_id)
	var receipt: Dictionary = Ledger.make_receipt(str(profile["account_key"]),
		level_id, str(level["tasks"][4]["id"]), "restoration")
	assert_true(bool(Ledger.apply_receipt(profile, receipt, atlas).get("applied", false)),
		"Source-authored EXP04 restoration proof required: %s" % level_id)


func _profile(atlas: Dictionary, region: int, mode: String, account: String,
		first_join_only: bool = false) -> Dictionary:
	var profile: Dictionary = Ledger.new_profile(account)
	for earlier: int in range(region):
		for slot: int in SPINE:
			_restore(profile, atlas, earlier * 8 + slot)
	var base: int = region * 8
	_restore(profile, atlas, base + 1)
	_restore(profile, atlas, base + (2 if mode == "resilience_first" else 3))
	if not first_join_only:
		_restore(profile, atlas, base + 4)
		_restore(profile, atlas, base + (5 if mode == "resilience_first" else 6))
	return profile


func _context(atlas: Dictionary, book: Dictionary,
		region: int, mode: String) -> Dictionary:
	var site_id: String = "LV_%03d" % (region * 8 + 7)
	var profile: Dictionary = _profile(atlas, region, mode,
		"cascade_r%02d_%s" % [region + 1, mode])
	var net: Regional = Regional.new()
	var created: Dictionary = net.configure(atlas, profile, site_id)
	assert_true(bool(created.get("ok", false)), str(created))
	if not bool(created.get("ok", false)):
		return {}
	var chosen: Dictionary = net.select_strategy(mode)
	assert_true(bool(chosen.get("ok", false)), str(chosen))
	var response: Cascade = Cascade.new()
	var recipe: Dictionary = Cascade.entry_for(book, site_id)
	var setup: Dictionary = response.configure(recipe, net)
	assert_true(bool(setup.get("ok", false)), str(setup))
	if not bool(setup.get("ok", false)):
		return {}
	return {"response": response, "regional": net, "recipe": recipe}


func _send(host: Runtime, seq: int, board: String, action: String,
		peer: int = 1) -> Dictionary:
	return host.receive(peer, JSON.stringify({
		"session": host.session_id(), "seq": seq, "type": "operate_worksite",
		"entity": board, "payload": {"action": action}
	}).to_utf8_buffer())


func _start(region: int, mode: String, account: String, join: int,
		both_enabled: bool, cascade_enabled: bool) -> Dictionary:
	var atlas: Dictionary = Atlas.load_catalog()
	var saves: Saves = Saves.new()
	saves.configure(1, Offline.SAVE_BUILD_ID,
		ContentHash.content_revision(), ContentHash.rules_revision())
	var path: String = _root.path_join("r%02d" % region).path_join(account)
	var profile: Dictionary = _profile(atlas, region, mode, account, join == 4)
	var saved: Dictionary = saves.write_record(path.path_join("profiles").path_join(
		account).path_join(Ledger.PROFILE_FILE),
		Ledger.KIND_PROFILE, account, profile, STAMP)
	assert_true(bool(saved.get("ok", false)), str(saved))
	var host: Runtime = Runtime.new()
	var began: Dictionary = host.start("LV_%03d" % (region * 8 + join),
		Callable(self, "_host_position"), Callable(), account, true, path,
		true, true, true, true, true,
		true, true, true, true, true,
		true, true, true, true, true,
		both_enabled, cascade_enabled)
	return {"host": host, "reply": began}


func test_EXP015_A02_all_25_source_fault_cascades_require_original_risk_proofs() -> void:
	var atlas: Dictionary = Atlas.load_catalog()
	var network_book: Dictionary = Regional.load_book()
	var book: Dictionary = Cascade.load_book()
	assert_eq(Cascade.inspect(atlas, book, network_book)["junctions"], 25)
	for index: int in range(25):
		var source: Dictionary = book["entries"][index]
		assert_eq(str(source["junction_site_id"]), "LV_%03d" % (index * 8 + 7))
		var changed: Dictionary = book.duplicate(true)
		changed["entries"][index]["original_fault_signature"] = "FAKE"
		assert_eq(Cascade.inspect(atlas, changed, network_book)["code"],
			"CASCADE_SOURCE_IDENTITY")
	var broken: Dictionary = book.duplicate(true)
	broken["entries"][3]["backfeed_tie_id"] = "NET_FAKE_TIE"
	assert_eq(Cascade.inspect(atlas, broken, network_book)["code"],
		"CASCADE_TIE_SOURCE")
	broken = book.duplicate(true)
	broken["entries"][8]["normal_feeder_id"] = "NET_FAKE_FEEDER"
	assert_eq(Cascade.inspect(atlas, broken, network_book)["code"],
		"CASCADE_PRIMARY_SOURCE")
	broken = book.duplicate(true)
	broken["entries"][12]["managed_service_pressure"] = -1
	assert_eq(Cascade.inspect(atlas, broken, network_book)["code"],
		"CASCADE_RISK_PROOF")


func test_EXP015_A02_all_25_managed_fault_chains_have_real_clear_and_reset() -> void:
	var atlas: Dictionary = Atlas.load_catalog()
	var book: Dictionary = Cascade.load_book()
	var validated: int = 0
	for region: int in range(25):
		var context: Dictionary = _context(atlas, book, region, "resilience_first")
		if context.is_empty():
			continue
		var response: Cascade = context["response"]
		var network: Regional = context["regional"]
		var recipe: Dictionary = context["recipe"]
		var feeder: String = str(recipe["normal_feeder_id"])
		var reserve: int = int(network.snapshot()["reserve_pu"])
		assert_eq(response.operate("cascade_trip")["code"],
			"CASCADE_ASSESSMENT_REQUIRED")
		assert_true(bool(response.operate("cascade_assess").get("ok", false)))
		assert_true(bool(response.operate("cascade_trip").get("ok", false)))
		assert_eq(network.snapshot()["feeders"][feeder]["fault"],
			recipe["original_fault_signature"])
		assert_eq(network.host_transition("reset_feeder", feeder)["code"],
			"FEEDER_RESET_DENIED")
		assert_eq(response.operate("cascade_clear")["code"],
			"CASCADE_PREPARATION_REQUIRED")
		assert_true(bool(response.operate("cascade_managed").get("ok", false)))
		assert_true(bool(response.operate("cascade_prepare").get("ok", false)))
		assert_true(bool(response.operate("cascade_clear").get("ok", false)))
		assert_true(bool(response.operate("cascade_reconnect").get("ok", false)))
		assert_true(bool(response.operate("cascade_attest").get("ok", false)))
		assert_true(response.resolved())
		assert_eq(response.snapshot()["response_mode"], "controlled_shedding")
		assert_true(int(response.snapshot()["service_pressure"]) >=
			int(recipe["managed_service_pressure"]))
		assert_eq(int(network.snapshot()["reserve_pu"]), reserve)
		assert_eq(str(network.snapshot()["feeders"][feeder]["fault"]), "")
		assert_false(bool(network.snapshot()["feeders"][feeder]["isolated"]))
		assert_eq(response.snapshot()["events"].size(), 7)
		assert_eq(response.operate("cascade_attest")["code"],
			"CASCADE_SAFE_NORMAL_REQUIRED")
		validated += 1
		print("EXP015_A02_MANAGED region=%02d mode=shedding pressure=%d reserve=%d" %
			[region + 1, int(response.snapshot()["service_pressure"]), reserve])
	assert_eq(validated, 25)


func test_EXP015_A02_live_standby_paths_consume_reserve_without_double_arrival() -> void:
	var atlas: Dictionary = Atlas.load_catalog()
	var book: Dictionary = Cascade.load_book()
	var successful: int = 0
	var unavailable: int = 0
	for region: int in range(25):
		var context: Dictionary = _context(atlas, book, region, "critical_first")
		if context.is_empty():
			continue
		var response: Cascade = context["response"]
		var network: Regional = context["regional"]
		var recipe: Dictionary = context["recipe"]
		assert_true(bool(response.operate("cascade_assess").get("ok", false)))
		assert_true(bool(response.operate("cascade_trip").get("ok", false)))
		var before: Dictionary = network.snapshot()
		var result: Dictionary = response.operate("cascade_backfeed")
		if not bool(result.get("ok", false)):
			assert_eq(result["code"], "BREAK_BEFORE_MAKE_INTERLOCK")
			assert_eq(response.snapshot()["phase"], "fault_isolated")
			assert_eq(network.snapshot(), before)
			assert_true(bool(response.operate("cascade_managed").get("ok", false)))
			unavailable += 1
			continue
		assert_eq(int(network.snapshot()["reserve_pu"]), int(before["reserve_pu"]) - 2)
		assert_eq(int(response.snapshot()["reserve_spent"]), 2)
		assert_true(bool(network.snapshot()["ties"][str(recipe["backfeed_tie_id"])]["engaged"]))
		assert_eq(network.host_transition("reset_feeder",
			str(recipe["normal_feeder_id"]))["code"], "FEEDER_RESET_DENIED")
		assert_eq(response.operate("cascade_backfeed")["code"],
			"CASCADE_FAULT_ISOLATION_REQUIRED")
		assert_eq(int(network.snapshot()["reserve_pu"]), int(before["reserve_pu"]) - 2)
		assert_true(bool(response.operate("cascade_prepare").get("ok", false)))
		assert_true(bool(response.operate("cascade_clear").get("ok", false)))
		assert_eq(network.host_transition("reset_feeder",
			str(recipe["normal_feeder_id"]))["code"], "BREAK_BEFORE_MAKE_INTERLOCK")
		assert_true(bool(response.operate("cascade_reconnect").get("ok", false)))
		assert_false(bool(network.snapshot()["ties"][
			str(recipe["backfeed_tie_id"])]["engaged"]))
		assert_true(bool(response.operate("cascade_attest").get("ok", false)))
		assert_eq(int(network.snapshot()["reserve_pu"]), int(before["reserve_pu"]) - 2)
		successful += 1
		print("EXP015_A02_BACKFEED region=%02d mode=standby reserve_spent=2" %
			[region + 1])
	assert_true(successful >= 5, "Original source requires multiple truly live backfeed routes")
	assert_eq(successful + unavailable, 25)


func test_EXP015_A02_invalid_fault_recovery_proof_never_bypasses_containment() -> void:
	var context: Dictionary = _context(
		Atlas.load_catalog(), Cascade.load_book(), 0, "critical_first")
	assert_false(context.is_empty())
	var response: Cascade = context["response"]
	var network: Regional = context["regional"]
	var feeder: String = str(context["recipe"]["normal_feeder_id"])
	assert_true(bool(response.operate("cascade_assess").get("ok", false)))
	assert_true(bool(response.operate("cascade_trip").get("ok", false)))
	assert_true(bool(response.operate("cascade_managed").get("ok", false)))
	assert_true(bool(response.operate("cascade_prepare").get("ok", false)))
	var state: Dictionary = network.snapshot()
	assert_eq(network.host_transition("clear_fault", feeder, "CLIENT_PROOF")["code"],
		"UNVERIFIED_RECOVERY")
	assert_eq(network.snapshot(), state)
	assert_eq(response.operate("cascade_reconnect")["code"],
		"CASCADE_FAULT_CLEARANCE_REQUIRED")
	assert_true(bool(response.operate("cascade_clear").get("ok", false)))
	assert_true(bool(response.operate("cascade_reconnect").get("ok", false)))
	assert_true(bool(response.operate("cascade_attest").get("ok", false)))


func test_EXP015_A02_authenticated_host_cascade_replay_and_no_premature_rewards() -> void:
	for region: int in [0, 9, 24]:
		var opened: Dictionary = _start(region, "resilience_first",
			"exp015_a02_host_%02d" % (region + 1), 7, true, true)
		var begun: Dictionary = opened["reply"]
		assert_true(bool(begun.get("ok", false)), str(begun))
		if not bool(begun.get("ok", false)):
			continue
		var host: Runtime = opened["host"]
		assert_true(bool(begun["service_cascade_active"]))
		assert_false(bool(begun["incident_response_active"]))
		assert_true(str(begun["content_revision"]).begins_with("EXP015_A02_"))
		var board: String = str(host.worksite.definition_snapshot()["board"])
		_position = host.definition_snapshot()["positions"][board]
		var start_state: Dictionary = host.service_cascade.snapshot()
		assert_false(bool(_send(host, 1, board, "cascade_assess", 999).get("ok", false)))
		assert_eq(host.service_cascade.snapshot(), start_state)
		assert_eq(_send(host, 1, board, "cascade_trip")["code"],
			"CASCADE_ASSESSMENT_REQUIRED")
		assert_true(bool(_send(host, 2, board, "regional_resilience").get("ok", false)))
		assert_true(bool(_send(host, 3, board, "cascade_assess").get("ok", false)))
		assert_true(bool(_send(host, 4, board, "cascade_trip").get("ok", false)))
		assert_true(bool(_send(host, 5, board, "cascade_managed").get("ok", false)))
		assert_true(bool(_send(host, 6, board, "cascade_prepare").get("ok", false)))
		assert_eq(str(host._bespoke_guard(Runtime.PLAYER_ID,
			"request_extract", "ZONE_EXTRACT", {}).get("code", "")),
			"EXP015_A02_CASCADE_UNRESOLVED")
		assert_false(host.completed())
		assert_eq(host.pending_rewards("exp015_a02_host_%02d" % (region + 1)).size(), 0)
		assert_true(bool(_send(host, 7, board, "cascade_clear").get("ok", false)))
		assert_true(bool(_send(host, 8, board, "cascade_reconnect").get("ok", false)))
		assert_true(bool(_send(host, 9, board, "cascade_attest").get("ok", false)))
		assert_true(host.service_cascade.resolved())
		assert_true(bool(_send(host, 9, board, "cascade_attest").get("duplicate", false)))
		assert_eq(host.service_cascade.snapshot()["events"].size(), 7)
		assert_true(host.authoritative_state().has("exp015_service_cascade"))
		assert_eq(str(host.task_board()["service_cascade"]["phase"]), "attested")
		var protected: Dictionary = host.service_cascade.definition_snapshot()
		var safe: Dictionary = host.regional_network.snapshot()
		assert_eq(str(_send(host, 10, board,
			"regional_isolate:" + str(protected["normal_feeder_id"])).get("code", "")),
			"EXP015_A02_PROTECTED_NETWORK_ASSET")
		assert_eq(str(_send(host, 11, board,
			"regional_engage:" + str(protected["backfeed_tie_id"])).get("code", "")),
			"EXP015_A02_PROTECTED_NETWORK_ASSET")
		assert_eq(host.regional_network.snapshot(), safe,
			"the original board must not invalidate an attested cascade")
		assert_ne(str(host._bespoke_guard(Runtime.PLAYER_ID,
			"request_extract", "ZONE_EXTRACT", {}).get("code", "")),
			"EXP015_A02_CASCADE_UNRESOLVED")
		assert_false(host.completed(), "Cascade closed is not a completed mission")
		assert_eq(host.pending_rewards("exp015_a02_host_%02d" % (region + 1)).size(), 0)
		print("EXP015_A02_HOST region=%02d authenticated=true 7_approved=7 rewards=0" %
			[region + 1])


func test_EXP015_A02_first_or_join_retains_a01_and_legacy_opt_out() -> void:
	var both: Dictionary = _start(0, "resilience_first",
		"exp015_a02_first", 4, true, true)
	assert_true(bool(both["reply"].get("ok", false)), str(both["reply"]))
	if not bool(both["reply"].get("ok", false)):
		return
	var first: Runtime = both["host"]
	assert_true(first.incident_response != null)
	assert_true(first.service_cascade == null)
	assert_true(str(both["reply"]["content_revision"]).begins_with("EXP015_A01_"))
	Regional.clear_host_memory_for_test()
	var legacy: Dictionary = _start(0, "resilience_first",
		"exp015_a02_off", 7, false, false)
	assert_true(bool(legacy["reply"].get("ok", false)), str(legacy["reply"]))
	if not bool(legacy["reply"].get("ok", false)):
		return
	var original: Runtime = legacy["host"]
	assert_true(original.incident_response == null)
	assert_true(original.service_cascade == null)
	assert_true(str(legacy["reply"]["content_revision"]).begins_with("EXP014_A09_"))
	assert_false(original.task_board().has("service_cascade"))
	var rejected: Runtime = Runtime.new()
	assert_eq(str(rejected.start("LV_007", Callable(self, "_host_position"),
		Callable(), "", false, "",
		false, false, false, false, false,
		false, false, false, false, false,
		false, false, false, false, false,
		false, true).get("code", "")),
		"EXP015_A02_REQUIRES_A09_REGIONAL_NETWORK")


func test_EXP015_A02_attestation_checks_live_network_and_limits_asset_lock() -> void:
	var context: Dictionary = _context(
		Atlas.load_catalog(), Cascade.load_book(), 0, "critical_first")
	assert_false(context.is_empty())
	var response: Cascade = context["response"]
	var network: Regional = context["regional"]
	var source: Dictionary = context["recipe"]
	assert_true(response.protects_original_asset(
		"regional_reset:" + str(source["normal_feeder_id"])))
	assert_true(response.protects_original_asset(
		"regional_release:" + str(source["backfeed_tie_id"])))
	assert_false(response.protects_original_asset("regional_recharge"))
	assert_false(response.protects_original_asset("regional_isolate:OTHER_FEEDER"))
	for action: String in [
		"cascade_assess", "cascade_trip", "cascade_managed", "cascade_prepare",
		"cascade_clear", "cascade_reconnect", "cascade_attest"
	]:
		assert_true(bool(response.operate(action).get("ok", false)), action)
	assert_true(response.resolved())
	# Trusted test-only state tampering must revoke the existing attestation;
	# this path is NOT exposed through the secured player board.
	assert_true(bool(network.host_transition("isolate_feeder",
		str(source["normal_feeder_id"])).get("ok", false)))
	assert_false(response.resolved(),
		"attestation cannot outlive unsafe source feeder state")
