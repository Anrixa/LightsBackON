extends "res://tests/test_case.gd"
## EXP015 A12.3: genuine pre-existing original feeder faults are recoverable;
## missing EXP04 source receipts are NOT repairable by synthetic power claims.
const Atlas := preload("res://scripts/world/dispatch_atlas.gd")
const Ledger := preload("res://scripts/progression/expedition_ledger.gd")
const Network := preload("res://scripts/gameplay/expedition_regional_network.gd")
const Recovery := preload("res://scripts/gameplay/expedition_regional_anchor_recovery.gd")
const Runtime := preload("res://scripts/gameplay/expedition_host_session.gd")
const Saves := preload("res://scripts/persistence/save_service.gd")
const Offline := preload("res://scripts/persistence/offline_persistence.gd")
const ContentHash := preload("res://scripts/network/content_hash.gd")

const PRIOR: Array[int] = [1, 3, 4, 6, 7, 8]
const CURRENT: Array[int] = [1, 2, 3, 4, 6, 7]
const STAMP: String = "2026-11-22T00:00:00Z"
var _root: String = ""
var _position: Vector3 = Vector3.ZERO


func before_each() -> void:
	Network.clear_host_memory_for_test()
	_root = "user://exp015_a12_3_" + str(Time.get_ticks_usec()) + "_" + str(randi())
	_position = Vector3.ZERO


func after_each() -> void:
	Network.clear_host_memory_for_test()


func _position_for(_player: String) -> Vector3:
	return _position


func _restore(atlas: Dictionary, profile: Dictionary, index: int) -> void:
	var site: String = "LV_%03d" % index
	var level: Dictionary = Atlas.find_level(atlas, site)
	var receipt: Dictionary = Ledger.make_receipt(
		str(profile["account_key"]), site, str(level["tasks"][4]["id"]),
		"restoration")
	assert_true(bool(Ledger.apply_receipt(profile, receipt, atlas).get("applied", false)),
		"source-only fixture: never a game-played restoration receipt")


func _context(region: int, account: String, complete_anchor: bool) -> Dictionary:
	var atlas: Dictionary = Atlas.load_catalog()
	var profile: Dictionary = Ledger.new_profile(account)
	for previous: int in range(region):
		for slot: int in PRIOR:
			_restore(atlas, profile, previous * 8 + slot)
	var root: String = "LV_%03d" % (region * 8 + 1)
	var network: Network = Network.new()
	var configured: Dictionary = network.configure(atlas, profile, root)
	assert_true(bool(configured.get("ok", false)), str(configured))
	if not bool(configured.get("ok", false)):
		return {}
	for slot: int in CURRENT:
		_restore(atlas, profile, region * 8 + slot)
	var finale: String = "LV_%03d" % (region * 8 + 8)
	var attached: Dictionary = network.attach_site(atlas, profile, finale)
	assert_true(bool(attached.get("ok", false)), str(attached))
	if not bool(attached.get("ok", false)):
		return {}
	var path: Dictionary = network.anchor_route_snapshot()
	if complete_anchor:
		for blocker: Dictionary in path["blockers"]:
			if str(blocker["code"]) == "ORIGINAL_RECEIPT_MISSING":
				_restore(atlas, profile,
					str(blocker["site_id"]).trim_prefix("LV_").to_int())
		assert_true(bool(network.refresh_receipts(atlas, profile).get("ok", false)))
	return {"atlas": atlas, "profile": profile, "network": network}


