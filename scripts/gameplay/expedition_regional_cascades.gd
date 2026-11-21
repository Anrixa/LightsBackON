extends RefCounted
## EXP015 A02: host-owned second-junction fault cascade and service triage.
## No client-generated fault proof; operations only through authenticated
## SessionHost operate_worksite at the existing source-bound board.
## No production saves, additional EXP04 rewards, or physical grid solver.

const Atlas := preload("res://scripts/world/dispatch_atlas.gd")
const Regional := preload("res://scripts/gameplay/expedition_regional_network.gd")

const BOOK_PATH: String = "res://scenes/expeditions/region_cascades_exp015_a02.json"
const AUTHORITY: String = "EXP015_A02_AUTHORED_HOST_CASCADE_SOURCE"
const QUALIFICATION: String = "SOURCE_HEADLESS_ONLY_HUMAN_CONTROLLER_RELEASE_HELD"
const SOURCE_BINDING: String = "EXP014_A09_NORMAL_FEEDER_SECOND_TIE"
const PROTOCOLS: Dictionary = {
	"depth": ["water_table_containment", 3],
	"conductivity": ["arc_discharge_quarantine", 5],
	"mechanical": ["moving_contact_lockout", 2],
	"structure": ["buckled_support_isolation", 4],
	"weather": ["storm_conductor_clearance", 3]
}
const ACTIONS: Array[String] = [
	"cascade_assess", "cascade_trip", "cascade_backfeed", "cascade_managed",
	"cascade_prepare", "cascade_clear", "cascade_reconnect", "cascade_attest"
]

var _recipe: Dictionary = {}
var _network: Regional
var _phase: String = "inactive"
var _mode: String = ""
var _service_pressure: int = 0
var _reserve_spent: int = 0
var _critical_supply_at_assessment: bool = false
var _events: Array[Dictionary] = []


static func _fail(code: String) -> Dictionary:
	return {"ok": false, "code": code}


static func load_book() -> Dictionary:
	if not FileAccess.file_exists(BOOK_PATH):
		return {}
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(BOOK_PATH))
	return raw if raw is Dictionary else {}


static func entry_for(book: Dictionary, site_id: String) -> Dictionary:
	for value: Variant in book.get("entries", []):
		if value is Dictionary and value.get("junction_site_id") == site_id:
			return (value as Dictionary).duplicate(true)
	return {}


## Refuse fabricated feeder/tie IDs, source fault recovery or protocol swaps.
## Source book is independently checked in CI by an alternate Python oracle.
static func inspect(atlas: Dictionary, book: Dictionary,
		regional_book: Dictionary) -> Dictionary:
	if book.get("authority") != AUTHORITY or book.get("schema_version") != 1 \
			or book.get("qualification") != QUALIFICATION \
			or book.get("source_binding") != SOURCE_BINDING \
			or book.get("legacy_campaign_contracts_unchanged") != true \
			or not book.get("entries") is Array or book["entries"].size() != 25 \
			or not regional_book.get("regions") is Array \
			or regional_book["regions"].size() != 25:
		return _fail("CASCADE_BOOK_AUTHORITY")
	var seen: Dictionary = {}
	for index: int in range(25):
		var region: Dictionary = regional_book["regions"][index]
		var recipe: Dictionary = book["entries"][index]
		if not bool(Regional.inspect_region(atlas, region).get("ok", false)):
			return _fail("CASCADE_BAD_REGIONAL_SOURCE")
		var junction: String = str(region["source_sites"][6]["site_id"])
		if recipe.get("region_id") != region["region_id"] \
				or recipe.get("junction_site_id") != junction or seen.has(junction) \
				or recipe.get("risk_class") != region["risk_class"] \
				or recipe.get("qualification") != QUALIFICATION \
				or recipe.get("critical_service_site") != region["critical_service_site"] \
				or recipe.get("shelter_service_site") != region["shelter_service_site"] \
				or recipe.get("original_fault_signature") != region["fault_signature"] \
				or recipe.get("original_recovery_procedure") != region["recovery_procedure"]:
			return _fail("CASCADE_SOURCE_IDENTITY")
		var risk: String = str(recipe["risk_class"])
		if not PROTOCOLS.has(risk) or recipe.get("risk_protocol") != PROTOCOLS[risk][0] \
				or recipe.get("managed_service_pressure") != PROTOCOLS[risk][1]:
			return _fail("CASCADE_RISK_PROOF")
		var tie: Dictionary = region["standby_ties"][1]
		if recipe.get("backfeed_tie_id") != tie["edge_id"] \
				or recipe.get("backfeed_source_site") != tie["from"] \
				or recipe.get("affected_service_site") != tie["to"]:
			return _fail("CASCADE_TIE_SOURCE")
		var feeder: Dictionary = {}
		for edge: Dictionary in region["primary_feeders"]:
			if edge["to"] == tie["to"]:
				feeder = edge
				break
		if feeder.is_empty() or recipe.get("normal_feeder_id") != feeder["edge_id"]:
			return _fail("CASCADE_PRIMARY_SOURCE")
		seen[junction] = true
	return {"ok": true, "junctions": seen.size(), "protocols": PROTOCOLS.size()}


