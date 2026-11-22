extends "res://tests/test_case.gd"
## EXP015 A12.4: source history, not a returned-to-normal snapshot,
## controls whether verified original feeder signoff remains authoritative.
const Atlas := preload("res://scripts/world/dispatch_atlas.gd")
const Ledger := preload("res://scripts/progression/expedition_ledger.gd")
const Network := preload("res://scripts/gameplay/expedition_regional_network.gd")
const Recovery := preload("res://scripts/gameplay/expedition_regional_anchor_recovery.gd")

const PRIOR: Array[int] = [1, 3, 4, 6, 7, 8]
const CURRENT: Array[int] = [1, 2, 3, 4, 6, 7]


func before_each() -> void:
	Network.clear_host_memory_for_test()


func after_each() -> void:
	Network.clear_host_memory_for_test()


func _restore(atlas: Dictionary, profile: Dictionary, index: int) -> void:
	var site: String = "LV_%03d" % index
	var level: Dictionary = Atlas.find_level(atlas, site)
	var receipt: Dictionary = Ledger.make_receipt(
		str(profile["account_key"]), site, str(level["tasks"][4]["id"]),
		"restoration")
	assert_true(bool(Ledger.apply_receipt(profile, receipt, atlas).get("applied", false)))


func _context(region: int) -> Dictionary:
	var atlas: Dictionary = Atlas.load_catalog()
	var profile: Dictionary = Ledger.new_profile("a12_4_epoch_%02d" % region)
	for previous: int in range(region):
		for slot: int in PRIOR:
			_restore(atlas, profile, previous * 8 + slot)
	var network: Network = Network.new()
	var root: String = "LV_%03d" % (region * 8 + 1)
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
	for blocker: Dictionary in network.anchor_route_snapshot()["blockers"]:
		if str(blocker["code"]) == "ORIGINAL_RECEIPT_MISSING":
			_restore(atlas, profile,
				str(blocker["site_id"]).trim_prefix("LV_").to_int())
	assert_true(bool(network.refresh_receipts(atlas, profile).get("ok", false)))
	return {"network": network}


func _complete_real_repair(network: Network, recovery: Recovery,
		feeder: String, procedure: String) -> void:
	assert_true(bool(recovery.operate("anchor_audit").get("ok", false)))
	assert_true(bool(recovery.operate("anchor_trip").get("ok", false)))
	assert_true(bool(recovery.operate("anchor_proof:" + procedure).get("ok", false)))
	assert_true(bool(recovery.operate("anchor_reset").get("ok", false)))
	assert_true(bool(recovery.operate("anchor_verify").get("ok", false)))
	assert_true(bool(recovery.operate("anchor_signoff").get("ok", false)))
	assert_true(recovery.closed(), "original feeder proof must be live at signoff")
	assert_false(bool(network.snapshot()["feeders"][feeder]["isolated"]))


func test_EXP015_A12_4_25_regions_transient_fault_never_resurrects_signoff() -> void:
	var checked: int = 0
	for region: int in range(25):
		var context: Dictionary = _context(region)
		if context.is_empty():
			continue
		var network: Network = context["network"]
		var plan: Dictionary = network.anchor_route_snapshot()
		assert_true(bool(plan["anchor_energized"]))
		var feeder: String = str(plan["original_feeder_path"][-1]["edge_id"])
		var source: Dictionary = Network.entry_for(Network.load_book(),
			str(network.snapshot()["level_id"]))
		var reserve_before: int = int(network.snapshot()["reserve_pu"])
		var recovery: Recovery = Recovery.new()
		assert_true(bool(recovery.configure(network).get("ok", false)))
		_complete_real_repair(network, recovery, feeder,
			str(source["recovery_procedure"]))
		var recorded: int = int(recovery.snapshot()["verified_source_revision"])
		assert_true(bool(network.host_transition("trip_feeder",
			feeder, str(source["fault_signature"])).get("ok", false)))
		assert_false(recovery.closed())
		assert_true(bool(network.host_transition("clear_fault",
			feeder, str(source["recovery_procedure"])).get("ok", false)))
		assert_true(bool(network.host_transition("reset_feeder", feeder).get("ok", false)))
		assert_true(bool(network.anchor_route_snapshot()["anchor_energized"]))
		assert_true(int(recovery.snapshot()["current_source_revision"]) > recorded)
		assert_false(recovery.closed(),
			"transient fault and authentic repair cannot reuse earlier signoff")
		assert_true(bool(recovery.operate("anchor_audit").get("ok", false)))
		assert_eq(str(recovery.snapshot()["phase"]), "choice_pending")
		assert_eq(str(recovery.operate("anchor_signoff")["code"]),
			"ANCHOR_STABLE_SOURCE_REQUIRED")
		assert_eq(int(network.snapshot()["reserve_pu"]), reserve_before)
		checked += 1
	assert_eq(checked, 25)


func test_EXP015_A12_4_verified_but_not_signed_transient_change_requires_reaudit() -> void:
	var context: Dictionary = _context(0)
	if context.is_empty():
		return
	var network: Network = context["network"]
	var route: Dictionary = network.anchor_route_snapshot()
	var feeder: String = str(route["original_feeder_path"][-1]["edge_id"])
	var source: Dictionary = Network.entry_for(Network.load_book(),
		str(network.snapshot()["level_id"]))
	var recovery: Recovery = Recovery.new()
	assert_true(bool(recovery.configure(network).get("ok", false)))
	assert_true(bool(recovery.operate("anchor_audit").get("ok", false)))
	assert_true(bool(recovery.operate("anchor_trip").get("ok", false)))
	assert_true(bool(recovery.operate(
		"anchor_proof:" + str(source["recovery_procedure"])).get("ok", false)))
	assert_true(bool(recovery.operate("anchor_reset").get("ok", false)))
	assert_true(bool(recovery.operate("anchor_verify").get("ok", false)))
	assert_eq(str(recovery.snapshot()["phase"]), "verified")
	assert_true(bool(network.host_transition("isolate_feeder", feeder).get("ok", false)))
	assert_true(bool(network.host_transition("reset_feeder", feeder).get("ok", false)))
	assert_true(bool(network.anchor_route_snapshot()["anchor_energized"]))
	assert_eq(str(recovery.operate("anchor_signoff")["code"]),
		"ANCHOR_SOURCE_CHANGED_AFTER_VERIFY")
	assert_eq(str(recovery.snapshot()["phase"]), "audit_pending")
	assert_false(recovery.closed())
	_complete_real_repair(network, recovery, feeder,
		str(source["recovery_procedure"]))
	assert_true(recovery.closed(), "fresh proof and new source epoch can close")
