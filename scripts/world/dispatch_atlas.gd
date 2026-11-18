extends RefCounted
## EXP01: read-only, source-audited catalogue of future district dispatches.
## Existing SessionHost, mission authority, receipts and save identity are untouched.
## No entry in this atlas can authorize a world action or award credits.

const CATALOG_PATH: String = "res://scenes/expeditions/atlas.json"
const AUTHORITY: String = "DESIGN_PREVIEW_ONLY_NOT_GAMEPLAY"
const TASK_KINDS: Array[String] = [
	"investigation", "power_routing", "field_repair",
	"optional_discovery", "restoration"
]


static func load_catalog() -> Dictionary:
	if not FileAccess.file_exists(CATALOG_PATH):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CATALOG_PATH))
	return parsed if parsed is Dictionary else {}


## Check references, cardinalities, unique narratives, and the explicit preview
## ceiling. Content cannot become an accidental new gameplay authority.
static func inspect(data: Dictionary) -> Dictionary:
	var failures: Array[String] = []
	if int(data.get("schema_version", -1)) != 1 or str(data.get("authority", "")) != AUTHORITY:
		failures.append("BAD_SCHEMA_OR_AUTHORITY")
	if data.get("legacy_campaign_contracts_unchanged") != true:
		failures.append("LEGACY_CAMPAIGN_MUST_REMAIN_UNCHANGED")
	var raw_regions: Variant = data.get("regions")
	var raw_locations: Variant = data.get("locations")
	var raw_levels: Variant = data.get("levels")
	if not (raw_regions is Array and raw_locations is Array and raw_levels is Array):
		return {"ok": false, "failures": ["MISSING_COLLECTIONS"], "regions": 0,
			"locations": 0, "levels": 0, "tasks": 0, "collectibles": 0}
	var regions: Array = raw_regions
	var locations: Array = raw_locations
	var levels: Array = raw_levels
	if regions.size() != 25 or locations.size() != 200 or levels.size() != 200:
		failures.append("INCORRECT_CATALOG_SIZE")
	var region_ids: Dictionary = {}
	for row: Variant in regions:
		if not row is Dictionary:
			failures.append("INVALID_REGION_RECORD")
			continue
		var district: Dictionary = row
		var id: String = str(district.get("id", ""))
		if id.is_empty() or region_ids.has(id) or str(district.get("name", "")).is_empty():
			failures.append("INVALID_OR_DUPLICATE_REGION_" + id)
		region_ids[id] = true
	var location_ids: Dictionary = {}
	var location_names: Dictionary = {}
	var per_region: Dictionary = {}
	for row: Variant in locations:
		if not row is Dictionary:
			failures.append("INVALID_LOCATION_RECORD")
			continue
		var location: Dictionary = row
		var id: String = str(location.get("id", ""))
		var name: String = str(location.get("name", ""))
		var district: String = str(location.get("district_id", ""))
		if id.is_empty() or location_ids.has(id) or name.is_empty() or location_names.has(name):
			failures.append("INVALID_OR_DUPLICATE_LOCATION_" + id)
		if not region_ids.has(district) or str(location.get("production_status")) != "UNBUILT_LOCATION":
			failures.append("UNAUTHORIZED_LOCATION_" + id)
		location_ids[id] = true
		location_names[name] = true
		per_region[district] = int(per_region.get(district, 0)) + 1
	for id: String in region_ids:
		if int(per_region.get(id, 0)) != 8:
			failures.append("REGION_HAS_NOT_EIGHT_LOCATIONS_" + id)
	var level_ids: Dictionary = {}
	var used_locations: Dictionary = {}
	var task_ids: Dictionary = {}
	var task_descriptions: Dictionary = {}
	var collectible_ids: Dictionary = {}
	var puzzle_keys: Dictionary = {}
	var mechanic_types: Dictionary = {}
	var total_tasks: int = 0
	for row: Variant in levels:
		if not row is Dictionary:
			failures.append("INVALID_LEVEL_RECORD")
			continue
		var level: Dictionary = row
		var id: String = str(level.get("id", ""))
		var loc: String = str(level.get("location_id", ""))
		var region: String = str(level.get("region_id", ""))
		var puzzle: String = str(level.get("puzzle_identity", ""))
		if id.is_empty() or level_ids.has(id) or not location_ids.has(loc) or used_locations.has(loc):
			failures.append("INVALID_OR_DUPLICATE_LEVEL_" + id)
		if puzzle.is_empty() or puzzle_keys.has(puzzle):
			failures.append("DUPLICATE_PUZZLE_" + id)
		if not region_ids.has(region) or str(level.get("runtime_status")) != "DESIGN_BRIEFING_ONLY" \
				or str(level.get("scoring_authority")) != "PREVIEW_POINTS_ONLY":
			failures.append("UNAUTHORIZED_LEVEL_" + id)
		if str(level.get("mission_hook", "")).length() < 60:
			failures.append("MISSING_MISSION_STORY_" + id)
		level_ids[id] = true
		used_locations[loc] = true
		puzzle_keys[puzzle] = true
		var raw_tasks: Variant = level.get("tasks")
		if not (raw_tasks is Array) or (raw_tasks as Array).size() != 5:
			failures.append("LEVEL_NEEDS_FIVE_TASKS_" + id)
			continue
		var tasks: Array = raw_tasks
		var required_count: int = 0
		for ordinal: int in range(TASK_KINDS.size()):
			var raw_task: Variant = tasks[ordinal]
			if not raw_task is Dictionary:
				failures.append("INVALID_TASK_RECORD_" + id)
				continue
			var task: Dictionary = raw_task
			var task_id: String = str(task.get("id", ""))
			var briefing: String = str(task.get("briefing", ""))
			var mechanic: String = str(task.get("mechanic", ""))
			if task_id.is_empty() or task_ids.has(task_id) or task.get("ordinal") != ordinal + 1:
				failures.append("INVALID_OR_DUPLICATE_TASK_" + task_id)
			if task.get("kind") != TASK_KINDS[ordinal] or briefing.length() < 75 \
					or task_descriptions.has(briefing) or mechanic.is_empty():
				failures.append("MISSING_OR_DUPLICATE_TASK_CONTENT_" + task_id)
			if task.get("status") != "DESIGN_ONLY_NOT_HOST_ENABLED":
				failures.append("TASK_IMPERSONATES_HOST_" + task_id)
			var required: bool = task.get("required") == true
			if required != (ordinal != 3):
				failures.append("INVALID_REQUIRED_STAGE_" + task_id)
			if required:
				required_count += 1
			# Godot JSON.parse_string represents JSON numeric literals as float.
			# Accept only finite, nonnegative, exactly integral values, so 55.25
			# cannot silently become 55 or claim a valid planned score.
			var raw_points: Variant = task.get("field_points_preview")
			var valid_points: bool = raw_points is int or raw_points is float
			if valid_points:
				var value: float = float(raw_points)
				valid_points = not is_nan(value) and not is_inf(value) and value >= 0.0 \
					and value <= 200.0 and value == float(int(value))
			if not valid_points:
				failures.append("INVALID_PREVIEW_POINTS_" + task_id)
			task_ids[task_id] = true
			task_descriptions[briefing] = true
			mechanic_types[mechanic] = true
			total_tasks += 1
		if required_count != 4:
			failures.append("WRONG_REQUIRED_COUNT_" + id)
		var collectible: Variant = level.get("collectible")
		if not collectible is Dictionary:
			failures.append("MISSING_COLLECTIBLE_" + id)
			continue
		var find: Dictionary = collectible
		var find_id: String = str(find.get("id", ""))
		if find_id.is_empty() or collectible_ids.has(find_id) or \
				find.get("discovery_task_id") != str(tasks[3].get("id", "")) or \
				find.get("effect") != "LORE_ONLY_NO_POWER_OR_CREDITS" or \
				find.get("status") != "PLANNED_NOT_COLLECTIBLE":
			failures.append("INVALID_COLLECTIBLE_" + id)
		collectible_ids[find_id] = true
	if total_tasks != 1000 or collectible_ids.size() != 200 or mechanic_types.size() < 20:
		failures.append("CATALOG_DIVERSITY_OR_QUANTITY_FAILED")
	return {"ok": failures.is_empty(), "failures": failures,
		"regions": regions.size(), "locations": locations.size(),
		"levels": levels.size(), "tasks": total_tasks,
		"collectibles": collectible_ids.size(), "mechanics": mechanic_types.size(),
		"puzzle_signatures": puzzle_keys.size()}


