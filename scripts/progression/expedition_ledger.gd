extends RefCounted
## EXP04: additive, bounded personal expedition field-score ledger.
##
## This record is deliberately separate from V08's profile.json and receipts.json:
## no C01-C12 credits, stars, campaign unlocks or checkpoint can be modified.
## Only a host-created receipt for an actual EXP03 task transition or for a
## host-range-checked lore pickup may enter the inbox. Receipts are idempotent
## across sessions and crashes; the SaveService checksum is NOT anti-cheat.

const Atlas := preload("res://scripts/world/dispatch_atlas.gd")
const SaveService := preload("res://scripts/persistence/save_service.gd")
const PowerGrid := preload("res://scripts/simulation/power_grid.gd")

const SCHEMA: int = 1
const PROFILE_FILE: String = "expeditions.json"
const INBOX_FILE: String = "expedition_receipts.json"
const KIND_PROFILE: String = "expedition_profile"
const KIND_INBOX: String = "expedition_receipts"
const MAX_LEVELS: int = 200
const MAX_TASKS: int = 1000
const MAX_FINDS: int = 200
const MAX_FIELD_POINTS: int = 57000  # 200 * (40 + 55 + 70 + 35 + 85)
const TASK_POINTS: Dictionary = {
	"investigation": 40,
	"power_routing": 55,
	"field_repair": 70,
	"optional_discovery": 35,
	"restoration": 85
}


static func _fail(code: String) -> Dictionary:
	return {"ok": false, "code": code}


static func new_profile(account_key: String) -> Dictionary:
	return {"expedition_schema": SCHEMA, "account_key": account_key,
		"field_points": 0, "earned_tasks": {}, "lore_finds": {},
		"completed_levels": {}, "applied_receipts": {}}


## The host owns the caller and the event; catalog preview points are ignored.
## A particular source task/find pays only once over a profile's lifetime.
static func make_receipt(account_key: String, level_id: String,
		entity_id: String, kind: String) -> Dictionary:
	var category: String = "lore" if kind == "lore" else "task"
	var points: int = 0 if category == "lore" else int(TASK_POINTS.get(kind, -1))
	var key: String = ("%s|%s|%s|%s" % [
		"EXP04_V1", account_key, category, entity_id]).sha256_text()
	return {"receipt_key": key, "account_key": account_key,
		"level_id": level_id, "entity_id": entity_id,
		"category": category, "kind": kind, "points": points}


## Refuse forged IDs, mismatched category/level, rewritten amounts, foreign
## accounts, and stale receipts. No client-supplied score is accepted.
static func _validate_receipt(account: String, receipt: Dictionary,
		atlas: Dictionary) -> Dictionary:
	if not SaveService.is_valid_key(account) or receipt.get("account_key") != account:
		return _fail("WRONG_ACCOUNT")
	var id: String = str(receipt.get("entity_id", ""))
	var level_id: String = str(receipt.get("level_id", ""))
	var category: String = str(receipt.get("category", ""))
	var kind: String = str(receipt.get("kind", ""))
	var level: Dictionary = Atlas.find_level(atlas, level_id)
	if level.is_empty():
		return _fail("UNKNOWN_LEVEL")
	var expected: int = -1
	if category == "task":
		for task: Dictionary in level["tasks"]:
			if task["id"] == id and task["kind"] == kind:
				expected = int(TASK_POINTS.get(kind, -1))
				break
	elif category == "lore":
		var find: Dictionary = level["collectible"]
		if find["id"] == id and kind == "lore" and 				find["effect"] == "LORE_ONLY_NO_POWER_OR_CREDITS":
			expected = 0
	if expected < 0 or PowerGrid.to_int(receipt.get("points")) != expected:
		return _fail("BAD_REWARD")
	var key: String = ("%s|%s|%s|%s" % [
		"EXP04_V1", account, category, id]).sha256_text()
	if receipt.get("receipt_key") != key:
		return _fail("BAD_RECEIPT_KEY")
	return {"ok": true, "receipt_key": key, "points": expected}


static func apply_receipt(profile: Dictionary, receipt: Dictionary,
		atlas: Dictionary) -> Dictionary:
	if profile.get("expedition_schema") != SCHEMA or 			profile.get("account_key") != receipt.get("account_key"):
		return _fail("BAD_PROFILE")
	var validation: Dictionary = _validate_receipt(str(profile["account_key"]),
		receipt, atlas)
	if not validation["ok"]:
		return validation
	var key: String = str(validation["receipt_key"])
	var applied: Dictionary = profile.get("applied_receipts", {})
	if applied.has(key):
		return {"ok": true, "applied": false}
	var tasks: Dictionary = profile.get("earned_tasks", {})
	var finds: Dictionary = profile.get("lore_finds", {})
	var completed: Dictionary = profile.get("completed_levels", {})
	var points: Variant = PowerGrid.to_int(profile.get("field_points"))
	if points == null or int(points) < 0 or int(points) > MAX_FIELD_POINTS or 			tasks.size() > MAX_TASKS or finds.size() > MAX_FINDS:
		return _fail("BAD_PROFILE")
	var incoming: int = int(validation["points"])
	if int(points) + incoming > MAX_FIELD_POINTS:
		return _fail("FIELD_POINTS_CAP")
	var id: String = str(receipt["entity_id"])
	if receipt["category"] == "task":
		if tasks.size() >= MAX_TASKS or tasks.has(id):
			return _fail("TASK_CAP_OR_DUPLICATE")
	else:
		if finds.size() >= MAX_FINDS or finds.has(id):
			return _fail("FIND_CAP_OR_DUPLICATE")
	# Every mutation below is part of the same atomic profile payload write.
	if receipt["category"] == "task":
		tasks[id] = true
		if receipt["kind"] == "restoration":
			completed[str(receipt["level_id"])] = true
	else:
		finds[id] = true
	profile["field_points"] = int(points) + incoming
	applied[key] = true
	profile["applied_receipts"] = applied
	profile["earned_tasks"] = tasks
	profile["lore_finds"] = finds
	profile["completed_levels"] = completed
	return {"ok": true, "applied": true}


