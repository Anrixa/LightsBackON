extends RefCounted
## EXP015 A01 — optional host-owned regional emergency response.
## Source-pinned to original A09 primary feeder + normally-open standby tie.
## Invoked exclusively by the existing authenticated SessionHost worksite board.
## Incident evidence has NO EXP04 task receipt, production save, or custom RPC.
const Atlas := preload("res://scripts/world/dispatch_atlas.gd")
const Regional := preload("res://scripts/gameplay/expedition_regional_network.gd")

const BOOK_PATH: String = "res://scenes/expeditions/region_incidents_exp015_a01.json"
const AUTHORITY: String = "EXP015_A01_AUTHORED_EMERGENCY_RESPONSE_SOURCE"
const QUALIFICATION: String = "SOURCE_HEADLESS_ONLY_HUMAN_CONTROLLER_RELEASE_HELD"
const PROTOCOLS: Dictionary = {
	"depth": ["isolate_waterlogged_duct", 2],
	"conductivity": ["prove_arc_free_separation", 3],
	"mechanical": ["secure_mechanical_interlock", 1],
	"structure": ["shore_distressed_feeder", 2],
	"weather": ["weatherproof_exposed_joint", 3]
}
const ACTIONS: Array[String] = [
	"incident_survey", "incident_isolate", "incident_transfer",
	"incident_managed", "incident_prepare", "incident_recover",
	"incident_certify"
]

var _spec: Dictionary = {}
var _network: Regional
var _phase: String = "inactive"
var _mode: String = ""
var _unserved_pressure: int = 0
var _events: Array[Dictionary] = []


static func _fail(code: String) -> Dictionary:
	return {"ok": false, "code": code}


static func load_book() -> Dictionary:
	if not FileAccess.file_exists(BOOK_PATH):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(BOOK_PATH))
	return parsed if parsed is Dictionary else {}


static func entry_for(book: Dictionary, level_id: String) -> Dictionary:
	for raw: Variant in book.get("entries", []):
		if raw is Dictionary and raw.get("incident_site_id") == level_id:
			return (raw as Dictionary).duplicate(true)
	return {}


## Incident recipes cannot invent electrical assets or alter the original
## eight-site EXP05 route graph. Every named asset must come from A09 sources.
static func inspect(atlas: Dictionary, book: Dictionary,
		regional_book: Dictionary) -> Dictionary:
	if book.get("schema_version") != 1 or book.get("authority") != AUTHORITY or \
			book.get("qualification") != QUALIFICATION or \
			book.get("source_binding") != "EXP014_A09_FEEDER_AND_TIE" or \
			book.get("legacy_campaign_contracts_unchanged") != true or \
			not book.get("entries") is Array or \
			book["entries"].size() != 25 or regional_book.get("regions", []).size() != 25:
		return _fail("INCIDENT_BOOK_AUTHORITY")
	var distinct: Dictionary = {}
	for i: int in range(25):
		var region: Dictionary = regional_book["regions"][i]
		var entry: Dictionary = book["entries"][i]
		var site: String = str(region["source_sites"][3]["site_id"])
		if not bool(Regional.inspect_region(atlas, region).get("ok", false)) or \
				entry.get("region_id") != region.get("region_id") or \
				entry.get("incident_site_id") != site or distinct.has(site) or \
				entry.get("risk_class") != region.get("risk_class") or \
				entry.get("qualification") != QUALIFICATION or \
				not PROTOCOLS.has(str(entry.get("risk_class", ""))):
			return _fail("INCIDENT_SOURCE_MISMATCH")
		var protocol: Array = PROTOCOLS[str(entry["risk_class"])]
		if entry.get("preparation_protocol") != protocol[0] or \
				entry.get("managed_unserved_pressure_pu") != protocol[1]:
			return _fail("INCIDENT_RISK_PROTOCOL_MISMATCH")
		var tie: Dictionary = region["standby_ties"][0]
		if entry.get("standby_tie_id") != tie.get("edge_id") or \
				entry.get("standby_source_site") != tie.get("from") or \
				entry.get("affected_service_site") != tie.get("to"):
			return _fail("INCIDENT_STANDBY_SOURCE_MISMATCH")
		var incoming: Dictionary = {}
		for feeder: Dictionary in region["primary_feeders"]:
			if feeder["to"] == tie["to"]:
				incoming = feeder
				break
		if incoming.is_empty() or entry.get("normal_feeder_id") != incoming.get("edge_id"):
			return _fail("INCIDENT_FEEDER_SOURCE_MISMATCH")
		distinct[site] = true
	return {"ok": true, "incidents": distinct.size(), "risk_protocols": PROTOCOLS.size()}


