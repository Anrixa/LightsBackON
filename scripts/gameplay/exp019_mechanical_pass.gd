extends RefCounted
## EXP019 A05 — host-only, opt-in procedural proof on an EXISTING WO board.
## The 200 unlabelled sequences are distinct by the order and branching of
## operational interlocks, never by level name, cosmetic signature or timer.
const RiskProfiles := preload("res://scripts/world/expedition_environment_feedback.gd")
const Physical := preload("res://scripts/world/exp019_physical_worksite.gd")
const QUALIFICATION: String = "SOURCE_HEADLESS_200_DISTINCT_HOST_MECHANICS_RELEASE_HELD"
const OPERATIONS: Array[String] = ["secure", "divert", "refit", "stabilize"]
const INITIAL_KITS: int = 3
const INITIAL_RESERVE: int = 2
const COSTS: Dictionary = {
	"depth": {"kits":1, "reserve":1, "stability":1},
	"conductivity": {"kits":2, "reserve":1, "stability":2},
	"mechanical": {"kits":1, "reserve":2, "stability":1},
	"structure": {"kits":2, "reserve":2, "stability":2},
	"weather": {"kits":1, "reserve":1, "stability":2}
}

var _profile: Dictionary = {}
var _done: Array[String] = []
var _kits: int = INITIAL_KITS
var _reserve: int = INITIAL_RESERVE
var _protection: int = 1
var _stability: int = 0
var _recovered: int = 0
var _fault: String = ""
var _history: Array[Dictionary] = []
var _revision: int = 0


static func _fail(code: String) -> Dictionary:
	return {"ok": false, "code": code, "qualification": QUALIFICATION}


## Procedure topology is driven by the source's real regional hazard class.
## Trace always precedes intervention; proof always follows intervention.
## Per-class permutations of four physically different operations (24) plus
## three guarded resource branches (72) supply >56 noncosmetic profiles even
## in the largest (depth) risk family. Source-independent topology remains unique.
static func inspect(plan: Dictionary) -> Dictionary:
	if not Physical.inspect(plan).get("ok", false):
		return _fail("EXP019_A05_PHYSICAL_SOURCE_REQUIRED")
	var region: String = str(plan["region_id"])
	if not RiskProfiles.PROFILES.has(region):
		return _fail("EXP019_A05_UNKNOWN_SOURCE_RISK")
	var risk: String = str(RiskProfiles.PROFILES[region]["apparatus"])
	if not COSTS.has(risk):
		return _fail("EXP019_A05_UNKNOWN_RISK_GUARD")
	var serial: int = int(plan["serial"])
	var region_index: int = int((serial - 1) / 8) + 1
	var ordinal: int = (serial - 1) % 8
	for earlier: int in range(1, region_index):
		var other: String = "REG_%02d" % earlier
		if str(RiskProfiles.PROFILES[other]["apparatus"]) == risk:
			ordinal += 8
	var pick: int = ordinal % 24
	var branch: int = int(ordinal / 24)
	if branch > 2:
		return _fail("EXP019_A05_UNSUPPORTED_RESOURCE_BRANCH")
	var pool: Array[String] = OPERATIONS.duplicate()
	var stages: Array[String] = ["trace"]
	for weight: int in [6, 2, 1, 1]:
		var index: int = int(pick / weight)
		pick = pick % weight
		stages.append(pool[index])
		pool.remove_at(index)
	if branch == 1:
		stages.append("recheck")
	elif branch == 2:
		stages.append("protect")
	stages.append("prove")
	var structural_key: String = JSON.stringify({
		"risk_guard": risk, "stages": stages,
		"resource_costs": COSTS[risk], "host_guards": [
			"GRID_VERIFIED", "WORKSITE_SOLVED", "HAZARD_SAFE",
			"WEST_RESTORED", "METER_PROOF"],
		"fault_recovery": "RESTART_INSPECTION"
	})
	return {"ok": true, "level_id": plan["id"],
		"location_id": plan["location_id"], "region_id": region,
		"source_risk": plan["hazard"], "risk_class": risk,
		"resource_costs": COSTS[risk], "sequence": stages,
		"branch": branch, "structure": structural_key,
		"qualification": QUALIFICATION}

func configure(plan: Dictionary) -> Dictionary:
	if not _profile.is_empty():
		return _fail("EXP019_A05_ALREADY_CONFIGURED")
	var result: Dictionary = inspect(plan)
	if result.get("ok", false):
		_profile = result
	return result


func solved() -> bool:
	return not _profile.is_empty() and _fault == "" and \
			_done.size() == (_profile["sequence"] as Array).size()


