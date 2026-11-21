extends RefCounted
## EXP015 A05: source-bound critical-service assurance after A04.
## Actual A09 critical feeder fault, reserve recharge or conservation, and
## live-state-dependent priority/managed response; no independent RPC or reward.

const Atlas := preload("res://scripts/world/dispatch_atlas.gd")
const Network := preload("res://scripts/gameplay/expedition_regional_network.gd")
const Aftercare := preload("res://scripts/gameplay/expedition_regional_aftercare.gd")

const BOOK_PATH: String = "res://scenes/expeditions/region_assurance_exp015_a05.json"
const AUTHORITY: String = "EXP015_A05_ORIGINAL_CRITICAL_SERVICE_ASSURANCE"
const QUALIFICATION: String = "SOURCE_HEADLESS_ONLY_HUMAN_CONTROLLER_RELEASE_HELD"
const RISK: Dictionary = {
	"depth": ["dry_critical_feeder_clearance", 3],
	"conductivity": ["critical_insulation_proof", 5],
	"mechanical": ["critical_transfer_latch_proof", 2],
	"structure": ["critical_support_stability", 4],
	"weather": ["critical_exposure_reclearance", 3]
}
const ACTIONS: Array[String] = [
	"assurance_assess", "assurance_recharge", "assurance_conserve",
	"assurance_trip", "assurance_priority", "assurance_managed",
	"assurance_clear", "assurance_reset", "assurance_verify",
	"assurance_signoff"
]

var _spec: Dictionary = {}
var _network: Network
var _aftercare: Aftercare
var _phase: String = "inactive"
var _reserve_policy: String = ""
var _service_policy: String = ""
var _critical_originally_live: bool = false
var _reserve_recovered_pu: int = 0
var _critical_pressure_pu: int = 0
var _events: Array[Dictionary] = []


static func _fail(code: String) -> Dictionary:
	return {"ok": false, "code": code}


static func load_book() -> Dictionary:
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(BOOK_PATH))
	return value if value is Dictionary else {}


static func entry_for(book: Dictionary, site_id: String) -> Dictionary:
	for entry: Variant in book.get("entries", []):
		if entry is Dictionary and entry.get("finale_site_id") == site_id:
			return (entry as Dictionary).duplicate(true)
	return {}


static func inspect(atlas: Dictionary, book: Dictionary,
		networks: Dictionary, aftercare: Dictionary) -> Dictionary:
	if book.get("schema_version") != 1 or book.get("authority") != AUTHORITY or \
			book.get("predecessor") != "EXP015_A04" or \
			book.get("qualification") != QUALIFICATION or \
			book.get("original_campaign_unchanged") != true or \
			not book.get("entries") is Array or book["entries"].size() != 25 or \
			not networks.get("regions") is Array or networks["regions"].size() != 25 or \
			not aftercare.get("entries") is Array or aftercare["entries"].size() != 25:
		return _fail("ASSURANCE_BOOK_AUTHORITY")
	var seen: Dictionary = {}
	for i: int in range(25):
		var region: Dictionary = networks["regions"][i]
		var prior: Dictionary = aftercare["entries"][i]
		var item: Dictionary = book["entries"][i]
		var risk: String = str(region["risk_class"])
		var feeder: Dictionary = {}
		for edge: Dictionary in region["primary_feeders"]:
			if edge["to"] == region["critical_service_site"]:
				feeder = edge
		if not RISK.has(risk) or feeder.is_empty() or \
				not bool(Network.inspect_region(atlas, region).get("ok", false)) or \
				seen.has(str(item.get("finale_site_id", ""))) or \
				item.get("region_id") != region["region_id"] or \
				item.get("finale_site_id") != prior["finale_site_id"] or \
				item.get("critical_service_site") != region["critical_service_site"] or \
				item.get("critical_feeder_id") != feeder["edge_id"] or \
				item.get("reserve_anchor_site") != region["reserve_anchor_site"] or \
				item.get("shelter_feeder_id") != prior["recovery_feeder_id"] or \
				item.get("fault_signature") != region["fault_signature"] or \
				item.get("recovery_procedure") != region["recovery_procedure"] or \
				item.get("risk_class") != risk or \
				item.get("critical_retest_protocol") != RISK[risk][0] or \
				item.get("managed_pressure_pu") != RISK[risk][1] or \
				item.get("source_qualification") != QUALIFICATION:
			return _fail("ASSURANCE_ORIGINAL_CRITICAL_SOURCE_MISMATCH")
		seen[str(item["finale_site_id"])] = true
	return {"ok": true, "regions": seen.size(), "risk_classes": RISK.size()}


