extends RefCounted
## EXP015 A04: opt-in post-finale stress, standby choice, and source-proven recovery.
## Only trusted SessionHost worksite actions can invoke this controller.
## Uses the real A09 regional graph, reserve and break-before-make transitions.
## No new RPC, synthetic EXP04 receipt, reward, electrical solver or save schema.

const Atlas := preload("res://scripts/world/dispatch_atlas.gd")
const Network := preload("res://scripts/gameplay/expedition_regional_network.gd")
const Finale := preload("res://scripts/gameplay/expedition_regional_finales.gd")

const BOOK_PATH: String = "res://scenes/expeditions/region_aftercare_exp015_a04.json"
const AUTHORITY: String = "EXP015_A04_ORIGINAL_POST_FINALE_FEEDER_STRESS"
const QUALIFICATION: String = "SOURCE_HEADLESS_ONLY_HUMAN_CONTROLLER_RELEASE_HELD"
const RISK_PROTOCOLS: Dictionary = {
	"depth": ["trench_dryness_retest", 3],
	"conductivity": ["insulation_requalification", 5],
	"mechanical": ["load_latch_reinspection", 2],
	"structure": ["support_brace_reinspection", 4],
	"weather": ["exposed_span_clearance", 3]
}
const ACTIONS: Array[String] = [
	"aftercare_assess", "aftercare_trip", "aftercare_transfer", "aftercare_managed",
	"aftercare_clear", "aftercare_release", "aftercare_reset",
	"aftercare_verify", "aftercare_signoff"
]

var _recipe: Dictionary = {}
var _network: Network
var _finale: Finale
var _phase: String = "inactive"
var _route: String = ""
var _original_shelter_live: bool = false
var _managed_pressure_pu: int = 0
var _reserve_consumed_pu: int = 0
var _events: Array[Dictionary] = []


static func _fail(code: String) -> Dictionary:
	return {"ok": false, "code": code}


static func load_book() -> Dictionary:
	if not FileAccess.file_exists(BOOK_PATH):
		return {}
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(BOOK_PATH))
	return value if value is Dictionary else {}


static func entry_for(book: Dictionary, site_id: String) -> Dictionary:
	for value: Variant in book.get("entries", []):
		if value is Dictionary and value.get("finale_site_id") == site_id:
			return (value as Dictionary).duplicate(true)
	return {}


## Validate every authored asset against A03 and the original A09 topology.
## No client recipe or self-declared source fingerprint is accepted.
static func inspect(atlas: Dictionary, book: Dictionary,
		networks: Dictionary, finales: Dictionary) -> Dictionary:
	if book.get("schema_version") != 1 or book.get("authority") != AUTHORITY or \
			book.get("qualification") != QUALIFICATION or \
			book.get("predecessor") != "EXP015_A03" or \
			book.get("original_campaign_unchanged") != true or \
			not book.get("entries") is Array or book["entries"].size() != 25 or \
			not networks.get("regions") is Array or networks["regions"].size() != 25 or \
			not bool(Finale.inspect(atlas, finales, networks).get("ok", false)):
		return _fail("AFTERCARE_SOURCE_AUTHORITY")
	var seen: Dictionary = {}
	for i: int in range(25):
		var region: Dictionary = networks["regions"][i]
		var finale: Dictionary = finales["entries"][i]
		var item: Dictionary = book["entries"][i]
		var risk: String = str(region["risk_class"])
		var site: String = str(region["source_sites"][7]["site_id"])
		if not RISK_PROTOCOLS.has(risk) or seen.has(site) or \
				item.get("region_id") != region["region_id"] or \
				item.get("finale_site_id") != site or \
				item.get("shelter_service_site") != region["shelter_service_site"] or \
				item.get("critical_service_site") != region["critical_service_site"] or \
				item.get("recovery_feeder_id") != finale["shelter_feeder_id"] or \
				item.get("standby_tie_id") != finale["shelter_standby_tie_id"] or \
				item.get("fault_signature") != region["fault_signature"] or \
				item.get("recovery_procedure") != region["recovery_procedure"] or \
				item.get("risk_class") != risk or \
				item.get("retest_protocol") != RISK_PROTOCOLS[risk][0] or \
				item.get("managed_dark_pressure_pu") != RISK_PROTOCOLS[risk][1] or \
				item.get("source_qualification") != QUALIFICATION:
			return _fail("AFTERCARE_ORIGINAL_ASSET_MISMATCH")
		if not bool(Network.inspect_region(atlas, region).get("ok", false)):
			return _fail("AFTERCARE_NETWORK_INVALID")
		seen[site] = true
	return {"ok": true, "regions": seen.size(), "risk_families": RISK_PROTOCOLS.size()}