static func _profile_dir(root: String, account: String) -> String:
	return root.path_join("profiles").path_join(account)


static func _checked_record(saves: SaveService, path: String,
		kind: String, account: String) -> Dictionary:
	var result: Dictionary = saves.read_record(path)
	if not bool(result.get("ok", false)):
		return result
	var envelope: Dictionary = result["envelope"]
	if envelope.get("kind") != kind or envelope.get("record_id") != account or 			not result.get("payload") is Dictionary:
		return _fail("FOREIGN_RECORD")
	return result


## A corrupt, wrong-kind, or newer record is never replaced with a blank one.
static func load_profile(saves: SaveService, account: String,
		root: String) -> Dictionary:
	if not SaveService.is_valid_key(account):
		return _fail("INVALID_ACCOUNT")
	var path: String = _profile_dir(root, account).path_join(PROFILE_FILE)
	var read: Dictionary = _checked_record(saves, path, KIND_PROFILE, account)
	if read.get("code") == "NOT_FOUND":
		return {"ok": true, "profile": new_profile(account), "existing": false}
	if not bool(read.get("ok", false)):
		return read
	var profile: Dictionary = read["payload"]
	if profile.get("expedition_schema") != SCHEMA or profile.get("account_key") != account or 			not profile.get("earned_tasks") is Dictionary or 			not profile.get("lore_finds") is Dictionary or 			not profile.get("completed_levels") is Dictionary or 			not profile.get("applied_receipts") is Dictionary:
		return _fail("BAD_PROFILE")
	var points: Variant = PowerGrid.to_int(profile.get("field_points"))
	if points == null or int(points) < 0 or int(points) > MAX_FIELD_POINTS or 			(profile["earned_tasks"] as Dictionary).size() > MAX_TASKS or 			(profile["lore_finds"] as Dictionary).size() > MAX_FINDS or 			(profile["completed_levels"] as Dictionary).size() > MAX_LEVELS:
		return _fail("BAD_PROFILE")
	return {"ok": true, "profile": profile, "existing": true}


## Durable recovery order: inbox first -> validated, deduped profile write ->
## acknowledgements. No inbox or profile is erased during a partial failure.
static func receive(saves: SaveService, account: String, root: String,
		receipts: Array, saved_at_utc: String) -> Dictionary:
	var loaded: Dictionary = load_profile(saves, account, root)
	if not bool(loaded.get("ok", false)):
		return loaded
	var atlas: Dictionary = Atlas.load_catalog()
	if not bool(Atlas.inspect(atlas).get("ok", false)):
		return _fail("SOURCE_ATLAS_INVALID")
	var dir: String = _profile_dir(root, account)
	var inbox_path: String = dir.path_join(INBOX_FILE)
	var old: Dictionary = _checked_record(saves, inbox_path, KIND_INBOX, account)
	var inbox: Dictionary = {}
	if bool(old.get("ok", false)):
		inbox = old["payload"].get("receipts", {})
		if not inbox is Dictionary:
			return _fail("BAD_INBOX")
	elif old.get("code") != "NOT_FOUND":
		return old
	for raw: Variant in receipts:
		if not raw is Dictionary:
			return _fail("BAD_RECEIPT")
		var r: Dictionary = raw
		var valid: Dictionary = _validate_receipt(account, r, atlas)
		if not bool(valid.get("ok", false)):
			return valid
		inbox[str(valid["receipt_key"])] = r.duplicate(true)
	if inbox.size() > MAX_TASKS + MAX_FINDS:
		return _fail("INBOX_CAP")
	if not receipts.is_empty():
		var saved: Dictionary = saves.write_record(inbox_path, KIND_INBOX, account,
			{"receipts": inbox}, saved_at_utc)
		if not saved.get("ok", false):
			return saved
	var profile: Dictionary = loaded["profile"]
	var acknowledgements: Array[String] = []
	var keys: Array = inbox.keys()
	keys.sort()
	for key: Variant in keys:
		var valid: Dictionary = _validate_receipt(account, inbox[key], atlas)
		if not valid.get("ok", false) or str(valid.get("receipt_key", "")) != str(key):
			return _fail("BAD_INBOX_RECEIPT")
		var applied: Dictionary = apply_receipt(profile, inbox[key], atlas)
		if not bool(applied.get("ok", false)):
			return applied
		acknowledgements.append(str(key))
	if not inbox.is_empty():
		var write: Dictionary = saves.write_record(dir.path_join(PROFILE_FILE),
			KIND_PROFILE, account, profile, saved_at_utc)
		if not bool(write.get("ok", false)):
			return write
	return {"ok": true, "profile": profile, "acks": acknowledgements}
