extends "res://tests/test_case.gd"
## EXP015 A01: 25 authored emergency-response chains.
## Physical/controller/Steam/real power-flow/release qualification remains held.
const Atlas := preload("res://scripts/world/dispatch_atlas.gd")
const Ledger := preload("res://scripts/progression/expedition_ledger.gd")
const Network := preload("res://scripts/gameplay/expedition_regional_network.gd")
const Response := preload("res://scripts/gameplay/expedition_regional_emergencies.gd")
const Runtime := preload("res://scripts/gameplay/expedition_host_session.gd")
const Saves := preload("res://scripts/persistence/save_service.gd")
const Offline := preload("res://scripts/persistence/offline_persistence.gd")
const ContentHash := preload("res://scripts/network/content_hash.gd")
const Campaign := preload("res://scripts/progression/expedition_campaign.gd")

const SPINE: Array[int] = [1, 3, 4, 6, 7, 8]
const STAMP: String = "2026-11-22T00:00:00Z"
var _position: Vector3 = Vector3.ZERO
var _root: String = ""


func before_each() -> void:
	Network.clear_host_memory_for_test()
	_position = Vector3.ZERO
	_root = "user://exp015_a01_" + str(Time.get_ticks_usec())


func after_each() -> void:
	Network.clear_host_memory_for_test()


func _host_position(_id: String) -> Vector3:
	return _position


func _restore(profile: Dictionary, atlas: Dictionary, number: int) -> void:
	var level: Dictionary = Atlas.find_level(atlas, "LV_%03d" % number)
	var receipt: Dictionary = Ledger.make_receipt(str(profile["account_key"]),
		str(level["id"]), str(level["tasks"][4]["id"]), "restoration")
	assert_true(bool(Ledger.apply_receipt(profile, receipt, atlas).get("applied", false)))


func _profile(atlas: Dictionary, region: int, mode: String, account: String) -> Dictionary:
	var profile: Dictionary = Ledger.new_profile(account)
	for prior: int in range(region):
		for slot: int in SPINE:
			_restore(profile, atlas, prior * 8 + slot)
	_restore(profile, atlas, region * 8 + 1)
	_restore(profile, atlas, region * 8 + (2 if mode == "resilience_first" else 3))
	return profile


func _service(atlas: Dictionary, book: Dictionary, region: int, mode: String) -> Dictionary:
	var site: String = "LV_%03d" % (region * 8 + 4)
	var profile: Dictionary = _profile(atlas, region, mode,
		"a015_r%02d_%s" % [region + 1, mode])
	var network: Network = Network.new()
	var ready: Dictionary = network.configure(atlas, profile, site)
	assert_true(bool(ready.get("ok", false)), str(ready))
	if not bool(ready.get("ok", false)):
		return {}
	assert_true(bool(network.select_strategy(mode).get("ok", false)))
	var incident: Response = Response.new()
	var recipe: Dictionary = Response.entry_for(book, site)
	var configured: Dictionary = incident.configure(recipe, network)
	assert_true(bool(configured.get("ok", false)), str(configured))
	return {"incident": incident, "network": network, "recipe": recipe}


func _send(host: Runtime, seq: int, board: String, action: String,
		peer: int = 1) -> Dictionary:
	return host.receive(peer, JSON.stringify({
		"session": host.session_id(), "seq": seq,
		"type": "operate_worksite", "entity": board,
		"payload": {"action": action}
	}).to_utf8_buffer())


func _start(region: int, mode: String, account: String,
		root: String, opt_in: bool) -> Dictionary:
	var atlas: Dictionary = Atlas.load_catalog()
	var saves: Saves = Saves.new()
	saves.configure(1, Offline.SAVE_BUILD_ID,
		ContentHash.content_revision(), ContentHash.rules_revision())
	var profile: Dictionary = _profile(atlas, region, mode, account)
	var profile_path: String = root.path_join("profiles").path_join(account).path_join(
		Ledger.PROFILE_FILE)
	var written: Dictionary = saves.write_record(profile_path,
		Ledger.KIND_PROFILE, account, profile, STAMP)
	assert_true(bool(written.get("ok", false)), str(written))
	var host: Runtime = Runtime.new()
	var started: Dictionary = host.start("LV_%03d" % (region * 8 + 4),
		Callable(self, "_host_position"), Callable(), account, true, root,
		true, true, true, true, true,
		true, true, true, true, true,
		true, true, true, true, true, opt_in)
	return {"host": host, "result": started}