func configure(recipe: Dictionary, network: Network, finale: Finale) -> Dictionary:
	if not _recipe.is_empty() or network == null or finale == null:
		return _fail("AFTERCARE_ALREADY_CONFIGURED_OR_MISSING_HOST")
	var book: Dictionary = load_book()
	var networks: Dictionary = Network.load_book()
	var finales: Dictionary = Finale.load_book()
	var verdict: Dictionary = inspect(Atlas.load_catalog(), book, networks, finales)
	if not bool(verdict.get("ok", false)):
		return verdict
	var trusted: Dictionary = entry_for(book, str(recipe.get("finale_site_id", "")))
	if trusted.is_empty() or trusted != recipe:
		return _fail("AFTERCARE_UNTRUSTED_RECIPE")
	var state: Dictionary = network.snapshot()
	if state.get("region_id") != trusted["region_id"] or \
			state.get("level_id") != trusted["finale_site_id"] or \
			finale.definition_snapshot() != Finale.entry_for(
				finales, str(trusted["finale_site_id"])):
		return _fail("AFTERCARE_HOST_CONTEXT_MISMATCH")
	_recipe = trusted.duplicate(true)
	_network = network
	_finale = finale
	_phase = "awaiting_finale"
	return {"ok": true, "region_id": _recipe["region_id"]}


func definition_snapshot() -> Dictionary:
	return _recipe.duplicate(true)


## Preserve finite reserve while an opted-in post-finale decision is underway.
## A03 independently protects this incident's feeder and standby tie.
func protects_original_action(action: String) -> bool:
	return not _recipe.is_empty() and _phase != "awaiting_finale" and \
		action == "regional_recharge"


func _source_valid() -> bool:
	if _network == null or _finale == null or _recipe.is_empty():
		return false
	var state: Dictionary = _network.snapshot()
	if state.get("region_id") != _recipe["region_id"] or \
			state.get("level_id") != _recipe["finale_site_id"] or \
			not _finale.closed():
		return false
	var feeder: Dictionary = state["feeders"][str(_recipe["recovery_feeder_id"])]
	var tie: Dictionary = state["ties"][str(_recipe["standby_tie_id"])]
	return not bool(feeder["isolated"]) and str(feeder["fault"]) == "" and \
		not bool(tie["engaged"]) and \
		bool(state["sites"][str(_recipe["shelter_service_site"])]["energized"]) == \
		_original_shelter_live


func closed() -> bool:
	return _phase == "signed_off" and _source_valid()


func snapshot() -> Dictionary:
	if _recipe.is_empty():
		return {}
	var state: Dictionary = _network.snapshot()
	return {
		"region_id": _recipe["region_id"],
		"finale_site_id": _recipe["finale_site_id"],
		"retest_protocol": _recipe["retest_protocol"],
		"phase": _phase, "recovery_route": _route,
		"shelter_initially_live": _original_shelter_live,
		"shelter_now_live": bool(state["sites"][str(_recipe["shelter_service_site"])]["energized"]),
		"reserve_consumed_pu": _reserve_consumed_pu,
		"managed_dark_pressure_pu": _managed_pressure_pu,
		"source_proof_current": _source_valid() if _phase == "verified" or _phase == "signed_off" else false,
		"closed": closed(), "events": _events.duplicate(true),
		"qualification": QUALIFICATION
	}


