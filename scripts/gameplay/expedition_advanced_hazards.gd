extends RefCounted
## EXP016 A07: source-anchored hazards materially gate all advanced operations.
## These steps supplement, never bypass, original A07 containment.

const PATH: String = "res://scenes/expeditions/exp016_hazard_protocols_a07.json"
const QUALIFICATION: String = "SOURCE_HEADLESS_ONLY_HUMAN_CONTROLLER_RELEASE_HELD"
const STATIONS: Dictionary = {
	"repairs": ["A", "C", "B"],
	"switches": ["B", "A", "C"],
	"both": ["C", "B", "A"]
}

static func load_book() -> Dictionary:
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if not value is Dictionary or value.get("authority") != "EXP016_A07_ENVIRONMENTAL_OPERATION_ORDER" or \
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
	var record: Dictionary = records[serial - 1]
	return record.duplicate(true) if record.get("level_id") == level_id else {}

static func inspect(atlas: Dictionary, encounter_book: Dictionary,
		contingency_book: Dictionary, book: Dictionary) -> Dictionary:
	if book.get("authority") != "EXP016_A07_ENVIRONMENTAL_OPERATION_ORDER" or \
			not book.get("entries") is Array or book["entries"].size() != 200:
		return {"ok": false, "code": "EXP016_A07_BOOK_INVALID"}
	for i: int in range(200):
		var level: Dictionary = atlas["levels"][i]
		var encounter: Dictionary = encounter_book["entries"][i]
		var contingency: Dictionary = contingency_book["entries"][i]
		var entry: Dictionary = book["entries"][i]
		var blocked: String = str(encounter["hazard"]["blocks"])
		if not STATIONS.has(blocked):
			return {"ok": false, "code": "EXP016_A07_UNKNOWN_HAZARD"}
		var expected: Dictionary = {
			"level_id": level["id"],
			"location_id": level["location_id"],
			"region_id": level["region_id"],
			"source_puzzle_identity": level["puzzle_identity"],
			"source_hazard_kind": encounter["hazard"]["kind"],
			"source_blocked_operations": blocked,
			"source_risk_guard": contingency["risk_guard"],
			"source_task_ids": level["tasks"].map(
				func(t: Dictionary) -> String: return str(t["id"])),
			"survey_station": STATIONS[blocked][0],
			"isolate_station": STATIONS[blocked][1],
			"clear_station": STATIONS[blocked][2],
		}
		for key: String in expected:
			if entry.get(key) != expected[key]:
				return {"ok": false, "code": "EXP016_A07_SOURCE_DRIFT",
					"level": level["id"], "field": key}
	return {"ok": true, "cases": 200, "qualification": QUALIFICATION}