func test_EXP015_A01_all_25_source_pins_reject_forged_feeders_and_protocols() -> void:
	var atlas: Dictionary = Atlas.load_catalog()
	var network_book: Dictionary = Network.load_book()
	var book: Dictionary = Response.load_book()
	assert_eq(Response.inspect(atlas, book, network_book)["incidents"], 25)
	for region: int in range(25):
		var entry: Dictionary = book["entries"][region]
		assert_eq(str(entry["incident_site_id"]), "LV_%03d" % (region * 8 + 4))
		assert_eq(int(entry["managed_unserved_pressure_pu"]),
			int(Response.PROTOCOLS[str(entry["risk_class"])][1]))
	var bad: Dictionary = book.duplicate(true)
	bad["entries"][9]["normal_feeder_id"] = "NET_FAKE_EDGE"
	assert_eq(Response.inspect(atlas, bad, network_book)["code"],
		"INCIDENT_FEEDER_SOURCE_MISMATCH")
	bad = book.duplicate(true)
	bad["entries"][4]["standby_tie_id"] = "NET_FAKE_TIE"
	assert_eq(Response.inspect(atlas, bad, network_book)["code"],
		"INCIDENT_STANDBY_SOURCE_MISMATCH")
	bad = book.duplicate(true)
	bad["entries"][21]["preparation_protocol"] = "cosmetic_relabel"
	assert_eq(Response.inspect(atlas, bad, network_book)["code"],
		"INCIDENT_RISK_PROTOCOL_MISMATCH")
	bad = book.duplicate(true)
	bad["entries"][14]["incident_site_id"] = "LV_999"
	assert_eq(Response.inspect(atlas, bad, network_book)["code"],
		"INCIDENT_SOURCE_MISMATCH")


func test_EXP015_A01_25_managed_outage_chains_are_recoverable_without_minting_reserve() -> void:
	var atlas: Dictionary = Atlas.load_catalog()
	var book: Dictionary = Response.load_book()
	var certified: int = 0
	for region: int in range(25):
		var context: Dictionary = _service(atlas, book, region, "resilience_first")
		if context.is_empty():
			continue
		var case: Response = context["incident"]
		var network: Network = context["network"]
		var recipe: Dictionary = context["recipe"]
		var initial: int = int(network.snapshot()["reserve_pu"])
		assert_eq(case.operate("incident_isolate")["code"], "INCIDENT_SURVEY_REQUIRED")
		assert_true(bool(case.operate("incident_survey")["ok"]))
		assert_true(bool(case.operate("incident_isolate")["ok"]))
		assert_eq(case.operate("incident_certify")["code"],
			"INCIDENT_RECOVERY_EVIDENCE_REQUIRED")
		assert_true(bool(case.operate("incident_managed")["ok"]))
		assert_eq(int(case.snapshot()["unserved_pressure_pu"]),
			int(recipe["managed_unserved_pressure_pu"]))
		assert_true(bool(case.operate("incident_prepare")["ok"]))
		assert_true(network.site_prepared())
		assert_true(bool(case.operate("incident_recover")["ok"]))
		assert_true(bool(case.operate("incident_certify")["ok"]))
		assert_true(case.certified())
		assert_eq(case.snapshot()["mode"], "managed_outage")
		assert_eq(int(network.snapshot()["reserve_pu"]), initial)
		assert_false(bool(network.snapshot()["feeders"][
			str(recipe["normal_feeder_id"])]["isolated"]))
		assert_eq(case.snapshot()["events"].size(), 6)
		assert_eq(case.operate("incident_certify")["code"],
			"INCIDENT_RECOVERY_EVIDENCE_REQUIRED")
		certified += 1
		print("EXP015_MANAGED region=%02d/25 event_count=%d pressure=%d" %
			[region + 1, case.snapshot()["events"].size(),
			int(case.snapshot()["unserved_pressure_pu"])])
	assert_eq(certified, 25)


