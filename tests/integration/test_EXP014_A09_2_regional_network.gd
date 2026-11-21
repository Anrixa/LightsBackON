extends "res://tests/test_case.gd"
## A09.2 host-source, receipt and feeder-transition regression (headless only).
const Atlas := preload("res://scripts/world/dispatch_atlas.gd")
const Campaign := preload("res://scripts/progression/expedition_campaign.gd")
const Ledger := preload("res://scripts/progression/expedition_ledger.gd")
const Network := preload("res://scripts/gameplay/expedition_regional_network.gd")

const ACCOUNT: String = "a092_probe"

func _restore(profile: Dictionary, atlas: Dictionary, level_id: String) -> void:
	var source: Dictionary = Atlas.find_level(atlas, level_id)
	var receipt: Dictionary = Ledger.make_receipt(ACCOUNT, level_id,
		str(source["tasks"][4]["id"]), "restoration")
	var result: Dictionary = Ledger.apply_receipt(profile, receipt, atlas)
	assert_true(bool(result.get("applied", false)), str(result))


func test_EXP014_A09_2_all_regional_networks_are_real_source_bound() -> void:
	var atlas: Dictionary = Atlas.load_catalog()
	var book: Dictionary = Network.load_book()
	assert_eq(book["regions"].size(), 25)
	for region: Dictionary in book["regions"]:
		var gate: Dictionary = Network.inspect_region(atlas, region)
		assert_true(bool(gate.get("ok", false)), str(region.get("region_id", "")) + ": " + str(gate))
		assert_eq(int(gate.get("sites", 0)), 8)
		var bad: Dictionary = region.duplicate(true)
		bad["source_sites"][0]["source_task_ids"][0] = "JOB_FORGED"
		assert_eq(Network.inspect_region(atlas, bad)["code"], "NETWORK_TASK_SOURCE_MISMATCH")


func test_EXP014_A09_2_receipt_gating_fault_isolation_and_safe_reset() -> void:
	var atlas: Dictionary = Atlas.load_catalog()
	var profile: Dictionary = Ledger.new_profile(ACCOUNT)
	var net: Network = Network.new()
	assert_eq(net.configure(atlas, profile, "LV_002")["code"], "NETWORK_CAMPAIGN_LOCK")
	assert_true(bool(net.configure(atlas, profile, "LV_001").get("ok", false)))
	var empty: Dictionary = net.snapshot()
	assert_eq(empty["reserve_pu"], 6)
	assert_false(bool(empty["sites"]["LV_001"]["energized"]))
	_restore(profile, atlas, "LV_001")
	assert_true(bool(net.refresh_receipts(atlas, profile)["ok"]))
	assert_true(bool(net.snapshot()["sites"]["LV_001"]["energized"]))
	var feeder: String = "NET_01_F01"
	assert_true(bool(net.host_transition("trip_feeder", feeder, "seepage_reentry")["ok"]))
	assert_eq(net.host_transition("reset_feeder", feeder)["code"], "FEEDER_RESET_DENIED")
	assert_eq(net.host_transition("clear_fault", feeder, "WRONG")["code"], "UNVERIFIED_RECOVERY")
	assert_true(bool(net.host_transition("clear_fault", feeder, "wet_trench_isolation")["ok"]))
	assert_true(bool(net.host_transition("reset_feeder", feeder)["ok"]))
	var forged: Dictionary = profile.duplicate(true)
	forged["completed_levels"]["LV_002"] = true
	assert_eq(net.refresh_receipts(atlas, forged)["code"], "RESTORATION_RECEIPT_HOLD")
	assert_false(bool(net.snapshot()["sites"]["LV_002"]["restored"]))


func test_EXP014_A09_2_non_replayable_reserve_and_tie_interlocks() -> void:
	var atlas: Dictionary = Atlas.load_catalog()
	var profile: Dictionary = Ledger.new_profile(ACCOUNT)
	_restore(profile, atlas, "LV_001")
	_restore(profile, atlas, "LV_003")
	var net: Network = Network.new()
	assert_true(bool(net.configure(atlas, profile, "LV_003")["ok"]))
	assert_eq(net.host_transition("engage_tie", "NET_01_T01")["code"],
		"BREAK_BEFORE_MAKE_INTERLOCK")
	# The isolated normal LV_006 arrival makes standby safe to engage.
	assert_true(bool(net.host_transition("isolate_feeder", "NET_01_F05")["ok"]))
	assert_true(bool(net.host_transition("engage_tie", "NET_01_T01")["ok"]))
	assert_eq(net.snapshot()["reserve_pu"], 4)
	assert_eq(net.host_transition("engage_tie", "NET_01_T01")["code"], "TIE_UNAVAILABLE")
	assert_eq(net.snapshot()["reserve_pu"], 4)
	assert_true(bool(net.host_transition("release_tie", "NET_01_T01")["ok"]))
	assert_eq(net.snapshot()["reserve_pu"], 4) # opening does not mint power
	assert_eq(net.host_transition("recharge_reserve", "LV_006")["code"], "RESERVE_RECHARGE_DENIED")
