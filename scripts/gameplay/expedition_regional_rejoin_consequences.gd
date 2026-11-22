extends RefCounted
## EXP015 A08: 50 ORIGINAL rejoin-site consequences bound to A07's real
## A09 feeder event ledger. Never trust a client route claim or forged receipt.
## Existing authenticated SessionHost worksite board is the only ingress.

const Atlas := preload("res://scripts/world/dispatch_atlas.gd")
const Regional := preload("res://scripts/gameplay/expedition_regional_network.gd")
const Incident := preload("res://scripts/gameplay/expedition_regional_emergencies.gd")
const Cascade := preload("res://scripts/gameplay/expedition_regional_cascades.gd")

const BOOK_PATH: String = "res://scenes/expeditions/region_rejoins_exp015_a08.json"
const AUTHORITY: String = "EXP015_A08_REAL_ROUTE_EVIDENCE_REJOIN"
const QUALIFICATION: String = "SOURCE_HEADLESS_ONLY_HUMAN_CONTROLLER_RELEASE_HELD"
const RISK: Dictionary = {
	"depth": ["rejoin_dewater_and_lockout", 3],
	"conductivity": ["rejoin_arc_free_continuity", 5],
	"mechanical": ["rejoin_mechanical_interlock", 2],
	"structure": ["rejoin_shoring_clearance", 4],
	"weather": ["rejoin_weather_seal_proof", 3]
}
const ACTIONS: Array[String] = [
	"rejoin_assess", "rejoin_trace_a", "rejoin_trace_b",
	"rejoin_unverified", "rejoin_trip", "rejoin_priority",
	"rejoin_managed", "rejoin_stage", "rejoin_clear",
	"rejoin_release", "rejoin_reset", "rejoin_verify", "rejoin_signoff"
]

var _recipe: Dictionary = {}
var _network: Regional
var _incident: Incident
var _cascade: Cascade
var _phase: String = "inactive"
var _route: String = ""
var _service_mode: String = ""
var _proven_a: bool = false
var _proven_b: bool = false
var _critical_initially_live: bool = false
var _site_originally_ready: bool = false
var _reserve_spent_pu: int = 0
var _managed_pressure_pu: int = 0
var _tie_staged: bool = false
var _events: Array[Dictionary] = []


static func _fail(code: String) -> Dictionary:
	return {"ok": false, "code": code}


static func load_book() -> Dictionary:
	if not FileAccess.file_exists(BOOK_PATH):
		return {}
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(BOOK_PATH))
	return raw if raw is Dictionary else {}


static func entry_for(book: Dictionary, site_id: String) -> Dictionary:
	for raw: Variant in book.get("entries", []):
		if raw is Dictionary and raw.get("join_site_id") == site_id:
			return (raw as Dictionary).duplicate(true)
	return {}


