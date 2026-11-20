extends RefCounted
## EXP014 A06 — source-bound, host-owned operational consequences.
##
## All transitions use SessionHost's existing authenticated operate_worksite
## ingress and original SC_* stations. This opt-in ledger records operational
## liabilities in the active session only: it never writes production saves,
## awards credits, trusts client clocks, or grants physical-route certification.

const QUALIFICATION: String = "SOURCE_HEADLESS_ONLY_HUMAN_CONTROLLER_RELEASE_HELD"
const MODES: Array[String] = ["buffer", "managed"]
const ROUTES: Array[String] = ["priority", "resilience"]
const GUARDS: Array[String] = [
	"logistics_solved", "faults_solved", "balancing_solved", "consequences_solved"
]

var _spec: Dictionary = {}
var _phase: String = "inactive"
var _route: String = ""
var _approach: String = ""
var _mode: String = ""
var _tick: int = 0
var _witness_tick: int = -1
var _phase_tick: int = 0
var _reserve: int = 2
var _service_debt: int = 0
var _exposure_ticks: int = 0
var _incidents: int = 0
var _recoveries: int = 0
var _audit_count: int = 0
var _fault: String = ""
var _history: Array[Dictionary] = []
var _solved: bool = false


static func _reject(code: String) -> Dictionary:
	return {"ok": false, "code": "EXP014_A06_" + code}


## Bind to two independently source-pinned predecessor definitions, never
## to client data or an invented set of new task/interaction identifiers.
static func inspect(approach: Dictionary, contingency: Dictionary) -> Dictionary:
	if approach.get("qualification") != QUALIFICATION or \
			contingency.get("qualification") != QUALIFICATION:
		return _reject("QUALIFICATION_INVALID")
	for field: String in ["level_id", "location_id", "region_id", "source_risk",
			"source_task_ids", "targets"]:
		if approach.get(field) != contingency.get(field):
			return _reject("SOURCE_DRIFT_" + field)
	var level_id: String = str(approach.get("level_id", ""))
	var serial: int = int(level_id.trim_prefix("LV_")) if level_id.begins_with("LV_") else 0
	if serial < 1 or serial > 200 or level_id != "LV_%03d" % serial or \
			approach.get("region_id") != "REG_%02d" % (int((serial - 1) / 8) + 1):
		return _reject("ATLAS_IDENTITY_INVALID")
	var tasks: Variant = approach.get("source_task_ids")
	if not tasks is Array or tasks.size() != 5:
		return _reject("TASK_COUNT")
	for index: int in range(5):
		if str(tasks[index]) != "JOB_%03d_%d" % [serial, index + 1]:
			return _reject("TASK_SPLICE")
	var targets: Variant = approach.get("targets")
	if not targets is Dictionary or targets.size() != 3:
		return _reject("TARGET_COUNT")
	for letter: String in ["A", "B", "C"]:
		if targets.get(letter) != "SC_%03d_%s" % [serial, letter]:
			return _reject("TARGET_SPLICE")
	if contingency.get("recovery_target") != targets["C"]:
		return _reject("RECOVERY_SPLICE")
	var profile: Variant = approach.get("profile")
	if not profile is Dictionary or \
			not GUARDS.has(str(profile.get("guard", ""))) or \
			not ROUTES.has(str(profile.get("recommend", ""))):
		return _reject("POLICY_INVALID")
	return {"ok": true, "level_id": level_id, "qualification": QUALIFICATION}


func configure(approach: Dictionary, contingency: Dictionary) -> Dictionary:
	if not _spec.is_empty():
		return _reject("ALREADY_CONFIGURED")
	var audit: Dictionary = inspect(approach, contingency)
	if not bool(audit.get("ok", false)):
		return audit
	_spec = {
		"level_id": approach["level_id"],
		"location_id": approach["location_id"],
		"region_id": approach["region_id"],
		"source_risk": approach["source_risk"],
		"source_task_ids": approach["source_task_ids"].duplicate(true),
		"targets": approach["targets"].duplicate(true),
		"guard": str(approach["profile"]["guard"]),
		"recommended_route": str(approach["profile"]["recommend"]),
		"qualification": QUALIFICATION
	}
	return {"ok": true, "level_id": _spec["level_id"]}


