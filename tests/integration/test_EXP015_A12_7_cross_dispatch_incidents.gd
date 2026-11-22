extends "res://tests/test_case.gd"
## EXP015 A12.7 — authenticate, invalidate, and requalify ORIGINAL source
## incidents across successive dispatches. All state is process-local.
## Human/controller, equipment, live networking and release gates stay held.
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
	_root = "user://exp015_a12_7_" + str(Time.get_ticks_usec()) + "_" + str(randi())
	_position = Vector3.ZERO


func after_each() -> void:
	Network.clear_host_memory_for_test()


func _position_for(_player: String) -> Vector3:
	return _position


func _restore(atlas: Dictionary, profile: Dictionary, index: int) -> void:
	var id: String = "LV_%03d" % index
	var level: Dictionary = Atlas.find_level(atlas, id)
	var receipt: Dictionary = Ledger.make_receipt(str(profile["account_key"]),
		id, str(level["tasks"][4]["id"]), "restoration")
	assert_true(bool(Ledger.apply_receipt(profile, receipt, atlas).get("applied", false)),
		"A12.7 fixture receipts are never production gameplay claims")


func _profile(atlas: Dictionary, region: int, account: String) -> Dictionary:
	var profile: Dictionary = Ledger.new_profile(account)
	for preceding: int in range(region):
		for slot: int in PRIOR:
			_restore(atlas, profile, 8 * preceding + slot)
	return profile


func _save(profile: Dictionary, account: String, stage: String) -> String:
	var storage: Saves = Saves.new()
	storage.configure(1, Offline.SAVE_BUILD_ID,
		ContentHash.content_revision(), ContentHash.rules_revision())
	var root: String = _root.path_join(account).path_join(stage)
	var path: String = root.path_join("profiles").path_join(account).path_join(
		Ledger.PROFILE_FILE)
	var written: Dictionary = storage.write_record(path, Ledger.KIND_PROFILE,
		account, profile, STAMP)
	assert_true(bool(written.get("ok", false)), str(written))
	return root


