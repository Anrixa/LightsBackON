extends "res://tests/test_case.gd"
## EXP015 A08: 50 ORIGINAL regional joins × authentic A09 recovery histories.
## EXP04 receipts are isolated source-only fixtures; not gameplay completions.
const Atlas := preload("res://scripts/world/dispatch_atlas.gd")
const Ledger := preload("res://scripts/progression/expedition_ledger.gd")
const Network := preload("res://scripts/gameplay/expedition_regional_network.gd")
const Incident := preload("res://scripts/gameplay/expedition_regional_emergencies.gd")
const Cascade := preload("res://scripts/gameplay/expedition_regional_cascades.gd")
const Alternate := preload("res://scripts/gameplay/expedition_regional_alt_routes.gd")
const Rejoin := preload("res://scripts/gameplay/expedition_regional_rejoin_consequences.gd")
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
	_root = "user://exp015_a08_" + str(Time.get_ticks_usec()) + "_" + str(randi())
	_position = Vector3.ZERO


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
		"A08 test-only EXP04 progression receipt, never player completion")


func _profile(atlas: Dictionary, region: int, stage: int,
		first: String, second: String, account: String) -> Dictionary:
	var profile: Dictionary = Ledger.new_profile(account)
	for earlier: int in range(region):
		for slot: int in SPINE:
			_restore(profile, atlas, earlier * 8 + slot)
	var start: int = 8 * region
	_restore(profile, atlas, start + 1)
	if stage >= 4:
		_restore(profile, atlas, start + (2 if first == "a" else 3))
	if stage >= 7:
		_restore(profile, atlas, start + 4)
		_restore(profile, atlas, start + (5 if second == "a" else 6))
	return profile


func _context(region: int, stage: int,
		first: String, second: String) -> Dictionary:
	var atlas: Dictionary = Atlas.load_catalog()
	var profile: Dictionary = _profile(atlas, region, stage, first, second,
		"a08_direct_%02d_%d_%s%s" % [region + 1, stage, first, second])
	var level_id: String = "LV_%03d" % (region * 8 + stage)
	var network: Network = Network.new()
	var ready: Dictionary = network.configure(atlas, profile, level_id)
	assert_true(bool(ready.get("ok", false)), str(ready))
	if not bool(ready.get("ok", false)):
		return {}
	var policy: String = "resilience_first" if first == "a" else "critical_first"
	assert_true(bool(network.select_strategy(policy).get("ok", false)))
	var incident: Incident
	var cascade: Cascade
	if stage == 4:
		incident = Incident.new()
		assert_true(bool(incident.configure(
			Incident.entry_for(Incident.load_book(), level_id),
			network).get("ok", false)))
	else:
		cascade = Cascade.new()
		assert_true(bool(cascade.configure(
			Cascade.entry_for(Cascade.load_book(), level_id),
			network).get("ok", false)))
	var rejoin: Rejoin = Rejoin.new()
	var configured: Dictionary = rejoin.configure(
		Rejoin.entry_for(Rejoin.load_book(), level_id), network, incident, cascade)
	assert_true(bool(configured.get("ok", false)), str(configured))
	if not bool(configured.get("ok", false)):
		return {}
	return {"network": network, "incident": incident,
		"cascade": cascade, "rejoin": rejoin}


func _resolve_parent(context: Dictionary, stage: int) -> void:
	if stage == 4:
		var response: Incident = context["incident"]
		for action: String in ["incident_survey", "incident_isolate",
			"incident_managed", "incident_prepare",
			"incident_recover", "incident_certify"]:
			assert_true(bool(response.operate(action).get("ok", false)), action)
		assert_true(response.certified())
	else:
		var cascade: Cascade = context["cascade"]
		for action: String in ["cascade_assess", "cascade_trip",
			"cascade_managed", "cascade_prepare", "cascade_clear",
			"cascade_reconnect", "cascade_attest"]:
			assert_true(bool(cascade.operate(action).get("ok", false)), action)
		assert_true(cascade.resolved())