func definition_snapshot() -> Dictionary:
	return _spec.duplicate(true)


func target_ids() -> Array:
	return _spec.get("targets", {}).values()


func _target(letter: String) -> String:
	return str((_spec["targets"] as Dictionary)[letter])


func started() -> bool:
	return _phase != "inactive"


func prepared() -> bool:
	return ["monitor", "audit_primary", "audit_secondary", "backlog", "signoff", "certified"].has(_phase)


func needs_action() -> bool:
	return ["plan", "audit_primary", "audit_secondary", "backlog", "signoff", "fault"].has(_phase)


func solved() -> bool:
	return _solved


func begin(recon: Dictionary) -> Dictionary:
	if _spec.is_empty() or started() or \
			not bool(recon.get("solved", false)) or \
			recon.get("level_id") != _spec["level_id"] or \
			recon.get("region_id") != _spec["region_id"] or \
			recon.get("observed_risk") != _spec["source_risk"] or \
			not ROUTES.has(str(recon.get("route", ""))) or \
			not ["guarded", "urgent"].has(str(recon.get("approach", ""))):
		return _reject("RECON_AUTHORITY_NOT_READY")
	_route = str(recon["route"])
	_approach = str(recon["approach"])
	_phase = "plan"
	_log("RECON_ACCEPTED")
	return {"ok": true, "state": snapshot()}


func _log(event: String) -> void:
	_history.append({"tick": _tick, "event": event, "phase": _phase})
	if _history.size() > 16:
		_history.pop_front()


func _fault_now(reason: String) -> Dictionary:
	_fault = reason
	_phase = "fault"
	_incidents += 1
	_service_debt = mini(6, _service_debt + 1)
	_log("FAULT_" + reason)
	return _reject(reason)


func _next() -> Dictionary:
	if _spec.is_empty() or _solved:
		return {}
	match _phase:
		"plan":
			return {"target": _target("A"), "action": "buffer_service",
				"alternative": "accept_managed_outage"}
		"audit_primary":
			return {"target": _target("B"), "action": "sample_service"}
		"audit_secondary":
			return {"target": _target("C"), "action": "crosscheck_service"}
		"backlog":
			return {"target": _target("B"), "action": "mitigate_backlog"}
		"signoff":
			return {"target": _target("A"), "action": "certify_service"}
		"fault":
			return {"target": _target("C"), "action": "recover"}
	return {}


func snapshot() -> Dictionary:
	var quality: int = maxi(0, 100 - _service_debt * 12 - _incidents * 9 -
		(8 if _approach == "urgent" else 0) -
		(6 if _route == "priority" else 0))
	return {"level_id": str(_spec.get("level_id", "")),
		"region_id": str(_spec.get("region_id", "")),
		"phase": _phase, "route": _route, "approach": _approach,
		"mode": _mode, "tick": _tick, "reserve": _reserve,
		"service_debt": _service_debt, "exposure_ticks": _exposure_ticks,
		"incidents": _incidents, "recoveries": _recoveries,
		"audit_count": _audit_count, "quality_index": quality,
		"fault": _fault, "solved": _solved, "next": _next(),
		"recovery_target": _target("C") if not _spec.is_empty() else "",
		"history": _history.duplicate(true),
		"qualification": QUALIFICATION}


## Timer comes exclusively from the host worksite tick callback. Debt is
## bounded; long missions do not become permanently unsolvable.
func advance(facts: Dictionary) -> void:
	if not started() or _solved:
		return
	_tick += 1
	if _phase == "fault":
		return
	if not bool(facts.get(str(_spec["guard"]), false)) and _phase != "plan":
		_fault_now("UPSTREAM_SUPPORT_LOST")
		return
	if _phase == "monitor":
		_exposure_ticks += 1
		if _exposure_ticks % 15 == 0:
			var liability: int = 1 if _mode == "managed" else \
				1 if _route == "priority" and _approach == "urgent" else 0
			_service_debt = mini(6, _service_debt + liability)
		if bool(facts.get("site_intervention_solved", false)) and \
				bool(facts.get("site_contingency_solved", false)):
			_phase = "audit_primary"
			_audit_count = 0
			_log("RESTORATION_READY_FOR_AUDIT")