func _start(level: String, account: String, root: String,
		finale: bool) -> Dictionary:
	var session: Runtime = Runtime.new()
	var started: Dictionary
	if finale:
		started = session.start(level, Callable(self, "_position_for"),
			Callable(), account, true, root,
			true, true, true, true, true,
			true, true, true, true, true,
			true, true, true, true, true,
			true, true, true, true, true,
			false, false, false, true, true)
	else:
		started = session.start(level, Callable(self, "_position_for"),
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


func _send(session: Runtime, sequence: int, board: String, action: String,
		peer: int = 1) -> Dictionary:
	session.host.tick(sequence)
	return session.receive(peer, JSON.stringify({
		"session": session.session_id(), "seq": sequence,
		"type": "operate_worksite", "entity": board,
		"payload": {"action": action}
	}).to_utf8_buffer())


func _replay(session: Runtime, board: String, actions: Array[String],
		first_sequence: int = 1) -> void:
	for index: int in range(actions.size()):
		var response: Dictionary = _send(session, first_sequence + index,
			board, actions[index])
		assert_true(bool(response.get("ok", false)),
			"A12.7 real host command " + actions[index] + " " + str(response))


func _anchor_actions(session: Runtime, dark: bool) -> Array[String]:
	if dark:
		return ["anchor_audit", "anchor_defer", "anchor_verify", "anchor_signoff"]
	var original: Dictionary = session.regional_anchor_recovery.definition_snapshot()
	return ["anchor_audit", "anchor_trip",
		"anchor_proof:" + str(original["original_recovery_proof"]),
		"anchor_reset", "anchor_verify", "anchor_signoff"]


func _off_path_feeder(network: Network) -> String:
	var original: Dictionary = {}
	for edge: Dictionary in network.anchor_route_snapshot()["original_feeder_path"]:
		original[str(edge["edge_id"])] = true
	for feeder: String in network.snapshot()["feeders"]:
		if not original.has(feeder):
			return feeder
	return ""


func _scenario(region: int, policy: String) -> bool:
	Network.clear_host_memory_for_test()
	var account: String = "a12_7_%02d_%s" % [region + 1, policy]
	var atlas: Dictionary = Atlas.load_catalog()
	var profile: Dictionary = _profile(atlas, region, account)
	var root_id: String = "LV_%03d" % (8 * region + 1)
	var finale_id: String = "LV_%03d" % (8 * region + 8)
	var root: Dictionary = _start(root_id, account,
		_save(profile, account, "root"), false)
	if root.is_empty():
		return false
	var entry_host: Runtime = root["session"]
	var network: Network = entry_host.regional_network
	var entry: Dictionary = entry_host.regional_entry.definition_snapshot()
	_replay(entry_host, str(root["board"]), [
		"entry_survey", "entry_isolate",
		"entry_critical" if policy == "buffer" else "entry_transport",
		"entry_contain:" + str(entry["entry_risk_proof"]),
		"entry_buffer" if policy == "buffer" else "entry_managed",
		"entry_unblock", "entry_verify", "entry_signoff"
	])
	assert_true(entry_host.regional_entry.closed())
	for slot: int in CURRENT:
		_restore(atlas, profile, 8 * region + slot)
	var first: Dictionary = _start(finale_id, account,
		_save(profile, account, "finale_1"), true)
	if first.is_empty():
		return false
	var first_host: Runtime = first["session"]
	assert_true(first_host.regional_network == network)
	var route: Dictionary = network.anchor_route_snapshot()
	var dark: bool = false
	for blocker: Dictionary in route["blockers"]:
		if str(blocker["code"]) == "ORIGINAL_RECEIPT_MISSING":
			dark = true
	assert_eq(dark, region in [10, 24])
	var actions: Array[String] = _anchor_actions(first_host, dark)
	_replay(first_host, str(first["board"]), actions)
	assert_true(first_host.regional_anchor_recovery.closed())
	var signed_revision: int = int(first_host.regional_anchor_recovery.snapshot()[
		"verified_source_revision"])
	var reserve: int = int(network.snapshot()["reserve_pu"])
	var debt: int = int(network.site_conditions()["service_debt"])
	assert_eq(debt, 2 if policy == "managed" else 0)
	var epoch: int = network.current_dispatch_epoch()
	var off_path: String = _off_path_feeder(network)
	assert_false(off_path.is_empty(), "original graph must expose off-path control")
	if off_path.is_empty():
		return false
	# An irrelevant original edge may change without falsely invalidating
	# the genuinely source-bound reserve-anchor signoff.
	assert_true(bool(network.host_transition("isolate_feeder", off_path).get("ok", false)))
	assert_true(bool(network.host_transition("reset_feeder", off_path).get("ok", false)))
	assert_eq(int(first_host.regional_anchor_recovery.snapshot()[
		"current_source_revision"]), signed_revision)
	assert_true(first_host.regional_anchor_recovery.closed())
	# Even if electricity returns to exactly the previous appearance,
	# an original feeder's append-only fault history invalidates proof.
	var original_path: Array = network.anchor_route_snapshot()["original_feeder_path"]
	var original_feeder: String = str(original_path[-1]["edge_id"])
	assert_true(bool(network.host_transition("isolate_feeder",
		original_feeder).get("ok", false)))
	assert_true(bool(network.host_transition("reset_feeder",
		original_feeder).get("ok", false)))
	assert_false(first_host.regional_anchor_recovery.closed())
	assert_true(int(first_host.regional_anchor_recovery.snapshot()[
		"current_source_revision"]) > signed_revision)
	assert_eq(int(network.snapshot()["reserve_pu"]), reserve)
	assert_eq(int(network.site_conditions()["service_debt"]), debt)
	var events_before_attach: int = network.snapshot()["events"].size()
	var second: Dictionary = _start(finale_id, account,
		_save(profile, account, "finale_2"), true)
	if second.is_empty():
		return false
	var second_host: Runtime = second["session"]
	assert_true(second_host.regional_network == network)
	assert_eq(network.current_dispatch_epoch(), epoch + 1)
	assert_eq(network.snapshot()["events"].size(), events_before_attach)
	assert_false(first_host.regional_anchor_recovery.closed())
	assert_eq(str(_send(first_host, actions.size() + 1,
		str(first["board"]), "anchor_audit")["code"]),
		"ANCHOR_DISPATCH_CONTEXT_EXPIRED")
	assert_eq(str(second_host.regional_anchor_recovery.snapshot()["phase"]),
		"audit_pending")
	assert_false(bool(_send(second_host, 1, str(second["board"]),
		"anchor_audit", 999).get("ok", false)),
		"foreign peer must not obtain a fresh source audit")
	_replay(second_host, str(second["board"]),
		_anchor_actions(second_host, dark))
	assert_true(second_host.regional_anchor_recovery.closed(),
		"fresh source authority must be earned by the current dispatch")
	assert_false(first_host.regional_anchor_recovery.closed())
	assert_eq(int(network.snapshot()["reserve_pu"]), reserve)
	assert_eq(int(network.site_conditions()["service_debt"]), debt)
	assert_eq(first_host.pending_rewards(account).size(), 0)
	assert_eq(second_host.pending_rewards(account).size(), 0)
	assert_false(second_host.completed(), "source signoff is not mission completion")
	return true


func test_EXP015_A12_7_original_cross_dispatch_50_incident_replays() -> void:
	var qualified: int = 0
	for region: int in range(25):
		for policy: String in ["buffer", "managed"]:
			if _scenario(region, policy):
				qualified += 1
				print("EXP015_A12_7 region=%02d policy=%s incident_replay=PASS" %
					[region + 1, policy])
	assert_eq(qualified, 50)


func _verification_preempted_by_dispatch(region: int) -> void:
	Network.clear_host_memory_for_test()
	var atlas: Dictionary = Atlas.load_catalog()
	var account: String = "a12_7_unsigned_%02d" % region
	var profile: Dictionary = _profile(atlas, region, account)
	for slot: int in CURRENT:
		_restore(atlas, profile, 8 * region + slot)
	var finale: String = "LV_%03d" % (8 * region + 8)
	var initial: Dictionary = _start(finale, account,
		_save(profile, account, "unsigned_1"), true)
	if initial.is_empty():
		return
	var first: Runtime = initial["session"]
	var route: Dictionary = first.regional_network.anchor_route_snapshot()
	var dark: bool = false
	for blocker: Dictionary in route["blockers"]:
		if str(blocker["code"]) == "ORIGINAL_RECEIPT_MISSING":
			dark = true
	var complete: Array[String] = _anchor_actions(first, dark)
	var unsigned: Array[String] = complete.duplicate()
	unsigned.pop_back()
	_replay(first, str(initial["board"]), unsigned)
	assert_eq(str(first.regional_anchor_recovery.snapshot()["phase"]), "verified")
	var second: Dictionary = _start(finale, account,
		_save(profile, account, "unsigned_2"), true)
	if second.is_empty():
		return
	var current: Runtime = second["session"]
	assert_true(current.regional_network == first.regional_network)
	assert_false(first.regional_anchor_recovery.closed())
	assert_eq(str(_send(first, unsigned.size() + 1,
		str(initial["board"]), "anchor_signoff")["code"]),
		"ANCHOR_DISPATCH_CONTEXT_EXPIRED")
	assert_eq(str(current.regional_anchor_recovery.snapshot()["phase"]),
		"audit_pending")
	assert_eq(str(_send(current, 1, str(second["board"]),
		"anchor_signoff")["code"]), "ANCHOR_STABLE_SOURCE_REQUIRED")
	_replay(current, str(second["board"]), _anchor_actions(current, dark), 2)
	assert_true(current.regional_anchor_recovery.closed())
	assert_eq(first.pending_rewards(account).size(), 0)
	assert_eq(current.pending_rewards(account).size(), 0)


func test_EXP015_A12_7_preempted_verified_live_and_dark_signoffs() -> void:
	_verification_preempted_by_dispatch(0)
	_verification_preempted_by_dispatch(10)