func test_EXP015_A01_source_live_standby_recovery_consumes_reserve_once() -> void:
	var atlas: Dictionary = Atlas.load_catalog()
	var book: Dictionary = Response.load_book()
	var transfers: int = 0
	for region: int in range(25):
		var context: Dictionary = _service(atlas, book, region, "critical_first")
		if context.is_empty():
			continue
		var case: Response = context["incident"]
		var network: Network = context["network"]
		var recipe: Dictionary = context["recipe"]
		var source: String = str(recipe["standby_source_site"])
		if not bool(network.snapshot()["sites"][source]["energized"]):
			continue
		var initial: int = int(network.snapshot()["reserve_pu"])
		assert_true(bool(case.operate("incident_survey")["ok"]))
		assert_true(bool(case.operate("incident_isolate")["ok"]))
		assert_true(bool(case.operate("incident_transfer")["ok"]))
		assert_eq(int(network.snapshot()["reserve_pu"]), initial - 2)
		assert_eq(case.operate("incident_transfer")["code"],
			"INCIDENT_ISOLATION_REQUIRED")
		assert_eq(int(network.snapshot()["reserve_pu"]), initial - 2)
		assert_true(bool(network.snapshot()["ties"][
			str(recipe["standby_tie_id"])]["engaged"]))
		assert_true(bool(case.operate("incident_prepare")["ok"]))
		assert_true(bool(case.operate("incident_recover")["ok"]))
		assert_false(bool(network.snapshot()["ties"][
			str(recipe["standby_tie_id"])]["engaged"]))
		assert_true(bool(case.operate("incident_certify")["ok"]))
		assert_eq(int(network.snapshot()["reserve_pu"]), initial - 2,
			"released standby may never refund already used reserve")
		assert_eq(case.snapshot()["mode"], "standby_transfer")
		transfers += 1
		print("EXP015_STANDBY region=%02d reserve_initial=%d reserve_final=%d" %
			[region + 1, initial, int(network.snapshot()["reserve_pu"])])
	assert_true(transfers >= 5, "Source-linked real standby must be viable in >=5 regions")


func test_EXP015_A01_bad_fault_proof_blocks_closeout_then_trusted_recovery_works() -> void:
	var atlas: Dictionary = Atlas.load_catalog()
	var book: Dictionary = Response.load_book()
	var context: Dictionary = _service(atlas, book, 0, "resilience_first")
	assert_false(context.is_empty())
	var case: Response = context["incident"]
	var network: Network = context["network"]
	var source: Dictionary = Network.load_book()["regions"][0]
	var edge: String = str(context["recipe"]["normal_feeder_id"])
	assert_true(bool(case.operate("incident_survey")["ok"]))
	assert_true(bool(case.operate("incident_isolate")["ok"]))
	assert_true(bool(case.operate("incident_managed")["ok"]))
	assert_true(bool(case.operate("incident_prepare")["ok"]))
	assert_true(bool(network.host_transition("trip_feeder", edge,
		str(source["fault_signature"]))["ok"]))
	assert_eq(case.operate("incident_recover")["code"], "INCIDENT_FEEDER_STILL_FAULTED")
	assert_eq(case.snapshot()["phase"], "prepared")
	assert_eq(network.host_transition("clear_fault", edge, "FAKE_PROOF")["code"],
		"UNVERIFIED_RECOVERY")
	assert_true(bool(network.host_transition("clear_fault", edge,
		str(source["recovery_procedure"]))["ok"]))
	assert_true(bool(case.operate("incident_recover")["ok"]))
	assert_true(bool(case.operate("incident_certify")["ok"]))