## Only the existing host-owned SC_* interaction ingress may call this.
func operate(entity: String, action: String, facts: Dictionary) -> Dictionary:
	if _spec.is_empty() or not target_ids().has(entity):
		return _reject("UNKNOWN_TARGET")
	if not needs_action():
		return _reject("NO_ACTION_AVAILABLE")
	if _phase == "fault":
		if entity != _target("C") or action != "recover" or \
				not bool(facts.get(str(_spec["guard"]), false)):
			return _reject("RECOVERY_REQUIRED")
		_fault = ""
		_recoveries += 1
		_audit_count = 0
		_witness_tick = -1
		_phase = "audit_primary" if bool(facts.get("site_contingency_solved", false)) and \
			bool(facts.get("site_intervention_solved", false)) else "plan"
		_log("HOST_RECOVERED")
		return {"ok": true, "state": snapshot()}
	var next: Dictionary = _next()
	if entity != str(next.get("target", "")):
		return _reject("WRONG_STATION")
	if _phase == "plan":
		if not bool(facts.get("worksite_opened", false)) or \
				not bool(facts.get(str(_spec["guard"]), false)):
			return _reject("PRECONDITION_NOT_READY")
		if action == "buffer_service":
			if _reserve < 1:
				return _reject("RESERVE_EXHAUSTED")
			_reserve -= 1
			_mode = "buffer"
		elif action == "accept_managed_outage":
			_mode = "managed"
			_service_debt = mini(6, _service_debt + 2)
		else:
			return _reject("UNSUPPORTED_PLAN")
		_phase = "monitor"
		_phase_tick = _tick
		_log("PLAN_" + _mode.to_upper())
	elif _phase == "audit_primary":
		if action != "sample_service" or not bool(facts.get("site_contingency_solved", false)) or \
				not bool(facts.get("site_intervention_solved", false)):
			return _reject("RESTORATION_EVIDENCE_REQUIRED")
		_audit_count = 1
		_witness_tick = _tick
		_phase = "audit_secondary"
		_log("PRIMARY_SAMPLE")
	elif _phase == "audit_secondary":
		if action != "crosscheck_service":
			return _reject("FALSE_WITNESS")
		var gap: int = 2 if _route == "priority" else 4
		if _tick - _witness_tick < gap:
			return _reject("WITNESS_NOT_SETTLED")
		_audit_count = 2
		_phase_tick = _tick
		_phase = "backlog" if _service_debt > 0 else "signoff"
		_log("CROSSCHECK_ACCEPTED")
	elif _phase == "backlog":
		if action != "mitigate_backlog":
			return _reject("BACKLOG_UNMITIGATED")
		# Operational debt is an actual extra intervention, not a cosmetic
		# score deduction. Residual liability is retained as an outcome.
		_service_debt = maxi(0, _service_debt - 3)
		_phase_tick = _tick
		_phase = "backlog" if _service_debt > 0 else "signoff"
		_log("BACKLOG_MITIGATED")
	elif _phase == "signoff":
		if action != "certify_service" or not bool(facts.get("site_contingency_solved", false)) or \
				not bool(facts.get("site_intervention_solved", false)) or \
				str(facts.get("worksite_route", "")) != _route:
			return _reject("SOURCE_ROUTE_OR_RESTORATION_UNVERIFIED")
		if _audit_count != 2 or _tick - _phase_tick < 3:
			return _reject("FINAL_SETTLING_REQUIRED")
		_solved = true
		_phase = "certified"
		_log("SERVICE_CONSEQUENCES_CERTIFIED")
	else:
		return _reject("INVALID_PHASE")
	return {"ok": true, "state": snapshot()}
