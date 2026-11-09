extends "res://tests/test_case.gd"
## SAVE22 / ADR-018: offline checkpoints survive presentation-only content edits and nothing else.

const ContentHash := preload("res://scripts/network/content_hash.gd")
const Offline := preload("res://scripts/gameplay/offline_c01_session.gd")
const Store := preload("res://scripts/persistence/offline_persistence.gd")
const SaveService := preload("res://scripts/persistence/save_service.gd")
const Codec := preload("res://scripts/persistence/checkpoint_codec.gd")

## Modules that decide or restore authoritative state must never read a presentation-only file (ADR-018 decision 7).
const AUTHORITATIVE_DIRS: Array[String] = ["res://scripts/simulation", "res://scripts/interaction",
	"res://scripts/persistence", "res://scripts/network"]
const AUTHORITATIVE_FILES: Array[String] = ["res://scripts/gameplay/offline_c01_session.gd"]

var _root: String
var _store: Store
var _session: Offline


func before_each() -> void:
	_root = "user://test_save22/run_%d_%d" % [Time.get_ticks_usec(), randi()]
	_store = Store.new()
	assert_true(_store.initialize(_root.path_join("saves"))["ok"])
	_session = Offline.new()
	var errors: Array[Dictionary] = _session.setup(func(_player: String, _entity: String) -> bool: return true,
		func(_player: String) -> Vector3i: return Vector3i(450, 90, 1500))
	assert_true(errors.is_empty(), str(errors))


func after_each() -> void:
	_session = null
	_store = null
	_remove_tree(_root)


# --- hash -------------------------------------------------------------------------------------------------------

func test_SAVE22_shipped_list_gives_a_distinct_rules_revision() -> void:
	var listed: Dictionary = ContentHash.presentation_paths()
	assert_true(listed.has("content/ui/strings/en.json"), str(listed.keys()))
	assert_false(listed.has("content/save_compat.json"))
	assert_ne(ContentHash.rules_revision(), "")
	assert_ne(ContentHash.rules_revision(), ContentHash.content_revision())


func test_SAVE22_presentation_edit_changes_only_the_full_revision() -> void:
	var copy: String = _copy_content()
	var full: String = ContentHash.content_revision(copy)
	var rules: String = ContentHash.rules_revision(copy)
	assert_eq(full, ContentHash.content_revision(), "a copy hashes like res://content")
	assert_eq(rules, ContentHash.rules_revision())
	for rel: String in ContentHash.presentation_paths(copy).keys():
		_append(copy.get_base_dir().path_join(rel))
	assert_ne(ContentHash.content_revision(copy), full, "co-op joins still see the edit")
	assert_eq(ContentHash.rules_revision(copy), rules, "checkpoints do not")


func test_SAVE22_rules_unlisted_and_list_edits_change_both() -> void:
	var copy: String = _copy_content()
	for rel: String in ["contracts/c01_alder_street/grid.json", "world/alder_street.json", "offline_solo.json",
			"save_compat.json"]:
		var full: String = ContentHash.content_revision(copy)
		var rules: String = ContentHash.rules_revision(copy)
		_append(copy.path_join(rel))
		assert_ne(ContentHash.content_revision(copy), full, rel)
		assert_ne(ContentHash.rules_revision(copy), rules, rel)
	var before: String = ContentHash.rules_revision(copy)
	_write(copy.path_join("world/look_unclassified.json"), "{}\n")
	assert_ne(ContentHash.rules_revision(copy), before, "a new file counts as rules until someone lists it")


func test_SAVE22_broken_list_gives_no_rules_revision() -> void:
	var copy: String = _copy_content()
	var compat: String = copy.path_join(ContentHash.COMPAT_FILE)
	for text: String in ["{broken", "{\"presentation_only\": \"x\"}", "{\"presentation_only\": []}",
			"{\"presentation_only\": [{\"path\": \"content/ui/missing.json\"}]}",
			"{\"presentation_only\": [{\"path\": \"content/save_compat.json\"}]}"]:
		_write(compat, text)
		assert_eq(ContentHash.rules_revision(copy), "", text)
	DirAccess.remove_absolute(compat)
	assert_eq(ContentHash.rules_revision(copy), "")