func _run(context: Dictionary, stage: int, source: String) -> Dictionary:
	var rejoin: Rejoin = context["rejoin"]
	var network: Network = context["network"]
	assert_eq(rejoin.operate("rejoin_assess")["code"], "REJOIN_PARENT_PROOF_REQUIRED")
	_resolve_parent(context, stage)
	assert_true(bool(rejoin.operate("rejoin_assess").get("ok", false)))
	assert_false(bool(rejoin.snapshot()["prior_route_a_proven"]))
	assert_false(bool(rejoin.snapshot()["prior_route_b_proven"]))
	assert_eq(rejoin.operate("rejoin_trace_a")["code"],
		"REJOIN_ORIGINAL_A_PROOF_REQUIRED")
	assert_eq(rejoin.operate("rejoin_trace_b")["code"],
		"REJOIN_ORIGINAL_B_PROOF_REQUIRED")
	assert_true(bool(rejoin.operate("rejoin_unverified").get("ok", false)))
	assert_true(bool(rejoin.operate("rejoin_trip").get("ok", false)))
	assert_eq(rejoin.operate("rejoin_reset")["code"], "REJOIN_RESET_NOT_READY")
	var staged: bool = false
	var critical_live: bool = bool(rejoin.snapshot()["critical_initially_energized"])
	if stage == 4:
		if critical_live:
			assert_true(bool(rejoin.operate("rejoin_priority").get("ok", false)))
		else:
			assert_eq(rejoin.operate("rejoin_priority")["code"],
				"REJOIN_PRIORITY_REQUIRES_CRITICAL_SUPPLY")
			assert_true(bool(rejoin.operate("rejoin_managed").get("ok", false)))
	else:
		var transfer: Dictionary = rejoin.operate("rejoin_stage")
		if bool(transfer.get("ok", false)):
			staged = true
			assert_eq(int(rejoin.snapshot()["reserve_spent_pu"]), 2)
		else:
			assert_eq(str(transfer.get("code", "")),
				"REJOIN_REAL_STANDBY_SOURCE_UNAVAILABLE")
			assert_true(bool(rejoin.operate("rejoin_managed").get("ok", false)))
	var recipe: Dictionary = rejoin.definition_snapshot()
	assert_eq(rejoin.operate("rejoin_contain:FAKE")["code"],
		"REJOIN_UNKNOWN_OR_FORGED_ACTION")
	assert_true(bool(rejoin.operate("rejoin_contain:" +
		str(recipe["rejoin_risk_protocol"])).get("ok", false)))
	assert_true(bool(rejoin.operate("rejoin_clear").get("ok", false)))
	if stage == 7:
		assert_true(bool(rejoin.operate("rejoin_release").get("ok", false)))
	assert_true(bool(rejoin.operate("rejoin_reset").get("ok", false)))
	assert_true(bool(rejoin.operate("rejoin_verify").get("ok", false)))
	assert_true(bool(rejoin.operate("rejoin_signoff").get("ok", false)))
	assert_true(rejoin.closed())
	assert_true(context["incident"].certified() if stage == 4 else
		context["cascade"].resolved())
	assert_false(bool(network.snapshot()["sites"][
		str(recipe["join_site_id"])]["restored"]))
	assert_false(bool(rejoin.snapshot()["standby_staged"]))
	assert_eq(int(rejoin.snapshot()["reserve_spent_pu"]), 2 if staged else 0)
	assert_true(int(rejoin.snapshot()["managed_pressure_pu"]) >= 2,
		"Unverified source route must remain explicitly managed, not fictitious")
	return {"ok": true, "staged": staged, "stage": stage}


func test_EXP015_A08_original_50_join_source_bindings_reject_forgery() -> void:
	var gate: Dictionary = Rejoin.inspect(Atlas.load_catalog(),
		Rejoin.load_book(), Network.load_book())
	assert_true(bool(gate.get("ok", false)), str(gate))
	assert_eq(int(gate["original_joins"]), 50)
	assert_eq(int(gate["role_counts"]["first_rejoin"]), 25)
	assert_eq(int(gate["role_counts"]["second_rejoin"]), 25)
	var altered: Dictionary = Rejoin.load_book()
	altered["entries"][33]["join_feeder_id"] = "FABRICATED_FEEDER"
	assert_eq(Rejoin.inspect(Atlas.load_catalog(),
		altered, Network.load_book())["code"], "REJOIN_ORIGINAL_SOURCE_MISMATCH")


func test_EXP015_A08_150_original_critical_and_standby_rejoin_scenarios() -> void:
	var done: int = 0
	var candidates: Dictionary = {
		"first_a_second_a": 0, "first_a_second_b": 0,
		"first_b_second_a": 0, "first_b_second_b": 0}
	for region: int in range(25):
		for first: String in ["a", "b"]:
			var first_ctx: Dictionary = _context(region, 4, first, "a")
			if not first_ctx.is_empty():
				assert_true(bool(_run(first_ctx, 4, first).get("ok", false)))
				done += 1
			for second: String in ["a", "b"]:
				var ctx: Dictionary = _context(region, 7, first, second)
				if ctx.is_empty():
					continue
				var result: Dictionary = _run(ctx, 7, second)
				if bool(result.get("ok", false)):
					done += 1
					if bool(result["staged"]):
						var key: String = "first_%s_second_%s" % [first, second]
						candidates[key] = int(candidates[key]) + 1
				print("EXP015_A08_REJOIN region=%02d first=%s second=%s "
					% [region + 1, first, second],
					"stage=7 original_standby=", result.get("staged", false))
	assert_eq(done, 150)
	assert_eq(candidates, {
		"first_a_second_a": 13, "first_a_second_b": 11,
		"first_b_second_a": 9, "first_b_second_b": 11})


