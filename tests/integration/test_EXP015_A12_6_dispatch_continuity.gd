extends "res://tests/test_case.gd"
## EXP015 A12.6: authenticated cold-source commissioning and repeated
## finale dispatch in all 25 original regions (2 finite resource policies).
## This is process-local host source evidence, not restart persistence.
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
	_root = "user://exp015_a12_6_" + str(Time.get_ticks_usec()) + "_" + str(randi())
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
		"A12.6 isolated EXP04 fixture is not production restoration")


func _profile(atlas: Dictionary, region: int, account: String) -> Dictionary:
	var profile: Dictionary = Ledger.new_profile(account)
	for prior: int in range(region):
		for slot: int in PRIOR:
			_restore(atlas, profile, 8 * prior + slot)
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


func _start(level_id: String, account: String, root: String,
		finale: bool) -> Dictionary:
	var session: Runtime = Runtime.new()
	var started: Dictionary = {}
	if finale:
		# Original A12.5 opt-in stack: regional settlement and anchor.
		started = session.start(level_id, Callable(self, "_position_for"),
			Callable(), account, true, root,
			true, true, true, true, true,
			true, true, true, true, true,
			true, true, true, true, true,
			true, true, true, true, true,
			false, false, false, true, true)
	else:
		# Original A09 entry opt-in; no finale anchor controller.
		started = session.start(level_id, Callable(self, "_position_for"),
			Callable(), account, true, root,
			true, true, true, true, true,
			true, true, true, true, true,
			true, true, true, true, true,
			true, true, true, true, true,
			true, true, true)
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


func _replay(session: Runtime, board: String, actions: Array[String]) -> void:
	for index: int in range(actions.size()):
		var reply: Dictionary = _send(session, index + 1, board, actions[index])
		assert_true(bool(reply.get("ok", false)),
			"A12.6 " + actions[index] + " " + str(reply))


