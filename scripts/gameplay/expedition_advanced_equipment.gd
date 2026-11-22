extends RefCounted
## EXP016 A08 source-validated worksite tool allocation.
## No player can declare equipment ownership: SessionHost admitted tools only.

const PATH: String = "res://scenes/expeditions/exp016_equipment_a08.json"
const QUALIFICATION: String = "SOURCE_HEADLESS_ONLY_HUMAN_CONTROLLER_RELEASE_HELD"
const TOOLS: Array[String] = ["meter", "screwdriver", "puller", "cutter", "crimper"]
const REQUIRED_TOOLS: Dictionary = {
	"trace": "meter", "isolate": "screwdriver", "crosscheck": "meter",
	"tag": "puller", "compare": "meter", "meter": "meter",
	"repair": "crimper", "reconcile": "cutter", "attest": "meter",
	"stabilize": "screwdriver"
}

static func load_book() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if not parsed is Dictionary or parsed.get("authority") != "EXP016_A08_AUTHENTICATED_EQUIPMENT_ALLOCATION" or \
			parsed.get("qualification") != QUALIFICATION or \
			not parsed.get("entries") is Array or parsed["entries"].size() != 200:
		return {}
	return parsed

static func entry_for(book: Dictionary, level_id: String) -> Dictionary:
	if not level_id.begins_with("LV_"):
		return {}
	var serial: int = int(level_id.trim_prefix("LV_"))
	var entries: Array = book.get("entries", [])
	if serial < 1 or serial > 200 or level_id != "LV_%03d" % serial or entries.size() != 200:
		return {}
	var e: Dictionary = entries[serial - 1]
	return e.duplicate(true) if e.get("level_id") == level_id else {}

static func inspect(atlas: Dictionary, worksite_book: Dictionary,
		book: Dictionary) -> Dictionary:
	if book.get("authority") != "EXP016_A08_AUTHENTICATED_EQUIPMENT_ALLOCATION" or \
			not book.get("entries") is Array or book["entries"].size() != 200:
		return {"ok": false, "code": "EXP016_A08_BAD_SOURCE_BOOK"}
	for i: int in range(200):
		var level: Dictionary = atlas["levels"][i]
		var worksite: Dictionary = worksite_book["entries"][i]
		var e: Dictionary = book["entries"][i]
		var pins: Dictionary = {
			"level_id": level["id"], "location_id": level["location_id"],
			"region_id": level["region_id"], "source_puzzle_identity": level["puzzle_identity"],
			"source_task_ids": level["tasks"].map(func(t: Dictionary) -> String: return str(t["id"])),
			"source_worksite_encounter_key": worksite["encounter_key"],
			"reserve_cells": worksite["cell_budget"],
			"authorized_tools": TOOLS,
			"required_tools": REQUIRED_TOOLS,
			"charged_operations": ["repair"],
		}
		for key: String in pins:
			if e.get(key) != pins[key]:
				return {"ok": false, "code": "EXP016_A08_SOURCE_DRIFT", "level": level["id"], "field": key}
	return {"ok": true, "cases": 200, "qualification": QUALIFICATION}
