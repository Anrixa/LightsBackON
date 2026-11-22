extends "res://tests/test_case.gd"
## EXP015 A09: 25 cold root sources x 4 original feeder/reserve paths.
## Original EXP04 receipts are injected only in ephemeral TEST fixtures.
const Atlas := preload("res://scripts/world/dispatch_atlas.gd")
const Ledger := preload("res://scripts/progression/expedition_ledger.gd")
const Network := preload("res://scripts/gameplay/expedition_regional_network.gd")
const Entry := preload("res://scripts/gameplay/expedition_regional_entry_commissioning.gd")
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
	_root = "user://exp015_a09_" + str(Time.get_ticks_usec()) + "_" + str(randi())
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
		"source-only A09 fixture receipt; never production host completion")


func _profile(atlas: Dictionary, region: int, account: String) -> Dictionary:
	var profile: Dictionary = Ledger.new_profile(account)
	for prior: int in range(region):
		for slot: int in SPINE:
			_restore(profile, atlas, prior * 8 + slot)
	return profile


func _context(region: int) -> Dictionary:
	var atlas: Dictionary = Atlas.load_catalog()
	var site: String = "LV_%03d" % (8 * region + 1)
	var profile: Dictionary = _profile(atlas, region,
		"a09_original_%02d" % (region + 1))
	var network: Network = Network.new()
	var started: Dictionary = network.configure(atlas, profile, site)
	assert_true(bool(started.get("ok", false)), str(started))
	if not bool(started.get("ok", false)):
		return {}
	var recipe: Dictionary = Entry.entry_for(Entry.load_book(), site)
	var controller: Entry = Entry.new()
	var configured: Dictionary = controller.configure(recipe, network)
	assert_true(bool(configured.get("ok", false)), str(configured))
	if not bool(configured.get("ok", false)):
		return {}
	return {"network": network, "controller": controller,
		"recipe": recipe, "profile": profile, "atlas": atlas}


func _run(context: Dictionary, preferred: String, policy: String) -> Dictionary:
	var controller: Entry = context["controller"]
	var network: Network = context["network"]
	var recipe: Dictionary = context["recipe"]
	var before: Dictionary = network.snapshot()
	var reserve: int = int(before["reserve_pu"])
	assert_false(bool(before["sites"][str(recipe["entry_site_id"])]["restored"]))
	assert_false(bool(before["sites"][str(recipe["entry_site_id"])]["energized"]))
	assert_eq(controller.operate("entry_buffer")["code"],
		"ENTRY_RISK_CLEARANCE_REQUIRED")
	assert_true(bool(controller.operate("entry_survey").get("ok", false)))
	assert_true(bool(controller.operate("entry_isolate").get("ok", false)))
	var first_a: String = str(recipe["transport_feeder_id"])
	var first_b: String = str(recipe["critical_feeder_id"])
	assert_true(bool(network.snapshot()["feeders"][first_a]["isolated"]))
	assert_true(bool(network.snapshot()["feeders"][first_b]["isolated"]))
	assert_true(bool(controller.operate(
		"entry_critical" if preferred == "critical" else
		"entry_transport").get("ok", false)))
	assert_eq(bool(network.snapshot()["feeders"][first_a]["isolated"]),
		preferred == "critical")
	assert_eq(bool(network.snapshot()["feeders"][first_b]["isolated"]),
		preferred == "transport")
	assert_eq(controller.operate("entry_contain:FAKED")["code"],
		"ENTRY_UNKNOWN_OR_FORGED_ACTION")
	assert_true(bool(controller.operate("entry_contain:" +
		str(recipe["entry_risk_proof"])).get("ok", false)))
	assert_eq(controller.operate("entry_unblock")["code"],
		"ENTRY_RESERVE_DECISION_REQUIRED")
	assert_true(bool(controller.operate(
		"entry_buffer" if policy == "buffer" else "entry_managed").get("ok", false)))
	var middle: Dictionary = network.snapshot()
	assert_eq(int(middle["reserve_pu"]), reserve - (2 if policy == "buffer" else 0))
	assert_eq(int(network.site_conditions()["service_debt"]),
		0 if policy == "buffer" else 2)
	assert_true(network.site_prepared())
	assert_true(bool(controller.operate("entry_unblock").get("ok", false)))
	assert_false(bool(network.snapshot()["feeders"][first_a]["isolated"]))
	assert_false(bool(network.snapshot()["feeders"][first_b]["isolated"]))
	assert_true(bool(controller.operate("entry_verify").get("ok", false)))
	assert_true(bool(controller.operate("entry_signoff").get("ok", false)))
	assert_true(controller.closed())
	assert_false(bool(controller.snapshot()["root_restoration_receipt"]))
	assert_false(bool(controller.snapshot()["root_actually_energized"]))
	assert_eq(int(controller.snapshot()["reserve_spent_pu"]),
		2 if policy == "buffer" else 0)
	assert_eq(int(controller.snapshot()["live_regional_service_debt"]),
		0 if policy == "buffer" else 2)
	return {"ok": true, "reserve": int(network.snapshot()["reserve_pu"]),
		"debt": int(network.site_conditions()["service_debt"]),
		"root": str(recipe["entry_site_id"])}