func configure(source: Dictionary, network: Regional) -> Dictionary:
	if not _recipe.is_empty() or network == null:
		return _fail("CASCADE_ALREADY_CONFIGURED_OR_MISSING_NETWORK")
	var book: Dictionary = load_book()
	var verified: Dictionary = inspect(Atlas.load_catalog(), book, Regional.load_book())
	if not bool(verified.get("ok", false)):
		return verified
	var pinned: Dictionary = entry_for(book, str(source.get("junction_site_id", "")))
	if pinned.is_empty() or pinned != source:
		return _fail("CASCADE_UNPINNED_SOURCE")
	var region: Dictionary = network.snapshot()
	if region.is_empty() or region.get("region_id") != pinned["region_id"] \
			or region.get("level_id") != pinned["junction_site_id"] \
			or not region["feeders"].has(str(pinned["normal_feeder_id"])) \
			or not region["ties"].has(str(pinned["backfeed_tie_id"])):
		return _fail("CASCADE_HOST_REGION_MISMATCH")
	_recipe = pinned.duplicate(true)
	_network = network
	_phase = "assessment_pending"
	return {"ok": true, "junction": _recipe["junction_site_id"]}


func definition_snapshot() -> Dictionary:
	return _recipe.duplicate(true)


func resolved() -> bool:
	return _phase == "attested"


func snapshot() -> Dictionary:
	if _recipe.is_empty():
		return {}
	return {
		"region_id": _recipe["region_id"],
		"junction_site_id": _recipe["junction_site_id"],
		"affected_service_site": _recipe["affected_service_site"],
		"critical_service_site": _recipe["critical_service_site"],
		"shelter_service_site": _recipe["shelter_service_site"],
		"normal_feeder_id": _recipe["normal_feeder_id"],
		"backfeed_tie_id": _recipe["backfeed_tie_id"],
		"risk_protocol": _recipe["risk_protocol"],
		"phase": _phase, "response_mode": _mode,
		"service_pressure": _service_pressure,
		"reserve_spent": _reserve_spent,
		"critical_supply_at_assessment": _critical_supply_at_assessment,
		"resolved": resolved(),
		"events": _events.duplicate(true),
		"qualification": QUALIFICATION
	}


func _record(action: String) -> void:
	_events.append({"sequence": _events.size() + 1, "action": action,
		"phase": _phase, "response_mode": _mode})


