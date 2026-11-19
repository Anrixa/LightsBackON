extends "res://tests/test_case.gd"
## EXP05 automated certification: exact 25x8 authored route graph, non-exclusive
## branches, host-enforced locks, crash-replay recovery and untouched C01 files.
## This does NOT qualify continuous first-person/controller playability.

const Atlas := preload("res://scripts/world/dispatch_atlas.gd")
const Campaign := preload("res://scripts/progression/expedition_campaign.gd")
const Ledger := preload("res://scripts/progression/expedition_ledger.gd")
const Runtime := preload("res://scripts/gameplay/expedition_host_session.gd")
const Saves := preload("res://scripts/persistence/save_service.gd")
const LegacyRewards := preload("res://scripts/progression/reward_service.gd")

const ACCOUNT: String = "exp05_probe_account"
const NOW: String = "2026-11-19T12:00:00Z"
var _root: String = ""
var _saves: Saves
var _atlas: Dictionary = {}
var _routes: Dictionary = {}


func before_each() -> void:
	_root = "user://exp05_test_" + str(Time.get_ticks_usec()) + "_" + str(randi() % 100000)
	_saves = Saves.new()
	_saves.configure(1, "exp05-test", "exp05-test-content")
	_atlas = Atlas.load_catalog()
	_routes = Campaign.load_routes()


func after_each() -> void:
	_remove_tree(_root)


func _remove_tree(path: String) -> void:
	var dir: DirAccess = DirAccess.open(path)
	if dir == null:
		return
	for file: String in dir.get_files():
		DirAccess.remove_absolute(path.path_join(file))
	for name: String in dir.get_directories():
		_remove_tree(path.path_join(name))
	DirAccess.remove_absolute(path)


func _restore(profile: Dictionary, number: int) -> void:
	var level_id: String = "LV_%03d" % number
	var level: Dictionary = Atlas.find_level(_atlas, level_id)
	var task: Dictionary = level["tasks"][4]
	var receipt: Dictionary = Ledger.make_receipt(ACCOUNT, level_id,
		str(task["id"]), str(task["kind"]))
	var result: Dictionary = Ledger.apply_receipt(profile, receipt, _atlas)
	assert_true(bool(result.get("applied", false)), str(result))


func _host_position(_player: String) -> Vector3:
	return Vector3(0.0, 0.90, 0.0)


func test_EXP05_graph_contains_25_authored_chapters_and_200_exact_source_nodes() -> void:
	var check: Dictionary = Campaign.inspect(_atlas, _routes)
	assert_true(bool(check.get("ok", false)), str(check))
	assert_eq(int(check["regions"]), 25)
	assert_eq(int(check["levels"]), 200)
	assert_eq(int(check["branch_points"]), 50)
	assert_eq(int(check["or_joins"]), 50)
	var seen: Dictionary = {}
	for node: Dictionary in _routes["nodes"]:
		assert_false(seen.has(node["route_label"]))
		seen[node["route_label"]] = true
		assert_true(str(node["narrative"]).length() >= 60)
	assert_eq(seen.size(), 200)
	for chapter: Dictionary in _routes["chapters"]:
		assert_true(str(chapter["first_fork"]).contains("or"))
		assert_true(str(chapter["second_fork"]).contains("or"))