func test_EXP015_A01_authenticated_host_commands_gate_incident_and_reward() -> void:
	for region: int in [0, 9, 24]:
		var account: String = "exp015_host_%02d" % (region + 1)
		var root: String = _root.path_join(account)
		var opened: Dictionary = _start(region, "resilience_first", account, root, true)
		var reply: Dictionary = opened["result"]
		assert_true(bool(reply.get("ok", false)), str(reply))
		if not bool(reply.get("ok", false)):
			continue
		var host: Runtime = opened["host"]
		assert_true(bool(reply["incident_response_active"]))
		assert_true(str(reply["content_revision"]).begins_with("EXP015_A01_"))
		var board: String = str(host.worksite.definition_snapshot()["board"])
		_position = host.definition_snapshot()["positions"][board]
		var previous: Dictionary = host.incident_response.snapshot()
		assert_false(bool(_send(host, 1, board, "incident_survey", 999).get("ok", false)))
		assert_eq(host.incident_response.snapshot(), previous)
		assert_eq(_send(host, 1, board, "incident_survey")["code"],
			"INCIDENT_STRATEGY_AND_SURVEY_REQUIRED")
		assert_true(bool(_send(host, 2, board, "regional_resilience")["ok"]))
		assert_true(bool(_send(host, 3, board, "incident_survey")["ok"]))
		assert_true(bool(_send(host, 4, board, "incident_isolate")["ok"]))
		assert_true(bool(_send(host, 5, board, "incident_managed")["ok"]))
		assert_true(bool(_send(host, 6, board, "incident_prepare")["ok"]))
		assert_eq(str(host._bespoke_guard(Runtime.PLAYER_ID,
			"request_extract", "ZONE_EXTRACT", {}).get("code", "")),
			"EXP015_INCIDENT_RESPONSE_REQUIRED")
		assert_false(host.completed())
		assert_eq(host.pending_rewards(account).size(), 0)
		assert_true(bool(_send(host, 7, board, "incident_recover")["ok"]))
		assert_true(bool(_send(host, 8, board, "incident_certify")["ok"]))
		assert_true(host.incident_response.certified())
		assert_true(bool(_send(host, 8, board, "incident_certify").get("duplicate", false)))
		assert_eq(host.incident_response.snapshot()["events"].size(), 6)
		assert_true(host.authoritative_state().has("exp015_incident_response"))
		assert_eq(host.task_board()["incident_response"]["phase"], "certified")
		assert_ne(str(host._bespoke_guard(Runtime.PLAYER_ID,
			"request_extract", "ZONE_EXTRACT", {}).get("code", "")),
			"EXP015_INCIDENT_RESPONSE_REQUIRED")
		assert_false(host.completed(), "Incident certification is NOT mission completion")
		assert_eq(host.pending_rewards(account).size(), 0)
		print("EXP015_HOST region=%02d authenticated=7 incident_certified=true rewards=0" %
			[region + 1])


func test_EXP015_A01_explicit_opt_in_preserves_original_a09_sessions() -> void:
	var account: String = "exp015_legacy_unchanged"
	var root: String = _root.path_join("legacy")
	var baseline: Dictionary = _start(0, "resilience_first", account, root, false)
	assert_true(bool(baseline["result"].get("ok", false)), str(baseline["result"]))
	if not bool(baseline["result"].get("ok", false)):
		return
	var host: Runtime = baseline["host"]
	assert_true(bool(baseline["result"]["regional_network_active"]))
	assert_false(bool(baseline["result"]["incident_response_active"]))
	assert_true(host.incident_response == null)
	assert_false(host.task_board().has("incident_response"))
	assert_true(str(baseline["result"]["content_revision"]).begins_with("EXP014_A09_"))
	var fake: Runtime = Runtime.new()
	var rejected: Dictionary = fake.start("LV_001", Callable(self, "_host_position"),
		Callable(), "", false, "",
		false, false, false, false, false,
		false, false, false, false, false,
		false, false, false, false, false, true)
	assert_eq(str(rejected["code"]), "EXP015_REQUIRES_A09_REGIONAL_NETWORK")
