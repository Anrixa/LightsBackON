extends "res://tests/test_case.gd"
## EXP014 A10.3: adversarial regional authority, receipt and legacy isolation.
## These are source/headless host tests; never infer player/physics/Steam release.
const Atlas := preload("res://scripts/world/dispatch_atlas.gd")
const Campaign := preload("res://scripts/progression/expedition_campaign.gd")
const Ledger := preload("res://scripts/progression/expedition_ledger.gd")
const Network := preload("res://scripts/gameplay/expedition_regional_network.gd")
const Runtime := preload("res://scripts/gameplay/expedition_host_session.gd")
const LegacyRewards := preload("res://scripts/progression/reward_service.gd")

var _position: Vector3 = Vector3.ZERO


func before_each() -> void:
	Network.clear_host_memory_for_test()
	_position = Vector3.ZERO


func after_each() -> void:
	Network.clear_host_memory_for_test()


func _host_position(_player: String) -> Vector3:
	return _position


func _restore(profile: Dictionary, atlas: Dictionary, level_id: String) -> void:
	var level: Dictionary = Atlas.find_level(atlas, level_id)
	var receipt: Dictionary = Ledger.make_receipt(str(profile["account_key"]),
		level_id, str(level["tasks"][4]["id"]), "restoration")
	var answer: Dictionary = Ledger.apply_receipt(profile, receipt, atlas)
	assert_true(bool(answer.get("applied", false)), "%s: %s" % [level_id, str(answer)])


func _source_profile(atlas: Dictionary, region_index: int, account: String) -> Dictionary:
	var profile: Dictionary = Ledger.new_profile(account)
	# Test-only fixture: the earlier chapter's authentic finale restoration
	# supplies the original EXP05 entry gate. Not a claimed player playthrough.
	if region_index > 0:
		_restore(profile, atlas, "LV_%03d" % (region_index * 8))
	return profile


func _wire(host: Runtime, seq: int, board: String, action: String,
		session: String = "") -> PackedByteArray:
	return JSON.stringify({"session": host.session_id() if session == "" else session,
		"seq": seq, "type": "operate_worksite", "entity": board,
		"payload": {"action": action}}).to_utf8_buffer()


func test_EXP014_A10_3_all_25_regions_reject_fault_forgery_and_broken_source_schemas() -> void:
	var atlas: Dictionary = Atlas.load_catalog()
	var book: Dictionary = Network.load_book()
	var counted: int = 0
	for index: int in range(25):
		var region: Dictionary = book["regions"][index]
		var profile: Dictionary = _source_profile(atlas, index,
			"a103_fault_%02d" % (index + 1))
		var root_id: String = str(region["root_source_id"])
		var feeder: String = str(region["primary_feeders"][0]["edge_id"])
		var network: Network = Network.new()
		assert_true(bool(network.configure(atlas, profile, root_id)["ok"]))
		_restore(profile, atlas, root_id)
		assert_true(bool(network.refresh_receipts(atlas, profile)["ok"]))
		var start: Dictionary = network.snapshot()
		assert_eq(network.host_transition("trip_feeder", feeder, "FORGED_FAULT")["code"],
			"UNVERIFIED_REGION_FAULT")
		assert_eq(network.snapshot(), start)
		assert_true(bool(network.host_transition("trip_feeder", feeder,
			str(region["fault_signature"]))["ok"]))
		assert_eq(network.host_transition("reset_feeder", feeder)["code"],
			"FEEDER_RESET_DENIED")
		assert_eq(network.host_transition("clear_fault", feeder, "FAKE_RECOVERY")["code"],
			"UNVERIFIED_RECOVERY")
		assert_true(bool(network.host_transition("clear_fault", feeder,
			str(region["recovery_procedure"]))["ok"]))
		assert_true(bool(network.host_transition("reset_feeder", feeder)["ok"]))
		assert_eq(int(network.snapshot()["reserve_pu"]), int(start["reserve_pu"]))
		var forged: Dictionary = region.duplicate(true)
		forged["standby_ties"][0]["normally_closed"] = true
		assert_eq(Network.inspect_region(atlas, forged)["code"], "BAD_STANDBY_TIE")
		forged = region.duplicate(true)
		forged["initial_reserve_pu"] = -1
		assert_eq(Network.inspect_region(atlas, forged)["code"], "INVALID_RESERVE")
		forged = region.duplicate(true)
		forged["primary_feeders"][0]["capacity_pu"] = -10
		assert_eq(Network.inspect_region(atlas, forged)["code"], "BAD_FEEDER")
		forged = region.duplicate(true)
		forged["source_sites"][0]["source_task_ids"][0] = "JOB_FORGED_1"
		assert_eq(Network.inspect_region(atlas, forged)["code"], "NETWORK_TASK_SOURCE_MISMATCH")
		counted += 1
		print("A10_3_FAULT_AND_SCHEMA region=%02d/%02d" % [index + 1, 25])
	assert_eq(counted, 25)


