extends RefCounted
## EXP015 A10 — finite original-regional service debt settlement at 25 finales.
## No client-supplied debt/receipt, reward, new RPC, electrical source or save.
const Atlas := preload("res://scripts/world/dispatch_atlas.gd")
const Network := preload("res://scripts/gameplay/expedition_regional_network.gd")
const Assurance := preload("res://scripts/gameplay/expedition_regional_assurance.gd")

const BOOK_PATH: String = "res://scenes/expeditions/region_settlements_exp015_a10.json"
const AUTHORITY: String = "EXP015_A10_SOURCE_BOUND_FINITE_DEBT_SETTLEMENT"
const QUALIFICATION: String = "SOURCE_HEADLESS_ONLY_HUMAN_CONTROLLER_RELEASE_HELD"
const RISKS: Dictionary = {
	"depth": "settle_dry_feeder_audit",
	"conductivity": "settle_insulation_audit",
	"mechanical": "settle_interlock_audit",
	"structure": "settle_structure_audit",
	"weather": "settle_exposure_audit"
}
const ACTIONS: Array[String] = [
	"settlement_audit", "settlement_pay", "settlement_defer",
	"settlement_clear", "settlement_verify", "settlement_signoff"
]

var _recipe: Dictionary = {}
var _network: Network
var _assurance: Assurance
var _phase: String = "inactive"
var _policy: String = ""
var _opening_reserve: int = 0
var _opening_debt: int = 0
var _closing_reserve: int = 0
var _closing_debt: int = 0
var _events: Array[Dictionary] = []


static func _fail(code: String) -> Dictionary:
	return {"ok": false, "code": code}


static func load_book() -> Dictionary:
	if not FileAccess.file_exists(BOOK_PATH):
		return {}
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(BOOK_PATH))
	return data if data is Dictionary else {}


static func entry_for(book: Dictionary, site_id: String) -> Dictionary:
	for raw: Variant in book.get("entries", []):
		if raw is Dictionary and raw.get("finale_site_id") == site_id:
			return (raw as Dictionary).duplicate(true)
	return {}


static func inspect(atlas: Dictionary, book: Dictionary, networks: Dictionary,
		assurance: Dictionary) -> Dictionary:
	if book.get("schema_version") != 1 or book.get("authority") != AUTHORITY or \
			book.get("predecessor") != "EXP015_A09" or \
			book.get("qualification") != QUALIFICATION or \
			book.get("legacy_campaign_contracts_unchanged") != true or \
			book.get("original_settlement_sites") != 25 or \
			not book.get("entries") is Array or book["entries"].size() != 25 or \
			not networks.get("regions") is Array or networks["regions"].size() != 25 or \
			not assurance.get("entries") is Array or assurance["entries"].size() != 25:
		return _fail("SETTLEMENT_SOURCE_AUTHORITY")
	var seen: Dictionary = {}
	var risk_set: Dictionary = {}
	for i: int in range(25):
		var region: Dictionary = networks["regions"][i]
		var prior: Dictionary = assurance["entries"][i]
		var recipe: Dictionary = book["entries"][i]
		var finale: String = str(region["shelter_service_site"])
		var site: Dictionary = {}
		for source: Dictionary in region["source_sites"]:
			if source["site_id"] == finale:
				site = source
		var risk: String = str(region["risk_class"])
		if not bool(Network.inspect_region(atlas, region).get("ok", false)) or \
				site.is_empty() or site["campaign_role"] != "finale" or \
				not RISKS.has(risk) or seen.has(finale) or \
				prior.get("finale_site_id") != finale or \
				recipe.get("region_id") != region["region_id"] or \
				recipe.get("finale_site_id") != finale or \
				recipe.get("root_source_site_id") != region["root_source_id"] or \
				recipe.get("reserve_anchor_site_id") != region["reserve_anchor_site"] or \
				recipe.get("critical_service_site_id") != region["critical_service_site"] or \
				recipe.get("risk_class") != risk or \
				recipe.get("audit_proof") != RISKS[risk] or \
				recipe.get("original_finale_task_ids") != site["source_task_ids"] or \
				recipe.get("initial_reserve_pu") != region["initial_reserve_pu"] or \
				recipe.get("qualification") != QUALIFICATION:
			return _fail("SETTLEMENT_ORIGINAL_SOURCE_MISMATCH")
		seen[finale] = true
		risk_set[risk] = true
	if seen.size() != 25 or risk_set.size() != 5:
		return _fail("SETTLEMENT_SOURCE_COVERAGE")
	return {"ok": true, "original_finales": seen.size(), "risk_classes": risk_set.size()}


func configure(recipe: Dictionary, network: Network, assurance: Assurance) -> Dictionary:
	if not _recipe.is_empty() or network == null or assurance == null:
		return _fail("SETTLEMENT_MISSING_HOST_AUTHORITY")
	var source: Dictionary = load_book()
	var checked: Dictionary = inspect(Atlas.load_catalog(), source,
		Network.load_book(), Assurance.load_book())
	if not bool(checked.get("ok", false)):
		return checked
	var trusted: Dictionary = entry_for(source, str(recipe.get("finale_site_id", "")))
	if trusted.is_empty() or recipe != trusted:
		return _fail("SETTLEMENT_UNTRUSTED_SOURCE")
	var current: Dictionary = network.snapshot()
	if current.get("level_id") != trusted["finale_site_id"] or \
			current.get("region_id") != trusted["region_id"] or \
			assurance.definition_snapshot().get("finale_site_id") != trusted["finale_site_id"]:
		return _fail("SETTLEMENT_DISPATCH_SOURCE_MISMATCH")
	_recipe = trusted
	_network = network
	_assurance = assurance
	_phase = "audit_pending"
	return {"ok": true, "original_finale": trusted["finale_site_id"]}