func test_EXP015_A12_3_real_25_region_external_source_faults() -> void:
	var recovered: int = 0
	for region: int in range(25):
		var context: Dictionary = _context(region,
			"a12_3_external_%02d" % (region + 1), true)
		if context.is_empty():
			continue
		var network: Network = context["network"]
		var path: Dictionary = network.anchor_route_snapshot()
		assert_true(bool(path["anchor_energized"]), str(path))
		var feeders: Array = path["original_feeder_path"]
		var affected: String = str(feeders[region % feeders.size()]["edge_id"])
		var original: Dictionary = Network.entry_for(Network.load_book(),
			str(network.snapshot()["level_id"]))
		var before: Dictionary = network.site_conditions()
		assert_true(bool(network.host_transition("trip_feeder",
			affected, str(original["fault_signature"])).get("ok", false)))
		assert_false(bool(network.anchor_route_snapshot()["anchor_energized"]))
		var controller: Recovery = Recovery.new()
		assert_true(bool(controller.configure(network).get("ok", false)))
		assert_true(bool(controller.operate("anchor_audit").get("ok", false)))
		assert_eq(str(controller.operate("anchor_defer")["code"]),
			"ANCHOR_REAL_DARK_SOURCE_REQUIRED")
		assert_eq(str(controller.operate("anchor_trip")["code"]),
			"ANCHOR_LIVE_ORIGINAL_PATH_REQUIRED")
		assert_true(bool(controller.operate("anchor_repair").get("ok", false)))
		assert_eq(str(controller.snapshot()["active_recovery_feeder"]), affected)
		assert_eq(str(controller.operate("anchor_reset")["code"]),
			"ANCHOR_ORIGINAL_CLEARANCE_REQUIRED")
		assert_eq(str(controller.operate("anchor_proof:FAKE")["code"]),
			"ANCHOR_UNKNOWN_OR_FORGED_PROOF")
		var clearance: String = "anchor_proof:" + str(original["recovery_procedure"])
		assert_true(bool(controller.operate(clearance).get("ok", false)))
		assert_false(bool(network.anchor_route_snapshot()["anchor_energized"]))
		assert_true(bool(controller.operate("anchor_reset").get("ok", false)))
		assert_true(bool(controller.operate("anchor_verify").get("ok", false)))
		assert_true(bool(controller.operate("anchor_signoff").get("ok", false)))
		assert_true(controller.closed())
		assert_eq(int(network.snapshot()["reserve_pu"]), int(before["reserve_pu"]))
		assert_eq(int(network.site_conditions()["service_debt"]),
			int(before["service_debt"]))
		assert_true(bool(network.host_transition("isolate_feeder", affected).get("ok", false)))
		assert_false(controller.closed(), "new real feeder isolation revokes closeout")
		assert_true(bool(network.host_transition("reset_feeder", affected).get("ok", false)))
		assert_true(controller.closed())
		recovered += 1
	assert_eq(recovered, 25)


func test_EXP015_A12_3_multiple_original_faults_must_all_be_repaired() -> void:
	var context: Dictionary = _context(0, "a12_3_two_authentic_faults", true)
	if context.is_empty():
		return
	var network: Network = context["network"]
	var path: Dictionary = network.anchor_route_snapshot()
	var edges: Array = path["original_feeder_path"]
	assert_true(edges.size() >= 2)
	if edges.size() < 2:
		return
	var original: Dictionary = Network.entry_for(Network.load_book(),
		str(network.snapshot()["level_id"]))
	var proof: String = "anchor_proof:" + str(original["recovery_procedure"])
	for i: int in range(2):
		assert_true(bool(network.host_transition("trip_feeder",
			str(edges[i]["edge_id"]), str(original["fault_signature"])).get("ok", false)))
	var controller: Recovery = Recovery.new()
	assert_true(bool(controller.configure(network).get("ok", false)))
	assert_true(bool(controller.operate("anchor_audit").get("ok", false)))
	for i: int in range(2):
		assert_true(bool(controller.operate("anchor_repair").get("ok", false)))
		assert_eq(str(controller.snapshot()["active_recovery_feeder"]),
			str(edges[i]["edge_id"]))
		assert_true(bool(controller.operate(proof).get("ok", false)))
		assert_true(bool(controller.operate("anchor_reset").get("ok", false)))
		assert_eq(str(controller.snapshot()["phase"]),
			"choice_pending" if i == 0 else "verification_pending")
	assert_true(bool(controller.operate("anchor_verify").get("ok", false)))
	assert_true(bool(controller.operate("anchor_signoff").get("ok", false)))
	assert_true(controller.closed())
	for edge: Dictionary in edges:
		assert_true(controller.protects_original_asset(
			"regional_isolate:" + str(edge["edge_id"])))
		assert_true(controller.protects_original_asset(
			"regional_reset:" + str(edge["edge_id"])))


