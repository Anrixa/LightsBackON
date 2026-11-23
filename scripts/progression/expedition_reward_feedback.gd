extends RefCounted
## EXP020 A03. Never awards points: verifies and presents only a successful
## existing EXP04 Ledger.receive commit and original host-issued receipts.
## Lore collectibles are source-backed non-currency finds (0 points).
const Ledger := preload("res://scripts/progression/expedition_ledger.gd")
const Atlas := preload("res://scripts/world/dispatch_atlas.gd")
const SaveService := preload("res://scripts/persistence/save_service.gd")
const PowerGrid := preload("res://scripts/simulation/power_grid.gd")

const AUTHORITY: String = "EXP020_A03_COMMITTED_LEDGER_DISPLAY_ONLY"


static func _fail(code: String) -> Dictionary:
	return {"ok": false, "code": code}


static func _valid_profile(profile: Dictionary, account: String) -> bool:
	# JSON loading may represent an integral score as float. Mirror the
	# existing EXP04 ledger's strict integral parser, never TYPE_INT alone.
	var verified_points: Variant = PowerGrid.to_int(profile.get("field_points"))
	return verified_points != null and SaveService.is_valid_key(account) and 		profile.get("expedition_schema") == Ledger.SCHEMA and 		profile.get("account_key") == account and 		profile.get("earned_tasks") is Dictionary and 		profile.get("lore_finds") is Dictionary and 		profile.get("completed_levels") is Dictionary and 		profile.get("applied_receipts") is Dictionary and 		(profile["earned_tasks"] as Dictionary).size() <= Ledger.MAX_TASKS and 		(profile["lore_finds"] as Dictionary).size() <= Ledger.MAX_FINDS and 		(profile["completed_levels"] as Dictionary).size() <= Ledger.MAX_LEVELS and 		int(verified_points) == verified_points and 		int(profile["field_points"]) >= 0 and 		int(profile["field_points"]) <= Ledger.MAX_FIELD_POINTS


## Before/after are committed local profile snapshots. This function has no
## write handle; a fabricated receipt cannot trigger any reward or HUD credit.
## For inbox crash recovery, total score delta may additionally include older
## committed receipts not listed among this dispatch's pending host queue.
static func after_commit(before: Dictionary, after: Dictionary,
		host_pending: Array, atlas: Dictionary, account: String) -> Dictionary:
	if not _valid_profile(before, account) or not _valid_profile(after, account):
		return _fail("INVALID_EXP04_PROFILE")
	if not bool(Atlas.inspect(atlas).get("ok", false)):
		return _fail("SOURCE_ATLAS_INVALID")
	var old_keys: Dictionary = before["applied_receipts"]
	var new_keys: Dictionary = after["applied_receipts"]
	if new_keys.size() < old_keys.size() or 			int(after["field_points"]) < int(before["field_points"]):
		return _fail("LEDGER_ROLLBACK_HOLD")
	for old_key: String in old_keys:
		if not new_keys.has(old_key):
			return _fail("LEDGER_RECEIPT_REMOVED")
	var gained: int = 0
	var granted: Array[Dictionary] = []
	var finds: Array[String] = []
	var seen: Dictionary = {}
	for raw: Variant in host_pending:
		if not raw is Dictionary:
			return _fail("BAD_HOST_RECEIPT")
		var receipt: Dictionary = raw
		var check: Dictionary = Ledger._validate_receipt(account, receipt, atlas)
		if not bool(check.get("ok", false)):
			return _fail("UNTRUSTED_HOST_RECEIPT")
		var key: String = str(check["receipt_key"])
		if seen.has(key):
			continue
		seen[key] = true
		if not new_keys.has(key):
			return _fail("RECEIPT_NOT_COMMITTED")
		if old_keys.has(key):
			continue
		if receipt["category"] == "task":
			if not (after["earned_tasks"] as Dictionary).has(str(receipt["entity_id"])):
				return _fail("COMMITTED_TASK_MISSING")
			gained += int(check["points"])
			granted.append({"task_id": str(receipt["entity_id"]),
				"kind": str(receipt["kind"]), "points": int(check["points"])})
		else:
			if not (after["lore_finds"] as Dictionary).has(str(receipt["entity_id"])):
				return _fail("COMMITTED_FIND_MISSING")
			finds.append(str(receipt["entity_id"]))
	if gained > int(after["field_points"]) - int(before["field_points"]):
		return _fail("UNBACKED_SCORE_CHANGE")
	return {"ok": true, "authority": AUTHORITY,
		"new_host_receipts": granted.size() + finds.size(),
		"new_task_points": gained, "tasks": granted, "lore_finds": finds,
		"total_field_points": int(after["field_points"]),
		"total_tasks": (after["earned_tasks"] as Dictionary).size(),
		"total_collectibles": (after["lore_finds"] as Dictionary).size(),
		"replay_did_not_double_pay": true}


static func summary(profile: Dictionary, account: String,
		last_commit: Dictionary = {}) -> Dictionary:
	if not _valid_profile(profile, account):
		return _fail("INVALID_EXP04_PROFILE")
	var lines: Array[String] = [
		"FIELD SCORE: %d/%d verified ledger entries" % [
			int(profile["field_points"]), Ledger.MAX_FIELD_POINTS],
		"TASK RECEIPTS: %d/%d" % [
			(profile["earned_tasks"] as Dictionary).size(), Ledger.MAX_TASKS],
		"RECOVERED FIELD COLLECTIBLES: %d/%d (lore, no power or credits)" % [
			(profile["lore_finds"] as Dictionary).size(), Ledger.MAX_FINDS],
		"All awards are accounted for by the existing account-specific EXP04 receipt keys."
	]
	if bool(last_commit.get("ok", false)) and 			int(last_commit.get("new_host_receipts", 0)) > 0:
		lines.append("LAST HOST COMMIT: +%d points from %d new verified receipts" % [
			int(last_commit["new_task_points"]), int(last_commit["new_host_receipts"])])
		for find_id: String in last_commit.get("lore_finds", []):
			lines.append("LORE CACHE FOUND: " + find_id + " (0 credits, original collectible)")
	return {"ok": true, "lines": lines,
		"field_points": int(profile["field_points"]),
		"collectibles": (profile["lore_finds"] as Dictionary).size()}
