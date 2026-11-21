extends "res://tests/test_case.gd"
## EXP014 A09.5 integration safety gates: live break-before-make and
## authenticated regional completion. Source/headless only; physical held.

const Atlas := preload("res://scripts/world/dispatch_atlas.gd")
const Ledger := preload("res://scripts/progression/expedition_ledger.gd")
const Network := preload("res://scripts/gameplay/expedition_regional_network.gd")
const Runtime := preload("res://scripts/gameplay/expedition_host_session.gd")

var _position: Vector3 = Vector3.ZERO

func before_each() -> void:
	Network.clear_host_memory_for_test()
	_position = Vector3.ZERO


func after_each() -> void:
	Network.clear_host_memory_for_test()


func _stand(_player: String) -> Vector3:
	return _position


func _restore(profile: Dictionary, atlas: Dictionary, id: String) -> void:
	var source: Dictionary = Atlas.find_level(atlas, id)
	var receipt: Dictionary = Ledger.make_receipt(str(profile["account_key"]),
		id, str(source["tasks"][4]["id"]), "restoration")
	var applied: Dictionary = Ledger.apply_receipt(profile, receipt, atlas)
	assert_true(bool(applied.get("applied", false)), str(applied))


func test_EXP014_A09_5_reset_refuses_make_before_break_even_when_receiver_dark() -> void:
	var atlas: Dictionary = Atlas.load_catalog()
	var profile: Dictionary = Ledger.new_profile("a095_interlock")
	_restore(profile, atlas, "LV_001")
	_restore(profile, atlas, "LV_003")
	var net: Network = Network.new()
	assert_true(bool(net.configure(atlas, profile, "LV_003").get("ok", false)))
	assert_true(bool(net.host_transition("isolate_feeder", "NET_01_F05")["ok"]))
	assert_true(bool(net.host_transition("engage_tie", "NET_01_T01")["ok"]))
	assert_eq(net.host_transition("reset_feeder", "NET_01_F05")["code"],
		"BREAK_BEFORE_MAKE_INTERLOCK")
	assert_true(bool(net.snapshot()["feeders"]["NET_01_F05"]["isolated"]))
	assert_true(bool(net.snapshot()["ties"]["NET_01_T01"]["engaged"]))
	assert_eq(net.snapshot()["reserve_pu"], 4)
	assert_true(bool(net.host_transition("release_tie", "NET_01_T01")["ok"]))
	assert_true(bool(net.host_transition("reset_feeder", "NET_01_F05")["ok"]))
	assert_false(bool(net.snapshot()["feeders"]["NET_01_F05"]["isolated"]))
	assert_eq(net.snapshot()["reserve_pu"], 4)


func test_EXP014_A09_5_mutated_double_standby_must_not_double_energize() -> void:
	var atlas: Dictionary = Atlas.load_catalog()
	var profile: Dictionary = Ledger.new_profile("a095_double")
	_restore(profile, atlas, "LV_001")
	_restore(profile, atlas, "LV_003")
	var book: Dictionary = Network.load_book().duplicate(true)
	book["regions"][0]["standby_ties"][1]["to"] = "LV_006"
	var net: Network = Network.new()
	var outcome: Dictionary = net.configure(atlas, profile, "LV_003", book)
	assert_true(bool(outcome.get("ok", false)), str(outcome))
	if not bool(outcome.get("ok", false)):
		return
	assert_true(bool(net.host_transition("isolate_feeder", "NET_01_F05")["ok"]))
	assert_true(bool(net.host_transition("engage_tie", "NET_01_T01")["ok"]))
	assert_eq(net.host_transition("engage_tie", "NET_01_T02")["code"],
		"BREAK_BEFORE_MAKE_INTERLOCK")
	assert_eq(net.snapshot()["reserve_pu"], 4)
	assert_false(bool(net.snapshot()["ties"]["NET_01_T02"]["engaged"]))


func test_EXP014_A09_5_recharge_requires_live_restored_reserve_anchor() -> void:
	var atlas: Dictionary = Atlas.load_catalog()
	var profile: Dictionary = Ledger.new_profile("a095_recharge")
	_restore(profile, atlas, "LV_001")
	_restore(profile, atlas, "LV_006")
	var net: Network = Network.new()
	assert_true(bool(net.configure(atlas, profile, "LV_001")["ok"]))
	assert_eq(net.host_transition("recharge_reserve", "LV_006")["code"],
		"RESERVE_RECHARGE_DENIED")
	_restore(profile, atlas, "LV_002")
	assert_true(bool(net.refresh_receipts(atlas, profile)["ok"]))
	assert_true(bool(net.snapshot()["sites"]["LV_006"]["energized"]))
	assert_true(bool(net.host_transition("recharge_reserve", "LV_006")["ok"]))
	assert_eq(net.host_transition("recharge_reserve", "LV_006")["code"],
		"RESERVE_RECHARGE_DENIED")


func test_EXP014_A09_5_opt_in_host_blocks_extraction_until_regional_preparation() -> void:
	var host: Runtime = Runtime.new()
	var account: String = "a095_host_gate"
	var root: String = "user://a095_gate_" + str(Time.get_ticks_usec())
	var result: Dictionary = host.start("LV_001", Callable(self, "_stand"),
		Callable(), account, true, root, true, true, true, true, true,
		true, true, true, true, true, true, true, true, true, true)
	assert_true(bool(result.get("ok", false)), str(result))
	if not bool(result.get("ok", false)):
		return
	assert_true(bool(result["regional_network_active"]))
	var guard: Dictionary = host._bespoke_guard(Runtime.PLAYER_ID,
		"request_extract", "ZONE_EXTRACT", {})
	assert_eq(str(guard.get("code", "")), "EXP014_A09_PREPARATION_REQUIRED")
	assert_false(host.completed())
	var before: Dictionary = host.task_board()
	assert_false(bool(before["mission_completed"]))
	var board: String = str(host.worksite.definition_snapshot()["board"])
	_position = host.definition_snapshot()["positions"][board]
	var wire: PackedByteArray = JSON.stringify({"session": host.session_id(),
		"seq": 1, "type": "operate_worksite", "entity": board,
		"payload": {"action": "regional_managed"}}).to_utf8_buffer()
	var unauthorized: Dictionary = host.receive(999, wire)
	assert_false(bool(unauthorized.get("ok", false)))
	assert_false(host.regional_network.site_prepared())
	var permitted: Dictionary = host.receive(1, wire)
	assert_true(bool(permitted.get("ok", false)), str(permitted))
	assert_true(host.regional_network.site_prepared())
	guard = host._bespoke_guard(Runtime.PLAYER_ID,
		"request_extract", "ZONE_EXTRACT", {})
	assert_ne(str(guard.get("code", "")), "EXP014_A09_PREPARATION_REQUIRED")
	assert_false(host.completed(), "Regional preparation alone cannot complete the mission")
	assert_eq(host.pending_rewards(account).size(), 0)
