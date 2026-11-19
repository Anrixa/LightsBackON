extends RefCounted
## EXP05: 25 authored restoration corridors / 200 level-gated dispatches.
## Unlocks are derived solely from EXP04 host-restoration receipts already
## persisted in the separate expedition ledger. There is no extra currency,
## client "unlocked" flag, exclusive branch deletion, or C01-C12 save change.
## This is an automated source gate, NOT physical playability certification.

const Atlas := preload("res://scripts/world/dispatch_atlas.gd")
const Ledger := preload("res://scripts/progression/expedition_ledger.gd")
const SaveService := preload("res://scripts/persistence/save_service.gd")

const ROUTES_PATH: String = "res://scenes/expeditions/campaign_routes.json"
const AUTHORITY: String = "EXP05_HOST_RESTORATION_ONLY"
const BRANCH_POLICY: String = "OR_JOIN_NON_EXCLUSIVE_REPLAYABLE"
const ROLES: Array[String] = [
	"entry", "first_route_a", "first_route_b", "first_rejoin",
	"second_route_a", "second_route_b", "second_rejoin", "finale"
]
const REGIONS: int = 25
const LEVELS_PER_REGION: int = 8


static func _fail(code: String) -> Dictionary:
	return {"ok": false, "code": code}


static func _id(number: int) -> String:
	return "LV_%03d" % number


static func load_routes() -> Dictionary:
	if not FileAccess.file_exists(ROUTES_PATH):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(ROUTES_PATH))
	return parsed if parsed is Dictionary else {}


## Canonical dependency pattern, not mutable client progress. Each rejoin
## accepts EITHER incoming completed branch; both branches stay available.
static func _dependencies(number: int) -> Array[String]:
	var result: Array[String] = []
	var slot: int = (number - 1) % LEVELS_PER_REGION
	var base: int = number - 1 - slot
	match slot:
		0:
			if base > 0:
				result.append(_id(base))
		1, 2:
			result.append(_id(base + 1))
		3:
			result.append(_id(base + 2))
			result.append(_id(base + 3))
		4, 5:
			result.append(_id(base + 4))
		6:
			result.append(_id(base + 5))
			result.append(_id(base + 6))
		7:
			result.append(_id(base + 7))
	return result


## Refuse extra/missing nodes, swapped region IDs, cycles, skipped mandatory
## junctions, mutated prerequisite semantics and duplicate authored copy.
static func inspect(atlas: Dictionary, routes: Dictionary) -> Dictionary:
	if not bool(Atlas.inspect(atlas).get("ok", false)):
		return _fail("INVALID_ATLAS")
	if routes.get("schema_version") != 1 or routes.get("authority") != AUTHORITY \
			or routes.get("branch_policy") != BRANCH_POLICY \
			or routes.get("legacy_campaign_contracts_unchanged") != true:
		return _fail("BAD_CAMPAIGN_AUTHORITY")
	if not routes.get("nodes") is Array or not routes.get("chapters") is Array:
		return _fail("MISSING_ROUTES")
	var nodes: Array = routes["nodes"]
	var chapters: Array = routes["chapters"]
	if nodes.size() != REGIONS * LEVELS_PER_REGION or chapters.size() != REGIONS:
		return _fail("CAMPAIGN_CARDINALITY")
	var unique_labels: Dictionary = {}
	for region_index: int in range(REGIONS):
		var region: Dictionary = atlas["regions"][region_index]
		if not chapters[region_index] is Dictionary:
			return _fail("BAD_CHAPTER")
		var chapter: Dictionary = chapters[region_index]
		if chapter.get("region_id") != region.get("id"):
			return _fail("CHAPTER_REGION_MISMATCH")
		for field: String in ["chapter_title", "opening", "first_fork", "second_fork", "finale"]:
			if not chapter.get(field) is String or str(chapter[field]).length() < 24:
				return _fail("MISSING_CHAPTER_STORY")
	for index: int in range(nodes.size()):
		if not nodes[index] is Dictionary:
			return _fail("BAD_NODE")
		var node: Dictionary = nodes[index]
		var original: Dictionary = atlas["levels"][index]
		var number: int = index + 1
		if node.get("level_id") != _id(number) \
				or node.get("level_id") != original.get("id") \
				or node.get("region_id") != original.get("region_id") \
				or node.get("role") != ROLES[index % LEVELS_PER_REGION]:
			return _fail("NODE_SOURCE_MISMATCH")
		var label: String = str(node.get("route_label", ""))
		if label.length() < 12 or unique_labels.has(label) \
				or not node.get("narrative") is String \
				or str(node.get("narrative", "")).length() < 60:
			return _fail("DUPLICATE_OR_MISSING_ROUTE_STORY")
		unique_labels[label] = true
		if not node.get("requires_any") is Array:
			return _fail("BAD_PREREQUISITES")
		var listed: Array = node["requires_any"]
		var expected: Array[String] = _dependencies(number)
		if listed.size() != expected.size():
			return _fail("UNAUTHORIZED_ROUTE_GRAPH")
		for j: int in range(expected.size()):
			if listed[j] != expected[j]:
				return _fail("UNAUTHORIZED_ROUTE_GRAPH")
	return {"ok": true, "regions": REGIONS, "levels": nodes.size(),
		"branch_points": REGIONS * 2, "or_joins": REGIONS * 2}


