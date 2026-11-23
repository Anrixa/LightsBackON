extends RefCounted
## EXP020 A04: durable source-authored narrative binding, no new game authority.
## Work orders are pinned to the original 25 regions, 200 locations, all
## original job IDs and the existing non-currency collectible. Only evidence
## already completed by the real host is presented as a discovered result.
const Atlas := preload("res://scripts/world/dispatch_atlas.gd")
const Campaign := preload("res://scripts/progression/expedition_campaign.gd")
const Networks := preload("res://scripts/gameplay/expedition_regional_network.gd")

const BOOK_PATH: String = "res://scenes/expeditions/exp020_workorders_a04.json"
const AUTHORITY: String = "EXP020_A04_CANONICAL_SITE_STORIES"
const QUALIFICATION: String = "SOURCE_HEADLESS_ONLY_RELEASE_HELD"


static func _fail(code: String) -> Dictionary:
	return {"ok": false, "code": code}


static func load_book() -> Dictionary:
	if not FileAccess.file_exists(BOOK_PATH):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(BOOK_PATH))
	return parsed if parsed is Dictionary else {}


static func entry_for(book: Dictionary, level_id: String) -> Dictionary:
	for record: Variant in book.get("work_orders", []):
		if record is Dictionary and record.get("level_id") == level_id:
			return (record as Dictionary).duplicate(true)
	return {}


static func inspect(atlas: Dictionary, route_book: Dictionary,
		network_book: Dictionary, source: Dictionary) -> Dictionary:
	if source.get("schema_version") != 1 or source.get("authority") != AUTHORITY or 			source.get("qualification") != QUALIFICATION or 			source.get("legacy_campaign_unchanged") != true or 			source.get("origin") != "ORIGINAL_ATLAS_REGIONAL_NETWORK_AND_EXP05_NARRATIVE" or 			not source.get("regions") is Array or 			not source.get("work_orders") is Array or 			(source["regions"] as Array).size() != 25 or 			(source["work_orders"] as Array).size() != 200:
		return _fail("STORY_SOURCE_AUTHORITY")
	if not bool(Campaign.inspect(atlas, route_book).get("ok",false)):
		return _fail("CAMPAIGN_SOURCE_UNQUALIFIED")
	if not network_book.get("regions") is Array or 			(network_book["regions"] as Array).size() != 25:
		return _fail("REGIONAL_SOURCE_UNQUALIFIED")
	for i: int in range(25):
		var actual: Dictionary = atlas["regions"][i]
		var chapter: Dictionary = route_book["chapters"][i]
		var expected: Dictionary = network_book["regions"][i]
		var row: Dictionary = source["regions"][i]
		var critical: Dictionary = expected["source_sites"].filter(
			func(x: Dictionary) -> bool: return x["site_id"] == expected["critical_service_site"])[0]
		var shelter: Dictionary = expected["source_sites"].filter(
			func(x: Dictionary) -> bool: return x["site_id"] == expected["shelter_service_site"])[0]
		var stakes: String = "%s carries the regional critical-service watch. %s is the shelter handoff; both require independently verified restoration." % [
			str(critical["location_name"]), str(shelter["location_name"])]
		if row.get("region_id") != actual["id"] or 				row.get("chapter_title") != chapter["chapter_title"] or 				row.get("opening") != chapter["opening"] or 				row.get("environment") != actual["setting"] or 				row.get("hazard") != actual["hazard"] or 				row.get("climate") != actual["climate"] or 				row.get("palette") != actual["palette"] or 				row.get("service_stakes") != stakes or 				row.get("first_fork") != chapter["first_fork"] or 				row.get("second_fork") != chapter["second_fork"] or 				row.get("finale") != chapter["finale"]:
			return _fail("REGIONAL_STORY_SOURCE_MISMATCH")
	for i: int in range(200):
		var site: Dictionary = source["work_orders"][i]
		var level: Dictionary = atlas["levels"][i]
		var loc: Dictionary = atlas["locations"][i]
		var region: Dictionary = network_book["regions"][int(i / 8.0)]
		var binding: Dictionary = region["source_sites"][i % 8]
		var route: Dictionary = route_book["nodes"][i]
		if site.get("level_id") != level["id"] or 				site.get("location_id") != loc["id"] or 				site.get("region_id") != level["region_id"] or 				site.get("location_name") != loc["name"] or 				site.get("worksite_family") != binding["worksite_family"] or 				site.get("work_order_title") != level["title"] or 				site.get("route_label") != route["route_label"] or 				site.get("public_dispatch") != route["narrative"] or 				site.get("mission_context") != level["mission_hook"] or 				site.get("environmental_clue") != loc["story_hook"] or 				site.get("site_hazard") != loc["risk"] or 				site.get("optional_find_id") != level["collectible"]["id"] or 				site.get("optional_find_name") != level["collectible"]["name"] or 				site.get("optional_find_set") != level["collectible"]["set"] or 				site.get("actual_system_source") != "EXP03_HOST_TASKS_AND_EXP014_SITE_PROOF":
			return _fail("WORK_ORDER_SOURCE_MISMATCH")
		var job_ids: Array = site.get("original_job_ids", [])
		if job_ids.size() != 5:
			return _fail("WORK_ORDER_TASK_COUNT")
		for j: int in range(5):
			if job_ids[j] != level["tasks"][j]["id"]:
				return _fail("WORK_ORDER_JOB_ID_MISMATCH")
	return {"ok": true, "regions": 25, "work_orders": 200,
		"source_task_ids": 1000, "collectible_ids": 200}