func test_EXP05_first_entry_only_then_both_forks_and_either_join() -> void:
	var profile: Dictionary = Ledger.new_profile(ACCOUNT)
	var result: Dictionary = Campaign.evaluate(profile, _atlas, _routes)
	assert_true(bool(result.get("ok", false)), str(result))
	assert_eq(int(result["available"]), 1)
	assert_eq(int(result["locked"]), 199)
	assert_eq(result["states"]["LV_001"]["status"], "AVAILABLE")
	assert_eq(result["states"]["LV_002"]["status"], "LOCKED")
	_restore(profile, 1)
	result = Campaign.evaluate(profile, _atlas, _routes)
	assert_eq(result["states"]["LV_002"]["status"], "AVAILABLE")
	assert_eq(result["states"]["LV_003"]["status"], "AVAILABLE")
	assert_eq(result["states"]["LV_004"]["status"], "LOCKED")
	_restore(profile, 3)
	result = Campaign.evaluate(profile, _atlas, _routes)
	assert_eq(result["states"]["LV_004"]["status"], "AVAILABLE",
		"either fork opens the next junction")
	assert_eq(result["states"]["LV_002"]["status"], "AVAILABLE",
		"other route remains accessible, never permanently discarded")
	_restore(profile, 4)
	assert_eq(Campaign.evaluate(profile, _atlas, _routes)["states"]["LV_006"]["status"],
		"AVAILABLE")
	_restore(profile, 6)
	result = Campaign.evaluate(profile, _atlas, _routes)
	assert_eq(result["states"]["LV_007"]["status"], "AVAILABLE")
	assert_eq(result["states"]["LV_005"]["status"], "AVAILABLE")
	_restore(profile, 7)
	_restore(profile, 8)
	result = Campaign.evaluate(profile, _atlas, _routes)
	assert_eq(result["states"]["LV_009"]["status"], "AVAILABLE")
	assert_eq(result["states"]["LV_002"]["status"], "AVAILABLE")
	assert_eq(result["states"]["LV_008"]["status"], "RESTORED")
	assert_eq(int(result["cleared_regions"]), 1)


func test_EXP05_all_25_region_spines_reach_finale_and_leave_50_optional_routes() -> void:
	var profile: Dictionary = Ledger.new_profile(ACCOUNT)
	for region: int in range(25):
		var base: int = region * 8
		for slot: int in [1, 3, 4, 6, 7, 8]:
			var number: int = base + slot
			var access: Dictionary = Campaign.can_launch(profile, _atlas, _routes,
				"LV_%03d" % number)
			assert_true(bool(access.get("ok", false)), str(access))
			_restore(profile, number)
	var all: Dictionary = Campaign.evaluate(profile, _atlas, _routes)
	assert_true(bool(all.get("ok", false)), str(all))
	assert_eq(int(all["restored"]), 150)
	assert_eq(int(all["available"]), 50)
	assert_eq(int(all["locked"]), 0)
	assert_eq(int(all["cleared_regions"]), 25)
	assert_eq(int(profile["field_points"]), 150 * 85)
	assert_eq((profile["completed_levels"] as Dictionary).size(), 150)
	assert_eq(Campaign.can_launch(profile, _atlas, _routes, "LV_999")["code"],
		"UNKNOWN_LEVEL")


func test_EXP05_rejects_forged_edges_unknown_progress_and_orphan_restorations() -> void:
	var forged: Dictionary = _routes.duplicate(true)
	(forged["nodes"][3] as Dictionary)["requires_any"] = ["LV_001"]
	assert_eq(Campaign.inspect(_atlas, forged)["code"], "UNAUTHORIZED_ROUTE_GRAPH")
	forged = _routes.duplicate(true)
	(forged["nodes"][0] as Dictionary)["requires_any"] = ["LV_200"]
	assert_eq(Campaign.inspect(_atlas, forged)["code"], "UNAUTHORIZED_ROUTE_GRAPH")
	forged = _routes.duplicate(true)
	(forged["nodes"][1] as Dictionary)["route_label"] = forged["nodes"][0]["route_label"]
	assert_eq(Campaign.inspect(_atlas, forged)["code"], "DUPLICATE_OR_MISSING_ROUTE_STORY")
	var profile: Dictionary = Ledger.new_profile(ACCOUNT)
	profile["completed_levels"]["LV_200"] = true
	assert_eq(Campaign.evaluate(profile, _atlas, _routes)["code"],
		"RESTORATION_RECEIPT_MISMATCH")
	profile = Ledger.new_profile(ACCOUNT)
	profile["completed_levels"]["LV_999"] = true
	assert_eq(Campaign.evaluate(profile, _atlas, _routes)["code"],
		"FOREIGN_COMPLETED_LEVEL")
	profile = Ledger.new_profile(ACCOUNT)
	_restore(profile, 1)
	profile["completed_levels"].erase("LV_001")
	assert_eq(Campaign.evaluate(profile, _atlas, _routes)["code"],
		"RESTORATION_RECEIPT_MISMATCH")


