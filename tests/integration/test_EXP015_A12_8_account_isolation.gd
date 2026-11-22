extends "res://tests/test_case.gd"
## EXP015 A12.8: independent process-local host authority per account
## and original region. Tests real A09 source and authenticated SessionHost.
const Atlas := preload("res://scripts/world/dispatch_atlas.gd")
const Ledger := preload("res://scripts/progression/expedition_ledger.gd")
const Network := preload("res://scripts/gameplay/expedition_regional_network.gd")
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
	_root = "user://exp015_a12_8_" + str(Time.get_ticks_usec()) + "_" + str(randi())
	_position = Vector3.ZERO


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
		"isolated original receipt fixture must be valid")


func _profile(atlas: Dictionary, region: int, account: String) -> Dictionary:
	var profile: Dictionary = Ledger.new_profile(account)
	for previous: int in range(region):
		for slot: int in PRIOR:
			_restore(atlas, profile, 8 * previous + slot)
	for slot: int in CURRENT:
		_restore(atlas, profile, 8 * region + slot)
	return profile


func _save(profile: Dictionary, account: String, stage: String) -> String:
	var storage: Saves = Saves.new()
	storage.configure(1, Offline.SAVE_BUILD_ID,
		ContentHash.content_revision(), ContentHash.rules_revision())
	var root: String = _root.path_join(account).path_join(stage)
	var path: String = root.path_join("profiles").path_join(account).path_join(
		Ledger.PROFILE_FILE)
	var result: Dictionary = storage.write_record(path, Ledger.KIND_PROFILE,
		account, profile, STAMP)
	assert_true(bool(result.get("ok", false)), str(result))
	return root


func _start(account: String, profile: Dictionary, stage: String) -> Dictionary:
	var session: Runtime = Runtime.new()
	var started: Dictionary = session.start("LV_008",
		Callable(self, "_position_for"), Callable(), account, true,
		_save(profile, account, stage),
		true, true, true, true, true,
		true, true, true, true, true,
		true, true, true, true, true,
		true, true, true, true, true,
		false, false, false, true, true)
	assert_true(bool(started.get("ok", false)), str(started))
	if not bool(started.get("ok", false)):
		return {}
	var board: String = str(session.worksite.definition_snapshot()["board"])
	_position = session.definition_snapshot()["positions"][board]
	return {"session": session, "board": board}


func _send(session: Runtime, seq: int, board: String, action: String,
		peer: int = 1) -> Dictionary:
	session.host.tick(seq)
	return session.receive(peer, JSON.stringify({
		"session": session.session_id(), "seq": seq,
		"type": "operate_worksite", "entity": board,
		"payload": {"action": action}
	}).to_utf8_buffer())


func _qualify(session: Runtime, board: String) -> void:
	var proof: String = str(session.regional_anchor_recovery.
		definition_snapshot()["original_recovery_proof"])
	var actions: Array[String] = [
		"anchor_audit", "anchor_trip", "anchor_proof:" + proof,
		"anchor_reset", "anchor_verify", "anchor_signoff"
	]
	for i: int in range(actions.size()):
		var result: Dictionary = _send(session, i + 1, board, actions[i])
		assert_true(bool(result.get("ok", false)), str(result))
	assert_true(session.regional_anchor_recovery.closed())


