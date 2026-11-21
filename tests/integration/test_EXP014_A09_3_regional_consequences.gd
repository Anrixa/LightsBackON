extends "res://tests/test_case.gd"
## EXP014 A09.3: receipt-derived operational choices, shared live host context
## and recoverable islanding. No physical/controller/release certification.
const Atlas := preload("res://scripts/world/dispatch_atlas.gd")
const Ledger := preload("res://scripts/progression/expedition_ledger.gd")
const Network := preload("res://scripts/gameplay/expedition_regional_network.gd")
const Runtime := preload("res://scripts/gameplay/expedition_host_session.gd")

func _restore(profile: Dictionary, atlas: Dictionary, level_id: String) -> void:
	var level: Dictionary = Atlas.find_level(atlas, level_id)
	var receipt: Dictionary = Ledger.make_receipt(str(profile["account_key"]),
		level_id, str(level["tasks"][4]["id"]), "restoration")
	var result: Dictionary = Ledger.apply_receipt(profile, receipt, atlas)
	assert_true(bool(result.get("applied", false)), str(result))


func _position(_player: String) -> Vector3:
	return Vector3(0.0, 0.9, 0.0)


func test_EXP014_A09_3_receipt_strategies_change_actual_future_network_state() -> void:
	Network.clear_host_memory_for_test()
	var atlas: Dictionary = Atlas.load_catalog()
	var critical: Dictionary = Ledger.new_profile("a093_critical")
	_restore(critical, atlas, "LV_001")
	_restore(critical, atlas, "LV_003")
	var c: Dictionary = Network.acquire(atlas, critical, "LV_004")
	assert_true(bool(c.get("ok", false)), str(c))
	if not bool(c.get("ok", false)):
		return
	var network: Variant = c["network"]
	assert_eq(network.select_strategy("resilience_first")["code"],
		"REGIONAL_STRATEGY_RECEIPT_REQUIRED")
	assert_true(bool(network.select_strategy("critical_first")["ok"]))
	assert_eq(network.snapshot()["reserve_pu"], 4)
	assert_eq(network.site_conditions()["service_debt"], 0)
	assert_eq(network.select_strategy("critical_first")["code"], "REGIONAL_STRATEGY_ALREADY_LOCKED")
	_restore(critical, atlas, "LV_004")
	var next: Dictionary = Network.acquire(atlas, critical, "LV_006")
	assert_true(bool(next.get("ok", false)), str(next))
	if bool(next.get("ok", false)):
		assert_true(bool(next["reused"]))
		assert_eq(next["network"].snapshot()["strategy"], "critical_first")
		assert_false(bool(next["network"].site_conditions()["supply_ready"]))
		assert_true(bool(next["network"].prepare_site("buffer")["ok"]))
		assert_eq(next["network"].snapshot()["reserve_pu"], 2)

	var resilience: Dictionary = Ledger.new_profile("a093_resilience")
	_restore(resilience, atlas, "LV_001")
	_restore(resilience, atlas, "LV_002")
	var r: Dictionary = Network.acquire(atlas, resilience, "LV_004")
	assert_true(bool(r.get("ok", false)), str(r))
	if not bool(r.get("ok", false)):
		return
	var resilient: Variant = r["network"]
	assert_true(bool(resilient.select_strategy("resilience_first")["ok"]))
	assert_eq(resilient.snapshot()["reserve_pu"], 6)
	assert_eq(resilient.site_conditions()["service_debt"], 2)
	assert_ne(resilient.snapshot()["strategy"], network.snapshot()["strategy"])
	assert_true(bool(resilient.prepare_site("managed")["ok"]))
	assert_eq(resilient.snapshot()["reserve_pu"], 6)
	assert_eq(resilient.prepare_site("buffer")["code"], "SITE_ALREADY_PREPARED")
	Network.clear_host_memory_for_test()


func test_EXP014_A09_3_unverified_context_or_legacy_opt_in_fails_closed() -> void:
	Network.clear_host_memory_for_test()
	var atlas: Dictionary = Atlas.load_catalog()
	var profile: Dictionary = Ledger.new_profile("a093_invalid")
	_restore(profile, atlas, "LV_001")
	var created: Dictionary = Network.acquire(atlas, profile, "LV_002")
	assert_true(bool(created.get("ok", false)), str(created))
	var fake: Dictionary = profile.duplicate(true)
	fake["completed_levels"]["LV_004"] = true
	assert_eq(Network.acquire(atlas, fake, "LV_003")["code"], "RESTORATION_RECEIPT_HOLD")
	var host: Runtime = Runtime.new()
	var illegal: Dictionary = host.start("LV_001", Callable(self, "_position"),
		Callable(), "", false, "", true, true, true, true, true,
		true, true, true, true, true, true, true, true, true, true)
	assert_eq(illegal["code"], "EXP014_A09_REQUIRES_A08_AND_HOST_CAMPAIGN")
	Network.clear_host_memory_for_test()