## The host alone supplies all fault and recovery proofs from pinned A09 source.
## A failed operation must preserve the phase, reserve and service pressure.
func operate(action: String) -> Dictionary:
	if _recipe.is_empty():
		return _fail("CASCADE_NOT_CONFIGURED")
	if not ACTIONS.has(action):
		return _fail("CASCADE_UNKNOWN_ACTION")
	var state: Dictionary = _network.snapshot()
	if state.get("level_id") != _recipe["junction_site_id"] \
			or state.get("region_id") != _recipe["region_id"]:
		return _fail("CASCADE_DISPATCH_CHANGED")
	var feeder_id: String = str(_recipe["normal_feeder_id"])
	var tie_id: String = str(_recipe["backfeed_tie_id"])
	var feeder: Dictionary = state["feeders"][feeder_id]
	var tie: Dictionary = state["ties"][tie_id]
	var result: Dictionary = {}
	match action:
		"cascade_assess":
			if _phase != "assessment_pending" or str(state["strategy"]).is_empty():
				return _fail("CASCADE_STRATEGY_REQUIRED")
			_critical_supply_at_assessment = bool(
				state["sites"][str(_recipe["critical_service_site"])]["supply_ready"])
			_phase = "assessed"
		"cascade_trip":
			if _phase != "assessed":
				return _fail("CASCADE_ASSESSMENT_REQUIRED")
			result = _network.host_transition("trip_feeder", feeder_id,
				str(_recipe["original_fault_signature"]))
			if not bool(result.get("ok", false)):
				return result
			_phase = "fault_isolated"
		"cascade_backfeed":
			if _phase != "fault_isolated":
				return _fail("CASCADE_FAULT_ISOLATION_REQUIRED")
			var before: int = int(state["reserve_pu"])
			result = _network.host_transition("engage_tie", tie_id)
			if not bool(result.get("ok", false)):
				return result
			_reserve_spent = before - int(_network.snapshot()["reserve_pu"])
			_mode = "standby_service"
			_service_pressure = 0 if _critical_supply_at_assessment else 1
			_phase = "service_triaged"
		"cascade_managed":
			if _phase != "fault_isolated":
				return _fail("CASCADE_FAULT_ISOLATION_REQUIRED")
			if bool(tie["engaged"]):
				return _fail("CASCADE_FOREIGN_TRANSFER_ACTIVE")
			_mode = "controlled_shedding"
			_service_pressure = int(_recipe["managed_service_pressure"]) + (
				0 if _critical_supply_at_assessment else 2)
			_phase = "service_triaged"
		"cascade_prepare":
			if _phase != "service_triaged":
				return _fail("CASCADE_SERVICE_TRIAGE_REQUIRED")
			if not _network.site_prepared():
				result = _network.prepare_site("managed")
				if not bool(result.get("ok", false)):
					return result
			_phase = "teams_deployed"
		"cascade_clear":
			if _phase != "teams_deployed" or not _network.site_prepared():
				return _fail("CASCADE_PREPARATION_REQUIRED")
			result = _network.host_transition("clear_fault", feeder_id,
				str(_recipe["original_recovery_procedure"]))
			if not bool(result.get("ok", false)):
				return result
			_phase = "fault_cleared"
		"cascade_reconnect":
			if _phase != "fault_cleared" or str(feeder["fault"]) != "" \
					or not bool(feeder["isolated"]):
				return _fail("CASCADE_FAULT_CLEARANCE_REQUIRED")
			if _mode == "standby_service":
				if not bool(tie["engaged"]):
					return _fail("CASCADE_STANDBY_PROOF_MISSING")
				result = _network.host_transition("release_tie", tie_id)
				if not bool(result.get("ok", false)):
					return result
			elif bool(tie["engaged"]):
				return _fail("CASCADE_FOREIGN_TRANSFER_ACTIVE")
			result = _network.host_transition("reset_feeder", feeder_id)
			if not bool(result.get("ok", false)):
				return result
			_phase = "normal_service_recovered"
		"cascade_attest":
			if _phase != "normal_service_recovered" or not _network.site_prepared() \
					or str(feeder["fault"]) != "" or bool(feeder["isolated"]) \
					or bool(tie["engaged"]):
				return _fail("CASCADE_SAFE_NORMAL_REQUIRED")
			_phase = "attested"
	_record(action)
	return {"ok": true, "snapshot": snapshot()}
