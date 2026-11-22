extends RefCounted
## EXP015 A03: opt-in final dispatch service portfolio, bound to original A09.
## Exact original feeder readiness and finite standby reserve are authoritative.
## Never invent EXP04 receipts, production credits, electric flow or player proof.

const Atlas := preload("res://scripts/world/dispatch_atlas.gd")
const Regional := preload("res://scripts/gameplay/expedition_regional_network.gd")

const BOOK_PATH: String = "res://scenes/expeditions/region_finales_exp015_a03.json"
const AUTHORITY: String = "EXP015_A03_AUTHORED_FINALE_TRIAGE_SOURCE"
const BINDING: String = "EXP014_A09_ORIGINAL_CRITICAL_SHELTER_AND_FEEDER"
const HOLD: String = "SOURCE_HEADLESS_ONLY_HUMAN_CONTROLLER_RELEASE_HELD"
const RISK: Dictionary = {
	"depth": ["groundwater_isolation_review", 3],
	"conductivity": ["arc_clearance_assurance", 5],
	"mechanical": ["load_transfer_interlock_review", 2],
	"structure": ["support_stability_release", 4],
	"weather": ["exposed_conductor_reclearance", 3]
}
const ACTIONS: Array[String] = [
	"finale_assess", "finale_critical_verified", "finale_critical_contingency",
	"finale_buffer", "finale_managed", "finale_verify", "finale_signoff"
]

var _spec: Dictionary = {}
var _regional: Regional
var _phase: String = "inactive"
var _critical_route: String = ""
var _shelter_route: String = ""
var _critical_initially_live: bool = false
var _shelter_initially_ready: bool = false
var _critical_contingency_pressure: int = 0
var _shelter_service_pressure: int = 0
var _reserve_consumed: int = 0
var _events: Array[Dictionary] = []


static func _fail(code: String) -> Dictionary:
	return {"ok": false, "code": code}


static func load_book() -> Dictionary:
	if not FileAccess.file_exists(BOOK_PATH):
		return {}
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(BOOK_PATH))
	return value if value is Dictionary else {}


static func entry_for(book: Dictionary, site_id: String) -> Dictionary:
	for item: Variant in book.get("entries", []):
		if item is Dictionary and item.get("finale_site_id") == site_id:
			return (item as Dictionary).duplicate(true)
	return {}


## Check against complete existing A09 authority, not a client-supplied recipe.
static func inspect(atlas: Dictionary, book: Dictionary, network_book: Dictionary) -> Dictionary:
	if book.get("schema_version") != 1 or book.get("authority") != AUTHORITY or \
			book.get("qualification") != HOLD or book.get("source_binding") != BINDING or \
			book.get("original_campaign_unchanged") != true or \
			not book.get("entries") is Array or book["entries"].size() != 25 or \
			not network_book.get("regions") is Array or network_book["regions"].size() != 25:
		return _fail("FINALE_SOURCE_AUTHORITY")
	var seen: Dictionary = {}
	for i: int in range(25):
		var r: Dictionary = network_book["regions"][i]
		var e: Dictionary = book["entries"][i]
		if not bool(Regional.inspect_region(atlas, r).get("ok", false)):
			return _fail("FINALE_A09_SOURCE_INVALID")
		var site: String = str(r["source_sites"][7]["site_id"])
		if e.get("region_id") != r["region_id"] or e.get("finale_site_id") != site or \
				seen.has(site) or e.get("shelter_service_site") != site or \
				e.get("critical_service_site") != r["critical_service_site"] or \
				e.get("reserve_anchor_site") != r["reserve_anchor_site"] or \
				e.get("root_source_site") != r["root_source_id"] or \
				e.get("risk_class") != r["risk_class"] or e.get("source_qualification") != HOLD:
			return _fail("FINALE_ORIGINAL_SITE_SOURCE_MISMATCH")
		var risk: String = str(e["risk_class"])
		if not RISK.has(risk) or e.get("risk_closeout_protocol") != RISK[risk][0] or \
				e.get("critical_dark_pressure_pu") != RISK[risk][1]:
			return _fail("FINALE_RISK_PROTOCOL_MISMATCH")
		var critical: Dictionary = {}
		var shelter: Dictionary = {}
		for feeder: Dictionary in r["primary_feeders"]:
			if feeder["to"] == e["critical_service_site"]:
				critical = feeder
			if feeder["to"] == site:
				shelter = feeder
		if critical.is_empty() or shelter.is_empty() or \
				e.get("critical_feeder_id") != critical["edge_id"] or \
				e.get("shelter_feeder_id") != shelter["edge_id"] or \
				e.get("shelter_standby_tie_id") != r["standby_ties"][1]["edge_id"]:
			return _fail("FINALE_FEEDER_PROVENANCE_MISMATCH")
		seen[site] = true
	return {"ok": true, "regions": seen.size(), "risk_families": RISK.size()}


