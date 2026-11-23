extends RefCounted
## Local-only C01 save coordinator. Wraps G06's checksum/backup writer and
## CheckpointCodec; never writes Steam credentials or client-authoritative state.
##
## One random pseudonymous identity is saved once. Subsequent launches reuse it.
## A corrupt/newer identity fails closed so it cannot orphan an existing profile.
## A mismatched checkpoint is never silently overwritten by autosave.
## ADR-018: a checkpoint from content that differs only in presentation-only files (content/save_compat.json) is
## accepted when it carries the same rules_revision; saves without that field keep the strict full-revision rule.

const SaveService := preload("res://scripts/persistence/save_service.gd")
const Codec := preload("res://scripts/persistence/checkpoint_codec.gd")
const ContentHash := preload("res://scripts/network/content_hash.gd")
const PowerGrid := preload("res://scripts/simulation/power_grid.gd")

const ID_KIND: String = "offline_identity"
const PROFILE_KIND: String = "profile"
const ACCOUNT_ID: String = "LOCAL_SOLO"
const CHECKPOINT_ID: String = "SOLO_C01"
const CONTRACT_ID: String = "C01"
const PROFILE_FILE: String = "profile.json"
const CHECKPOINT_FILE: String = "checkpoints/SOLO_C01.json"
const SAVE_BUILD_ID: String = "offline-game"
const HEADLESS_SANDBOX_ROOT: String = "user://test_runtime/headless_offline"

var account_key: String = ""
var _root: String = ""
var _save: SaveService
var _revision: String = ""
var _rules_revision: String = ""
var _initialized: bool = false


## Headless scene probes use their own sandbox. Do not let test scenes launched
## by CI (or by an owner running --headless locally) overwrite played progress.
## The override is for isolated unit tests, production windowed uses user://.
static func runtime_root() -> String:
	return HEADLESS_SANDBOX_ROOT if DisplayServer.get_name() == "headless" else "user://"


func initialize(storage_root: String = "") -> Dictionary:
	_root = runtime_root() if storage_root == "" else storage_root
	_initialized = false
	account_key = ""
	var versions: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/versions.json"))
	_revision = ContentHash.content_revision()
	_rules_revision = ContentHash.rules_revision()
	_save = SaveService.new()
	_save.configure(int(versions["save_schema_version"]), SAVE_BUILD_ID, _revision, _rules_revision)
	var path: String = _root.path_join("offline_identity.json")
	var read: Dictionary = _save.read_record(path)
	if read.get("ok", false):
		var valid: Dictionary = _validate_envelope(read, ID_KIND, ACCOUNT_ID, false)
		if not valid.get("ok", false):
			return valid
		var payload: Dictionary = read["payload"]
		if not (payload.get("account_key") is String and SaveService.is_valid_key(payload["account_key"])):
			return _failure("BAD_IDENTITY", "offline identity record is malformed; existing saves were preserved")
		account_key = str(payload["account_key"])
	elif str(read.get("code", "")) == "NOT_FOUND":
		var key: String = "solo_" + Crypto.new().generate_random_bytes(16).hex_encode()
		var write: Dictionary = _save.write_record(path, ID_KIND, ACCOUNT_ID, {"account_key": key}, _utc_now())
		if not write.get("ok", false):
			return write
		account_key = key
	else:
		return _failure(str(read.get("code", "BAD_IDENTITY")),
			"offline identity could not be loaded; no new profile was created")
	_initialized = true
	return {"ok": true, "account_key": account_key}


func checkpoint_path() -> String:
	return _profile_dir().path_join(CHECKPOINT_FILE)


func profile_path() -> String:
	return _profile_dir().path_join(PROFILE_FILE)


func _profile_dir() -> String:
	return _root.path_join("profiles").path_join(account_key)


## No checkpoint is normal for a new player. Bad/newer saves are an error,
## never interpreted as "start over" or overwritten without explicit handling.
func checkpoint_status() -> Dictionary:
	if not _initialized:
		return _failure("NOT_READY", "offline identity is unavailable")
	var read: Dictionary = _save.read_record(checkpoint_path())
	if str(read.get("code", "")) == "NOT_FOUND":
		return {"ok": true, "available": false}
	if not read.get("ok", false):
		return read
	var checked: Dictionary = _validate_envelope(read, Codec.KIND, CHECKPOINT_ID, true)
	if not checked.get("ok", false):
		return checked
	var payload: Dictionary = read["payload"]
	if not (payload.get("campaign_id") == CHECKPOINT_ID and payload.get("contract_id") == CONTRACT_ID):
		return _failure("BAD_CHECKPOINT", "saved campaign or contract does not match this solo mission")
	var placement: Dictionary = _validate_view(payload.get("view", {}))
	if not placement.get("ok", false):
		return placement
	return {"ok": true, "available": true, "payload": payload,
		"view": placement["view"], "issues": read.get("issues", []), "source": read["source"],
		"presentation_changed": checked.get("presentation_changed", false)}


## Caller must pass a *freshly configured* session and discard it on any
## failure, because CheckpointCodec restores several services sequentially.
func restore_into(session: RefCounted) -> Dictionary:
	var status: Dictionary = checkpoint_status()
	if not status.get("ok", false) or not status.get("available", false):
		return status
	var problems: Array[Dictionary] = Codec.restore(status["payload"], CONTRACT_ID,
		session.get("grid"), session.get("interaction"), session.get("equipment"), session.get("mission"))
	if not problems.is_empty():
		return _failure("BAD_CHECKPOINT", "checkpoint state cannot be restored safely: %s" % str(problems))
	session.set("_tick", int(session.get("grid").get("tick")))
	return status


