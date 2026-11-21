extends "res://tests/test_case.gd"
## EXP014 A09.4: all-region panel binding and actual SessionHost ingress.
## Excludes human/controller, GPU, Steam, physics, production-save certification.
const Atlas := preload("res://scripts/world/dispatch_atlas.gd")
const Ledger := preload("res://scripts/progression/expedition_ledger.gd")
const Network := preload("res://scripts/gameplay/expedition_regional_network.gd")
const Panel := preload("res://scripts/ui/expedition_regional_panel.gd")
const Runtime := preload("res://scripts/gameplay/expedition_host_session.gd")

var _last_action: String = ""
var _host_position: Vector3 = Vector3.ZERO


func _accepted(action: String) -> void:
	_last_action = action


func _position(_player: String) -> Vector3:
	return _host_position


func _restore(profile: Dictionary, atlas: Dictionary, level_id: String) -> void:
	var level: Dictionary = Atlas.find_level(atlas, level_id)
	var receipt: Dictionary = Ledger.make_receipt(str(profile["account_key"]),
		level_id, str(level["tasks"][4]["id"]), "restoration")
	var reply: Dictionary = Ledger.apply_receipt(profile, receipt, atlas)
	assert_true(bool(reply.get("applied", false)), str(reply))


func test_EXP014_A09_4_all_25_regional_panels_show_200_canonical_sites() -> void:
	var atlas: Dictionary = Atlas.load_catalog()
	var profile: Dictionary = Ledger.new_profile("a094_all_source")
	for level: Dictionary in atlas["levels"]:
		_restore(profile, atlas, str(level["id"]))
	var book: Dictionary = Network.load_book()
	var shown: Dictionary = {}
	for region: Dictionary in book["regions"]:
		var id: String = str(region["root_source_id"])
		var net: Network = Network.new()
		var configured: Dictionary = net.configure(atlas, profile, id)
		assert_true(bool(configured.get("ok", false)), str(configured))
		if not bool(configured.get("ok", false)):
			continue
		var panel: Panel = Panel.new()
		var snapshot: Dictionary = net.snapshot()
		panel.show_network(snapshot)
		assert_eq(snapshot["sites"].size(), 8)
		assert_eq(snapshot["feeders"].size(), 7)
		assert_eq(snapshot["ties"].size(), 2)
		assert_true(panel._heading.text.contains(id))
		assert_true(panel._nodes.text.contains(str(region["critical_service_site"])))
		assert_true(panel._assets.text.contains(str(region["primary_feeders"][0]["edge_id"])))
		shown[id] = true
	assert_eq(shown.size(), 25)


func test_EXP014_A09_4_panel_controls_submit_source_asset_not_local_verdict() -> void:
	_last_action = ""
	var atlas: Dictionary = Atlas.load_catalog()
	var profile: Dictionary = Ledger.new_profile("a094_view")
	var net: Network = Network.new()
	assert_true(bool(net.configure(atlas, profile, "LV_001")["ok"]))
	var panel: Panel = Panel.new()
	panel.action_requested.connect(Callable(self, "_accepted"))
	panel.show_network(net.snapshot())
	panel._handle("toggle_feeder")
	assert_eq(_last_action, "regional_isolate:NET_01_F01")
	assert_true(bool(net.host_transition("isolate_feeder", "NET_01_F01")["ok"]))
	panel.show_network(net.snapshot())
	panel._handle("toggle_feeder")
	assert_eq(_last_action, "regional_reset:NET_01_F01")
	panel.show_reply({"ok": false, "code": "BREAK_BEFORE_MAKE_INTERLOCK"})
	assert_true(panel._reply.text.contains("BREAK_BEFORE_MAKE_INTERLOCK"))
	assert_eq(net.snapshot()["reserve_pu"], 6)
	panel._handle("next_tie")
	panel._handle("toggle_tie")
	assert_true(_last_action.begins_with("regional_engage:NET_01_T"))


func test_EXP014_A09_4_real_host_ingress_rejects_foreign_peer_and_replays() -> void:
	Network.clear_host_memory_for_test()
	var runtime: Runtime = Runtime.new()
	var account: String = "a094_auth_host"
	var root: String = "user://a094_test_" + str(Time.get_ticks_usec())
	var started: Dictionary = runtime.start("LV_001", Callable(self, "_position"),
		Callable(), account, true, root, true, true, true, true, true,
		true, true, true, true, true, true, true, true, true, true)
	assert_true(bool(started.get("ok", false)), str(started))
	if not bool(started.get("ok", false)):
		return
	assert_true(bool(started["regional_network_active"]))
	var board: String = str(runtime.worksite.definition_snapshot()["board"])
	_host_position = runtime.definition_snapshot()["positions"][board]
	var message: Dictionary = {"session": runtime.session_id(), "seq": 1,
		"type": "operate_worksite", "entity": board,
		"payload": {"action": "regional_managed"}}
	var wire: PackedByteArray = JSON.stringify(message).to_utf8_buffer()
	var rejected: Dictionary = runtime.receive(999, wire)
	assert_false(bool(rejected.get("ok", false)))
	assert_false(runtime.regional_network.site_prepared())
	var accepted: Dictionary = runtime.receive(1, wire)
	assert_true(bool(accepted.get("ok", false)), str(accepted))
	assert_true(runtime.regional_network.site_prepared())
	var after: Dictionary = runtime.regional_network.snapshot()
	var duplicate: Dictionary = runtime.receive(1, wire)
	assert_true(bool(duplicate.get("duplicate", false)))
	assert_eq(runtime.regional_network.snapshot()["events"].size(), after["events"].size())
	var wrong: Dictionary = {"session": runtime.session_id(), "seq": 2,
		"type": "operate_worksite", "entity": "FORGED_BOARD",
		"payload": {"action": "regional_buffer"}}
	assert_false(bool(runtime.receive(1, JSON.stringify(wrong).to_utf8_buffer()).get("ok", false)))
	Network.clear_host_memory_for_test()