func configure(recipe: Dictionary, regional: Regional) -> Dictionary:
	if not _spec.is_empty() or regional == null:
		return _fail("FINALE_ALREADY_CONFIGURED_OR_MISSING_NETWORK")
	var book: Dictionary = load_book()
	var validation: Dictionary = inspect(Atlas.load_catalog(), book, Regional.load_book())
	if not bool(validation.get("ok", false)):
		return validation
	var approved: Dictionary = entry_for(book, str(recipe.get("finale_site_id", "")))
	if approved.is_empty() or approved != recipe:
		return _fail("FINALE_UNTRUSTED_RECIPE")
	var state: Dictionary = regional.snapshot()
	if state.is_empty() or state.get("region_id") != approved["region_id"] or \
			state.get("level_id") != approved["finale_site_id"] or \
			not state["feeders"].has(str(approved["critical_feeder_id"])) or \
			not state["feeders"].has(str(approved["shelter_feeder_id"])) or \
			not state["ties"].has(str(approved["shelter_standby_tie_id"])):
		return _fail("FINALE_HOST_CONTEXT_MISMATCH")
	_regional = regional
	_spec = approved.duplicate(true)
	_phase = "assessment_pending"
	return {"ok": true, "region_id": _spec["region_id"], "finale": _spec["finale_site_id"]}


func definition_snapshot() -> Dictionary:
	return _spec.duplicate(true)


## Original A09 board permits generic source switching and preparation. Only
## original critical/shelter feeders and second standby tie are protected
## during this opt-in finale; unrelated A09 controls stay functional.
func protects_original_action(action: String) -> bool:
	if _spec.is_empty():
		return false
	if ["regional_managed", "regional_buffer"].has(action):
		return true
	var parts: PackedStringArray = action.split(":")
	if parts.size() < 2:
		return false
	if ["regional_isolate", "regional_reset"].has(parts[0]):
		return [str(_spec["critical_feeder_id"]), str(_spec["shelter_feeder_id"])].has(parts[1])
	if ["regional_engage", "regional_release"].has(parts[0]):
		return parts[1] == str(_spec["shelter_standby_tie_id"])
	return false


func _current_validity() -> bool:
	if _regional == null or _spec.is_empty():
		return false
	var state: Dictionary = _regional.snapshot()
	if state.is_empty() or state.get("region_id") != _spec["region_id"] or \
			state.get("level_id") != _spec["finale_site_id"] or not _regional.site_prepared():
		return false
	var shelter: Dictionary = state["feeders"][str(_spec["shelter_feeder_id"])]
	var critical: Dictionary = state["feeders"][str(_spec["critical_feeder_id"])]
	var tie: Dictionary = state["ties"][str(_spec["shelter_standby_tie_id"])]
	if bool(shelter["isolated"]) or str(shelter["fault"]) != "" or bool(tie["engaged"]):
		return false
	if bool(critical["isolated"]) or str(critical["fault"]) != "":
		return false
	var critical_live: bool = bool(state["sites"][str(_spec["critical_service_site"])]["energized"])
	return critical_live == _critical_initially_live


func closed() -> bool:
	return _phase == "signed_off" and _current_validity()