func write_checkpoint(session: RefCounted, position_cm: Vector3i, yaw_millirad: int,
		pitch_millirad: int, tool_slot: int) -> Dictionary:
	if not _initialized:
		return _failure("NOT_READY", "offline identity is unavailable")
	# Refuse to replace corrupt, future-schema or different-content progress.
	var existing: Dictionary = checkpoint_status()
	if not existing.get("ok", false):
		return existing
	var view: Dictionary = {"position_cm": [position_cm.x, position_cm.y, position_cm.z],
		"yaw_millirad": yaw_millirad, "pitch_millirad": pitch_millirad, "tool_slot": tool_slot}
	var valid: Dictionary = _validate_view(view)
	if not valid.get("ok", false):
		return valid
	var payload: Dictionary = Codec.encode(CHECKPOINT_ID, CONTRACT_ID,
		session.get("grid"), session.get("interaction"), session.get("equipment"), session.get("mission"))
	payload["view"] = view
	return _save.write_record(checkpoint_path(), Codec.KIND, CHECKPOINT_ID, payload, _utc_now())


func read_preferences(model: RefCounted) -> Dictionary:
	if not _initialized:
		return _failure("NOT_READY", "offline identity is unavailable")
	var read: Dictionary = _save.read_record(profile_path())
	if str(read.get("code", "")) == "NOT_FOUND":
		return {"ok": true, "available": false}
	if not read.get("ok", false):
		return read
	var checked: Dictionary = _validate_envelope(read, PROFILE_KIND, ACCOUNT_ID, false)
	if not checked.get("ok", false):
		return checked
	var payload: Dictionary = read["payload"]
	if not (payload.get("accessibility") is Dictionary and model.call("restore_snapshot", payload["accessibility"])):
		return _failure("BAD_PROFILE", "accessibility settings are invalid; the saved file was preserved")
	return {"ok": true, "available": true, "issues": read.get("issues", []), "source": read["source"]}


func write_preferences(model: RefCounted) -> Dictionary:
	if not _initialized:
		return _failure("NOT_READY", "offline identity is unavailable")
	var current: Dictionary = _save.read_record(profile_path())
	if current.get("ok", false):
		var checked: Dictionary = _validate_envelope(current, PROFILE_KIND, ACCOUNT_ID, false)
		if not checked.get("ok", false):
			return checked
	elif current.get("code", "") != "NOT_FOUND":
		return current
	return _save.write_record(profile_path(), PROFILE_KIND, ACCOUNT_ID,
		{"accessibility": model.call("snapshot")}, _utc_now())


func _validate_envelope(read: Dictionary, kind: String, record_id: String, check_revision: bool) -> Dictionary:
	var env: Dictionary = read.get("envelope", {})
	if env.get("kind") != kind or env.get("record_id") != record_id:
		return _failure("BAD_RECORD", "saved record has an unexpected identity or type")
	if not check_revision or env.get("content_revision") == _revision:
		return {"ok": true}
	# ADR-018: only presentation-only files changed. Old saves carry no rules_revision and stay on the strict rule;
	# an empty local rules revision (broken save_compat.json) never matches anything.
	var saved_rules: Variant = env.get(SaveService.RULES_REVISION_FIELD)
	if _rules_revision != "" and saved_rules is String and saved_rules == _rules_revision:
		return {"ok": true, "presentation_changed": true}
	return _failure("CONTENT_MISMATCH", "mission content changed; existing progress is preserved")


static func _validate_view(view: Variant) -> Dictionary:
	if not view is Dictionary:
		return _failure("BAD_VIEW", "missing player view in checkpoint")
	var d: Dictionary = view
	var pos: Variant = d.get("position_cm")
	if not (pos is Array and (pos as Array).size() == 3):
		return _failure("BAD_VIEW", "checkpoint position is missing or malformed")
	var n: Array[int] = []
	for i: int in 3:
		if typeof(pos[i]) != TYPE_INT:
			return _failure("BAD_VIEW", "checkpoint position must use integer centimeters")
		n.append(int(pos[i]))
	# Bounds are intentionally conservative; players outside them use van recovery,
	# not an unbounded world position from a disk file.
	if n[0] < 0 or n[0] > 11000 or n[1] < -350 or n[1] > 400 or n[2] < 0 or n[2] > 7000:
		return _failure("BAD_VIEW", "checkpoint position is outside Alder Street")
	for k: String in ["yaw_millirad", "pitch_millirad", "tool_slot"]:
		if typeof(d.get(k)) != TYPE_INT:
			return _failure("BAD_VIEW", "checkpoint view field %s is not an integer" % k)
	if absi(int(d["yaw_millirad"])) > 6284 or absi(int(d["pitch_millirad"])) > 1600 or \
			int(d["tool_slot"]) < 1 or int(d["tool_slot"]) > 5:
		return _failure("BAD_VIEW", "checkpoint view fields are out of bounds")
	return {"ok": true, "view": d.duplicate(true)}


static func _utc_now() -> String:
	return Time.get_datetime_string_from_system(true, false) + "Z"


static func _failure(code: String, message: String) -> Dictionary:
	return {"ok": false, "code": code, "message": message}
