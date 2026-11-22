extends "res://tests/test_case.gd"
## EXP015 A12.5 — real SessionHost ingress, trusted A09 source transitions,
## stale temporal signoff denial, idempotency and unrelated feeder isolation.
## No physical playability, networking or release claims are made.
const Atlas := preload("res://scripts/world/dispatch_atlas.gd")
const Ledger := preload("res://scripts/progression/expedition_ledger.gd")
const Network := preload("res://scripts/gameplay/expedition_regional_network.gd")
const Runtime := preload("res://scripts/gameplay/expedition_host_session.gd")
const Saves := preload("res://scripts/persistence/save_service.gd")
const Offline := preload("res://scripts/persistence/offline_persistence.gd")
const ContentHash := preload("res://scripts/network/content_hash.gd")

const STAMP: String = "2026-11-22T00:00:00Z"
const ORIGINAL_SITES: Array[int] = [1, 2, 3, 4, 6, 7]
var _root: String = ""
var _position: Vector3 = Vector3.ZERO


func before_each() -> void:
	Network.clear_host_memory_for_test()
	_root = "user://exp015_a12_5_" + str(Time.get_ticks_usec()) + "_" + str(randi())
	_position = Vector3.ZERO


func after_each() -> void:
	Network.clear_host_memory_for_test()


func _position_for(_player: String) -> Vector3:
	return _position


func _restore(atlas: Dictionary, profile: Dictionary, index: int) -> void:
	var site: String = "LV_%03d" % index
	var level: Dictionary = Atlas.find_level(atlas, site)
	var receipt: Dictionary = Ledger.make_receipt(
		str(profile["account_key"]), site, str(level["tasks"][4]["id"]), "restoration")
	assert_true(bool(Ledger.apply_receipt(profile, receipt, atlas).get("applied", false)),
		"A12.5 original receipt is an isolated fixture, never a played restoration")


func _session(case_id: String) -> Dictionary:
	var account: String = "a12_5_" + case_id
	var atlas: Dictionary = Atlas.load_catalog()
	var profile: Dictionary = Ledger.new_profile(account)
	for index: int in ORIGINAL_SITES:
		_restore(atlas, profile, index)
	var store: Saves = Saves.new()
	store.configure(1, Offline.SAVE_BUILD_ID,
		ContentHash.content_revision(), ContentHash.rules_revision())
	var profile_path: String = _root.path_join("profiles").path_join(account).path_join(
		Ledger.PROFILE_FILE)
	var saved: Dictionary = store.write_record(profile_path, Ledger.KIND_PROFILE,
		account, profile, STAMP)
	assert_true(bool(saved.get("ok", false)), str(saved))
	if not bool(saved.get("ok", false)):
		return {}
	var session: Runtime = Runtime.new()
	var started: Dictionary = session.start("LV_008",
		Callable(self, "_position_for"), Callable(), account, true, _root,
		true, true, true, true, true,
		true, true, true, true, true,
		true, true, true, true, true,
		true, true, true, true, true,
		false, false, false, true, true)
	assert_true(bool(started.get("ok", false)), str(started))
	if not bool(started.get("ok", false)):
		return {}
	assert_true(str(started["content_revision"]).begins_with("EXP015_A12_6_"))
	var board: String = str(session.worksite.definition_snapshot()["board"])
	_position = session.definition_snapshot()["positions"][board]
	var network: Network = session.regional_network
	var route: Dictionary = network.anchor_route_snapshot()
	assert_true(bool(route["anchor_energized"]))
	var feeder: String = str(route["original_feeder_path"][-1]["edge_id"])
	var original: Dictionary = Network.entry_for(Network.load_book(), "LV_008")
	return {"session": session, "network": network, "board": board,
		"account": account, "feeder": feeder, "source": original}


## All worksite actions traverse SessionHost identity/sequence/range/dedupe
## before touching the opt-in source controller.
func _send(session: Runtime, sequence: int, board: String, action: String,
		peer: int = 1) -> Dictionary:
	session.host.tick(sequence)
	return session.receive(peer, JSON.stringify({
		"session": session.session_id(), "seq": sequence,
		"type": "operate_worksite", "entity": board,
		"payload": {"action": action}
	}).to_utf8_buffer())


func _complete(session: Runtime, board: String, proof: String,
		start_sequence: int) -> void:
	assert_true(bool(_send(session, start_sequence, board, "anchor_audit").get("ok", false)))
	assert_true(bool(_send(session, start_sequence + 1, board, "anchor_trip").get("ok", false)))
	assert_true(bool(_send(session, start_sequence + 2, board,
		"anchor_proof:" + proof).get("ok", false)))
	assert_true(bool(_send(session, start_sequence + 3, board, "anchor_reset").get("ok", false)))
	assert_true(bool(_send(session, start_sequence + 4, board, "anchor_verify").get("ok", false)))
	assert_true(bool(_send(session, start_sequence + 5, board, "anchor_signoff").get("ok", false)))


