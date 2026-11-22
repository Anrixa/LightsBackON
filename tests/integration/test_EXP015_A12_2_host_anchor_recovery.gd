extends "res://tests/test_case.gd"
## EXP015 A12.2 original finite-power fault recovery, 25 regions, no rewards.
const Atlas := preload("res://scripts/world/dispatch_atlas.gd")
const Ledger := preload("res://scripts/progression/expedition_ledger.gd")
const Network := preload("res://scripts/gameplay/expedition_regional_network.gd")
const Recovery := preload("res://scripts/gameplay/expedition_regional_anchor_recovery.gd")
const Runtime := preload("res://scripts/gameplay/expedition_host_session.gd")
const Saves := preload("res://scripts/persistence/save_service.gd")
const Offline := preload("res://scripts/persistence/offline_persistence.gd")
const ContentHash := preload("res://scripts/network/content_hash.gd")

const PRIOR: Array[int] = [1, 3, 4, 6, 7, 8]
const LOCAL: Array[int] = [1, 2, 3, 4, 6, 7]
const STAMP: String = "2026-11-22T00:00:00Z"
var _root: String = ""
var _position: Vector3 = Vector3.ZERO


func before_each() -> void:
	Network.clear_host_memory_for_test()
	_root = "user://exp015_a12_2_" + str(Time.get_ticks_usec()) + "_" + str(randi())


func after_each() -> void:
	Network.clear_host_memory_for_test()


func _position_for(_player: String) -> Vector3:
	return _position


func _restore(atlas: Dictionary, profile: Dictionary, index: int) -> void:
	var site: String = "LV_%03d" % index
	var level: Dictionary = Atlas.find_level(atlas, site)
	var receipt: Dictionary = Ledger.make_receipt(str(profile["account_key"]),
		site, str(level["tasks"][4]["id"]), "restoration")
	assert_true(bool(Ledger.apply_receipt(profile, receipt, atlas).get("applied", false)),
		"source-only EXP04 test fixture; no actual gameplay restoration")


func _context(region: int, account: String) -> Dictionary:
	var atlas: Dictionary = Atlas.load_catalog()
	var profile: Dictionary = Ledger.new_profile(account)
	for previous: int in range(region):
		for slot: int in PRIOR:
			_restore(atlas, profile, previous * 8 + slot)
	var network: Network = Network.new()
	var root: String = "LV_%03d" % (region * 8 + 1)
	assert_true(bool(network.configure(atlas, profile, root).get("ok", false)))
	for slot: int in LOCAL:
		_restore(atlas, profile, region * 8 + slot)
	var finale: String = "LV_%03d" % (region * 8 + 8)
	assert_true(bool(network.attach_site(atlas, profile, finale).get("ok", false)))
	return {"atlas": atlas, "profile": profile, "network": network, "finale": finale}


func test_EXP015_A12_2_25_original_host_recovery_or_managed_defer() -> void:
	var actual: int = 0
	var deferred: int = 0
	for region: int in range(25):
		var context: Dictionary = _context(region, "a12_2_%02d" % (region + 1))
		var network: Network = context["network"]
		var recovery: Recovery = Recovery.new()
		assert_true(bool(recovery.configure(network).get("ok", false)))
		var initial_reserve: int = int(network.snapshot()["reserve_pu"])
		assert_true(bool(recovery.operate("anchor_audit").get("ok", false)))
		var definition: Dictionary = recovery.definition_snapshot()
		if bool(network.anchor_route_snapshot()["anchor_energized"]):
			assert_eq(str(recovery.operate("anchor_defer")["code"]),
				"ANCHOR_REAL_DARK_SOURCE_REQUIRED")
			assert_true(bool(recovery.operate("anchor_trip").get("ok", false)))
			assert_false(bool(network.anchor_route_snapshot()["anchor_energized"]))
			assert_eq(str(recovery.operate("anchor_reset")["code"]),
				"ANCHOR_ORIGINAL_CLEARANCE_REQUIRED")
			assert_eq(str(recovery.operate("anchor_proof:FAKE")["code"]),
				"ANCHOR_UNKNOWN_OR_FORGED_PROOF")
			var proof: String = "anchor_proof:" + str(definition["original_recovery_proof"])
			assert_true(bool(recovery.operate(proof).get("ok", false)))
			assert_false(bool(network.anchor_route_snapshot()["anchor_energized"]),
				"clearance cannot silently reclose original isolated feeder")
			assert_true(bool(recovery.operate("anchor_reset").get("ok", false)))
		else:
			deferred += 1
			assert_true(region in [10, 24])
			assert_eq(str(recovery.operate("anchor_trip")["code"]),
				"ANCHOR_LIVE_ORIGINAL_PATH_REQUIRED")
			assert_true(bool(recovery.operate("anchor_defer").get("ok", false)))
		assert_true(bool(recovery.operate("anchor_verify").get("ok", false)))
		assert_true(bool(recovery.operate("anchor_signoff").get("ok", false)))
		assert_true(recovery.closed())
		assert_eq(int(network.snapshot()["reserve_pu"]), initial_reserve)
		assert_eq(network.site_conditions()["service_debt"], 0)
		assert_eq(str(recovery.operate("anchor_signoff")["code"]), "ANCHOR_ALREADY_SIGNED_OFF")
		actual += 1
	assert_eq(actual, 25)
	assert_eq(deferred, 2)