func _scenario(region: int, policy: String) -> bool:
	Network.clear_host_memory_for_test()
	var account: String = "a12_6_%02d_%s" % [region + 1, policy]
	var atlas: Dictionary = Atlas.load_catalog()
	var profile: Dictionary = _profile(atlas, region, account)
	var root_id: String = "LV_%03d" % (8 * region + 1)
	var finale_id: String = "LV_%03d" % (8 * region + 8)
	var first: Dictionary = _start(root_id, account,
		_save(profile, account, "root"), false)
	if first.is_empty():
		return false
	var first_host: Runtime = first["session"]
	var original_network: Network = first_host.regional_network
	assert_true(first_host.regional_entry != null)
	var source: Dictionary = first_host.regional_entry.definition_snapshot()
	var initial_reserve: int = int(original_network.snapshot()["reserve_pu"])
	var root_epoch: int = original_network.current_dispatch_epoch()
	_replay(first_host, str(first["board"]), [
		"entry_survey", "entry_isolate",
		"entry_critical" if policy == "buffer" else "entry_transport",
		"entry_contain:" + str(source["entry_risk_proof"]),
		"entry_buffer" if policy == "buffer" else "entry_managed",
		"entry_unblock", "entry_verify", "entry_signoff"
	])
	assert_true(first_host.regional_entry.closed())
	var reserve: int = int(original_network.snapshot()["reserve_pu"])
	var debt: int = int(original_network.site_conditions()["service_debt"])
	assert_eq(reserve, initial_reserve - (2 if policy == "buffer" else 0))
	assert_eq(debt, 2 if policy == "managed" else 0)
	assert_eq(first_host.pending_rewards(account).size(), 0)
	var event_count: int = original_network.snapshot()["events"].size()
	for slot: int in CURRENT:
		_restore(atlas, profile, 8 * region + slot)
	var final_one: Dictionary = _start(finale_id, account,
		_save(profile, account, "finale_one"), true)
	if final_one.is_empty():
		return false
	var first_finale: Runtime = final_one["session"]
	var network: Network = first_finale.regional_network
	assert_true(network == original_network, "same host-owned A09 ledger")
	assert_eq(network.current_dispatch_epoch(), root_epoch + 1)
	assert_eq(int(network.snapshot()["reserve_pu"]), reserve)
	assert_eq(int(network.site_conditions()["service_debt"]), debt)
	assert_eq(network.snapshot()["events"].size(), event_count,
		"dispatch attachment is not an electrical mutation")
	assert_true(bool(network.snapshot()["sites"][root_id]["restored"]))
	var route: Dictionary = network.anchor_route_snapshot()
	var missing: bool = false
	for blocker: Dictionary in route["blockers"]:
		if str(blocker["code"]) == "ORIGINAL_RECEIPT_MISSING":
			missing = true
	assert_eq(missing, region in [10, 24])
	assert_eq(bool(route["anchor_energized"]), not missing)
	var actions: Array[String] = []
	if missing:
		actions = ["anchor_audit", "anchor_defer", "anchor_verify", "anchor_signoff"]
	else:
		actions = ["anchor_audit", "anchor_trip",
			"anchor_proof:" + str(first_finale.regional_anchor_recovery.
				definition_snapshot()["original_recovery_proof"]),
			"anchor_reset", "anchor_verify", "anchor_signoff"]
	assert_false(bool(_send(first_finale, 1, str(final_one["board"]),
		"anchor_audit", 999).get("ok", false)))
	_replay(first_finale, str(final_one["board"]), actions)
	assert_true(first_finale.regional_anchor_recovery.closed())
	assert_eq(int(network.snapshot()["reserve_pu"]), reserve)
	assert_eq(int(network.site_conditions()["service_debt"]), debt)
	assert_eq(first_finale.pending_rewards(account).size(), 0)
	var old_epoch: int = network.current_dispatch_epoch()
	var old_revision: int = int(first_finale.regional_anchor_recovery.snapshot()[
		"verified_source_revision"])
	var final_two: Dictionary = _start(finale_id, account,
		_save(profile, account, "finale_two"), true)
	if final_two.is_empty():
		return false
	var second_finale: Runtime = final_two["session"]
	assert_true(second_finale.regional_network == network)
	assert_eq(network.current_dispatch_epoch(), old_epoch + 1)
	assert_eq(int(network.snapshot()["reserve_pu"]), reserve)
	assert_eq(int(network.site_conditions()["service_debt"]), debt)
	assert_false(first_finale.regional_anchor_recovery.closed(),
		"old source proof expires when same account opens a new dispatch")
	assert_eq(str(_send(first_finale, actions.size() + 1,
		str(final_one["board"]), "anchor_signoff")["code"]),
		"ANCHOR_DISPATCH_CONTEXT_EXPIRED")
	assert_eq(int(first_finale.regional_anchor_recovery.snapshot()[
		"verified_source_revision"]), old_revision)
	# A12.13 must deny canonical source reads from the superseded host.
	# Its private, already-earned recovery proof is still available only to
	# the host-side regression; no successor state may be exposed under old ID.
	assert_eq(str(first_finale.authoritative_state().get("code", "")),
		"EXP015_A12_13_STALE_HOST_SNAPSHOT")
	assert_false(bool(first_finale.regional_anchor_recovery.snapshot()["closed"]))
	var current_source: Dictionary = second_finale.authoritative_state()
	assert_true(current_source.has("exp015_regional_anchor_recovery"),
		"current dispatch retains its original recovery projection")
	assert_eq(str(second_finale.regional_anchor_recovery.snapshot()["phase"]),
		"audit_pending")
	assert_false(second_finale.regional_anchor_recovery.closed())
	assert_eq(second_finale.pending_rewards(account).size(), 0)
	assert_false(second_finale.completed())
	return true


func test_EXP015_A12_6_25_original_regions_two_policy_host_dispatches() -> void:
	var qualified: int = 0
	for region: int in range(25):
		for policy: String in ["buffer", "managed"]:
			if _scenario(region, policy):
				qualified += 1
				print("EXP015_A12_6 region=%02d policy=%s host_dispatch_epoch=PASS" %
					[region + 1, policy])
	assert_eq(qualified, 50)


func test_EXP015_A12_6_rejected_attach_cannot_invalidate_live_signoff() -> void:
	# Direct A09 host attachment denial may not advance an original epoch.
	var atlas: Dictionary = Atlas.load_catalog()
	var account: String = "a12_6_rejected_attachment"
	var profile: Dictionary = _profile(atlas, 0, account)
	var acquired: Dictionary = Network.acquire(atlas, profile, "LV_001")
	assert_true(bool(acquired.get("ok", false)))
	if not bool(acquired.get("ok", false)):
		return
	var network: Network = acquired["network"]
	var prior: int = network.current_dispatch_epoch()
	assert_eq(str(network.attach_site(atlas, profile, "LV_009")["code"]),
		"REGION_CONTEXT_MISMATCH")
	assert_eq(network.current_dispatch_epoch(), prior)