func test_EXP015_A12_5_authenticated_stale_signoff_never_resurrects() -> void:
	var ctx: Dictionary = _session("post_signoff")
	if ctx.is_empty():
		return
	var session: Runtime = ctx["session"]
	var network: Network = ctx["network"]
	var board: String = ctx["board"]
	var feeder: String = ctx["feeder"]
	var source: Dictionary = ctx["source"]
	var reserve: int = int(network.snapshot()["reserve_pu"])
	_complete(session, board, str(source["recovery_procedure"]), 1)
	assert_true(session.regional_anchor_recovery.closed())
	var before: int = int(session.regional_anchor_recovery.snapshot()[
		"verified_source_revision"])
	assert_true(bool(network.host_transition("trip_feeder",
		feeder, str(source["fault_signature"])).get("ok", false)))
	assert_false(session.regional_anchor_recovery.closed())
	assert_true(bool(network.host_transition("clear_fault",
		feeder, str(source["recovery_procedure"])).get("ok", false)))
	assert_true(bool(network.host_transition("reset_feeder", feeder).get("ok", false)))
	assert_true(bool(network.anchor_route_snapshot()["anchor_energized"]))
	assert_true(int(session.regional_anchor_recovery.snapshot()[
		"current_source_revision"]) > before)
	assert_false(session.regional_anchor_recovery.closed(),
		"the old authenticated signoff cannot become valid when power returns")
	assert_false(bool(session.authoritative_state()[
		"exp015_regional_anchor_recovery"]["closed"]))
	assert_true(bool(_send(session, 6, board, "anchor_signoff").get("duplicate", false)),
		"duplicate original sequence cannot renew stale signoff")
	assert_eq(str(_send(session, 7, board, "anchor_signoff")["code"]),
		"ANCHOR_STABLE_SOURCE_REQUIRED")
	_complete(session, board, str(source["recovery_procedure"]), 8)
	assert_true(session.regional_anchor_recovery.closed())
	assert_eq(int(network.snapshot()["reserve_pu"]), reserve)
	assert_eq(session.pending_rewards(str(ctx["account"])).size(), 0)


func test_EXP015_A12_5_verified_host_proof_expires_after_transient_source_change() -> void:
	var ctx: Dictionary = _session("pre_signoff")
	if ctx.is_empty():
		return
	var session: Runtime = ctx["session"]
	var network: Network = ctx["network"]
	var board: String = ctx["board"]
	var feeder: String = ctx["feeder"]
	var proof: String = str(ctx["source"]["recovery_procedure"])
	assert_false(bool(_send(session, 1, board, "anchor_audit", 999).get("ok", false)))
	assert_true(bool(_send(session, 1, board, "anchor_audit").get("ok", false)))
	assert_true(bool(_send(session, 2, board, "anchor_trip").get("ok", false)))
	assert_false(bool(_send(session, 3, board, "anchor_proof:FORGED").get("ok", false)))
	assert_true(bool(_send(session, 4, board, "anchor_proof:" + proof).get("ok", false)))
	assert_true(bool(_send(session, 5, board, "anchor_reset").get("ok", false)))
	assert_true(bool(_send(session, 6, board, "anchor_verify").get("ok", false)))
	assert_eq(str(session.regional_anchor_recovery.snapshot()["phase"]), "verified")
	assert_true(bool(network.host_transition("isolate_feeder", feeder).get("ok", false)))
	assert_true(bool(network.host_transition("reset_feeder", feeder).get("ok", false)))
	assert_eq(str(_send(session, 7, board, "anchor_signoff")["code"]),
		"ANCHOR_SOURCE_CHANGED_AFTER_VERIFY")
	assert_eq(str(session.regional_anchor_recovery.snapshot()["phase"]),
		"audit_pending")
	assert_false(session.regional_anchor_recovery.closed())
	_complete(session, board, proof, 8)
	assert_true(session.regional_anchor_recovery.closed())
	assert_false(session.completed(),
		"source proof alone must not bypass inherited mission completion gates")


func test_EXP015_A12_5_unrelated_source_event_does_not_revoke_original_signoff() -> void:
	var ctx: Dictionary = _session("off_route")
	if ctx.is_empty():
		return
	var session: Runtime = ctx["session"]
	var network: Network = ctx["network"]
	var board: String = ctx["board"]
	_complete(session, board, str(ctx["source"]["recovery_procedure"]), 1)
	assert_true(session.regional_anchor_recovery.closed())
	var before: int = int(session.regional_anchor_recovery.snapshot()[
		"verified_source_revision"])
	var original_edges: Dictionary = {}
	for edge: Dictionary in network.anchor_route_snapshot()["original_feeder_path"]:
		original_edges[str(edge["edge_id"])] = true
	var other: String = ""
	for feeder: String in network.snapshot()["feeders"]:
		if not original_edges.has(feeder):
			other = feeder
			break
	assert_false(other.is_empty(), "original region 01 includes off-path feeders")
	if other.is_empty():
		return
	assert_true(bool(network.host_transition("isolate_feeder", other).get("ok", false)))
	assert_true(bool(network.host_transition("reset_feeder", other).get("ok", false)))
	assert_eq(int(session.regional_anchor_recovery.snapshot()[
		"current_source_revision"]), before)
	assert_true(session.regional_anchor_recovery.closed(),
		"unrelated network work must not revoke the original anchor signoff")
	assert_eq(str(session.authoritative_state()[
		"exp015_regional_anchor_recovery"]["phase"]), "signed_off")