func test_EXP015_A12_8_25_original_regions_two_account_source_isolation() -> void:
	var atlas: Dictionary = Atlas.load_catalog()
	var qualified: int = 0
	for region: int in range(25):
		Network.clear_host_memory_for_test()
		var account_a: String = "a12_8_a_%02d" % region
		var account_b: String = "a12_8_b_%02d" % region
		var profile_a: Dictionary = _profile(atlas, region, account_a)
		var profile_b: Dictionary = _profile(atlas, region, account_b)
		var finale: String = "LV_%03d" % (8 * region + 8)
		var first: Dictionary = Network.acquire(atlas, profile_a, finale)
		var second: Dictionary = Network.acquire(atlas, profile_b, finale)
		assert_true(bool(first.get("ok", false)), str(first))
		assert_true(bool(second.get("ok", false)), str(second))
		if not bool(first.get("ok", false)) or not bool(second.get("ok", false)):
			continue
		var network_a: Network = first["network"]
		var network_b: Network = second["network"]
		assert_false(network_a == network_b,
			"accounts may never share regional host network memory")
		var epoch_a: int = network_a.current_dispatch_epoch()
		var epoch_b: int = network_b.current_dispatch_epoch()
		var before_b: Dictionary = network_b.snapshot()
		var route: Dictionary = network_a.anchor_route_snapshot()
		var original: String = str(route["original_feeder_path"][-1]["edge_id"])
		var proof: String = str(network_a.snapshot()["fault_signature"])
		assert_true(bool(network_a.host_transition(
			"trip_feeder", original, proof).get("ok", false)))
		assert_eq(network_b.snapshot(), before_b,
			"account B power/events/reserve/debt cannot mirror account A")
		assert_eq(network_a.current_dispatch_epoch(), epoch_a,
			"source mutation must not masquerade as dispatch attach")
		var events_a: int = network_a.snapshot()["events"].size()
		# An attempt to reuse this A09 network for another original region
		# must fail without changing its site, events, epoch or receipts.
		var foreign_region_site: String = ("LV_%03d" %
			(8 * (region + 1) + 1)) if region < 24 else "LV_001"
		var forbidden: Dictionary = network_a.attach_site(
			atlas, profile_a, foreign_region_site)
		assert_eq(str(forbidden.get("code", "")), "REGION_CONTEXT_MISMATCH")
		assert_eq(network_a.current_dispatch_epoch(), epoch_a)
		assert_eq(network_a.snapshot()["events"].size(), events_a)
		assert_eq(str(network_a.snapshot()["level_id"]), finale)
		# A rollback/incomplete ledger cannot attach to the live original
		# finale or advance its epoch. No source state is rolled back.
		var empty_profile: Dictionary = Ledger.new_profile(account_a)
		var denied: Dictionary = network_a.attach_site(
			atlas, empty_profile, finale)
		assert_false(bool(denied.get("ok", false)))
		assert_eq(network_a.current_dispatch_epoch(), epoch_a)
		assert_eq(network_a.snapshot()["events"].size(), events_a)
		# A valid re-entry affects B's epoch alone, never A's.
		var attached_b: Dictionary = Network.acquire(atlas, profile_b, finale)
		assert_true(bool(attached_b.get("ok", false)), str(attached_b))
		assert_true(attached_b.get("network") == network_b)
		assert_eq(network_b.current_dispatch_epoch(), epoch_b + 1)
		assert_eq(network_a.current_dispatch_epoch(), epoch_a)
		assert_eq(network_b.snapshot(), before_b,
			"successfully reattaching B cannot invent an electrical event")
		qualified += 1
		print("EXP015_A12_8 region=%02d two_account_isolation=PASS" % [region + 1])
	assert_eq(qualified, 25)


func test_EXP015_A12_8_authenticated_account_signoff_isolation() -> void:
	# This uses two independent signed host controllers, not an artificial
	# client-side source state flag, then dispatches only account A again.
	var atlas: Dictionary = Atlas.load_catalog()
	var account_a: String = "a12_8_host_a"
	var account_b: String = "a12_8_host_b"
	var profile_a: Dictionary = _profile(atlas, 0, account_a)
	var profile_b: Dictionary = _profile(atlas, 0, account_b)
	var a: Dictionary = _start(account_a, profile_a, "a_one")
	var b: Dictionary = _start(account_b, profile_b, "b_one")
	if a.is_empty() or b.is_empty():
		return
	var host_a: Runtime = a["session"]
	var host_b: Runtime = b["session"]
	var network_a: Network = host_a.regional_network
	var network_b: Network = host_b.regional_network
	assert_false(network_a == network_b)
	assert_false(bool(_send(host_b, 1, str(b["board"]),
		"anchor_audit", 999).get("ok", false)))
	_qualify(host_a, str(a["board"]))
	_qualify(host_b, str(b["board"]))
	var b_epoch: int = network_b.current_dispatch_epoch()
	var b_events: int = network_b.snapshot()["events"].size()
	var reentered: Dictionary = _start(account_a, profile_a, "a_two")
	if reentered.is_empty():
		return
	var new_a: Runtime = reentered["session"]
	assert_true(new_a.regional_network == network_a)
	assert_eq(network_a.current_dispatch_epoch(), 2)
	assert_false(host_a.regional_anchor_recovery.closed())
	assert_eq(str(_send(host_a, 7, str(a["board"]),
		"anchor_signoff")["code"]), "ANCHOR_DISPATCH_CONTEXT_EXPIRED")
	assert_eq(network_b.current_dispatch_epoch(), b_epoch)
	assert_eq(network_b.snapshot()["events"].size(), b_events)
	assert_true(host_b.regional_anchor_recovery.closed(),
		"A's new dispatch cannot invalidate B's still-current source proof")
	assert_false(new_a.regional_anchor_recovery.closed())
	assert_eq(host_a.pending_rewards(account_a).size(), 0)
	assert_eq(host_b.pending_rewards(account_b).size(), 0)
	assert_eq(new_a.pending_rewards(account_a).size(), 0)
