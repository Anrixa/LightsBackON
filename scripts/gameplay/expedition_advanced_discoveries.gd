extends RefCounted
## EXP016 A11: source-pinned optional lore proof, never a new reward currency.

const PATH: String = "res://scenes/expeditions/exp016_discoveries_a11.json"
const QUALIFICATION: String = "SOURCE_HEADLESS_ONLY_HUMAN_CONTROLLER_RELEASE_HELD"
const ACTIONS: Array[String] = [
	"case_discover_trace", "case_discover_crosscheck", "case_discover_authenticate"
]

static func load_book() -> Dictionary:
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if not value is Dictionary or value.get("authority") != "EXP016_A11_SOURCE_LORE_DISCOVERIES" or \
			value.get("qualification") != QUALIFICATION or \
			not value.get("entries") is Array or value["entries"].size() != 200:
		return {}
	return value

static func entry_for(book: Dictionary, level_id: String) -> Dictionary:
	if not level_id.begins_with("LV_"):
		return {}
	var serial: int = int(level_id.trim_prefix("LV_"))
	var entries: Array = book.get("entries", [])
	if serial < 1 or serial > 200 or level_id != "LV_%03d" % serial or entries.size() != 200:
		return {}
	var record: Dictionary = entries[serial - 1]
	return record.duplicate(true) if record.get("level_id") == level_id else {}

static func inspect(atlas: Dictionary, investigations: Dictionary,
		book: Dictionary) -> Dictionary:
	if book.get("authority") != "EXP016_A11_SOURCE_LORE_DISCOVERIES" or \
			not book.get("entries") is Array or book["entries"].size() != 200:
		return {"ok": false, "code": "EXP016_A11_BOOK_INVALID"}
	for i: int in range(200):
		var lv: Dictionary = atlas["levels"][i]
		var case_source: Dictionary = investigations["entries"][i]
		var source_find: Dictionary = lv["collectible"]
		var entry: Dictionary = book["entries"][i]
		var pins: Dictionary = {
			"level_id":lv["id"], "location_id":lv["location_id"],
			"region_id":lv["region_id"], "source_puzzle_identity":lv["puzzle_identity"],
			"source_task_id":lv["tasks"][3]["id"],
			"source_collectible_id":source_find["id"],
			"source_collectible_name":source_find["name"],
			"source_lore_set":source_find["set"],
			"source_effect":source_find["effect"],
			"source_stations":case_source["targets"]
		}
		for key: String in pins:
			if entry.get(key) != pins[key]:
				return {"ok": false, "code": "EXP016_A11_SOURCE_DRIFT", "level":lv["id"]}
		if entry.get("source_effect") != "LORE_ONLY_NO_POWER_OR_CREDITS" or \
				entry.get("research_chain", []).size() != 3:
			return {"ok": false, "code": "EXP016_A11_CURRENCY_OR_RESEARCH_VIOLATION"}
		for step: int in range(3):
			var procedure: Dictionary = entry["research_chain"][step]
			if procedure.get("action") != ACTIONS[step] or \
					procedure.get("station") != ["A","B","C"][step]:
				return {"ok": false, "code": "EXP016_A11_RESEARCH_STEP_DRIFT"}
	return {"ok": true, "lore_cases":200, "qualification":QUALIFICATION}
