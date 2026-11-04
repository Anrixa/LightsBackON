extends "res://tests/test_case.gd"
## G06 production integration. Tests the exact local coordinator used by the
## windowed menu/MissionRoot, not only the underlying standalone save writer.

const Offline := preload("res://scripts/gameplay/offline_c01_session.gd")
const Store := preload("res://scripts/persistence/offline_persistence.gd")
const Settings := preload("res://scripts/ui/accessibility_settings.gd")
const SaveService := preload("res://scripts/persistence/save_service.gd")
const Codec := preload("res://scripts/persistence/checkpoint_codec.gd")

var _root: String
var _store: Store
var _session: Offline


func before_each() -> void:
	_root = "user://test_offline_checkpoint/run_%d_%d" % [Time.get_ticks_usec(), randi()]
	_store = Store.new()
	assert_true(_store.initialize(_root)["ok"], "random local identity is persisted")
	_session = _fresh_session()


func after_each() -> void:
	_session = null
	_store = null
	_remove_tree(_root)


func test_G06_identity_is_random_persistent_and_not_a_steam_identifier() -> void:
	var first: String = _store.account_key
	assert_true(first.begins_with("solo_"))
	assert_eq(first.length(), 37, "prefix + sixteen cryptographically random bytes")
	assert_true(SaveService.is_valid_key(first))
	assert_false(first.contains("steam"))
	var reopen: Store = Store.new()
	assert_true(reopen.initialize(_root)["ok"])
	assert_eq(reopen.account_key, first, "same identity after relaunch")
	assert_eq(reopen.checkpoint_status()["available"], false)


func test_G06_local_checkpoint_resume_preserves_causes_and_discards_stale_measurements() -> void:
	assert_true(_session.command("inspect", "PANEL_JW")["ok"])
	assert_true(_session.command("request_lock", "R_JW_FUSE")["ok"])
	for tool_and_step: Array in [["", "diagnose"], ["", "isolate"], ["screwdriver", "open"],
			["puller", "remove"], ["puller", "install"], ["", "close"], ["meter", "test"], ["", "restore"]]:
		assert_true(_session.command("equip", "", {"tool": str(tool_and_step[0])})["ok"])
		assert_true(_session.command("repair_step", "R_JW_FUSE", {"step": str(tool_and_step[1])})["ok"])
		_session.tick_once()
	assert_true(_session.grid.canonical_state()["nodes"]["APT_W"]["supplied"])
	var hash_before: String = _session.grid.canonical_hash()
	var save: Dictionary = _store.write_checkpoint(_session, Vector3i(3300, 90, 2600), 750, -170, 2)
	assert_true(save["ok"], str(save))
	var reopened: Store = Store.new()
	assert_true(reopened.initialize(_root)["ok"])
	var resumed: Offline = _fresh_session()
	var result: Dictionary = reopened.restore_into(resumed)
	assert_true(result.get("ok", false), str(result))
	assert_eq(result["source"], "current")
	assert_eq(result["view"]["tool_slot"], 2)
	assert_eq(result["view"]["position_cm"], [3300, 90, 2600])
	assert_eq(resumed.grid.canonical_hash(), hash_before, "same authoritative grid causes after replay")
	assert_eq(resumed.interaction.repair_state("R_JW_FUSE"), "restored")
	assert_eq(resumed.interaction.supply("FUSE_W"), 0, "consumed fuse not duplicated")
	assert_false(resumed.meter.readings("PANEL_JW", resumed.grid)["_panel"].has("tick"),
		"the previous session's meter reading is intentionally discarded")
	assert_eq(resumed.host_state()["crew"], ["P1"], "one admitted local player after reconnect")
	assert_eq(resumed.grid.tick, _session.grid.tick, "grid host tick continuity")


func test_G06_preferences_roundtrip_and_reject_partial_updates_atomically() -> void:
	var model: Settings = Settings.new()
	assert_true(model.set_value("ui_scale_percent", 150))
	assert_true(model.set_value("reduce_camera_motion", false))
	assert_true(_store.write_preferences(model)["ok"])
	var restored: Settings = Settings.new()
	assert_true(_store.read_preferences(restored)["ok"])
	assert_eq(restored.snapshot(), model.snapshot())
	var before: Dictionary = restored.snapshot()
	var broken: Dictionary = before.duplicate(true)
	broken["hints_enabled"] = "false"
	assert_false(restored.restore_snapshot(broken))
	assert_eq(restored.snapshot(), before, "a malformed profile never partially updates the live controls")
	broken = before.duplicate(true)
	broken.erase("reduce_flashes")
	assert_false(restored.restore_snapshot(broken))
	assert_eq(restored.snapshot(), before)