static func inspect(atlas: Dictionary, book: Dictionary,
		networks: Dictionary) -> Dictionary:
	if book.get("schema_version") != 1 or book.get("authority") != AUTHORITY or \
			book.get("predecessor") != "EXP015_A07" or \
			book.get("qualification") != QUALIFICATION or \
			book.get("legacy_campaign_contracts_unchanged") != true or \
			book.get("original_rejoins") != 50 or \
			not book.get("entries") is Array or book["entries"].size() != 50 or \
			not networks.get("regions") is Array or networks["regions"].size() != 25:
		return _fail("REJOIN_SOURCE_AUTHORITY")
	var visited: Dictionary = {}
	var types: Dictionary = {"first_rejoin": 0, "second_rejoin": 0}
	var index: int = 0
	for region: Dictionary in networks["regions"]:
		if not bool(Regional.inspect_region(atlas, region).get("ok", false)):
			return _fail("REJOIN_ORIGINAL_NETWORK_INVALID")
		for slot: int in [3, 6]:
			var site: Dictionary = region["source_sites"][slot]
			var case: Dictionary = book["entries"][index]
			index += 1
			var join_id: String = str(site["site_id"])
			var original: Dictionary = Atlas.find_level(atlas, join_id)
			var task_ids: Array[String] = []
			for task: Dictionary in original.get("tasks", []):
				task_ids.append(str(task["id"]))
			var normal: Dictionary = {}
			var feeder_a: Dictionary = {}
			var feeder_b: Dictionary = {}
			var route_a: Dictionary = region["source_sites"][1 if slot == 3 else 4]
			var route_b: Dictionary = region["source_sites"][2 if slot == 3 else 5]
			var finale: Dictionary = region["source_sites"][7]
			var finale_normal: Dictionary = {}
			for edge: Dictionary in region["primary_feeders"]:
				if edge["to"] == join_id:
					normal = edge
				if edge["to"] == route_a["site_id"]:
					feeder_a = edge
				if edge["to"] == route_b["site_id"]:
					feeder_b = edge
				if edge["to"] == finale["site_id"]:
					finale_normal = edge
			var finale_tie: Dictionary = {}
			for tie: Dictionary in region["standby_ties"]:
				if tie["to"] == finale["site_id"]:
					finale_tie = tie
			var second: bool = slot == 6
			var role: String = str(site["campaign_role"])
			var risk: String = str(region["risk_class"])
			if original.is_empty() or normal.is_empty() or feeder_a.is_empty() or \
					feeder_b.is_empty() or finale_normal.is_empty() or \
					finale_tie.is_empty() or not RISK.has(risk) or visited.has(join_id) or \
					role != ("second_rejoin" if second else "first_rejoin") or \
					case.get("region_id") != region["region_id"] or \
					case.get("join_site_id") != join_id or \
					case.get("location_id") != site["location_id"] or \
					case.get("join_role") != role or \
					case.get("source_task_ids") != task_ids or \
					case.get("join_feeder_id") != normal["edge_id"] or \
					case.get("join_upstream_site_id") != normal["from"] or \
					case.get("route_a_site_id") != route_a["site_id"] or \
					case.get("route_a_feeder_id") != feeder_a["edge_id"] or \
					case.get("route_b_site_id") != route_b["site_id"] or \
					case.get("route_b_feeder_id") != feeder_b["edge_id"] or \
					case.get("critical_service_site") != region["critical_service_site"] or \
					case.get("finale_site_id") != finale["site_id"] or \
					case.get("finale_normal_feeder_id") != (
						finale_normal["edge_id"] if second else "") or \
					case.get("finale_standby_tie_id") != (
						finale_tie["edge_id"] if second else "") or \
					case.get("finale_standby_source_id") != (
						finale_tie["from"] if second else "") or \
					case.get("original_fault_signature") != region["fault_signature"] or \
					case.get("original_recovery_procedure") != region["recovery_procedure"] or \
					case.get("risk_class") != risk or \
					case.get("rejoin_risk_protocol") != RISK[risk][0] or \
					case.get("managed_pressure_pu") != RISK[risk][1] or \
					case.get("qualification") != QUALIFICATION:
				return _fail("REJOIN_ORIGINAL_SOURCE_MISMATCH")
			visited[join_id] = true
			types[role] = int(types[role]) + 1
	if types["first_rejoin"] != 25 or types["second_rejoin"] != 25:
		return _fail("REJOIN_ORIGINAL_ROLE_COVERAGE")
	return {"ok": true, "original_joins": visited.size(),
		"role_counts": types, "risk_protocols": RISK.size()}


