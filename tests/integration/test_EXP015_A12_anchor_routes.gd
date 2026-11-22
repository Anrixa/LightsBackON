extends "res://tests/test_case.gd"
## A12.1 real source feeder-path blockers and recovery; no hosted A12 ingress yet.
const Atlas := preload("res://scripts/world/dispatch_atlas.gd")
const Ledger := preload("res://scripts/progression/expedition_ledger.gd")
const Network := preload("res://scripts/gameplay/expedition_regional_network.gd")

const PRIOR_SPINE: Array[int] = [1, 3, 4, 6, 7, 8]
const CURRENT_SPINE: Array[int] = [1, 2, 3, 4, 6, 7]


func _restore(atlas: Dictionary, profile: Dictionary, index: int) -> void:
	var site: String = "LV_%03d" % index
	var level: Dictionary = Atlas.find_level(atlas, site)
	var receipt: Dictionary = Ledger.make_receipt(str(profile["account_key"]),
		site, str(level["tasks"][4]["id"]), "restoration")
	assert_true(bool(Ledger.apply_receipt(profile, receipt, atlas).get("applied", false)),
		"A12 headless original EXP04 receipt fixture only")


func test_EXP015_A12_original_anchor_paths_blockers_and_real_fault_recovery() -> void:
	var atlas: Dictionary = Atlas.load_catalog()
	var paths: int = 0
	var dark: int = 0
	for region: int in range(25):
		var profile: Dictionary = Ledger.new_profile("a12_route_%02d" % (region + 1))
		for previous: int in range(region):
			for slot: int in PRIOR_SPINE:
				_restore(atlas, profile, previous * 8 + slot)
		var root: String = "LV_%03d" % (region * 8 + 1)
		var network: Network = Network.new()
		assert_true(bool(network.configure(atlas, profile, root).get("ok", false)))
		for slot: int in CURRENT_SPINE:
			_restore(atlas, profile, region * 8 + slot)
		var finale: String = "LV_%03d" % (region * 8 + 8)
		assert_true(bool(network.attach_site(atlas, profile, finale).get("ok", false)))
		var original: Dictionary = Network.entry_for(Network.load_book(), finale)
		var anchor: String = str(original["reserve_anchor_site"])
		var evidence: Dictionary = network.anchor_route_snapshot()
		assert_true(bool(evidence.get("ok", false)), str(evidence))
		assert_eq(str(evidence["root_source_site_id"]), root)
		assert_eq(str(evidence["reserve_anchor_site_id"]), anchor)
		assert_eq(str(evidence["original_site_path"][0]), root)
		assert_eq(str(evidence["original_site_path"][-1]), anchor)
		assert_eq(evidence["original_feeder_path"].size() + 1,
			evidence["original_site_path"].size())
		var missing: Array[String] = []
		for block: Dictionary in evidence["blockers"]:
			if block["code"] == "ORIGINAL_RECEIPT_MISSING":
				missing.append(str(block["site_id"]))
		if not missing.is_empty():
			dark += 1
			assert_false(bool(evidence["anchor_energized"]))
			assert_true(region in [10, 24], "only two original dark-anchor regions")
			for site: String in missing:
				_restore(atlas, profile, site.trim_prefix("LV_").to_int())
			assert_true(bool(network.refresh_receipts(atlas, profile).get("ok", false)))
			evidence = network.anchor_route_snapshot()
		assert_true(bool(evidence["anchor_energized"]), str(evidence))
		assert_eq(evidence["blockers"].size(), 0)
		var reserves: int = int(evidence["reserve_pu"])
		var feeder_path: Array = evidence["original_feeder_path"]
		var target: String = str(feeder_path[-1]["edge_id"])
		var tripped: Dictionary = network.host_transition(
			"trip_feeder", target, str(original["fault_signature"]))
		assert_true(bool(tripped.get("ok", false)), str(tripped))
		var fault: Dictionary = network.anchor_route_snapshot()
		assert_false(bool(fault["anchor_energized"]))
		assert_true(fault["blockers"].any(func(b: Dictionary) -> bool:
			return b["code"] == "ORIGINAL_FEEDER_FAULT" and b["edge_id"] == target))
		assert_true(bool(network.host_transition(
			"clear_fault", target, str(original["recovery_procedure"])).get("ok", false)))
		assert_false(bool(network.anchor_route_snapshot()["anchor_energized"]),
			"fault clearance alone does not close an isolated original feeder")
		assert_true(bool(network.host_transition("reset_feeder", target).get("ok", false)))
		assert_true(bool(network.anchor_route_snapshot()["anchor_energized"]))
		assert_eq(int(network.anchor_route_snapshot()["reserve_pu"]), reserves)
		paths += 1
	assert_eq(paths, 25)
	assert_eq(dark, 2)


func test_EXP015_A12_unconfigured_network_cannot_invent_anchor_path() -> void:
	var network: Network = Network.new()
	assert_eq(str(network.anchor_route_snapshot().get("code", "")), "NOT_CONFIGURED")
