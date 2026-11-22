extends RefCounted
## EXP016 A10: per-account/per-region source-graph consequence continuity.
## Deliberately PROCESS-LOCAL. It is not a production save or EXP015 ledger.
## All writes must originate from authenticated host outcome after case solved.

const PATH: String = "res://scenes/expeditions/exp016_cascades_a10.json"
const QUALIFICATION: String = "SOURCE_HEADLESS_ONLY_HUMAN_CONTROLLER_RELEASE_HELD"
static var _ledger: Dictionary = {}

var _source: Dictionary = {}
var _account: String = ""
var _site_id: String = ""
var _inherited: int = 0

static func load_book() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if not parsed is Dictionary or parsed.get("authority") != "EXP016_A10_PROCESS_LOCAL_SOURCE_CASCADE" or \
			parsed.get("qualification") != QUALIFICATION or \
			not parsed.get("regions") is Array or parsed["regions"].size() != 25:
		return {}
	return parsed

static func inspect(atlas: Dictionary, network_book: Dictionary,
		book: Dictionary) -> Dictionary:
	if book.get("authority") != "EXP016_A10_PROCESS_LOCAL_SOURCE_CASCADE" or \
			not book.get("regions") is Array or book["regions"].size() != 25:
		return {"ok": false, "code": "EXP016_A10_BOOK_INVALID"}
	for i: int in range(25):
		var original: Dictionary = network_book["regions"][i]
		var source: Dictionary = book["regions"][i]
		var upstream: Dictionary = {}
		var ids: Array = []
		for site: Dictionary in original["source_sites"]:
			ids.append(site["site_id"])
			upstream[str(site["site_id"])] = []
		var edges: Array = []
		for edge: Dictionary in original["primary_feeders"]:
			upstream[str(edge["to"])].append(edge["from"])
			edges.append({"id":edge["edge_id"], "from":edge["from"],
				"to":edge["to"],"capacity_pu":edge["capacity_pu"]})
		if ids.size() != 8 or source.get("region_id") != original["region_id"] or \
				source.get("site_ids") != ids or \
				source.get("root_source_id") != original["root_source_id"] or \
				source.get("finale_site_id") != ids[7] or \
				source.get("primary_feeder_edges") != edges or \
				source.get("source_predecessors") != upstream or \
				source.get("initial_reserve_pu") != original["initial_reserve_pu"]:
			return {"ok": false, "code": "EXP016_A10_SOURCE_GRAPH_DRIFT",
				"region":original["region_id"]}
		for site_id: String in ids:
			if not atlas["levels"].any(func(level: Dictionary) -> bool:
					return level["id"] == site_id):
				return {"ok": false, "code": "EXP016_A10_FOREIGN_SITE"}
	return {"ok": true, "regions":25, "sites":200, "qualification":QUALIFICATION}

static func entry_for(book: Dictionary, level_id: String) -> Dictionary:
	for record: Dictionary in book.get("regions", []):
		if record.get("site_ids", []).has(level_id):
			return record.duplicate(true)
	return {}

static func reset_for_test() -> void:
	_ledger.clear()

func _key() -> String:
	return _account + "|" + str(_source.get("region_id", ""))

func _events() -> Dictionary:
	return _ledger.get(_key(), {})

func _pressure_from(site_id: String, events: Dictionary,
		visited: Dictionary) -> int:
	if visited.has(site_id):
		return 0
	visited[site_id] = true
	var result: int = 0
	for parent: String in _source["source_predecessors"].get(site_id, []):
		var prior: Dictionary = events.get(parent, {})
		result = maxi(result, int(prior.get("outgoing_pressure", 0)))
		result = maxi(result, _pressure_from(parent, events, visited))
	return result

func configure(source: Dictionary, account: String, level_id: String) -> Dictionary:
	if _source.size() > 0 or account.strip_edges().is_empty() or \
			not source.get("site_ids", []).has(level_id) or \
			not level_id.begins_with("LV_"):
		return {"ok": false, "code": "EXP016_A10_INVALID_HOST_SCOPE"}
	_source = source.duplicate(true)
	_account = account
	_site_id = level_id
	_inherited = _pressure_from(level_id, _events(), {})
	return {"ok": true, "inherited_pressure": _inherited, "account_scoped": true}

func record_host_completion(case_state: Dictionary) -> Dictionary:
	if _source.is_empty() or case_state.get("phase") != "solved" or \
			case_state.get("level_id") != _site_id:
		return {"ok": false, "code": "EXP016_A10_UNVERIFIED_HOST_COMPLETION"}
	var policy: String = str(case_state.get("service_policy", ""))
	if not ["priority", "resilience"].has(policy):
		return {"ok": false, "code": "EXP016_A10_POLICY_REQUIRED"}
	var fresh: Dictionary = {
		"site_id":_site_id, "policy":policy,
		"service_debt":int(case_state.get("service_debt", -1)),
		"faults":int(case_state.get("faults", -1)),
		"settled":bool(case_state.get("inherited_pressure_settled", false)),
		"inherited_pressure":_inherited,
	}
	if int(fresh["service_debt"]) < 0 or int(fresh["faults"]) < 0 or \
			(_inherited > 0 and not bool(fresh["settled"])):
		return {"ok": false, "code": "EXP016_A10_UNSETTLED_CASCADE"}
	fresh["outgoing_pressure"] = maxi(0,
		_inherited + int(fresh["service_debt"]) + int(fresh["faults"]) -
		(1 if _inherited > 0 else 0))
	var events: Dictionary = _events().duplicate(true)
	if events.has(_site_id):
		if events[_site_id] == fresh:
			return {"ok": true, "code":"IDEMPOTENT_HOST_RESULT", "pressure":fresh["outgoing_pressure"]}
		return {"ok": false, "code":"EXP016_A10_CONFLICTING_COMPLETION"}
	events[_site_id] = fresh
	_ledger[_key()] = events
	return {"ok": true, "code":"HOST_CASCADE_RECORDED", "pressure":fresh["outgoing_pressure"]}

func snapshot() -> Dictionary:
	return {"qualification":QUALIFICATION, "region_id":_source.get("region_id",""),
		"site_id":_site_id, "inherited_pressure":_inherited,
		"events":_events().duplicate(true), "durable":false}