func _record(action: String) -> void:
	_events.append({"sequence": _events.size() + 1, "action": action,
		"phase": _phase, "route": _route})


## The trusted SessionHost worksite board is the only ingress. All transitions
## use A09's existing real feeder fault, reserve and interlock operations.
func operate(action: String) -> Dictionary:
	if _recipe.is_empty():
		return _fail("AFTERCARE_NOT_CONFIGURED")
	if not ACTIONS.has(action):
		return _fail("AFTERCARE_UNKNOWN_ACTION")
	var state: Dictionary = _network.snapshot()
	if state.get("region_id") != _recipe["region_id"] or \
			state.get("level_id") != _recipe["finale_site_id"]:
		return _fail("AFTERCARE_DISPATCH_CHANGED")
	var feeder: String = str(_recipe["recovery_feeder_id"])
	var tie: String = str(_recipe["standby_tie_id"])
	var step: Dictionary = {}
	match action:
		"aftercare_assess":
			if _phase != "awaiting_finale" or not _finale.closed():
				return _fail("AFTERCARE_FINALE_SIGNOFF_REQUIRED")
			_original_shelter_live = bool(
				state["sites"][str(_recipe["shelter_service_site"])]["energized"])
			_phase = "stress_pending"
		"aftercare_trip":
			if _phase != "stress_pending" or not _finale.closed():
				return _fail("AFTERCARE_STRESS_NOT_AUTHORIZED")
			step = _network.host_transition(
				"trip_feeder", feeder, str(_recipe["fault_signature"]))
			if not bool(step.get("ok", false)):
				return step
			_phase = "service_choice"
		"aftercare_transfer":
			if _phase != "service_choice":
				return _fail("AFTERCARE_SERVICE_CHOICE_REQUIRED")
			var before: int = int(state["reserve_pu"])
			step = _network.host_transition("engage_tie", tie)
			if not bool(step.get("ok", false)):
				return step
			_reserve_consumed_pu = before - int(_network.snapshot()["reserve_pu"])
			_route = "standby_transfer"
			_phase = "repair_pending"
		"aftercare_managed":
			if _phase != "service_choice" or bool(state["ties"][tie]["engaged"]):
				return _fail("AFTERCARE_MANAGED_CHOICE_DENIED")
			_route = "managed_outage"
			_managed_pressure_pu = int(_recipe["managed_dark_pressure_pu"]) \
				if not bool(state["sites"][str(_recipe["shelter_service_site"])]["energized"]) else 0
			_phase = "repair_pending"
		"aftercare_clear":
			if _phase != "repair_pending":
				return _fail("AFTERCARE_REPAIR_NOT_READY")
			step = _network.host_transition(
				"clear_fault", feeder, str(_recipe["recovery_procedure"]))
			if not bool(step.get("ok", false)):
				return step
			_phase = "transfer_release"
		"aftercare_release":
			if _phase != "transfer_release":
				return _fail("AFTERCARE_RELEASE_NOT_READY")
			if _route == "standby_transfer":
				step = _network.host_transition("release_tie", tie)
				if not bool(step.get("ok", false)):
					return step
			elif bool(state["ties"][tie]["engaged"]):
				return _fail("AFTERCARE_UNEXPECTED_LIVE_TIE")
			_phase = "feeder_reset"
		"aftercare_reset":
			if _phase != "feeder_reset":
				return _fail("AFTERCARE_RESET_NOT_READY")
			step = _network.host_transition("reset_feeder", feeder)
			if not bool(step.get("ok", false)):
				return step
			_phase = "verification_pending"
		"aftercare_verify":
			if _phase != "verification_pending" or not _source_valid():
				return _fail("AFTERCARE_LIVE_PROOF_MISSING")
			_phase = "verified"
		"aftercare_signoff":
			if _phase != "verified" or not _source_valid():
				return _fail("AFTERCARE_RESTORATION_NOT_STABLE")
			_phase = "signed_off"
	_record(action)
	return {"ok": true, "snapshot": snapshot()}
