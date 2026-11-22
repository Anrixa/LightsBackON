extends "res://tests/test_case.gd"
## EXP020 A01: real EXP04 receipt and EXP05 campaign graph, original A09 topology.
const Atlas := preload("res://scripts/world/dispatch_atlas.gd")
const Ledger := preload("res://scripts/progression/expedition_ledger.gd")
const Campaign := preload("res://scripts/progression/expedition_campaign.gd")
const Networks := preload("res://scripts/gameplay/expedition_regional_network.gd")
const Consequences := preload("res://scripts/progression/expedition_campaign_consequences.gd")


func _restore(profile: Dictionary, atlas: Dictionary, level_id: String) -> void:
	var level: Dictionary = Atlas.find_level(atlas, level_id)
	var receipt: Dictionary = Ledger.make_receipt(str(profile["account_key"]),
		level_id, str(level["tasks"][4]["id"]), "restoration")
	assert_true(bool(Ledger.apply_receipt(profile, receipt, atlas).get("ok", false)))


func test_EXP020_A01_real_persistent_receipts_project_25_regions_and_linked_sites() -> void:
	var atlas: Dictionary = Atlas.load_catalog()
	var routes: Dictionary = Campaign.load_routes()
	var source: Dictionary = Networks.load_book()
	var profile: Dictionary = Ledger.new_profile("EXP020_A01_REAL")
	var first: Dictionary = Consequences.evaluate(profile, atlas, routes, source)
	assert_true(bool(first.get("ok", false)), str(first))
	assert_eq((first["regions"] as Dictionary).size(), 25)
	assert_eq(int(first["restored_receipts"]), 0)
	assert_eq(int(first["receipt_connected_sites"]), 0)
	var alder: Dictionary = first["regions"]["REG_01"]
	assert_false(bool(alder["sites"]["LV_002"]["normal_path_receipt_connected"]))
	_restore(profile, atlas, "LV_001")
	var one: Dictionary = Consequences.evaluate(profile, atlas, routes, source)
	assert_eq(int(one["restored_receipts"]), 1)
	assert_eq(int(one["regions"]["REG_01"]["receipt_connected_sites"]), 1)
	assert_false(bool(one["regions"]["REG_01"]["sites"]["LV_002"]["normal_path_receipt_connected"]))
	# Gain is a cardinality, not a truth flag. Preserve its numeric source contract.
	var projected_gain: Variant = one["regions"]["REG_01"]["sites"]["LV_002"]["potential_connected_gain"]
	assert_eq(typeof(projected_gain), TYPE_INT, "source-derived planning gain must be an integer")
	assert_true(int(projected_gain) > 0, "restoring the next available linked site has a positive gain")
	_restore(profile, atlas, "LV_002")
	var two: Dictionary = Consequences.evaluate(profile, atlas, routes, source)
	assert_eq(int(two["regions"]["REG_01"]["receipt_connected_sites"]), 2)
	assert_true(bool(two["regions"]["REG_01"]["sites"]["LV_002"]["normal_path_receipt_connected"]))
	assert_false(bool(two["regions"]["REG_01"]["live_electrical_state_verified"]))
	assert_eq(str(two["authority"]), Consequences.AUTHORITY)
	var repeated: Dictionary = Ledger.make_receipt("EXP020_A01_REAL", "LV_002",
		str(Atlas.find_level(atlas, "LV_002")["tasks"][4]["id"]), "restoration")
	assert_false(bool(Ledger.apply_receipt(profile, repeated, atlas)["applied"]))
	assert_eq(int(profile["completed_levels"].size()), 2)
	assert_eq(int(Consequences.evaluate(profile, atlas, routes, source)["restored_receipts"]), 2)


func test_EXP020_A01_foreign_source_and_unearned_completion_fail_closed() -> void:
	var atlas: Dictionary = Atlas.load_catalog()
	var routes: Dictionary = Campaign.load_routes()
	var source: Dictionary = Networks.load_book()
	var profile: Dictionary = Ledger.new_profile("EXP020_A01_HOLD")
	profile["completed_levels"]["LV_003"] = true
	assert_false(bool(Consequences.evaluate(profile, atlas, routes, source).get("ok", false)))
	var fresh: Dictionary = Ledger.new_profile("EXP020_A01_HOLD")
	var falsified: Dictionary = source.duplicate(true)
	falsified["regions"][0]["primary_feeders"][0]["from"] = "FORGED_ROOT"
	assert_false(bool(Consequences.evaluate(fresh, atlas, routes, falsified).get("ok", false)))
