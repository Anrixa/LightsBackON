extends "res://tests/test_case.gd"
## EXP04: authoritative lore pickup and additive per-account field score.
## Every checked position is host-owned; these are headless source probes,
## not a walked-route, controller, GPU or Steam qualification.

const Atlas := preload("res://scripts/world/dispatch_atlas.gd")
const Runtime := preload("res://scripts/gameplay/expedition_host_session.gd")
const Ledger := preload("res://scripts/progression/expedition_ledger.gd")
const Saves := preload("res://scripts/persistence/save_service.gd")
const LegacyRewards := preload("res://scripts/progression/reward_service.gd")

const NOW: String = "2026-11-19T10:00:00Z"
const ACCOUNT: String = "exp04_test_account"
var _position: Vector3 = Vector3(2.0, 0.90, 2.0)
var _root: String = ""
var _save: Saves


func before_each() -> void:
	_position = Vector3(2.0, 0.90, 2.0)
	_root = "user://exp04_test_" + str(Time.get_ticks_usec()) + "_" + str(randi() % 100000)
	_save = Saves.new()
	_save.configure(1, "exp04-test", "exp04-test-content")


func after_each() -> void:
	_remove_test_tree(_root)


func _remove_test_tree(path: String) -> void:
	var dir: DirAccess = DirAccess.open(path)
	if dir == null:
		return
	for item: String in dir.get_files():
		DirAccess.remove_absolute(path.path_join(item))
	for sub: String in dir.get_directories():
		_remove_test_tree(path.path_join(sub))
	DirAccess.remove_absolute(path)


func _host_position(_player: String) -> Vector3:
	return _position


func _session(level_id: String = "LV_017") -> Runtime:
	var runtime: Runtime = Runtime.new()
	var reply: Dictionary = runtime.start(level_id, Callable(self, "_host_position"),
		Callable(), ACCOUNT)
	assert_true(bool(reply.get("ok", false)), str(reply))
	return runtime


func _stand(runtime: Runtime, id: String) -> void:
	var p: Vector3 = runtime.definition_snapshot()["positions"][id]
	_position = Vector3(p.x, 0.90, p.z)


func _send(runtime: Runtime, seq: int, kind: String, entity: String,
		payload: Dictionary = {}, peer: int = 1) -> Dictionary:
	return runtime.receive(peer, JSON.stringify({
		"session": runtime.session_id(), "seq": seq,
		"type": kind, "entity": entity, "payload": payload
	}).to_utf8_buffer())


func test_EXP04_host_rejects_remote_early_replayed_and_forged_lore_claims() -> void:
	var runtime: Runtime = _session()
	var item: String = str(runtime.lore_state()["id"])
	assert_eq(item, "FIND_017")
	_stand(runtime, item)
	var denied: Dictionary = _send(runtime, 1, "collect_lore", item)
	assert_eq(str(denied["code"]), "DISCOVERY_EVIDENCE_REQUIRED")
	assert_false(bool(runtime.lore_state()["collected"]))
	assert_eq(runtime.pending_rewards(ACCOUNT).size(), 0)
	denied = _send(runtime, 2, "collect_lore", item, {}, 222)
	assert_eq(str(denied["code"]), "UNKNOWN_PEER")
	_stand(runtime, "PANEL_SPUR")
	assert_true(bool(_send(runtime, 2, "inspect", "PANEL_SPUR").get("ok", false)))
	assert_true(bool(runtime.task_board()["optional_completed"]))
	assert_eq(runtime.pending_rewards(ACCOUNT).size(), 1, "optional task yields exactly one receipt")
	_position = Vector3(2.0, 0.90, 2.0)
	denied = _send(runtime, 3, "collect_lore", item)
	assert_eq(str(denied["code"]), "NOT_IN_RANGE")
	assert_false(bool(runtime.lore_state()["collected"]))
	_stand(runtime, item)
	denied = _send(runtime, 4, "collect_lore", "FIND_999")
	assert_false(bool(denied.get("ok", true)))
	assert_false(bool(runtime.lore_state()["collected"]))
	var before: String = runtime.state_hash()
	var reply: Dictionary = _send(runtime, 5, "collect_lore", item)
	assert_true(bool(reply.get("ok", false)), str(reply))
	assert_true(bool(runtime.lore_state()["collected"]))
	assert_ne(runtime.state_hash(), before, "lore pickup belongs to the host's canonical state")
	assert_eq(runtime.pending_rewards(ACCOUNT).size(), 2, "one task and one lore receipt")
	var replay: Dictionary = _send(runtime, 5, "collect_lore", item)
	assert_true(bool(replay.get("duplicate", false)), str(replay))
	assert_eq(runtime.pending_rewards(ACCOUNT).size(), 2)
	assert_eq(str(_send(runtime, 6, "collect_lore", item).get("code", "")), "ALREADY_COLLECTED")
	assert_false(bool(_send(runtime, 7, "collect_lore", item,
		{"points": 999999}).get("ok", true)))
	assert_eq(runtime.pending_rewards("not_this_account").size(), 0)