func test_SAVE22_authoritative_modules_never_read_presentation_files() -> void:
	var files: Array[String] = AUTHORITATIVE_FILES.duplicate()
	for dir: String in AUTHORITATIVE_DIRS:
		_collect_scripts(dir, files)
	assert_true(files.size() > 10, "scanned %d scripts" % files.size())
	var needles: Array[String] = ["res://content/ui/", "ui_text.gd"]
	for rel: String in ContentHash.presentation_paths().keys():
		needles.append(rel.trim_prefix("content/"))
	for path: String in files:
		# The offline session phrases its prompts ("blocked" reasons, next step) through UiText. That is display only:
		# the decision is the branch taken, so the text may come from strings as long as nothing compares it.
		var display_only: bool = AUTHORITATIVE_FILES.has(path)
		for line: String in FileAccess.get_file_as_string(path).split("\n"):
			if line.strip_edges().begins_with("#"):
				continue  # comments may name a file (meter_model.gd documents status_states.json)
			if display_only and line.contains("UiText"):
				assert_false(line.contains("==") or line.contains("!=") or line.contains(".has("),
					"%s decides on translated text: %s" % [path, line.strip_edges()])
				continue
			for needle: String in needles:
				assert_false(line.contains(needle), "%s reads %s: %s" % [path, needle, line.strip_edges()])


# --- checkpoint load rule ---------------------------------------------------------------------------------------

func test_SAVE22_new_checkpoints_record_both_revisions() -> void:
	assert_true(_store.write_checkpoint(_session, Vector3i(450, 90, 1500), 0, 0, 1)["ok"])
	var env: Dictionary = _envelope()
	assert_eq(env["content_revision"], ContentHash.content_revision())
	assert_eq(env[SaveService.RULES_REVISION_FIELD], ContentHash.rules_revision())
	var status: Dictionary = _store.checkpoint_status()
	assert_true(status["ok"])
	assert_false(status["presentation_changed"], "same build, nothing changed")


func test_SAVE22_presentation_only_difference_resumes_and_autosave_updates_it() -> void:
	var payload: Dictionary = _saved_payload()
	_rewrite(payload, "older-presentation-content", ContentHash.rules_revision())
	var status: Dictionary = _store.checkpoint_status()
	assert_true(status.get("ok", false), str(status))
	assert_true(status["presentation_changed"])
	assert_eq(status["issues"], [] as Array, "no player-facing recovery notice for a look or text edit")
	var resumed: Offline = Offline.new()
	assert_true(resumed.setup(func(_p: String, _e: String) -> bool: return true,
		func(_p: String) -> Vector3i: return Vector3i(450, 90, 1500)).is_empty())
	assert_true(_store.restore_into(resumed).get("ok", false), "the shift continues")
	assert_true(_store.write_checkpoint(resumed, Vector3i(460, 90, 1500), 0, 0, 1)["ok"], "autosave may replace it")
	assert_eq(_envelope()["content_revision"], ContentHash.content_revision(), "rewritten with this build's revisions")
	assert_false(_store.checkpoint_status()["presentation_changed"])


func test_SAVE22_rules_difference_is_refused_and_preserved() -> void:
	_rewrite(_saved_payload(), "other-content", "other-rules")
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(_store.checkpoint_path())
	assert_eq(_store.checkpoint_status()["code"], "CONTENT_MISMATCH")
	assert_eq(_store.write_checkpoint(_session, Vector3i(460, 90, 1500), 0, 0, 1)["code"], "CONTENT_MISMATCH")
	assert_eq(FileAccess.get_file_as_bytes(_store.checkpoint_path()), bytes, "existing progress untouched")


