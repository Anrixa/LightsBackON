extends RefCounted
## EXP016 A06: host-only dual-source fault authority for all 200 authored cases.
## Diagnosis evidence is pinned to original fault and environmental hazard books.

const PATH: String = "res://scenes/expeditions/exp016_fault_layers_a06.json"
const QUALIFICATION: String = "SOURCE_HEADLESS_ONLY_HUMAN_CONTROLLER_RELEASE_HELD"
const AUTHORITY: String = "EXP016_A06_DUAL_SOURCE_FAULT_LAYERS"

static func load_book() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if not parsed is Dictionary or parsed.get("authority") != AUTHORITY or \
			parsed.get("qualification") != QUALIFICATION or \
			not parsed.get("entries") is Array or parsed["entries"].size() != 200:
		return {}
	return parsed

static func entry_for(book: Dictionary, level_id: String) -> Dictionary:
	if not level_id.begins_with("LV_"):
		return {}
	var serial: int = int(level_id.trim_prefix("LV_"))
	if serial < 1 or serial > 200 or level_id != "LV_%03d" % serial:
		return {}
	var entries: Variant = book.get("entries", [])
	if not entries is Array or entries.size() != 200:
		return {}
	var record: Dictionary = entries[serial - 1]
	return record.duplicate(true) if record.get("level_id") == level_id else {}

static func inspect(atlas: Dictionary, original_faults: Dictionary,
		encounters: Dictionary, book: Dictionary) -> Dictionary:
	if book.get("authority") != AUTHORITY or book.get("qualification") != QUALIFICATION or \
			not book.get("entries") is Array or book["entries"].size() != 200:
		return {"ok": false, "code": "EXP016_A06_BAD_SOURCE_BOOK"}
	for i: int in range(200):
		var level: Dictionary = atlas["levels"][i]
		var fault: Dictionary = original_faults["entries"][i]
		var encounter: Dictionary = encounters["entries"][i]
		var source: Dictionary = book["entries"][i]
		var pins: Dictionary = {
			"level_id": level["id"],
			"location_id": level["location_id"],
			"region_id": level["region_id"],
			"source_puzzle_identity": level["puzzle_identity"],
			"source_task_ids": level["tasks"].map(
				func(t: Dictionary) -> String: return str(t["id"])),
			"fault_scenario_key": fault["scenario_key"],
			"primary_fault_class": fault["fault_class"],
			"primary_signal": fault["signal_a"],
			"secondary_fault_class": "environmental_" + str(encounter["hazard"]["kind"]),
			"secondary_signal": str(encounter["hazard"]["kind"]) + "|" + str(encounter["hazard"]["blocks"]),
			"source_hazard_kind": encounter["hazard"]["kind"],
		}
		for key: String in pins:
			if source.get(key) != pins[key]:
				return {"ok": false, "code": "EXP016_A06_SOURCE_DRIFT", "level": level["id"], "field": key}
	return {"ok": true, "cases": 200, "qualification": QUALIFICATION}