func test_EXP014_A10_3_all_25_regions_finite_standby_and_bbm_under_missing_supply() -> void:
	var atlas: Dictionary = Atlas.load_catalog()
	var book: Dictionary = Network.load_book()
	var checked: int = 0
	for index: int in range(25):
		var region: Dictionary = book["regions"][index]
		var tie: Dictionary = region["standby_ties"][0]
		var root_id: String = str(region["root_source_id"])
		var incoming: Dictionary = {}
		for edge: Dictionary in region["primary_feeders"]:
			incoming[str(edge["to"])] = edge
		var profile: Dictionary = _source_profile(atlas, index,
			"a103_tie_%02d" % (index + 1))
		# Restore the actual normal-tree ancestors of the standby SOURCE,
		# keeping the destination dark. This is a source-valid isolated fixture.
		var cursor: String = str(tie["from"])
		var trail: Dictionary = {}
		while cursor != root_id:
			assert_false(trail.has(cursor), "source feeder graph must be acyclic")
			trail[cursor] = true
			assert_true(incoming.has(cursor), "all feeder paths must reach root")
			_restore(profile, atlas, cursor)
			cursor = str(incoming[cursor]["from"])
		_restore(profile, atlas, root_id)
		var normal: String = str(incoming[str(tie["to"])]["edge_id"])
		var net: Network = Network.new()
		assert_true(bool(net.configure(atlas, profile, root_id)["ok"]))
		var initial: int = int(net.snapshot()["reserve_pu"])
		assert_eq(net.host_transition("engage_tie", str(tie["edge_id"]))["code"],
			"BREAK_BEFORE_MAKE_INTERLOCK")
		assert_true(bool(net.host_transition("isolate_feeder", normal)["ok"]))
		assert_true(bool(net.host_transition("engage_tie", str(tie["edge_id"]))["ok"]))
		assert_eq(int(net.snapshot()["reserve_pu"]), initial - 2)
		assert_eq(net.host_transition("reset_feeder", normal)["code"],
			"BREAK_BEFORE_MAKE_INTERLOCK")
		assert_eq(net.host_transition("engage_tie", str(tie["edge_id"]))["code"],
			"TIE_UNAVAILABLE")
		assert_eq(int(net.snapshot()["reserve_pu"]), initial - 2)
		assert_true(bool(net.host_transition("release_tie", str(tie["edge_id"]))["ok"]))
		assert_true(bool(net.host_transition("reset_feeder", normal)["ok"]))
		assert_eq(int(net.snapshot()["reserve_pu"]), initial - 2,
			"opening a transfer may not mint reserve")
		var empty: Network = Network.new()
		assert_true(bool(empty.configure(atlas, profile, root_id)["ok"]))
		empty._reserve = 0  # Controlled test-only exhaustion injection.
		assert_true(bool(empty.host_transition("isolate_feeder", normal)["ok"]))
		assert_eq(empty.host_transition("engage_tie", str(tie["edge_id"]))["code"],
			"STANDBY_RESERVE_EXHAUSTED")
		assert_eq(int(empty.snapshot()["reserve_pu"]), 0)
		assert_false(bool(empty.snapshot()["ties"][str(tie["edge_id"])]["engaged"]))
		checked += 1
		print("A10_3_FINITE_STANDBY region=%02d/%02d" % [index + 1, 25])
	assert_eq(checked, 25)