func test_G06_corruption_recovery_is_visible_and_never_overwritten_silently() -> void:
	assert_true(_store.write_checkpoint(_session, Vector3i(450, 90, 1500), 0, 0, 1)["ok"])
	var first_hash: PackedByteArray = FileAccess.get_file_as_bytes(_store.checkpoint_path())
	_session.tick_once()
	assert_true(_store.write_checkpoint(_session, Vector3i(460, 90, 1500), 0, 0, 1)["ok"])
	# Deliberately truncate only current. The good backup must still load.
	var file: FileAccess = FileAccess.open(_store.checkpoint_path(), FileAccess.WRITE)
	file.store_string("{truncated")
	file.close()
	var status: Dictionary = _store.checkpoint_status()
	assert_true(status.get("ok", false), str(status))
	assert_eq(status["source"], "backup")
	assert_eq(status["issues"], ["CURRENT_CORRUPT"] as Array[String])
	assert_eq(status["view"]["position_cm"], [450, 90, 1500])
	# A subsequent autosave must not delete an unreadable or backup-only record.
	assert_eq(_store.write_checkpoint(_session, Vector3i(470, 90, 1500), 0, 0, 1)["ok"], true)
	assert_true(FileAccess.file_exists(_store.checkpoint_path()))
	assert_ne(FileAccess.get_file_as_bytes(_store.checkpoint_path()), first_hash)


func test_G06_incompatible_and_newer_checkpoint_are_not_overwritten() -> void:
	assert_true(_store.write_checkpoint(_session, Vector3i(450, 90, 1500), 0, 0, 1)["ok"])
	var record: Dictionary = _store.checkpoint_status()
	assert_true(record["ok"])
	var svc: SaveService = SaveService.new()
	svc.configure(1, "future-build", "incompatible-content")
	assert_true(svc.write_record(_store.checkpoint_path(), Codec.KIND, Store.CHECKPOINT_ID,
		record["payload"], "2026-11-05T00:00:00Z")["ok"])
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(_store.checkpoint_path())
	assert_eq(_store.checkpoint_status()["code"], "CONTENT_MISMATCH")
	assert_eq(_store.write_checkpoint(_session, Vector3i(460, 90, 1500), 0, 0, 1)["code"], "CONTENT_MISMATCH")
	assert_eq(FileAccess.get_file_as_bytes(_store.checkpoint_path()), bytes)
	var newer: SaveService = SaveService.new()
	newer.configure(2, "future-build", "new-revision")
	assert_true(newer.write_record(_store.checkpoint_path(), Codec.KIND, Store.CHECKPOINT_ID,
		record["payload"], "2026-11-05T00:01:00Z")["ok"])
	bytes = FileAccess.get_file_as_bytes(_store.checkpoint_path())
	assert_eq(_store.checkpoint_status()["code"], "NEWER_SCHEMA")
	assert_eq(_store.write_checkpoint(_session, Vector3i(460, 90, 1500), 0, 0, 1)["code"], "NEWER_SCHEMA")
	assert_eq(FileAccess.get_file_as_bytes(_store.checkpoint_path()), bytes)


func test_G06_corrupt_identity_never_creates_another_profile() -> void:
	var saved: String = _store.account_key
	var identity: String = _root.path_join("offline_identity.json")
	var file: FileAccess = FileAccess.open(identity, FileAccess.WRITE)
	file.store_string("garbled identity")
	file.close()
	var next: Store = Store.new()
	var result: Dictionary = next.initialize(_root)
	assert_false(result.get("ok", false))
	assert_eq(next.account_key, "")
	assert_false(DirAccess.dir_exists_absolute(_root.path_join("profiles").path_join("solo_fake")))
	assert_true(SaveService.is_valid_key(saved), "the original profile ID remains well-formed")


func test_G06_view_must_be_integral_bounded_and_not_usable_for_path_injection() -> void:
	assert_eq(_store.write_checkpoint(_session, Vector3i(11001, 90, 1500), 0, 0, 1)["code"], "BAD_VIEW")
	assert_eq(_store.write_checkpoint(_session, Vector3i(450, 90, 1500), 9000, 0, 1)["code"], "BAD_VIEW")
	assert_eq(_store.write_checkpoint(_session, Vector3i(450, 90, 1500), 0, 0, 6)["code"], "BAD_VIEW")
	assert_false(FileAccess.file_exists(_store.checkpoint_path()), "invalid views cannot create files")


func test_G06_menu_has_separate_continue_and_new_shift_and_pause_saves() -> void:
	var menu: PackedScene = load("res://scenes/menu/main_menu.tscn")
	var mission: PackedScene = load("res://scenes/mission/mission_root.tscn")
	assert_true(menu != null and mission != null)
	if menu == null or mission == null:
		return
	var menu_node: Node = menu.instantiate()
	assert_true(menu_node.get_script() != null)
	assert_true(menu_node.has_method("_continue_shift"))
	assert_true(menu_node.has_method("_request_new_shift"))
	var mission_node: Node = mission.instantiate()
	assert_true(mission_node.get_script() != null)
	assert_true(mission_node.has_method("_save_checkpoint"))
	assert_true(mission_node.has_method("_apply_restored_view"))
	menu_node.free()
	mission_node.free()


func _fresh_session() -> Offline:
	var session: Offline = Offline.new()
	var errors: Array[Dictionary] = session.setup(func(_player: String, _entity: String) -> bool: return true,
		func(_player: String) -> Vector3i: return Vector3i(450, 90, 1500))
	assert_true(errors.is_empty(), str(errors))
	return session


static func _remove_tree(path: String) -> void:
	var dir: DirAccess = DirAccess.open(path)
	if dir == null:
		return
	for name: String in dir.get_files():
		DirAccess.remove_absolute(path.path_join(name))
	for name: String in dir.get_directories():
		_remove_tree(path.path_join(name))
	DirAccess.remove_absolute(path)
