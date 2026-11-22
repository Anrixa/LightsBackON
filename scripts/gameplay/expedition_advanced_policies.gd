extends RefCounted
## EXP016 A09: source-validated service priority versus reserve resilience,
## with different accepted branch, incurred debt and required assurance.

const PATH: String = "res://scenes/expeditions/exp016_policies_a09.json"
const QUALIFICATION: String = "SOURCE_HEADLESS_ONLY_HUMAN_CONTROLLER_RELEASE_HELD"

static func load_book() -> Dictionary:
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if not value is Dictionary or value.get("authority") != "EXP016_A09_NONLINEAR_SOURCE_POLICIES" or \
			value.get("qualification") != QUALIFICATION or \
			not value.get("entries") is Array or value["entries"].size() != 200:
		return {}
	return value

static func entry_for(book: Dictionary, level_id: String) -> Dictionary:
	if not level_id.begins_with("LV_"):
		return {}
	var serial: int = int(level_id.trim_prefix("LV_"))
	var records: Array = book.get("entries", [])
	if serial < 1 or serial > 200 or level_id != "LV_%03d" % serial or records.size() != 200:
		return {}
	var entry: Dictionary = records[serial - 1]
	return entry.duplicate(true) if entry.get("level_id") == level_id else {}

static func inspect(atlas: Dictionary, contingency: Dictionary,
		book: Dictionary) -> Dictionary:
	if book.get("authority") != "EXP016_A09_NONLINEAR_SOURCE_POLICIES" or \
			not book.get("entries") is Array or book["entries"].size() != 200:
		return {"ok": false, "code": "EXP016_A09_BOOK_INVALID"}
	for i: int in range(200):
		var lv: Dictionary = atlas["levels"][i]
		var original: Dictionary = contingency["entries"][i]
		var e: Dictionary = book["entries"][i]
		var pins: Dictionary = {
			"level_id":lv["id"], "location_id":lv["location_id"],
			"region_id":lv["region_id"], "source_puzzle_identity":lv["puzzle_identity"],
			"source_task_ids":lv["tasks"].map(func(t: Dictionary) -> String: return str(t["id"])),
			"original_priority_actions":original["source_route_actions"]["priority"],
			"original_resilience_actions":original["source_route_actions"]["resilience"],
			"original_guard":original["risk_guard"]
		}
		for key: String in pins:
			if e.get(key) != pins[key]:
				return {"ok": false, "code": "EXP016_A09_SOURCE_DRIFT", "level":lv["id"]}
		var choices: Dictionary = e.get("options", {})
		if not choices.has("priority") or not choices.has("resilience") or \
				choices["priority"].get("route") != "forensic" or \
				choices["resilience"].get("route") != "field" or \
				not bool(choices["resilience"].get("assurance_check", false)) or \
				int(choices["priority"].get("service_debt", 0)) != 1 or \
				int(choices["resilience"].get("service_debt", -1)) != 0:
			return {"ok": false, "code": "EXP016_A09_MECHANICAL_POLICY_INVALID"}
	return {"ok": true, "cases":200, "routes":400, "qualification":QUALIFICATION}