func _send(session: Runtime, seq: int, board: String, action: String,
		peer: int = 1) -> Dictionary:
	session.host.tick(seq)
	return session.receive(peer, JSON.stringify({
		"session": session.session_id(), "seq": seq, "type": "operate_worksite",
		"entity": board, "payload": {"action": action}
	}).to_utf8_buffer())


func test_EXP015_A12_2_authenticated_host_board_and_opt_out() -> void:
	var account: String = "a12_2_host_auth"
	var context: Dictionary = _context(0, account)
	var profile: Dictionary = context["profile"]
	var store: Saves = Saves.new()
	store.configure(1, Offline.SAVE_BUILD_ID,
		ContentHash.content_revision(), ContentHash.rules_revision())
	var path: String = _root.path_join("profiles").path_join(account).path_join(
		Ledger.PROFILE_FILE)
	assert_true(bool(store.write_record(path, Ledger.KIND_PROFILE,
		account, profile, STAMP).get("ok", false)))
	var session: Runtime = Runtime.new()
	var ready: Dictionary = session.start("LV_008", Callable(self, "_position_for"),
		Callable(), account, true, _root,
		true, true, true, true, true,
		true, true, true, true, true,
		true, true, true, true, true,
		true, true, true, true, true,
		false, false, false, true, true)
	assert_true(bool(ready.get("ok", false)), str(ready))
	if not bool(ready.get("ok", false)):
		return
	assert_true(bool(ready["regional_anchor_recovery_active"]))
	assert_true(str(ready["content_revision"]).begins_with("EXP015_A12_6_"))
	var board: String = str(session.worksite.definition_snapshot()["board"])
	_position = session.definition_snapshot()["positions"][board]
	assert_false(bool(_send(session, 1, board, "anchor_audit", 999).get("ok", false)))
	assert_true(bool(_send(session, 1, board, "anchor_audit").get("ok", false)))
	assert_true(bool(_send(session, 2, board, "anchor_trip").get("ok", false)))
	assert_false(bool(_send(session, 3, board, "anchor_proof:FORGED").get("ok", false)))
	var proof: String = "anchor_proof:" + str(
		session.regional_anchor_recovery.definition_snapshot()["original_recovery_proof"])
	assert_true(bool(_send(session, 4, board, proof).get("ok", false)))
	assert_true(bool(_send(session, 5, board, "anchor_reset").get("ok", false)))
	assert_true(bool(_send(session, 6, board, "anchor_verify").get("ok", false)))
	assert_true(bool(_send(session, 7, board, "anchor_signoff").get("ok", false)))
	assert_true(session.regional_anchor_recovery.closed())
	assert_true(bool(_send(session, 7, board, "anchor_signoff").get("duplicate", false)))
	assert_eq(session.pending_rewards(account).size(), 0)
	assert_true(session.authoritative_state().has("exp015_regional_anchor_recovery"))
	assert_eq(session.task_board()["regional_anchor_recovery"]["phase"], "signed_off")
	assert_false(session.completed())


func test_EXP015_A12_2_no_host_can_bypass_parent_gates() -> void:
	var network: Network = Network.new()
	var empty: Recovery = Recovery.new()
	assert_eq(str(empty.configure(network)["code"]), "ANCHOR_NETWORK_NOT_CONFIGURED")
	assert_eq(str(empty.operate("anchor_trip")["code"]), "ANCHOR_NOT_CONFIGURED")