func snapshot() -> Dictionary:
	if _spec.is_empty():
		return {}
	return {
		"region_id": _spec["region_id"], "finale_site_id": _spec["finale_site_id"],
		"critical_service_site": _spec["critical_service_site"],
		"shelter_service_site": _spec["shelter_service_site"],
		"risk_closeout_protocol": _spec["risk_closeout_protocol"],
		"phase": _phase, "critical_route": _critical_route,
		"shelter_route": _shelter_route,
		"critical_initially_live": _critical_initially_live,
		"shelter_initially_ready": _shelter_initially_ready,
		"critical_contingency_pressure": _critical_contingency_pressure,
		"shelter_service_pressure": _shelter_service_pressure,
		"reserve_consumed": _reserve_consumed,
		"closed": closed(),
		"events": _events.duplicate(true), "qualification": HOLD
	}


func _record(action: String) -> void:
	_events.append({"sequence": _events.size() + 1, "action": action,
		"phase": _phase, "critical": _critical_route, "shelter": _shelter_route})


## Only the trusted authenticated SessionHost worksite callback may call this.
## No client supplies site ID, feeder, risk debt, power facts or receipt evidence.
func operate(action: String) -> Dictionary:
	if _spec.is_empty():
		return _fail("FINALE_NOT_CONFIGURED")
	if not ACTIONS.has(action):
		return _fail("FINALE_UNKNOWN_ACTION")
	var state: Dictionary = _regional.snapshot()
	if state.get("region_id") != _spec["region_id"] or \
			state.get("level_id") != _spec["finale_site_id"]:
		return _fail("FINALE_DISPATCH_CHANGED")
	var shelter_id: String = str(_spec["shelter_feeder_id"])
	var critical_id: String = str(_spec["critical_service_site"])
	match action:
		"finale_assess":
			if _phase != "assessment_pending" or str(state["strategy"]).is_empty():
				return _fail("FINALE_STRATEGY_REQUIRED")
			_critical_initially_live = bool(state["sites"][critical_id]["energized"])
			_shelter_initially_ready = bool(state["site_conditions"]["supply_ready"])
			_phase = "critical_review"
		"finale_critical_verified":
			if _phase != "critical_review" or not _critical_initially_live or \
					not bool(state["sites"][critical_id]["energized"]):
				return _fail("FINALE_CRITICAL_ENERGIZATION_MISSING")
			_critical_route = "verified_critical_supply"
			_phase = "shelter_choice"
		"finale_critical_contingency":
			if _phase != "critical_review" or _critical_initially_live:
				return _fail("FINALE_CONTINGENCY_NOT_REQUIRED")
			_critical_route = "documented_critical_outage"
			_critical_contingency_pressure = int(_spec["critical_dark_pressure_pu"])
			_phase = "shelter_choice"
		"finale_buffer", "finale_managed":
			if _phase != "shelter_choice" or bool(state["feeders"][shelter_id]["isolated"]) or \
					str(state["feeders"][shelter_id]["fault"]) != "" or \
					bool(state["ties"][str(_spec["shelter_standby_tie_id"])]["engaged"]):
				return _fail("FINALE_SHELTER_PRECONDITION_INVALID")
			var before: int = int(state["reserve_pu"])
			var choice: String = "buffer" if action == "finale_buffer" else "managed"
			var decided: Dictionary = _regional.prepare_site(choice)
			if not bool(decided.get("ok", false)):
				return decided
			_reserve_consumed = before - int(_regional.snapshot()["reserve_pu"])
			_shelter_service_pressure = 2 if choice == "managed" and not _shelter_initially_ready else 0
			_shelter_route = choice
			_phase = "verification_pending"
		"finale_verify":
			if _phase != "verification_pending" or not _current_validity():
				return _fail("FINALE_SOURCE_PROOF_NOT_CURRENT")
			_phase = "verified"
		"finale_signoff":
			if _phase != "verified" or not _current_validity():
				return _fail("FINALE_RESTORATION_NOT_VERIFIED")
			_phase = "signed_off"
	_record(action)
	return {"ok": true, "snapshot": snapshot()}