func test_EXP015_A09_25_original_cold_source_bindings_and_mutations() -> void:
	var checked: Dictionary = Entry.inspect(Atlas.load_catalog(),
		Entry.load_book(), Network.load_book())
	assert_true(bool(checked.get("ok", false)), str(checked))
	assert_eq(int(checked["original_roots"]), 25)
	assert_eq(int(checked["original_first_feed_paths"]), 50)
	var altered: Dictionary = Entry.load_book()
	altered["entries"][17]["critical_feeder_id"] = "FAKE"
	assert_eq(Entry.inspect(Atlas.load_catalog(),
		altered, Network.load_book())["code"], "ENTRY_ORIGINAL_SOURCE_MISMATCH")


func test_EXP015_A09_100_true_network_commissioning_and_supply_hold() -> void:
	var total: int = 0
	for region: int in range(25):
		for branch: String in ["critical", "transport"]:
			for policy: String in ["buffer", "managed"]:
				var context: Dictionary = _context(region)
				if context.is_empty():
					continue
				var result: Dictionary = _run(context, branch, policy)
				if bool(result.get("ok", false)):
					total += 1
				print("EXP015_A09_ROOT region=%02d source=%s first=%s policy=%s remaining=%d debt=%d" %
					[region + 1, str(result.get("root", "")), branch, policy,
					int(result.get("reserve", -1)), int(result.get("debt", -1))])
	assert_eq(total, 100)


func test_EXP015_A09_real_feeder_reisolation_revokes_signoff() -> void:
	var context: Dictionary = _context(0)
	if context.is_empty():
		return
	assert_true(bool(_run(context, "critical", "buffer").get("ok", false)))
	var controller: Entry = context["controller"]
	var network: Network = context["network"]
	var feeder: String = str(controller.definition_snapshot()["critical_feeder_id"])
	assert_true(controller.protects_original_asset("regional_reset:" + feeder))
	assert_true(controller.protects_original_asset("regional_buffer"))
	assert_true(controller.protects_original_asset("regional_managed"))
	assert_true(controller.protects_original_asset("regional_recharge"))
	assert_false(controller.protects_original_asset("regional_reset:FOREIGN_FEEDER"))
	assert_eq(network.host_transition("commit_entry_buffer",
		str(controller.definition_snapshot()["entry_site_id"]))["code"],
		"ENTRY_COMMITMENT_SOURCE_DENIED")
	assert_true(bool(network.host_transition("isolate_feeder", feeder).get("ok", false)))
	assert_false(controller.closed())
	assert_true(bool(network.host_transition("reset_feeder", feeder).get("ok", false)))
	assert_true(controller.closed())


func test_EXP015_A09_25_real_reserve_and_debt_handoff_to_next_dispatch() -> void:
	for region: int in range(25):
		for policy: String in ["buffer", "managed"]:
			var context: Dictionary = _context(region)
			if context.is_empty():
				continue
			var report: Dictionary = _run(context, "critical", policy)
			var network: Network = context["network"]
			var profile: Dictionary = context["profile"]
			var atlas: Dictionary = context["atlas"]
			var expected: int = int(report["reserve"])
			_restore(profile, atlas, 8 * region + 1)
			var next_site: String = "LV_%03d" % (8 * region + 3)
			var attached: Dictionary = network.attach_site(atlas, profile, next_site)
			assert_true(bool(attached.get("ok", false)), str(attached))
			assert_eq(int(network.snapshot()["reserve_pu"]), expected)
			assert_eq(int(network.site_conditions()["service_debt"]),
				0 if policy == "buffer" else 2)
			assert_true(bool(network.snapshot()["sites"][
				"LV_%03d" % (8 * region + 1)]["restored"]))
			assert_false(bool(network.snapshot()["sites"][next_site]["restored"]))
			assert_eq(network.host_transition("commit_entry_debt",
				"LV_%03d" % (8 * region + 1))["code"],
				"ENTRY_COMMITMENT_SOURCE_DENIED")
			print("EXP015_A09_HANDOFF region=%02d decision=%s next=%s reserve=%d" %
				[region + 1, policy, next_site, expected])


func _send(host: Runtime, seq: int, board: String, action: String,
		peer: int = 1) -> Dictionary:
	host.host.tick(seq) # Real 10Hz host time preserves original rate limiting.
	return host.receive(peer, JSON.stringify({
		"session": host.session_id(), "seq": seq, "type": "operate_worksite",
		"entity": board, "payload": {"action": action}
	}).to_utf8_buffer())