func configure(recipe: Dictionary, network: Regional) -> Dictionary:
	if not _spec.is_empty() or network == null:
		return _fail("INCIDENT_ALREADY_CONFIGURED_OR_MISSING_NETWORK")
	var source: Dictionary = load_book()
	var gate: Dictionary = inspect(Atlas.load_catalog(), source, Regional.load_book())
	if not bool(gate.get("ok", false)):
		return gate
	var approved: Dictionary = entry_for(source, str(recipe.get("incident_site_id", "")))
	if approved.is_empty() or approved != recipe:
		return _fail("INCIDENT_UNPINNED_RECIPE")
	var state: Dictionary = network.snapshot()
	if state.is_empty() or state.get("region_id") != approved["region_id"] or \
			state.get("level_id") != approved["incident_site_id"] or \
			not state["feeders"].has(str(approved["normal_feeder_id"])) or \
			not state["ties"].has(str(approved["standby_tie_id"])):
		return _fail("INCIDENT_HOST_CONTEXT_MISMATCH")
	_spec = approved.duplicate(true)
	_network = network
	_phase = "survey_pending"
	return {"ok": true, "incident_site_id": _spec["incident_site_id"]}


func definition_snapshot() -> Dictionary:
	return _spec.duplicate(true)


func certified() -> bool:
	return _phase == "certified"


func snapshot() -> Dictionary:
	if _spec.is_empty():
		return {}
	return {"region_id": _spec["region_id"],
		"incident_site_id": _spec["incident_site_id"],
		"affected_service_site": _spec["affected_service_site"],
		"normal_feeder_id": _spec["normal_feeder_id"],
		"standby_tie_id": _spec["standby_tie_id"],
		"hazard_protocol": _spec["preparation_protocol"],
		"phase": _phase, "mode": _mode,
		"unserved_pressure_pu": _unserved_pressure,
		"certified": certified(),
		"events": _events.duplicate(true),
		"qualification": QUALIFICATION}


func _record(action: String) -> void:
	_events.append({"sequence": _events.size() + 1, "action": action,
		"phase": _phase, "mode": _mode})


## The existing worksite board authenticates player, sequence, range, rate and
## source entity before invoking this method. No payload-supplied target/clock.
func operate(action: String) -> Dictionary:
	if _spec.is_empty():
		return _fail("INCIDENT_NOT_CONFIGURED")
	if not ACTIONS.has(action):
		return _fail("UNKNOWN_INCIDENT_ACTION")
	var network_state: Dictionary = _network.snapshot()
	if network_state.get("level_id") != _spec["incident_site_id"] or \
			network_state.get("region_id") != _spec["region_id"]:
		return _fail("INCIDENT_DISPATCH_CONTEXT_CHANGED")
	var feeder_id: String = str(_spec["normal_feeder_id"])
	var tie_id: String = str(_spec["standby_tie_id"])
	var feeder: Dictionary = network_state["feeders"][feeder_id]
	var tie: Dictionary = network_state["ties"][tie_id]
	var answer: Dictionary = {}
	match action:
		"incident_survey":
			if _phase != "survey_pending" or str(network_state["strategy"]).is_empty():
				return _fail("INCIDENT_STRATEGY_AND_SURVEY_REQUIRED")
			_phase = "surveyed"
		"incident_isolate":
			if _phase != "surveyed":
				return _fail("INCIDENT_SURVEY_REQUIRED")
			answer = _network.host_transition("isolate_feeder", feeder_id)
			if not bool(answer.get("ok", false)):
				return answer
			_phase = "isolated"
		"incident_transfer":
			if _phase != "isolated":
				return _fail("INCIDENT_ISOLATION_REQUIRED")
			answer = _network.host_transition("engage_tie", tie_id)
			if not bool(answer.get("ok", false)):
				return answer
			_mode = "standby_transfer"
			_phase = "stabilized"
		"incident_managed":
			if _phase != "isolated":
				return _fail("INCIDENT_ISOLATION_REQUIRED")
			if bool(tie["engaged"]):
				return _fail("INCIDENT_BREAK_BEFORE_MAKE_REQUIRED")
			_mode = "managed_outage"
			_unserved_pressure = int(_spec["managed_unserved_pressure_pu"])
			_phase = "stabilized"
		"incident_prepare":
			if _phase != "stabilized" or _mode.is_empty():
				return _fail("INCIDENT_STABILIZATION_REQUIRED")
			if not _network.site_prepared():
				answer = _network.prepare_site("managed")
				if not bool(answer.get("ok", false)):
					return answer
			_phase = "prepared"
		"incident_recover":
			if _phase != "prepared" or not _network.site_prepared():
				return _fail("INCIDENT_PREPARATION_REQUIRED")
			if str(feeder["fault"]) != "":
				return _fail("INCIDENT_FEEDER_STILL_FAULTED")
			if _mode == "standby_transfer":
				if not bool(tie["engaged"]):
					return _fail("INCIDENT_TRANSFER_PROOF_MISSING")
				answer = _network.host_transition("release_tie", tie_id)
				if not bool(answer.get("ok", false)):
					return answer
			elif bool(tie["engaged"]):
				return _fail("INCIDENT_FOREIGN_TIE_ENGAGED")
			answer = _network.host_transition("reset_feeder", feeder_id)
			if not bool(answer.get("ok", false)):
				return answer
			_phase = "recovered"
		"incident_certify":
			if _phase != "recovered" or not _network.site_prepared() or \
					bool(feeder["isolated"]) or str(feeder["fault"]) != "" or \
					bool(tie["engaged"]):
				return _fail("INCIDENT_RECOVERY_EVIDENCE_REQUIRED")
			_phase = "certified"
	_record(action)
	return {"ok": true, "snapshot": snapshot()}