func test_EXP015_A08_actual_A07_feeder_receipt_is_not_a_client_claim() -> void:
	# A07 original critical-health site (slot 3) precedes A01 slot 4.
	# Execute its REAL controller then attach the same host-owned network.
	for region: int in [0, 9, 24]:
		var atlas: Dictionary = Atlas.load_catalog()
		var profile: Dictionary = _profile(atlas, region, 1, "b", "a",
			"a08_prerecorded_%02d" % region)
		var previous: String = "LV_%03d" % (8 * region + 3)
		var destination: String = "LV_%03d" % (8 * region + 4)
		var network: Network = Network.new()
		assert_true(bool(network.configure(atlas, profile, previous).get("ok", false)))
		var prior: Alternate = Alternate.new()
		assert_true(bool(prior.configure(
			Alternate.entry_for(Alternate.load_book(), previous),
			network).get("ok", false)))
		var protocol: String = str(prior.definition_snapshot()["risk_containment_protocol"])
		for action: String in ["route_survey", "route_trip",
			"route_critical_priority", "route_contain:" + protocol,
			"route_clear", "route_reset", "route_verify", "route_signoff"]:
			assert_true(bool(prior.operate(action).get("ok", false)), action)
		assert_true(prior.closed())
		_restore(profile, atlas, 8 * region + 3)
		var attached: Dictionary = network.attach_site(atlas, profile, destination)
		assert_true(bool(attached.get("ok", false)), str(attached))
		assert_true(bool(network.select_strategy("critical_first").get("ok", false)))
		var incident: Incident = Incident.new()
		assert_true(bool(incident.configure(
			Incident.entry_for(Incident.load_book(), destination),
			network).get("ok", false)))
		var handoff: Rejoin = Rejoin.new()
		assert_true(bool(handoff.configure(
			Rejoin.entry_for(Rejoin.load_book(), destination),
			network, incident, null).get("ok", false)))
		var context: Dictionary = {"network": network, "incident": incident}
		_resolve_parent(context, 4)
		assert_true(bool(handoff.operate("rejoin_assess").get("ok", false)))
		assert_true(bool(handoff.snapshot()["prior_route_b_proven"]))
		assert_false(bool(handoff.snapshot()["prior_route_a_proven"]))
		assert_eq(handoff.operate("rejoin_trace_a")["code"],
			"REJOIN_ORIGINAL_A_PROOF_REQUIRED")
		for action: String in ["rejoin_trace_b", "rejoin_trip",
			"rejoin_priority", "rejoin_contain:" +
				str(handoff.definition_snapshot()["rejoin_risk_protocol"]),
			"rejoin_clear", "rejoin_reset", "rejoin_verify", "rejoin_signoff"]:
			assert_true(bool(handoff.operate(action).get("ok", false)), action)
		assert_true(handoff.closed())
		assert_eq(str(handoff.snapshot()["route_evidence"]), "verified_route_b")
		assert_eq(int(handoff.snapshot()["managed_pressure_pu"]), 0)


func _send(host: Runtime, seq: int, board: String, action: String,
		peer: int = 1) -> Dictionary:
	# Keep true production 20-commands/10-tick rate enforcement.
	host.host.tick(seq)
	return host.receive(peer, JSON.stringify({
		"session": host.session_id(), "seq": seq, "type": "operate_worksite",
		"entity": board, "payload": {"action": action}
	}).to_utf8_buffer())