func test_SAVE22_old_checkpoint_without_rules_revision_keeps_the_strict_rule() -> void:
	_rewrite(_saved_payload(), "pre-adr018-content", "")
	assert_false(_envelope().has(SaveService.RULES_REVISION_FIELD), "written like a save from before ADR-018")
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(_store.checkpoint_path())
	assert_eq(_store.checkpoint_status()["code"], "CONTENT_MISMATCH")
	assert_eq(_store.write_checkpoint(_session, Vector3i(460, 90, 1500), 0, 0, 1)["code"], "CONTENT_MISMATCH")
	assert_eq(FileAccess.get_file_as_bytes(_store.checkpoint_path()), bytes)
	# The same old save from the same content still loads, as before ADR-018.
	_rewrite(_saved_payload_from_disk(), ContentHash.content_revision(), "")
	assert_true(_store.checkpoint_status().get("ok", false))


func test_SAVE22_build_with_a_broken_list_accepts_nothing_by_rules() -> void:
	_rewrite(_saved_payload(), "older-presentation-content", ContentHash.rules_revision())
	_store.set("_rules_revision", "")  # what initialize() gets from a missing or malformed save_compat.json
	assert_eq(_store.checkpoint_status()["code"], "CONTENT_MISMATCH")


# --- helpers ----------------------------------------------------------------------------------------------------

func _saved_payload() -> Dictionary:
	assert_true(_store.write_checkpoint(_session, Vector3i(450, 90, 1500), 0, 0, 1)["ok"])
	return _saved_payload_from_disk()


func _saved_payload_from_disk() -> Dictionary:
	var svc: SaveService = SaveService.new()
	svc.configure(1, "probe", "probe")
	return svc.read_record(_store.checkpoint_path())["payload"]


## Rewrites the checkpoint as another build would have written it.
func _rewrite(payload: Dictionary, content_revision: String, rules_revision: String) -> void:
	var svc: SaveService = SaveService.new()
	svc.configure(1, "other-build", content_revision, rules_revision)
	assert_true(svc.write_record(_store.checkpoint_path(), Codec.KIND, Store.CHECKPOINT_ID, payload,
		"2026-11-09T00:00:00Z")["ok"])


func _envelope() -> Dictionary:
	var svc: SaveService = SaveService.new()
	svc.configure(1, "probe", "probe")
	return svc.read_record(_store.checkpoint_path())["envelope"]


func _copy_content() -> String:
	var dest: String = _root.path_join("copy/content")
	_copy_tree(ContentHash.ROOT, dest)
	return dest


func _copy_tree(from: String, to: String) -> void:
	DirAccess.make_dir_recursive_absolute(to)
	var d: DirAccess = DirAccess.open(from)
	for f: String in d.get_files():
		_write_bytes(to.path_join(f), FileAccess.get_file_as_bytes(from.path_join(f)))
	for sub: String in d.get_directories():
		_copy_tree(from.path_join(sub), to.path_join(sub))


func _append(path: String) -> void:
	_write_bytes(path, FileAccess.get_file_as_bytes(path) + "\n".to_utf8_buffer())


func _write(path: String, text: String) -> void:
	_write_bytes(path, text.to_utf8_buffer())


func _write_bytes(path: String, bytes: PackedByteArray) -> void:
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(bytes)
	f.close()


func _collect_scripts(dir_path: String, out: Array[String]) -> void:
	var d: DirAccess = DirAccess.open(dir_path)
	if d == null:
		return
	for f: String in d.get_files():
		if f.ends_with(".gd"):
			out.append(dir_path.path_join(f))
	for sub: String in d.get_directories():
		_collect_scripts(dir_path.path_join(sub), out)


func _remove_tree(path: String) -> void:
	var d: DirAccess = DirAccess.open(path)
	if d == null:
		return
	for f: String in d.get_files():
		DirAccess.remove_absolute(path.path_join(f))
	for sub: String in d.get_directories():
		_remove_tree(path.path_join(sub))
	DirAccess.remove_absolute(path)