func _start_host(region: int, account: String, active: bool) -> Dictionary:
	var atlas: Dictionary = Atlas.load_catalog()
	var profile: Dictionary = _profile(atlas, region, account)
	var saves: Saves = Saves.new()
	saves.configure(1, Offline.SAVE_BUILD_ID,
		ContentHash.content_revision(), ContentHash.rules_revision())
	var root: String = _root.path_join(account)
	var path: String = root.path_join("profiles").path_join(account).path_join(
		Ledger.PROFILE_FILE)
	assert_true(bool(saves.write_record(path, Ledger.KIND_PROFILE,
		account, profile, STAMP).get("ok", false)))
	var host: Runtime = Runtime.new()
	var ready: Dictionary
	if active:
		# All A01..A09 source features globally enabled. Only the new
		# ORIGINAL region entry is authored here; no default widening.
		ready = host.start("LV_%03d" % (region * 8 + 1),
			Callable(self, "_position_for"), Callable(), account, true, root,
			true, true, true, true, true,
			true, true, true, true, true,
			true, true, true, true, true,
			true, true, true, true, true,
			true, true, true)
	else:
		ready = host.start("LV_%03d" % (region * 8 + 1),
			Callable(self, "_position_for"), Callable(), account, true, root,
			true, true, true, true, true,
			true, true, true, true, true,
			true, true, true, true, true)
	return {"host": host, "reply": ready}


func test_EXP015_A09_actual_authenticated_entry_host_and_no_reward() -> void:
	for region: int in [0, 9, 24]:
		Network.clear_host_memory_for_test()
		var account: String = "a09_host_%02d" % region
		var begun: Dictionary = _start_host(region, account, true)
		assert_true(bool(begun["reply"].get("ok", false)), str(begun["reply"]))
		if not bool(begun["reply"].get("ok", false)):
			continue
		var host: Runtime = begun["host"]
		assert_true(bool(begun["reply"]["regional_entry_active"]))
		assert_false(bool(begun["reply"]["alternate_route_active"]))
		assert_false(bool(begun["reply"]["regional_rejoin_active"]))
		assert_true(str(begun["reply"]["content_revision"]).begins_with("EXP015_A09_"))
		var board: String = str(host.worksite.definition_snapshot()["board"])
		_position = host.definition_snapshot()["positions"][board]
		var recipe: Dictionary = host.regional_entry.definition_snapshot()
		assert_false(bool(_send(host, 1, board, "entry_survey", 999).get("ok", false)))
		assert_eq(str(_send(host, 1, board, "regional_buffer").get("code", "")),
			"EXP015_A09_PROTECTED_ENTRY_SOURCE")
		assert_eq(str(host._bespoke_guard(Runtime.PLAYER_ID,
			"request_extract", "ZONE_EXTRACT", {}).get("code", "")),
			"EXP014_A09_PREPARATION_REQUIRED")
		var seq: int = 2
		for action: String in ["entry_survey", "entry_isolate", "entry_critical",
			"entry_contain:" + str(recipe["entry_risk_proof"]), "entry_buffer",
			"entry_unblock", "entry_verify", "entry_signoff"]:
			var response: Dictionary = _send(host, seq, board, action)
			assert_true(bool(response.get("ok", false)), str(response) + " " + action)
			seq += 1
		assert_true(host.regional_entry.closed())
		assert_true(bool(_send(host, seq - 1, board, "entry_signoff").get("duplicate", false)))
		assert_eq(str(host.task_board()["regional_entry"]["phase"]), "signed_off")
		assert_true(host.authoritative_state().has("exp015_regional_entry"))
		assert_false(host.completed())
		assert_eq(host.pending_rewards(account).size(), 0)
		assert_eq(str(_send(host, seq, board, "regional_reset:" +
			str(recipe["transport_feeder_id"])).get("code", "")),
			"EXP015_A09_PROTECTED_ENTRY_SOURCE")
		print("EXP015_A09_HOST root=%s exact_ingress=PASS rewards=0" %
			str(recipe["entry_site_id"]))


func test_EXP015_A09_opt_out_preserves_original_A09_content_revision() -> void:
	var begun: Dictionary = _start_host(0, "a09_no_optin", false)
	assert_true(bool(begun["reply"].get("ok", false)), str(begun["reply"]))
	if bool(begun["reply"].get("ok", false)):
		assert_false(bool(begun["reply"]["regional_entry_active"]))
		assert_true(str(begun["reply"]["content_revision"]).begins_with("EXP014_A09_"))
		assert_false(begun["host"].task_board().has("regional_entry"))