func definition_snapshot() -> Dictionary:
	return _recipe.duplicate(true)


func protects_original_action(action: String) -> bool:
	return not _recipe.is_empty() and action == "regional_recharge"


func _source_valid() -> bool:
	if _recipe.is_empty() or _network == null or _assurance == null or \
			not _assurance.closed() or _policy.is_empty():
		return false
	var state: Dictionary = _network.snapshot()
	var condition: Dictionary = _network.site_conditions()
	if state.get("level_id") != _recipe["finale_site_id"] or \
			state.get("region_id") != _recipe["region_id"] or \
			not bool(state["sites"][str(_recipe["root_source_site_id"])]["restored"]) or \
			int(state["reserve_pu"]) != _closing_reserve or \
			int(condition["service_debt"]) != _closing_debt or \
			_closing_reserve < 0 or _closing_debt < 0:
		return false
	if _policy == "finite_settlement":
		return _opening_debt > 0 and _closing_debt == 0 and \
			_closing_reserve == _opening_reserve - _opening_debt and \
			bool(state["sites"][str(_recipe["reserve_anchor_site_id"])]["energized"])
	if _policy == "managed_deferral":
		return _opening_debt > 0 and _closing_debt == _opening_debt and \
			_closing_reserve == _opening_reserve
	return _policy == "no_debt" and _opening_debt == 0 and \
		_closing_debt == 0 and _closing_reserve == _opening_reserve


func closed() -> bool:
	return _phase == "signed_off" and _source_valid()


func snapshot() -> Dictionary:
	if _recipe.is_empty():
		return {}
	var state: Dictionary = _network.snapshot()
	return {"region_id": _recipe["region_id"],
		"finale_site_id": _recipe["finale_site_id"], "phase": _phase,
		"source_risk_proof": _recipe["audit_proof"],
		"reserve_anchor": _recipe["reserve_anchor_site_id"],
		"reserve_anchor_energized": bool(state["sites"][
			str(_recipe["reserve_anchor_site_id"])]["energized"]),
		"opening_reserve_pu": _opening_reserve, "opening_debt_pu": _opening_debt,
		"closing_reserve_pu": _closing_reserve, "closing_debt_pu": _closing_debt,
		"policy": _policy, "closed": closed(),
		"events": _events.duplicate(true), "qualification": QUALIFICATION}


func operate(action: String) -> Dictionary:
	if _recipe.is_empty():
		return _fail("SETTLEMENT_NOT_CONFIGURED")
	if not ACTIONS.has(action) and \
			action != "settlement_proof:" + str(_recipe["audit_proof"]):
		return _fail("SETTLEMENT_UNKNOWN_OR_FORGED_ACTION")
	var state: Dictionary = _network.snapshot()
	if state.get("level_id") != _recipe["finale_site_id"] or \
			state.get("region_id") != _recipe["region_id"]:
		return _fail("SETTLEMENT_DISPATCH_CHANGED")
	match action:
		"settlement_audit":
			if _phase != "audit_pending" or not _assurance.closed() or \
					not bool(state["sites"][str(_recipe["root_source_site_id"])]["restored"]):
				return _fail("SETTLEMENT_ASSURANCE_AND_ROOT_REQUIRED")
			_opening_reserve = int(state["reserve_pu"])
			_opening_debt = int(_network.site_conditions()["service_debt"])
			_phase = "risk_proof"
		"settlement_pay":
			if _phase != "choice_pending" or _opening_debt <= 0:
				return _fail("SETTLEMENT_OUTSTANDING_DEBT_REQUIRED")
			var committed: Dictionary = _network.host_transition(
				"retire_service_debt", str(_recipe["reserve_anchor_site_id"]))
			if not bool(committed.get("ok", false)):
				return committed
			_policy = "finite_settlement"
			_closing_reserve = int(_network.snapshot()["reserve_pu"])
			_closing_debt = int(_network.site_conditions()["service_debt"])
			_phase = "verification_pending"
		"settlement_defer":
			if _phase != "choice_pending" or _opening_debt <= 0:
				return _fail("SETTLEMENT_OUTSTANDING_DEBT_REQUIRED")
			_policy = "managed_deferral"
			_closing_reserve = int(state["reserve_pu"])
			_closing_debt = int(_network.site_conditions()["service_debt"])
			_phase = "verification_pending"
		"settlement_clear":
			if _phase != "choice_pending" or _opening_debt != 0:
				return _fail("SETTLEMENT_ZERO_DEBT_REQUIRED")
			_policy = "no_debt"
			_closing_reserve = int(state["reserve_pu"])
			_closing_debt = 0
			_phase = "verification_pending"
		"settlement_verify":
			if _phase != "verification_pending" or not _source_valid():
				return _fail("SETTLEMENT_REAL_LEDGER_PROOF_REQUIRED")
			_phase = "verified"
		"settlement_signoff":
			if _phase != "verified" or not _source_valid():
				return _fail("SETTLEMENT_STABLE_LEDGER_REQUIRED")
			_phase = "signed_off"
		_:
			if _phase != "risk_proof":
				return _fail("SETTLEMENT_AUDIT_REQUIRED")
			_phase = "choice_pending"
	_events.append({"sequence": _events.size() + 1, "action": action,
		"phase": _phase, "policy": _policy})
	return {"ok": true, "snapshot": snapshot()}