static func find_level(data: Dictionary, level_id: String) -> Dictionary:
	for row: Dictionary in data.get("levels", []):
		if row.get("id") == level_id:
			return row
	return {}


static func find_location(data: Dictionary, location_id: String) -> Dictionary:
	for row: Dictionary in data.get("locations", []):
		if row.get("id") == location_id:
			return row
	return {}


## Read-only filtering for the dispatch board; no unlock logic or save writes.
static func search_levels(data: Dictionary, region_id: String = "",
		needle: String = "") -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	var query: String = needle.strip_edges().to_lower()
	for row: Dictionary in data.get("levels", []):
		if region_id != "" and str(row.get("region_id", "")) != region_id:
			continue
		var location: Dictionary = find_location(data, str(row.get("location_id", "")))
		var corpus: String = "%s %s %s" % [
			str(row.get("title", "")), str(row.get("mission_hook", "")),
			str(location.get("name", ""))]
		if query != "" and not corpus.to_lower().contains(query):
			continue
		results.append(row)
	return results


## Planning total only. Credits and stars come from RewardService and a
## verified SessionHost result, never from this content or this method.
static func preview_points(level: Dictionary) -> int:
	var total: int = 0
	for task: Dictionary in level.get("tasks", []):
		total += int(task.get("field_points_preview", 0))
	return total