func configure(recipe: Dictionary, network: Regional,
		incident: Incident, cascade: Cascade) -> Dictionary:
	if not _recipe.is_empty() or network == null:
		return _fail("REJOIN_HOST_NOT_READY")
	var book: Dictionary = load_book()
	var gate: Dictionary = inspect(Atlas.load_catalog(), book, Regional.load_book())
	if not bool(gate.get("ok", false)):
		return gate
	var trusted: Dictionary = entry_for(book, str(recipe.get("join_site_id", "")))
	if trusted.is_empty() or trusted != recipe:
		return _fail("REJOIN_UNTRUSTED_RECIPE")
	var state: Dictionary = network.snapshot()
	if state.is_empty() or state.get("region_id") != trusted["region_id"] or \
			state.get("level_id") != trusted["join_site_id"]:
		return _fail("REJOIN_HOST_DISPATCH_CHANGED")
	if trusted["join_role"] == "first_rejoin":
		if incident == null or cascade != null or \
				incident.definition_snapshot().get("incident_site_id") != trusted["join_site_id"]:
			return _fail("REJOIN_FIRST_PARENT_INVALID")
	else:
		if cascade == null or incident != null or \
				cascade.definition_snapshot().get("junction_site_id") != trusted["join_site_id"]:
			return _fail("REJOIN_SECOND_PARENT_INVALID")
	_recipe = trusted.duplicate(true)
	_network = network
	_incident = incident
	_cascade = cascade
	_phase = "awaiting_parent"
	return {"ok": true, "join_site_id": trusted["join_site_id"],
		"join_role": trusted["join_role"]}


func definition_snapshot() -> Dictionary:
	return _recipe.duplicate(true)


func _parent_closed() -> bool:
	if _recipe.is_empty() or _network == null or not _network.site_prepared():
		return false
	if _incident != null:
		return _incident.certified()
	if _cascade != null:
		return _cascade.resolved()
	return false


func _prior_route_proof(state: Dictionary, route: String) -> bool:
	var site: String = str(_recipe["route_a_site_id"] if route == "a" else
		_recipe["route_b_site_id"])
	var feeder: String = str(_recipe["route_a_feeder_id"] if route == "a" else
		_recipe["route_b_feeder_id"])
	if not bool(state["sites"][site]["restored"]) or \
			bool(state["feeders"][feeder]["isolated"]) or \
			str(state["feeders"][feeder]["fault"]) != "":
		return false
	var progress: int = 0
	for step: Dictionary in state.get("events", []):
		if step.get("asset") != feeder:
			continue
		match str(step.get("action", "")):
			"trip_feeder":
				progress = 1
			"clear_fault":
				if progress == 1:
					progress = 2
			"reset_feeder":
				if progress == 2:
					progress = 3
			"isolate_feeder":
				progress = 0
	return progress == 3


func protects_original_asset(action: String) -> bool:
	if _recipe.is_empty():
		return false
	var parts: PackedStringArray = action.split(":")
	if parts.size() < 2:
		return false
	var feeders: Array[String] = [str(_recipe["join_feeder_id"])]
	if _recipe["join_role"] == "second_rejoin":
		feeders.append(str(_recipe["finale_normal_feeder_id"]))
	var tie: String = str(_recipe["finale_standby_tie_id"])
	if ["regional_isolate", "regional_reset"].has(parts[0]):
		return feeders.has(parts[1])
	if ["regional_engage", "regional_release"].has(parts[0]):
		return not tie.is_empty() and parts[1] == tie
	return false


func _source_valid() -> bool:
	if not _parent_closed() or _network == null or _recipe.is_empty():
		return false
	var state: Dictionary = _network.snapshot()
	if state.get("region_id") != _recipe["region_id"] or \
			state.get("level_id") != _recipe["join_site_id"]:
		return false
	var feeder: Dictionary = state["feeders"][str(_recipe["join_feeder_id"])]
	if bool(feeder["isolated"]) or str(feeder["fault"]) != "":
		return false
	if _recipe["join_role"] == "second_rejoin":
		var fin: Dictionary = state["feeders"][str(_recipe["finale_normal_feeder_id"])]
		var tie: Dictionary = state["ties"][str(_recipe["finale_standby_tie_id"])]
		if bool(fin["isolated"]) or str(fin["fault"]) != "" or bool(tie["engaged"]):
			return false
	return bool(state["sites"][str(_recipe["join_site_id"])]["supply_ready"]) == \
		_site_originally_ready


func closed() -> bool:
	return _phase == "signed_off" and _source_valid()