func configure(spec: Dictionary, network: Network, aftercare: Aftercare) -> Dictionary:
	if not _spec.is_empty() or network == null or aftercare == null:
		return _fail("ASSURANCE_ALREADY_CONFIGURED_OR_MISSING_HOST")
	var source: Dictionary = load_book()
	var verdict: Dictionary = inspect(Atlas.load_catalog(), source,
		Network.load_book(), Aftercare.load_book())
	if not bool(verdict.get("ok", false)):
		return verdict
	var trusted: Dictionary = entry_for(source, str(spec.get("finale_site_id", "")))
	if trusted.is_empty() or trusted != spec:
		return _fail("ASSURANCE_UNTRUSTED_RECIPE")
	var state: Dictionary = network.snapshot()
	if state.get("level_id") != trusted["finale_site_id"] or \
			state.get("region_id") != trusted["region_id"] or \
			aftercare.definition_snapshot().get("finale_site_id") != trusted["finale_site_id"]:
		return _fail("ASSURANCE_HOST_CONTEXT_MISMATCH")
	_network = network
	_aftercare = aftercare
	_spec = trusted.duplicate(true)
	_phase = "awaiting_aftercare"
	return {"ok": true, "region_id": _spec["region_id"]}


func definition_snapshot() -> Dictionary:
	return _spec.duplicate(true)


## Preserve this phase's reserve decision when owner opts in. A03 protects
## its original critical feeder, while A04 protects raw reserve recharge after
## its first assessment. No new RPC or user-supplied asset IDs.
func protects_original_action(action: String) -> bool:
	return not _spec.is_empty() and action == "regional_recharge"


func _source_valid() -> bool:
	if _network == null or _aftercare == null or _spec.is_empty() or \
			not _aftercare.closed():
		return false
	var state: Dictionary = _network.snapshot()
	if state.get("region_id") != _spec["region_id"] or \
			state.get("level_id") != _spec["finale_site_id"]:
		return false
	var feeder: Dictionary = state["feeders"][str(_spec["critical_feeder_id"])]
	var shelter: Dictionary = state["feeders"][str(_spec["shelter_feeder_id"])]
	return not bool(feeder["isolated"]) and str(feeder["fault"]) == "" and \
			not bool(shelter["isolated"]) and str(shelter["fault"]) == "" and \
			bool(state["sites"][str(_spec["critical_service_site"])]["energized"]) == \
			_critical_originally_live


func closed() -> bool:
	return _phase == "signed_off" and _source_valid()


func snapshot() -> Dictionary:
	if _spec.is_empty():
		return {}
	var state: Dictionary = _network.snapshot()
	return {"region_id": _spec["region_id"], "finale_site_id": _spec["finale_site_id"],
		"critical_retest_protocol": _spec["critical_retest_protocol"],
		"phase": _phase, "reserve_policy": _reserve_policy,
		"service_policy": _service_policy,
		"critical_originally_live": _critical_originally_live,
		"critical_now_live": bool(state["sites"][
			str(_spec["critical_service_site"])]["energized"]),
		"reserve_recovered_pu": _reserve_recovered_pu,
		"managed_pressure_pu": _critical_pressure_pu,
		"closed": closed(), "events": _events.duplicate(true),
		"qualification": QUALIFICATION}


