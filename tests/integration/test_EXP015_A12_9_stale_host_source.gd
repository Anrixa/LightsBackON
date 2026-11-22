extends "res://tests/test_case.gd"
## EXP015 A12.9: prohibit obsolete authenticated regional worksite commands.
## No new RPC; no network, reward, persistence or playability certification.
const Atlas := preload("res://scripts/world/dispatch_atlas.gd")
const Ledger := preload("res://scripts/progression/expedition_ledger.gd")
const Network := preload("res://scripts/gameplay/expedition_regional_network.gd")
const Runtime := preload("res://scripts/gameplay/expedition_host_session.gd")
const Saves := preload("res://scripts/persistence/save_service.gd")
const Offline := preload("res://scripts/persistence/offline_persistence.gd")
const ContentHash := preload("res://scripts/network/content_hash.gd")

const PRIOR: Array[int] = [1, 3, 4, 6, 7, 8]
const CURRENT: Array[int] = [1, 2, 3, 4, 6, 7]
const STAMP: String = "2026-11-23T00:00:00Z"
var _root: String = ""
var _position: Vector3 = Vector3.ZERO


func before_each() -> void:
	Network.clear_host_memory_for_test()
	_root = "user://exp015_a12_9_" + str(Time.get_ticks_usec()) + "_" + str(randi())
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
		"source-only fixture receipt rejected")


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
	var written: Dictionary = storage.write_record(path, Ledger.KIND_PROFILE,
		account, profile, STAMP)
	assert_true(bool(written.get("ok", false)), str(written))
	return root


func _start(level: String, profile: Dictionary, stage: String,
		finale: bool) -> Dictionary:
	var account: String = str(profile["account_key"])
	var session: Runtime = Runtime.new()
	var started: Dictionary
	if finale:
		started = session.start(level, Callable(self, "_position_for"),
			Callable(), account, true, _save(profile, account, stage),
			true, true, true, true, true,
			true, true, true, true, true,
			true, true, true, true, true,
			true, true, true, true, true,
			false, false, false, true, true)
	else:
		started = session.start(level, Callable(self, "_position_for"),
			Callable(), account, true, _save(profile, account, stage),
			true, true, true, true, true,
			true, true, true, true, true,
			true, true, true, true, true,
			true, true, true, true, true,
			true, true, true)
	assert_true(bool(started.get("ok", false)), str(started))
	if not bool(started.get("ok", false)):
		return {}
	if finale:
		assert_true(str(started["content_revision"]).begins_with("EXP015_A12_9_"))
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


func _assert_stale_fenced(session: Runtime, board: String,
		off_path_feeder: String) -> void:
	var actions: Array[String] = [
		"regional_critical", "regional_buffer", "regional_recharge",
		"regional_isolate:" + off_path_feeder, "settlement_audit",
		"assurance_audit", "aftercare_audit"
	]
	for i: int in range(actions.size()):
		var reply: Dictionary = _send(session, i + 1, board, actions[i])
		assert_eq(str(reply.get("code", "")),
			"EXP015_A12_9_STALE_HOST_DISPATCH",
			"obsolete authenticated command " + actions[i])


func _off_path(network: Network) -> String:
	var originals: Dictionary = {}
	for edge: Dictionary in network.anchor_route_snapshot()["original_feeder_path"]:
		originals[str(edge["edge_id"])] = true
	for edge: String in network.snapshot()["feeders"]:
		if not originals.has(edge):
			return edge
	return ""


func test_EXP015_A12_9_25_original_finales_obsolete_dispatch_fenced() -> void:
	var atlas: Dictionary = Atlas.load_catalog()
	var qualified: int = 0
	for region: int in range(25):
		Network.clear_host_memory_for_test()
		var account: String = "a12_9_%02d" % region
		var profile: Dictionary = _profile(atlas, region, account)
		for slot: int in CURRENT:
			_restore(atlas, profile, 8 * region + slot)
		var finale: String = "LV_%03d" % (8 * region + 8)
		var first: Dictionary = _start(finale, profile, "first", true)
		if first.is_empty():
			continue
		var old_host: Runtime = first["session"]
		var network: Network = old_host.regional_network
		var off_path: String = _off_path(network)
		assert_false(off_path.is_empty())
		if off_path.is_empty():
			continue
		var second: Dictionary = _start(finale, profile, "second", true)
		if second.is_empty():
			continue
		var current: Runtime = second["session"]
		assert_true(current.regional_network == network)
		assert_eq(network.current_dispatch_epoch(), 2)
		var before: Dictionary = network.snapshot()
		_assert_stale_fenced(old_host, str(first["board"]), off_path)
		assert_eq(str(_send(old_host, 8, str(first["board"]),
			"anchor_audit").get("code", "")),
			"ANCHOR_DISPATCH_CONTEXT_EXPIRED",
			"original A12.6 anchor fencing must retain its error contract")
		assert_eq(str(old_host._bespoke_guard(
			"P1", "request_extract", "", {}).get("code", "")),
			"EXP015_A12_9_STALE_HOST_DISPATCH",
			"obsolete original mission extraction is not authoritative")
		assert_eq(network.snapshot(), before,
			"stale commands cannot affect events, reserve, debt or feeder states")
		assert_eq(network.current_dispatch_epoch(), 2)
		assert_eq(old_host.pending_rewards(account).size(), 0)
		assert_eq(current.pending_rewards(account).size(), 0)
		# A live, current host still has original source authority; the
		# security fence must not disable the intended regional mechanic.
		var legitimate: Dictionary = _send(current, 1,
			str(second["board"]), "regional_critical")
		assert_true(bool(legitimate.get("ok", false)),
			"current regional_critical denied " + str(legitimate))
		assert_eq(int(network.snapshot()["reserve_pu"]),
			int(before["reserve_pu"]) - 2,
			"only the current host may commit the finite reserve policy")
		assert_false(current.regional_anchor_recovery.closed())
		qualified += 1
		print("EXP015_A12_9 region=%02d stale_write=DENIED fresh_write=PASS" %
			[region + 1])
	assert_eq(qualified, 25)


func test_EXP015_A12_9_old_entry_session_cannot_mutate_finale_source() -> void:
	var atlas: Dictionary = Atlas.load_catalog()
	var account: String = "a12_9_entry"
	var profile: Dictionary = _profile(atlas, 0, account)
	var root: Dictionary = _start("LV_001", profile, "entry", false)
	if root.is_empty():
		return
	var root_host: Runtime = root["session"]
	var network: Network = root_host.regional_network
	for slot: int in CURRENT:
		_restore(atlas, profile, slot)
	var finale: Dictionary = _start("LV_008", profile, "finale", true)
	if finale.is_empty():
		return
	assert_true(finale["session"].regional_network == network)
	var before: Dictionary = network.snapshot()
	var stale_actions: Array[String] = [
		"entry_survey", "regional_critical", "regional_buffer",
		"regional_isolate:" + _off_path(network)
	]
	for i: int in range(stale_actions.size()):
		var reply: Dictionary = _send(root_host, i + 1,
			str(root["board"]), stale_actions[i])
		assert_eq(str(reply.get("code", "")),
			"EXP015_A12_9_STALE_HOST_DISPATCH")
	assert_eq(network.snapshot(), before)
	assert_eq(network.current_dispatch_epoch(), 2)
	assert_eq(root_host.pending_rewards(account).size(), 0)
	assert_eq(finale["session"].pending_rewards(account).size(), 0)