func snapshot() -> Dictionary:
	if _recipe.is_empty():
		return {}
	var state: Dictionary = _network.snapshot()
	return {"region_id": _recipe["region_id"], "join_site_id": _recipe["join_site_id"],
		"role": _recipe["join_role"], "phase": _phase,
		"route_evidence": _route, "service_response": _service_mode,
		"prior_route_a_proven": _proven_a, "prior_route_b_proven": _proven_b,
		"critical_initially_energized": _critical_initially_live,
		"rejoin_supply_initially_ready": _site_originally_ready,
		"rejoin_supply_now_ready": bool(state["sites"][
			str(_recipe["join_site_id"])]["supply_ready"]),
		"standby_staged": _tie_staged, "reserve_spent_pu": _reserve_spent_pu,
		"managed_pressure_pu": _managed_pressure_pu,
		"risk_protocol": _recipe["rejoin_risk_protocol"],
		"parent_closed": _parent_closed(), "closed": closed(),
		"events": _events.duplicate(true), "qualification": QUALIFICATION}


func _record(action: String) -> void:
	_events.append({"sequence": _events.size() + 1, "action": action,
		"phase": _phase, "route": _route, "response": _service_mode})


func operate(action: String) -> Dictionary:
	if _recipe.is_empty():
		return _fail("REJOIN_NOT_CONFIGURED")
	if not ACTIONS.has(action) and \
			action != "rejoin_contain:" + str(_recipe["rejoin_risk_protocol"]):
		return _fail("REJOIN_UNKNOWN_OR_FORGED_ACTION")
	var state: Dictionary = _network.snapshot()
	if state.get("region_id") != _recipe["region_id"] or \
			state.get("level_id") != _recipe["join_site_id"]:
		return _fail("REJOIN_DISPATCH_CHANGED")
	var second: bool = _recipe["join_role"] == "second_rejoin"
	var feeder: String = str(_recipe["join_feeder_id"])
	var fin_feeder: String = str(_recipe["finale_normal_feeder_id"])
	var tie: String = str(_recipe["finale_standby_tie_id"])
	var response: Dictionary = {}
	match action:
		"rejoin_assess":
			if _phase != "awaiting_parent" or not _parent_closed():
				return _fail("REJOIN_PARENT_PROOF_REQUIRED")
			_proven_a = _prior_route_proof(state, "a")
			_proven_b = _prior_route_proof(state, "b")
			_critical_initially_live = bool(state["sites"][
				str(_recipe["critical_service_site"])]["energized"])
			_site_originally_ready = bool(state["sites"][
				str(_recipe["join_site_id"])]["supply_ready"])
			_phase = "route_choice"
		"rejoin_trace_a":
			if _phase != "route_choice" or not _proven_a:
				return _fail("REJOIN_ORIGINAL_A_PROOF_REQUIRED")
			_route = "verified_route_a"
			_phase = "stress_pending"
		"rejoin_trace_b":
			if _phase != "route_choice" or not _proven_b:
				return _fail("REJOIN_ORIGINAL_B_PROOF_REQUIRED")
			_route = "verified_route_b"
			_phase = "stress_pending"
		"rejoin_unverified":
			if _phase != "route_choice" or _proven_a or _proven_b:
				return _fail("REJOIN_ONLY_MISSING_PROOF_MANAGED")
			_route = "source_unverified_managed"
			_managed_pressure_pu = int(_recipe["managed_pressure_pu"])
			_phase = "stress_pending"
		"rejoin_trip":
			if _phase != "stress_pending" or not _parent_closed():
				return _fail("REJOIN_UNTRUSTED_SECONDARY_FAULT")
			response = _network.host_transition("trip_feeder", feeder,
				str(_recipe["original_fault_signature"]))
			if not bool(response.get("ok", false)):
				return response
			_phase = "service_choice"
		"rejoin_priority":
			if _phase != "service_choice" or second or \
					not _critical_initially_live:
				return _fail("REJOIN_PRIORITY_REQUIRES_CRITICAL_SUPPLY")
			_service_mode = "verified_critical_service_priority"
			_phase = "risk_proof"
		"rejoin_managed":
			if _phase != "service_choice":
				return _fail("REJOIN_MANAGED_RESPONSE_NOT_READY")
			_service_mode = "source_managed_recovery"
			_managed_pressure_pu = maxi(_managed_pressure_pu,
				int(_recipe["managed_pressure_pu"]))
			_phase = "risk_proof"
		"rejoin_stage":
			if _phase != "service_choice" or not second:
				return _fail("REJOIN_STANDBY_ONLY_SECOND_JOIN")
			var standby: Dictionary = state["ties"][tie]
			var main: Dictionary = state["feeders"][fin_feeder]
			var source: String = str(_recipe["finale_standby_source_id"])
			var destination: String = str(_recipe["finale_site_id"])
			# Prove the original A09 live source, break-before-make state,
			# reserve and original tie capacity before making ANY transition.
			if not bool(state["sites"][source]["energized"]) or \
					bool(state["sites"][destination]["energized"]) or \
					bool(standby["engaged"]) or bool(main["isolated"]) or \
					str(main["fault"]) != "" or int(state["reserve_pu"]) < 2 or \
					int(standby["capacity_pu"]) < 2:
				return _fail("REJOIN_REAL_STANDBY_SOURCE_UNAVAILABLE")
			response = _network.host_transition("isolate_feeder", fin_feeder)
			if not bool(response.get("ok", false)):
				return response
			var attached: Dictionary = _network.host_transition("engage_tie", tie)
			if not bool(attached.get("ok", false)):
				var rollback: Dictionary = _network.host_transition("reset_feeder", fin_feeder)
				if not bool(rollback.get("ok", false)):
					return _fail("REJOIN_STANDBY_ROLLBACK_FAILED")
				return _fail("REJOIN_STANDBY_ENGAGEMENT_DENIED")
			_reserve_spent_pu = 2
			_tie_staged = true
			_service_mode = "finite_original_standby_staging"
			_phase = "risk_proof"
		"rejoin_clear":
			if _phase != "clearance_ready":
				return _fail("REJOIN_RISK_PROOF_REQUIRED")
			response = _network.host_transition("clear_fault",
				feeder, str(_recipe["original_recovery_procedure"]))
			if not bool(response.get("ok", false)):
				return response
			_phase = "release_pending" if second else "reset_pending"
		"rejoin_release":
			if _phase != "release_pending" or not second:
				return _fail("REJOIN_RELEASE_NOT_READY")
			if _tie_staged:
				response = _network.host_transition("release_tie", tie)
				if not bool(response.get("ok", false)):
					return response
				response = _network.host_transition("reset_feeder", fin_feeder)
				if not bool(response.get("ok", false)):
					return response
				_tie_staged = false
			elif bool(state["ties"][tie]["engaged"]):
				return _fail("REJOIN_UNRECOGNIZED_TIE_ENGAGED")
			_phase = "reset_pending"
		"rejoin_reset":
			if _phase != "reset_pending":
				return _fail("REJOIN_RESET_NOT_READY")
			response = _network.host_transition("reset_feeder", feeder)
			if not bool(response.get("ok", false)):
				return response
			_phase = "verification_pending"
		"rejoin_verify":
			if _phase != "verification_pending" or not _source_valid():
				return _fail("REJOIN_REAL_NETWORK_PROOF_REQUIRED")
			_phase = "verified"
		"rejoin_signoff":
			if _phase != "verified" or not _source_valid():
				return _fail("REJOIN_STABLE_SOURCE_REQUIRED")
			_phase = "signed_off"
		_:
			if action != "rejoin_contain:" + str(_recipe["rejoin_risk_protocol"]) or \
					_phase != "risk_proof":
				return _fail("REJOIN_ORIGINAL_RISK_PROTOCOL_REQUIRED")
			_phase = "clearance_ready"
	_record(action)
	return {"ok": true, "snapshot": snapshot()}