func _record(action: String) -> void:
	_events.append({"sequence": _events.size() + 1,
		"action": action, "phase": _phase,
		"reserve_policy": _reserve_policy, "service_policy": _service_policy})


func operate(action: String) -> Dictionary:
	if _spec.is_empty():
		return _fail("ASSURANCE_NOT_CONFIGURED")
	if not ACTIONS.has(action):
		return _fail("ASSURANCE_UNKNOWN_ACTION")
	var state: Dictionary = _network.snapshot()
	if state.get("region_id") != _spec["region_id"] or \
			state.get("level_id") != _spec["finale_site_id"]:
		return _fail("ASSURANCE_DISPATCH_CHANGED")
	var feeder: String = str(_spec["critical_feeder_id"])
	var reply: Dictionary = {}
	match action:
		"assurance_assess":
			if _phase != "awaiting_aftercare" or not _aftercare.closed():
				return _fail("ASSURANCE_AFTERCARE_SIGNOFF_REQUIRED")
			_critical_originally_live = bool(state["sites"][
				str(_spec["critical_service_site"])]["energized"])
			_phase = "reserve_choice"
		"assurance_recharge":
			if _phase != "reserve_choice" or not _aftercare.closed():
				return _fail("ASSURANCE_RESERVE_CHOICE_REQUIRED")
			var before: int = int(state["reserve_pu"])
			reply = _network.host_transition(
				"recharge_reserve", str(_spec["reserve_anchor_site"]))
			if not bool(reply.get("ok", false)):
				return reply
			_reserve_recovered_pu = int(_network.snapshot()["reserve_pu"]) - before
			_reserve_policy = "source_recharge"
			_phase = "stress_pending"
		"assurance_conserve":
			if _phase != "reserve_choice":
				return _fail("ASSURANCE_RESERVE_CHOICE_REQUIRED")
			_reserve_policy = "reserve_conservation"
			_phase = "stress_pending"
		"assurance_trip":
			if _phase != "stress_pending" or not _aftercare.closed():
				return _fail("ASSURANCE_FAULT_NOT_AUTHORIZED")
			reply = _network.host_transition(
				"trip_feeder", feeder, str(_spec["fault_signature"]))
			if not bool(reply.get("ok", false)):
				return reply
			_phase = "service_choice"
		"assurance_priority":
			if _phase != "service_choice" or not _critical_originally_live:
				return _fail("ASSURANCE_PRIORITY_REQUIRES_LIVE_CRITICAL")
			_service_policy = "critical_priority_recovery"
			_phase = "repair_pending"
		"assurance_managed":
			if _phase != "service_choice":
				return _fail("ASSURANCE_SERVICE_CHOICE_REQUIRED")
			_service_policy = "managed_critical_outage"
			_critical_pressure_pu = int(_spec["managed_pressure_pu"])
			_phase = "repair_pending"
		"assurance_clear":
			if _phase != "repair_pending":
				return _fail("ASSURANCE_REPAIR_NOT_AUTHORIZED")
			reply = _network.host_transition(
				"clear_fault", feeder, str(_spec["recovery_procedure"]))
			if not bool(reply.get("ok", false)):
				return reply
			_phase = "reset_pending"
		"assurance_reset":
			if _phase != "reset_pending":
				return _fail("ASSURANCE_RESET_NOT_READY")
			reply = _network.host_transition("reset_feeder", feeder)
			if not bool(reply.get("ok", false)):
				return reply
			_phase = "verification_pending"
		"assurance_verify":
			if _phase != "verification_pending" or not _source_valid():
				return _fail("ASSURANCE_LIVE_PROOF_REQUIRED")
			_phase = "verified"
		"assurance_signoff":
			if _phase != "verified" or not _source_valid():
				return _fail("ASSURANCE_STABLE_SERVICE_REQUIRED")
			_phase = "signed_off"
	_record(action)
	return {"ok": true, "snapshot": snapshot()}