func test_EXP014_A10_3_forged_duplicate_receipts_never_rewrite_legacy_economy() -> void:
	var atlas: Dictionary = Atlas.load_catalog()
	var account: String = "a103_receipt"
	var profile: Dictionary = Ledger.new_profile(account)
	var legacy: Dictionary = LegacyRewards.new_profile(account)
	legacy["credits"] = 777
	var old_legacy: Dictionary = legacy.duplicate(true)
	var original: Dictionary = Ledger.make_receipt(account, "LV_001",
		"JOB_001_5", "restoration")
	var forged: Dictionary = original.duplicate(true)
	forged["points"] = 1000000
	assert_eq(Ledger.apply_receipt(profile, forged, atlas)["code"], "BAD_REWARD")
	forged = original.duplicate(true)
	forged["receipt_key"] = "FORGED"
	assert_eq(Ledger.apply_receipt(profile, forged, atlas)["code"], "BAD_RECEIPT_KEY")
	forged = original.duplicate(true)
	forged["entity_id"] = "JOB_200_5"
	assert_eq(Ledger.apply_receipt(profile, forged, atlas)["code"], "BAD_REWARD")
	forged = original.duplicate(true)
	forged["account_key"] = "foreign_account"
	assert_eq(Ledger.apply_receipt(profile, forged, atlas)["code"], "BAD_PROFILE")
	assert_eq(int(profile["field_points"]), 0)
	assert_eq(profile["completed_levels"].size(), 0)
	assert_true(bool(Ledger.apply_receipt(profile, original, atlas).get("applied", false)))
	var duplicate: Dictionary = Ledger.apply_receipt(profile, original, atlas)
	assert_true(bool(duplicate.get("ok", false)))
	assert_false(bool(duplicate.get("applied", true)))
	assert_eq(int(profile["field_points"]), 85)
	assert_eq(profile["completed_levels"].size(), 1)
	assert_true(bool(Campaign.can_launch(profile, atlas, Campaign.load_routes(),
		"LV_002").get("ok", false)))
	assert_eq(legacy, old_legacy, "EXP04 source receipts cannot change C01-C12 credits")
	var orphan: Dictionary = profile.duplicate(true)
	orphan["completed_levels"]["LV_008"] = true
	assert_eq(Campaign.evaluate(orphan, atlas, Campaign.load_routes())["code"],
		"RESTORATION_RECEIPT_MISMATCH")


func test_EXP014_A10_3_host_rejects_malformed_foreign_stale_and_client_progress() -> void:
	var host: Runtime = Runtime.new()
	var started: Dictionary = host.start("LV_001", Callable(self, "_host_position"),
		Callable(), "a103_wire", true, "user://a103_wire_isolated",
		true, true, true, true, true, true, true, true, true, true,
		true, true, true, true, true)
	assert_true(bool(started.get("ok", false)), str(started))
	if not bool(started.get("ok", false)):
		return
	var board: String = str(host.worksite.definition_snapshot()["board"])
	_position = host.definition_snapshot()["positions"][board]
	var before: Dictionary = host.regional_network.snapshot()
	assert_eq(host.receive(1, "NO_JSON".to_utf8_buffer())["code"], "MALFORMED")
	assert_eq(host.receive(777, _wire(host, 1, board, "regional_managed"))["code"],
		"UNKNOWN_PEER")
	assert_eq(host.receive(1, _wire(host, 1, board, "regional_managed",
		"FORGED_SESSION"))["code"], "WRONG_SESSION")
	assert_eq(host.regional_network.snapshot(), before)
	var corrupt: PackedByteArray = JSON.stringify({"session": host.session_id(),
		"seq": 1, "type": "operate_worksite", "entity": board,
		"payload": {"action": "regional_managed", "client_unlocked": true}
	}).to_utf8_buffer()
	assert_eq(host.receive(1, corrupt)["code"], "MALFORMED")
	assert_eq(host.regional_network.snapshot(), before)
	var accepted: Dictionary = host.receive(1, _wire(host, 1, board, "regional_managed"))
	assert_true(bool(accepted.get("ok", false)), str(accepted))
	assert_true(host.regional_network.site_prepared())
	var prepared: Dictionary = host.regional_network.snapshot()
	assert_true(bool(host.receive(1,
		_wire(host, 1, board, "regional_managed")).get("duplicate", false)))
	assert_eq(host.regional_network.snapshot(), prepared)
	assert_false(bool(host.receive(1,
		_wire(host, 70, "FORGED_BOARD", "regional_buffer")).get("ok", false)))
	assert_eq(host.receive(1, _wire(host, 1, board, "regional_managed"))["code"],
		"STALE_SEQUENCE")
	assert_eq(host.regional_network.snapshot(), prepared)
	assert_false(host.completed())
	assert_eq(host.pending_rewards("a103_wire").size(), 0)