## Source-validated public work order plus genuinely discovered host evidence.
## Uncollected item name/set and later puzzle explanations stay hidden.
static func compose(book: Dictionary, atlas: Dictionary, level_id: String,
		host_board: Dictionary) -> Dictionary:
	var entry: Dictionary = entry_for(book, level_id)
	var level: Dictionary = Atlas.find_level(atlas, level_id)
	if entry.is_empty() or level.is_empty() or 			entry.get("work_order_title") != level.get("title") or 			entry.get("optional_find_id") != level["collectible"]["id"] or 			not host_board.get("tasks") is Array:
		return _fail("WORK_ORDER_CONTEXT_MISMATCH")
	var verified: Dictionary = {}
	for task: Dictionary in host_board["tasks"]:
		var task_id: String = str(task.get("id", ""))
		if not entry["original_job_ids"].has(task_id) or verified.has(task_id):
			return _fail("FOREIGN_OR_DUPLICATE_TASK")
		verified[task_id] = bool(task.get("completed", false))
	var lines: Array[String] = [
		str(entry["work_order_title"]),
		"Location / system: %s / %s" % [
			str(entry["location_name"]), str(entry["worksite_family"])],
		"Site evidence: " + str(entry["environmental_clue"]),
		"Environmental watch: " + str(entry["site_hazard"]),
		str(entry["mission_context"])
	]
	var confirmed: Array[String] = []
	for original: Dictionary in level["tasks"]:
		if bool(verified.get(str(original["id"]), false)):
			confirmed.append(str(original["title"]))
	if confirmed.is_empty():
		lines.append("Field findings: unconfirmed until the host validates a task.")
	else:
		lines.append("Host-confirmed field work: " + ", ".join(confirmed))
	var found: bool = bool(host_board.get("lore_collected", false))
	if found:
		lines.append("Recovered local archive: %s / %s (lore only, no currency)" % [
			str(entry["optional_find_name"]), str(entry["optional_find_set"])])
	else:
		lines.append("Local archive: optional and undiscovered; no collection clue revealed.")
	return {"ok": true, "location": entry["location_name"],
		"headline": entry["work_order_title"], "story_lines": lines,
		"found": found, "optional_id": entry["optional_find_id"],
		"verified_tasks": confirmed.size(), "source_linked": true}