## Structural consistency check: completed levels must contain the actual
## restoration task and its EXP04 receipt in the atomic expedition profile.
## SaveService's checksums detect accidental damage, not malicious save edits.
static func _completed_from_receipts(profile: Dictionary, atlas: Dictionary) -> Dictionary:
	if profile.get("expedition_schema") != Ledger.SCHEMA \
			or not SaveService.is_valid_key(str(profile.get("account_key", ""))) \
			or not profile.get("completed_levels") is Dictionary \
			or not profile.get("earned_tasks") is Dictionary \
			or not profile.get("applied_receipts") is Dictionary:
		return _fail("INVALID_EXPEDITION_PROFILE")
	var completed: Dictionary = profile["completed_levels"]
	var tasks: Dictionary = profile["earned_tasks"]
	var applied: Dictionary = profile["applied_receipts"]
	var verified: Dictionary = {}
	for level: Dictionary in atlas["levels"]:
		var level_id: String = str(level["id"])
		var restoration: Dictionary = level["tasks"][4]
		var receipt: Dictionary = Ledger.make_receipt(str(profile["account_key"]),
			level_id, str(restoration["id"]), "restoration")
		var fully_recorded: bool = tasks.has(str(restoration["id"])) \
			and applied.has(str(receipt["receipt_key"]))
		var marked: bool = completed.has(level_id)
		if marked != fully_recorded or (marked and completed[level_id] != true):
			return _fail("RESTORATION_RECEIPT_MISMATCH")
		if marked:
			verified[level_id] = true
	if verified.size() != completed.size():
		return _fail("FOREIGN_COMPLETED_LEVEL")
	return {"ok": true, "completed": verified}


## No caller-supplied progress claims are accepted. The profile must have
## independently passed the source/receipt structure checks above.
static func evaluate(profile: Dictionary, atlas: Dictionary,
		routes: Dictionary) -> Dictionary:
	var check: Dictionary = inspect(atlas, routes)
	if not bool(check.get("ok", false)):
		return check
	var recovered: Dictionary = _completed_from_receipts(profile, atlas)
	if not bool(recovered.get("ok", false)):
		return recovered
	var completed: Dictionary = recovered["completed"]
	var states: Dictionary = {}
	var available: int = 0
	var locked: int = 0
	var restored: int = 0
	var cleared_regions: int = 0
	for entry: Variant in routes["nodes"]:
		var node: Dictionary = entry
		var id: String = str(node["level_id"])
		var requirements: Array = node["requires_any"]
		var accessible: bool = requirements.is_empty()
		for previous: Variant in requirements:
			if completed.has(str(previous)):
				accessible = true
				break
		var status: String = "LOCKED"
		if completed.has(id):
			status = "RESTORED"
			restored += 1
		elif accessible:
			status = "AVAILABLE"
			available += 1
		else:
			locked += 1
		if node["role"] == "finale" and status == "RESTORED":
			cleared_regions += 1
		states[id] = {
			"status": status, "can_launch": status != "LOCKED",
			"requires_any": requirements.duplicate(true),
			"role": node["role"], "route_label": node["route_label"],
			"narrative": node["narrative"],
			"region_id": node["region_id"]
		}
	return {"ok": true, "states": states, "available": available,
		"locked": locked, "restored": restored,
		"cleared_regions": cleared_regions,
		"total_regions": REGIONS, "total_levels": REGIONS * LEVELS_PER_REGION}


static func can_launch(profile: Dictionary, atlas: Dictionary, routes: Dictionary,
		level_id: String) -> Dictionary:
	var board: Dictionary = evaluate(profile, atlas, routes)
	if not bool(board.get("ok", false)):
		return board
	var states: Dictionary = board["states"]
	if not states.has(level_id):
		return _fail("UNKNOWN_LEVEL")
	var state: Dictionary = states[level_id]
	if not bool(state["can_launch"]):
		return {"ok": false, "code": "CAMPAIGN_LEVEL_LOCKED",
			"requires_any": state["requires_any"]}
	return {"ok": true, "status": state["status"], "level_id": level_id}