func test_EXP04_receipts_persist_atomically_and_never_touch_legacy_profile() -> void:
	var dir: String = _root.path_join("profiles").path_join(ACCOUNT)
	var old: Dictionary = LegacyRewards.new_profile(ACCOUNT)
	old["credits"] = 12345
	assert_true(bool(_save.write_record(dir.path_join("profile.json"),
		"profile", ACCOUNT, old, NOW)["ok"]))
	var untouched: PackedByteArray = FileAccess.get_file_as_bytes(dir.path_join("profile.json"))
	var runtime: Runtime = _session()
	_stand(runtime, "PANEL_SPUR")
	assert_true(bool(_send(runtime, 1, "inspect", "PANEL_SPUR").get("ok", false)))
	_stand(runtime, str(runtime.lore_state()["id"]))
	assert_true(bool(_send(runtime, 2, "collect_lore",
		str(runtime.lore_state()["id"])).get("ok", false)))
	var pending: Array[Dictionary] = runtime.pending_rewards(ACCOUNT)
	var saved: Dictionary = Ledger.receive(_save, ACCOUNT, _root, pending, NOW)
	assert_true(bool(saved.get("ok", false)), str(saved))
	assert_eq(int(saved["profile"]["field_points"]), 35)
	assert_eq((saved["profile"]["lore_finds"] as Dictionary).size(), 1)
	for key: String in saved["acks"]:
		runtime.ack_reward(ACCOUNT, key)
	assert_eq(runtime.pending_rewards(ACCOUNT).size(), 0)
	var again: Dictionary = Ledger.receive(_save, ACCOUNT, _root, pending, NOW)
	assert_true(bool(again["ok"]))
	assert_eq(int(again["profile"]["field_points"]), 35, "reconnect never pays twice")
	assert_eq(FileAccess.get_file_as_bytes(dir.path_join("profile.json")), untouched,
		"the original V08 profile is byte-identical")
	assert_false(FileAccess.file_exists(dir.path_join("checkpoints/SOLO_C01.json")))


func test_EXP04_all_1000_tasks_and_200_lore_ids_are_unique_and_points_bounded() -> void:
	var atlas: Dictionary = Atlas.load_catalog()
	assert_true(bool(Atlas.inspect(atlas)["ok"]))
	var profile: Dictionary = Ledger.new_profile(ACCOUNT)
	var source_receipts: Array[Dictionary] = []
	for level: Dictionary in atlas["levels"]:
		for task: Dictionary in level["tasks"]:
			var receipt: Dictionary = Ledger.make_receipt(ACCOUNT, str(level["id"]),
				str(task["id"]), str(task["kind"]))
			source_receipts.append(receipt)
			var applied: Dictionary = Ledger.apply_receipt(profile, receipt, atlas)
			assert_true(bool(applied.get("applied", false)), str(applied))
		var lore: Dictionary = level["collectible"]
		var find_receipt: Dictionary = Ledger.make_receipt(ACCOUNT, str(level["id"]),
			str(lore["id"]), "lore")
		source_receipts.append(find_receipt)
		assert_true(bool(Ledger.apply_receipt(profile, find_receipt, atlas).get("applied", false)))
	assert_eq((profile["earned_tasks"] as Dictionary).size(), 1000)
	assert_eq((profile["lore_finds"] as Dictionary).size(), 200)
	assert_eq((profile["completed_levels"] as Dictionary).size(), 200)
	assert_eq(int(profile["field_points"]), Ledger.MAX_FIELD_POINTS)
	assert_eq(source_receipts.size(), 1200)
	assert_false(bool(Ledger.apply_receipt(profile, source_receipts[0], atlas)["applied"]))
	assert_eq(int(profile["field_points"]), Ledger.MAX_FIELD_POINTS)
	var forged: Dictionary = source_receipts[0].duplicate(true)
	forged["points"] = 50000
	assert_eq(str(Ledger.apply_receipt(Ledger.new_profile(ACCOUNT), forged,
		atlas)["code"]), "BAD_REWARD")
	forged = source_receipts[0].duplicate(true)
	forged["account_key"] = "another_account"
	assert_eq(str(Ledger.apply_receipt(Ledger.new_profile(ACCOUNT), forged,
		atlas)["code"]), "BAD_PROFILE")


func test_EXP04_interrupted_inbox_recovers_and_corrupt_profile_is_never_reset() -> void:
	var atlas: Dictionary = Atlas.load_catalog()
	var level: Dictionary = atlas["levels"][0]
	var task: Dictionary = level["tasks"][0]
	var receipt: Dictionary = Ledger.make_receipt(ACCOUNT, str(level["id"]),
		str(task["id"]), str(task["kind"]))
	var dir: String = _root.path_join("profiles").path_join(ACCOUNT)
	assert_true(bool(_save.write_record(dir.path_join(Ledger.INBOX_FILE),
		Ledger.KIND_INBOX, ACCOUNT, {"receipts": {
			str(receipt["receipt_key"]): receipt
		}}, NOW)["ok"]))
	var healed: Dictionary = Ledger.receive(_save, ACCOUNT, _root, [], NOW)
	assert_true(bool(healed.get("ok", false)), str(healed))
	assert_eq(int(healed["profile"]["field_points"]), 40)
	assert_eq(int(Ledger.receive(_save, ACCOUNT, _root, [], NOW)["profile"]["field_points"]), 40)
	var path: String = dir.path_join(Ledger.PROFILE_FILE)
	var bad: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	bad.store_string("{unreadable")
	bad.close()
	var result: Dictionary = Ledger.receive(_save, ACCOUNT, _root, [receipt], NOW)
	# A valid .bak may be recovered by SaveService; that is permitted, but no
	# invalid primary record may be overwritten by a fabricated empty profile.
	assert_true(bool(result.get("ok", false)) or str(result.get("code", "")) == "CORRUPT")
	if not result.get("ok", false):
		assert_eq(FileAccess.get_file_as_string(path), "{unreadable")