func _start_host(stage: int, account: String, enabled: bool) -> Dictionary:
	var atlas: Dictionary = Atlas.load_catalog()
	var profile: Dictionary = _profile(atlas, 0, stage, "b", "a", account)
	var saves: Saves = Saves.new()
	saves.configure(1, Offline.SAVE_BUILD_ID,
		ContentHash.content_revision(), ContentHash.rules_revision())
	var root: String = _root.path_join(account)
	var path: String = root.path_join("profiles").path_join(account).path_join(
		Ledger.PROFILE_FILE)
	assert_true(bool(saves.write_record(path, Ledger.KIND_PROFILE,
		account, profile, STAMP).get("ok", false)))
	var host: Runtime = Runtime.new()
	var started: Dictionary = host.start("LV_%03d" % stage,
		Callable(self, "_position_for"), Callable(), account, true, root,
		true, true, true, true, true,
		true, true, true, true, true,
		true, true, true, true, true,
		true, true, true, true, true,
		true, enabled)
	return {"host": host, "reply": started}


func test_EXP015_A08_authenticated_original_first_second_rejoin_host() -> void:
	for stage: int in [4, 7]:
		Network.clear_host_memory_for_test()
		var account: String = "a08_host_%d" % stage
		var result: Dictionary = _start_host(stage, account, true)
		assert_true(bool(result["reply"].get("ok", false)), str(result["reply"]))
		if not bool(result["reply"].get("ok", false)):
			continue
		var host: Runtime = result["host"]
		assert_true(bool(result["reply"]["regional_rejoin_active"]))
		assert_true(str(result["reply"]["content_revision"]).begins_with("EXP015_A08_"))
		assert_true(host.regional_rejoin != null)
		assert_true(host.alternate_route == null)
		var board: String = str(host.worksite.definition_snapshot()["board"])
		_position = host.definition_snapshot()["positions"][board]
		assert_false(bool(_send(host, 1, board, "rejoin_assess", 999).get("ok", false)))
		assert_eq(_send(host, 1, board, "rejoin_assess")["code"],
			"REJOIN_PARENT_PROOF_REQUIRED")
		var seq: int = 2
		var parent: Array[String] = ["regional_critical"]
		if stage == 4:
			parent.append_array(["incident_survey", "incident_isolate",
				"incident_managed", "incident_prepare",
				"incident_recover", "incident_certify"])
		else:
			parent.append_array(["cascade_assess", "cascade_trip", "cascade_managed",
				"cascade_prepare", "cascade_clear",
				"cascade_reconnect", "cascade_attest"])
		for action: String in parent:
			var reply: Dictionary = _send(host, seq, board, action)
			assert_true(bool(reply.get("ok", false)), str(reply) + " " + action)
			seq += 1
		assert_eq(str(host._bespoke_guard(Runtime.PLAYER_ID,
			"request_extract", "ZONE_EXTRACT", {}).get("code", "")),
			"EXP015_A08_REAL_REJOIN_PROOF_REQUIRED")
		var actions: Array[String] = ["rejoin_assess", "rejoin_unverified",
			"rejoin_trip"]
		if stage == 4:
			actions.append("rejoin_priority")
		else:
			actions.append("rejoin_managed")
		actions.append("rejoin_contain:" +
			str(host.regional_rejoin.definition_snapshot()["rejoin_risk_protocol"]))
		actions.append("rejoin_clear")
		if stage == 7:
			actions.append("rejoin_release")
		actions.append_array(["rejoin_reset", "rejoin_verify", "rejoin_signoff"])
		for action: String in actions:
			var replied: Dictionary = _send(host, seq, board, action)
			assert_true(bool(replied.get("ok", false)), str(replied) + " " + action)
			seq += 1
		assert_true(host.regional_rejoin.closed())
		assert_true(bool(_send(host, seq - 1, board, "rejoin_signoff").get("duplicate", false)))
		assert_true(host.authoritative_state().has("exp015_regional_rejoin"))
		assert_false(host.completed())
		assert_eq(host.pending_rewards(account).size(), 0)
		var recipe: Dictionary = host.regional_rejoin.definition_snapshot()
		assert_eq(str(_send(host, seq, board, "regional_reset:" +
			str(recipe["join_feeder_id"])).get("code", "")),
			"EXP015_A08_PROTECTED_NETWORK_ASSET")
		print("EXP015_A08_HOST stage=%d authority=PASS rewards=0" % stage)


func test_EXP015_A08_optout_preserves_prior_A01_A02_revisions() -> void:
	for stage: int in [4, 7]:
		Network.clear_host_memory_for_test()
		var result: Dictionary = _start_host(stage,
			"a08_legacy_%d" % stage, false)
		assert_true(bool(result["reply"].get("ok", false)), str(result["reply"]))
		if bool(result["reply"].get("ok", false)):
			assert_false(bool(result["reply"]["regional_rejoin_active"]))
			assert_true(str(result["reply"]["content_revision"]).begins_with(
				"EXP015_A01_" if stage == 4 else "EXP015_A02_"))
