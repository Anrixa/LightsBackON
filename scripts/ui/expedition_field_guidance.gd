extends RefCounted
## EXP020 A02: one read-only presentation model for dispatch, field HUD and
## the optional network tablet. Reuses verified source identity and host facts.
## Never emits a host intent or guesses an undiscovered puzzle step.

const Atlas := preload("res://scripts/world/dispatch_atlas.gd")

const AUTHORITY: String = "EXP020_A02_PRESENTATION_FROM_HOST_AND_RECEIPTS"
const MAX_LINE_LEN: int = 240


static func _fail(code: String) -> Dictionary:
	return {"ok": false, "code": code}


static func _line(text: String) -> String:
	return text.substr(0, MAX_LINE_LEN)


static func build(atlas: Dictionary, routes: Dictionary, level_id: String,
		host_board: Dictionary, campaign_consequences: Dictionary,
		regional_host: Dictionary = {}) -> Dictionary:
	var level: Dictionary = Atlas.find_level(atlas, level_id)
	if level.is_empty():
		return _fail("UNKNOWN_LEVEL")
	if not host_board.get("tasks") is Array or 			not bool(campaign_consequences.get("ok", false)):
		return _fail("MISSING_HOST_OR_CAMPAIGN_PROOF")
	var region_id: String = str(level["region_id"])
	var chapters: Dictionary = campaign_consequences.get("regions", {})
	if not chapters.has(region_id):
		return _fail("WRONG_CAMPAIGN_REGION")
	var chapter: Dictionary = chapters[region_id]
	if not chapter.get("sites") is Dictionary or 			not chapter["sites"].has(level_id):
		return _fail("CAMPAIGN_SITE_MISSING")
	var route: Dictionary = {}
	for candidate: Dictionary in routes.get("nodes", []):
		if str(candidate.get("level_id", "")) == level_id:
			route = candidate
			break
	if route.is_empty() or route.get("region_id") != region_id:
		return _fail("SOURCE_ROUTE_MISMATCH")
	var source_chapter: Dictionary = {}
	for item: Dictionary in routes.get("chapters", []):
		if str(item.get("region_id", "")) == region_id:
			source_chapter = item
			break
	if source_chapter.is_empty():
		return _fail("SOURCE_STORY_MISSING")
	var location: Dictionary = Atlas.find_location(atlas, str(level["location_id"]))
	if location.is_empty():
		return _fail("LOCATION_MISSING")
	var briefing: Array[String] = [
		_line(str(source_chapter.get("chapter_title", ""))),
		_line(str(route["route_label"])),
		_line(str(route["narrative"])),
		_line(str(level["mission_hook"]))
	]
	var objectives: Array[String] = []
	var seen: Dictionary = {}
	var completed_count: int = 0
	for entry: Variant in host_board["tasks"]:
		if not entry is Dictionary:
			return _fail("HOST_TASK_FORMAT")
		var task: Dictionary = entry
		var task_id: String = str(task.get("id", ""))
		if seen.has(task_id):
			return _fail("DUPLICATE_HOST_TASK")
		seen[task_id] = true
		var found: bool = false
		for original: Dictionary in level["tasks"]:
			if str(original["id"]) == task_id:
				found = true
				break
		if not found:
			return _fail("UNRECOGNIZED_HOST_TASK")
		var status: String = "COMPLETE" if bool(task.get("completed", false)) else 			"OPTIONAL" if not bool(task.get("required", true)) else "OPEN"
		if status == "COMPLETE":
			completed_count += 1
		objectives.append(_line("[%s] %s" % [status, str(task.get("title", task_id))]))
	# Map labels show RECEIPTED status only; no client-provided unlocks or
	# live network state unless it comes from this very host's task board.
	var network: Array[String] = []
	var source_sites: Dictionary = chapter["sites"]
	var keys: Array = source_sites.keys()
	keys.sort()
	var trusted_live: bool = regional_host.get("region_id") == region_id and 			regional_host.get("sites") is Dictionary
	for key: Variant in keys:
		var id: String = str(key)
		var site: Dictionary = source_sites[id]
		var live_suffix: String = "live grid not read"
		if trusted_live and (regional_host["sites"] as Dictionary).has(id):
			var actual: Dictionary = regional_host["sites"][id]
			live_suffix = "host: energized" if bool(actual.get("energized", false)) else 				"host: dark"
		var status_text: String = "%s • %s • %s" % [
			str(site["location_name"]), str(site["status"]), live_suffix]
		network.append(_line(status_text))
	var evidence: Array[String] = []
	if completed_count == 0:
		evidence.append("No host-verified task evidence yet. Inspect local equipment and compare measurements.")
	else:
		evidence.append("%d/%d task receipts eligible or host-verified in this dispatch." % [
			completed_count, (host_board["tasks"] as Array).size()])
	for task: Dictionary in host_board["tasks"]:
		if bool(task.get("completed", false)):
			evidence.append(_line("Verified: " + str(task.get("title", task["id"]))))
	# No fault class, probe order, solution DAG, hidden recovery procedure,
	# exact next action or kit spend is included in any output.
	var current: Dictionary = chapter["sites"][level_id]
	var navigation: String = "Use the field plaques, reach-and-sight reticle and host tablet inspect."
	if bool(current.get("restoration_receipt", false)):
		navigation = "This site's restoration is archived; revisit for optional investigation only."
	return {"ok": true, "authority": AUTHORITY, "level_id": level_id,
		"region_id": region_id, "location": str(location["name"]),
		"briefing": briefing, "objectives": objectives,
		"network": network, "evidence": evidence,
		"navigation": navigation, "completed_tasks": completed_count,
		"solutions_exposed": false, "readonly": true}