func _next() -> String:
	if _profile.is_empty() or solved():
		return ""
	var seq: Array = _profile["sequence"]
	return str(seq[_done.size()]) if _done.size() < seq.size() else ""


func next_operation() -> Dictionary:
	if _fault != "":
		return {"action": "recover", "required": "HOST SAFE"}
	if solved() or _profile.is_empty():
		return {}
	return {"action": _next(), "required": "HOST VERIFIED"}


static func _live(facts: Dictionary) -> bool:
	return bool(facts.get("grid_verified", false)) and \
			bool(facts.get("worksite_solved", false)) and \
			bool(facts.get("environment_safe", false)) and \
			bool(facts.get("east_enabled", false)) and \
			bool(facts.get("west_restored", false))


## Every step consumes/updates host-owned procedural resources and cannot be
## completed by the client sending task progress, arbitrary IDs or elapsed time.
func operate(action: String, facts: Dictionary) -> Dictionary:
	if _profile.is_empty():
		return _fail("EXP019_A05_NOT_CONFIGURED")
	# Recovery is also an authority-bearing mutation. Verify that the caller's
	# host-owned hazard classification still matches the authored source before
	# any fault, stock or progression state can be reset.
	if str(facts.get("risk_class", "")) != str(_profile["risk_class"]):
		return _fail("EXP019_A05_HOST_SOURCE_RISK_MISMATCH")
	if action == "recover":
		if _fault == "" or not _live(facts):
			return _fail("EXP019_A05_NO_SAFE_RECOVERY")
		_fault = ""
		_done.clear()
		_kits = INITIAL_KITS
		_reserve = INITIAL_RESERVE
		_protection = 1
		_stability = 0
		_recovered += 1
		_revision += 1
		_history.append({"action": action, "revision": _revision})
		return {"ok": true, "recovery": true, "revision": _revision}
	if solved():
		return _fail("EXP019_A05_ALREADY_PROVED")
	if _fault != "":
		return _fail("EXP019_A05_RECOVERY_REQUIRED")
	if action != _next():
		return _fail("EXP019_A05_WRONG_AUTHORED_STEP")
	if not _live(facts):
		_fault = "LIVE_WORKSITE_INVARIANT_LOST"
		_revision += 1
		return _fail("EXP019_A05_HOST_REVERIFICATION_REQUIRED")
	var costs: Dictionary = _profile["resource_costs"]
	match action:
		"trace":
			_stability += 1
		"secure":
			_stability += 2
		"divert":
			if _reserve < int(costs["reserve"]):
				return _fail("EXP019_A05_RESERVE_EXHAUSTED")
			_reserve -= int(costs["reserve"])
		"refit":
			if _kits < int(costs["kits"]):
				return _fail("EXP019_A05_MATERIALS_EXHAUSTED")
			_kits -= int(costs["kits"])
		"stabilize":
			_stability += int(costs["stability"])
		"prove":
			if _stability < 4 or not bool(facts.get("diagnosis_confirmed", false)):
				return _fail("EXP019_A05_METER_PROOF_NOT_READY")
		"recheck":
			if not bool(facts.get("diagnosis_confirmed", false)) or _kits < 1:
				return _fail("EXP019_A05_RECHECK_STOCK_OR_EVIDENCE")
			_kits -= 1
		"protect":
			if _protection < 1 or not bool(facts.get("environment_safe", false)):
				return _fail("EXP019_A05_PROTECTION_STOCK_OR_HAZARD")
			_protection -= 1
		_:
			return _fail("EXP019_A05_BAD_SOURCE_ACTION")
	_done.append(action)
	_revision += 1
	_history.append({"action": action, "revision": _revision,
		"kits_after": _kits, "reserve_after": _reserve})
	return {"ok": true, "action": action, "revision": _revision,
		"solved": solved(), "remaining": (_profile["sequence"] as Array).size() - _done.size()}


func snapshot() -> Dictionary:
	return {"level_id": str(_profile.get("level_id", "")),
		"source_structure": str(_profile.get("structure", "")),
		"sequence": (_profile.get("sequence", []) as Array).duplicate(),
		"completed": _done.duplicate(), "next": next_operation(),
		"kits": _kits, "reserve": _reserve, "protection": _protection,
		"risk_class": str(_profile.get("risk_class", "")),
		"stability": _stability,
		"fault": _fault, "recoveries": _recovered, "revision": _revision,
		"solved": solved(), "history": _history.duplicate(true),
		"qualification": QUALIFICATION}