func test_EXP05_host_gate_rejects_locked_levels_and_accepts_saved_restoration() -> void:
	var initial: Runtime = Runtime.new()
	var forbidden: Dictionary = initial.start("LV_002",
		Callable(self, "_host_position"), Callable(), ACCOUNT, true, _root)
	assert_eq(str(forbidden.get("code", "")), "CAMPAIGN_LEVEL_LOCKED")
	assert_false(initial.completed())
	var allowed: Runtime = Runtime.new()
	assert_true(bool(allowed.start("LV_001", Callable(self, "_host_position"),
		Callable(), ACCOUNT, true, _root).get("ok", false)))
	var profile: Dictionary = Ledger.new_profile(ACCOUNT)
	_restore(profile, 1)
	var path: String = _root.path_join("profiles").path_join(ACCOUNT)
	assert_true(bool(_saves.write_record(path.path_join(Ledger.PROFILE_FILE),
		Ledger.KIND_PROFILE, ACCOUNT, profile, NOW).get("ok", false)))
	var next: Runtime = Runtime.new()
	assert_true(bool(next.start("LV_003", Callable(self, "_host_position"),
		Callable(), ACCOUNT, true, _root).get("ok", false)))
	var bypass: Runtime = Runtime.new()
	assert_eq(str(bypass.start("LV_008", Callable(self, "_host_position"),
		Callable(), ACCOUNT, true, _root).get("code", "")), "CAMPAIGN_LEVEL_LOCKED")


func test_EXP05_inbox_recovery_unlocks_once_without_legacy_profile_mutation() -> void:
	var dir: String = _root.path_join("profiles").path_join(ACCOUNT)
	var legacy: Dictionary = LegacyRewards.new_profile(ACCOUNT)
	legacy["credits"] = 87654
	assert_true(bool(_saves.write_record(dir.path_join("profile.json"),
		"profile", ACCOUNT, legacy, NOW).get("ok", false)))
	var legacy_before: PackedByteArray = FileAccess.get_file_as_bytes(
		dir.path_join("profile.json"))
	var level: Dictionary = _atlas["levels"][0]
	var restoration: Dictionary = level["tasks"][4]
	var receipt: Dictionary = Ledger.make_receipt(ACCOUNT, "LV_001",
		str(restoration["id"]), "restoration")
	assert_true(bool(_saves.write_record(dir.path_join(Ledger.INBOX_FILE),
		Ledger.KIND_INBOX, ACCOUNT, {
			"receipts": {str(receipt["receipt_key"]): receipt}
		}, NOW).get("ok", false)))
	var replay: Dictionary = Ledger.receive(_saves, ACCOUNT, _root, [], NOW)
	assert_true(bool(replay.get("ok", false)), str(replay))
	assert_eq(Campaign.evaluate(replay["profile"], _atlas, _routes)["states"]["LV_002"]["status"],
		"AVAILABLE")
	var again: Dictionary = Ledger.receive(_saves, ACCOUNT, _root, [receipt], NOW)
	assert_true(bool(again.get("ok", false)), str(again))
	assert_eq(int(again["profile"]["field_points"]), 85)
	assert_eq(FileAccess.get_file_as_bytes(dir.path_join("profile.json")), legacy_before)
	assert_false(FileAccess.file_exists(dir.path_join("checkpoints/SOLO_C01.json")))