func test_EXP015_A12_3_dark_upstream_receipt_is_not_repairable() -> void:
	for region: int in [10, 24]:
		var ctx: Dictionary = _context(region,
			"a12_3_missing_%02d" % (region + 1), false)
		if ctx.is_empty():
			continue
		var network: Network = ctx["network"]
		var missing: Dictionary = network.anchor_route_snapshot()
		assert_false(bool(missing["anchor_energized"]))
		var controller: Recovery = Recovery.new()
		assert_true(bool(controller.configure(network).get("ok", false)))
		assert_true(bool(controller.operate("anchor_audit").get("ok", false)))
		assert_eq(str(controller.operate("anchor_repair")["code"]),
			"ANCHOR_ORIGINAL_FEEDER_REPAIR_REQUIRED")
		assert_true(bool(controller.operate("anchor_defer").get("ok", false)))
		assert_true(bool(controller.operate("anchor_verify").get("ok", false)))
		assert_true(bool(controller.operate("anchor_signoff").get("ok", false)))
		assert_true(controller.closed())
		assert_false(bool(network.anchor_route_snapshot()["anchor_energized"]),
			"managed deferral is never synthetic restoration")
		for item: Dictionary in missing["blockers"]:
			if str(item["code"]) == "ORIGINAL_RECEIPT_MISSING":
				_restore(ctx["atlas"], ctx["profile"],
					str(item["site_id"]).trim_prefix("LV_").to_int())
		assert_true(bool(network.refresh_receipts(
			ctx["atlas"], ctx["profile"]).get("ok", false)))
		assert_false(controller.closed(), "new original receipt revokes dark signoff")
		assert_true(bool(network.anchor_route_snapshot()["anchor_energized"]))


func _send(host: Runtime, seq: int, board: String, action: String,
		peer: int = 1) -> Dictionary:
	host.host.tick(seq)
	return host.receive(peer, JSON.stringify({
		"session": host.session_id(), "seq": seq,
		"type": "operate_worksite", "entity": board,
		"payload": {"action": action}
	}).to_utf8_buffer())


func test_EXP015_A12_3_authenticated_host_rejects_bypass_and_repairs_fault() -> void:
	var account: String = "a12_3_authenticated_host"
	var ctx: Dictionary = _context(0, account, true)
	if ctx.is_empty():
		return
	var saves: Saves = Saves.new()
	saves.configure(1, Offline.SAVE_BUILD_ID,
		ContentHash.content_revision(), ContentHash.rules_revision())
	var path: String = _root.path_join("profiles").path_join(account).path_join(
		Ledger.PROFILE_FILE)
	assert_true(bool(saves.write_record(path, Ledger.KIND_PROFILE,
		account, ctx["profile"], STAMP).get("ok", false)))
	var host: Runtime = Runtime.new()
	var ready: Dictionary = host.start("LV_008", Callable(self, "_position_for"),
		Callable(), account, true, _root,
		true, true, true, true, true,
		true, true, true, true, true,
		true, true, true, true, true,
		true, true, true, true, true,
		false, false, false, true, true)
	assert_true(bool(ready.get("ok", false)), str(ready))
	if not bool(ready.get("ok", false)):
		return
	assert_true(str(ready["content_revision"]).begins_with("EXP015_A12_3_"))
	var board: String = str(host.worksite.definition_snapshot()["board"])
	_position = host.definition_snapshot()["positions"][board]
	var network: Network = host.regional_network
	var route: Dictionary = network.anchor_route_snapshot()
	var last: String = str(route["original_feeder_path"][-1]["edge_id"])
	var original: Dictionary = Network.entry_for(Network.load_book(), "LV_008")
	assert_true(bool(network.host_transition(
		"trip_feeder", last, str(original["fault_signature"])).get("ok", false)))
	assert_false(bool(_send(host, 1, board, "anchor_audit", 999).get("ok", false)))
	assert_true(bool(_send(host, 1, board, "anchor_audit").get("ok", false)))
	assert_eq(str(_send(host, 2, board, "regional_reset:" + last)["code"]),
		"EXP015_A12_PROTECTED_ORIGINAL_PATH")
	assert_eq(str(_send(host, 3, board, "anchor_defer")["code"]),
		"ANCHOR_REAL_DARK_SOURCE_REQUIRED")
	assert_true(bool(_send(host, 4, board, "anchor_repair").get("ok", false)))
	assert_false(bool(_send(host, 5, board, "anchor_proof:BAD").get("ok", false)))
	assert_true(bool(_send(host, 6, board,
		"anchor_proof:" + str(original["recovery_procedure"])).get("ok", false)))
	assert_true(bool(_send(host, 7, board, "anchor_reset").get("ok", false)))
	assert_true(bool(_send(host, 8, board, "anchor_verify").get("ok", false)))
	assert_true(bool(_send(host, 9, board, "anchor_signoff").get("ok", false)))
	assert_true(host.regional_anchor_recovery.closed())
	assert_true(bool(_send(host, 9, board, "anchor_signoff").get("duplicate", false)))
	assert_eq(host.pending_rewards(account).size(), 0)
	assert_false(host.completed())
