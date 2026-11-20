extends RefCounted
## EXP014 A07 — host-authoritative environmental hazard encounter.
##
## Opt-in source/headless candidate. Uses A06's immutable source/risk identity,
## the existing authenticated SC_* stations and SessionHost's host ticks.
## This is NOT a player collision, reachability, GPU or real-world safety model.

const QUALIFICATION: String = "SOURCE_HEADLESS_ONLY_HUMAN_CONTROLLER_RELEASE_HELD"
const MODES: Array[String] = ["engineered", "temporary"]
const ROUTES: Array[String] = ["priority", "resilience"]
const GUARDS: Array[String] = [
	"faults_solved", "logistics_solved", "balancing_solved", "consequences_solved"
]

## Each risk has an independently ordered, differently guarded mitigation
## graph. The functional profile (not action names / clocks) is the signature.
const PROFILES: Dictionary = {
	"depth": {
		"entry":"B", "restore":"C", "guard":"logistics_solved",
		"sequence":[
			{"station":"C", "action":"survey_waterline", "guard":"logistics_solved", "gap":0},
			{"station":"A", "action":"drain_feeder", "guard":"balancing_solved", "gap":3},
			{"station":"B", "action":"verify_drain", "guard":"faults_solved", "gap":3}],
		"settle":3, "pressure_period":24
	},
	"conductivity": {
		"entry":"C", "restore":"B", "guard":"faults_solved",
		"sequence":[
			{"station":"A", "action":"survey_contact", "guard":"faults_solved", "gap":0},
			{"station":"C", "action":"isolate_conductor", "guard":"logistics_solved", "gap":4}],
		"settle":4, "pressure_period":28
	},
	"mechanical": {
		"entry":"A", "restore":"B", "guard":"balancing_solved",
		"sequence":[
			{"station":"B", "action":"brake_drive", "guard":"balancing_solved", "gap":0},
			{"station":"C", "action":"clear_interlock", "guard":"faults_solved", "gap":3},
			{"station":"A", "action":"verify_latch", "guard":"logistics_solved", "gap":2}],
		"settle":5, "pressure_period":30
	},
	"structure": {
		"entry":"B", "restore":"A", "guard":"consequences_solved",
		"sequence":[
			{"station":"A", "action":"assess_span", "guard":"consequences_solved", "gap":0},
			{"station":"B", "action":"brace_anchor", "guard":"logistics_solved", "gap":5},
			{"station":"C", "action":"proof_clearance", "guard":"balancing_solved", "gap":3}],
		"settle":5, "pressure_period":26
	},
	"weather": {
		"entry":"C", "restore":"A", "guard":"faults_solved",
		"sequence":[
			{"station":"B", "action":"read_surge", "guard":"faults_solved", "gap":0},
			{"station":"A", "action":"shield_circuit", "guard":"balancing_solved", "gap":2},
			{"station":"C", "action":"verify_shield", "guard":"consequences_solved", "gap":4}],
		"settle":4, "pressure_period":22
	}
}

var _spec: Dictionary = {}
var _profile: Dictionary = {}
var _phase: String = "dormant"
var _mode: String = ""
var _route: String = ""
var _outcome_mode: String = ""
var _tick: int = 0
var _step: int = 0
var _last_proof: int = -1
var _settling_start: int = -1
var _exposure: int = 0
var _pressure: int = 0
var _materials: int = 2
var _liability: int = 0
var _fault: String = ""
var _failures: int = 0
var _recoveries: int = 0
var _post_step: int = 0
var _solved: bool = false
var _history: Array[Dictionary] = []


static func _reject(code: String) -> Dictionary:
	return {"ok": false, "code": "EXP014_A07_" + code, "qualification": QUALIFICATION}


static func inspect(approach: Dictionary, consequences: Dictionary,
		contingency: Dictionary) -> Dictionary:
	if approach.get("qualification") != QUALIFICATION or \
			consequences.get("qualification") != QUALIFICATION or \
			contingency.get("qualification") != QUALIFICATION:
		return _reject("SOURCE_QUALIFICATION")
	for field: String in ["level_id", "location_id", "region_id",
			"source_risk", "source_task_ids", "targets"]:
		if approach.get(field) != consequences.get(field) or \
				approach.get(field) != contingency.get(field):
			return _reject("SOURCE_DRIFT_" + field)
	var level: String = str(approach.get("level_id", ""))
	var number: int = int(level.trim_prefix("LV_")) if level.begins_with("LV_") else 0
	if number < 1 or number > 200 or level != "LV_%03d" % number or \
			str(approach.get("region_id", "")) != "REG_%02d" % (int((number - 1) / 8) + 1):
		return _reject("LEVEL_REGION_DRIFT")
	var tasks: Variant = approach.get("source_task_ids")
	if not tasks is Array or tasks.size() != 5:
		return _reject("TASK_COVERAGE")
	for i: int in range(5):
		if str(tasks[i]) != "JOB_%03d_%d" % [number, i + 1]:
			return _reject("TASK_SPLICE")
	var targets: Variant = approach.get("targets")
	if not targets is Dictionary or targets.size() != 3 or \
			contingency.get("recovery_target") != targets.get("C"):
		return _reject("TARGET_COVERAGE")
	for name: String in ["A", "B", "C"]:
		if targets.get(name) != "SC_%03d_%s" % [number, name]:
			return _reject("TARGET_SPLICE")
	var kind: String = str(consequences.get("risk_class", ""))
	if not PROFILES.has(kind) or \
			consequences.get("guard") != approach.get("profile", {}).get("guard") or \
			consequences.get("recommended_route") != approach.get("profile", {}).get("recommend"):
		return _reject("RISK_OR_GUARD_SPLICE")
	var profile: Dictionary = PROFILES[kind]
	if not GUARDS.has(str(profile.get("guard", ""))):
		return _reject("UNKNOWN_UPSTREAM_GUARD")
	return {"ok": true, "risk_class": kind, "level_id": level,
		"qualification": QUALIFICATION}


func configure(approach: Dictionary, consequences: Dictionary,
		contingency: Dictionary) -> Dictionary:
	if not _spec.is_empty():
		return _reject("ALREADY_CONFIGURED")
	var gate: Dictionary = inspect(approach, consequences, contingency)
	if not bool(gate["ok"]):
		return gate
	_spec = consequences.duplicate(true)
	_profile = PROFILES[str(gate["risk_class"])].duplicate(true)
	return {"ok": true, "level_id": str(_spec["level_id"])}


func definition_snapshot() -> Dictionary:
	return _spec.duplicate(true)


func target_ids() -> Array:
	return _spec.get("targets", {}).values()


func _target(letter: String) -> String:
	return str((_spec["targets"] as Dictionary)[letter])


func _record(event: String) -> void:
	_history.append({"tick": _tick, "event": event, "phase": _phase})
	if _history.size() > 24:
		_history.pop_front()


func started() -> bool:
	return _phase != "dormant"


func can_operate() -> bool:
	return ["contained", "postcheck", "certified"].has(_phase) and _fault == ""


func solved() -> bool:
	return _solved


func needs_action() -> bool:
	return ["choice", "mitigate", "postcheck", "fault"].has(_phase)


func begin(outcome: Dictionary) -> Dictionary:
	if _spec.is_empty() or started() or \
			not ["buffer", "managed"].has(str(outcome.get("mode", ""))) or \
			outcome.get("level_id") != _spec["level_id"] or \
			not ROUTES.has(str(outcome.get("route", ""))) or \
			not ["monitor", "audit", "backlog", "signoff", "certified"].has(
				str(outcome.get("phase", ""))):
		return _reject("OUTCOME_NOT_HOST_READY")
	_outcome_mode = str(outcome["mode"])
	_route = str(outcome["route"])
	_phase = "choice"
	_record("HAZARD_ATTACHED_TO_HOST_PLAN")
	return {"ok": true, "state": snapshot()}


func _next() -> Dictionary:
	if _spec.is_empty() or _solved:
		return {}
	match _phase:
		"choice":
			return {"target": _target(str(_profile["entry"])),
				"action": "engineer_control", "alternative": "temporary_bypass"}
		"mitigate":
			var steps: Array = _profile["sequence"]
			if _step < steps.size():
				return {"target": _target(str(steps[_step]["station"])),
					"action": str(steps[_step]["action"])}
		"postcheck":
			if _mode == "temporary" and _post_step == 0:
				return {"target": _target(str(_profile["entry"])),
					"action": "retire_temporary_bypass"}
			return {"target": _target(str(_profile["restore"])),
				"action": "verify_environment"}
		"fault":
			return {"target": _target("C"), "action": "recover"}
	return {}


func snapshot() -> Dictionary:
	return {"level_id": str(_spec.get("level_id", "")),
		"region_id": str(_spec.get("region_id", "")),
		"risk_class": str(_spec.get("risk_class", "")),
		"phase": _phase, "mode": _mode, "route": _route,
		"outcome_mode": _outcome_mode, "tick": _tick, "step": _step,
		"mitigation_total": (_profile.get("sequence", []) as Array).size(),
		"exposure": _exposure, "pressure": _pressure, "materials": _materials,
		"liability": _liability, "failures": _failures,
		"recoveries": _recoveries, "fault": _fault, "post_step": _post_step,
		"solved": _solved, "next": _next(),
		"recovery_target": _target("C") if not _spec.is_empty() else "",
		"history": _history.duplicate(true),
		"qualification": QUALIFICATION}


func _trip(code: String) -> Dictionary:
	_fault = code
	_phase = "fault"
	_failures += 1
	_liability = mini(6, _liability + 1)
	_record("TRIP_" + code)
	return _reject(code)


## Only the host's authoritative worksite tick drives environmental exposure.
## Outage exposure is a source engineering simulation, not a physical hazard.
func advance(facts: Dictionary) -> void:
	if not started() or _solved:
		return
	_tick += 1
	if _phase == "fault":
		return
	if _phase != "choice" and \
			not bool(facts.get(str(_profile["guard"]), false)):
		_trip("UPSTREAM_SUPPORT_LOST")
		return
	if _phase == "settle":
		if _tick - _settling_start >= int(_profile["settle"]):
			_phase = "contained"
			_record("MITIGATION_STABLE")
		return
	if _phase == "contained":
		if bool(facts.get("site_intervention_solved", false)) and \
				bool(facts.get("site_contingency_solved", false)):
			_phase = "postcheck"
			_post_step = 0
			_last_proof = -1
			_record("RESTORATION_POSTCHECK_REQUIRED")
			return
	# Finite pressure can create an actual fault requiring authenticated
	# recovery. A temporary/managed path accrues more quickly.
	if ["mitigate", "contained", "postcheck"].has(_phase):
		_exposure += 1
		var period: int = int(_profile["pressure_period"])
		if _mode == "temporary":
			period = maxi(6, int(period / 2))
		if _outcome_mode == "managed":
			period = maxi(6, period - 4)
		if _exposure % period == 0:
			_pressure = mini(8, _pressure + 1)
			if _pressure >= (6 if _route == "resilience" else 5):
				_trip("ENVIRONMENTAL_ESCALATION")


## Only SessionHost may call this via its authenticated operate_worksite path.
func operate(entity: String, action: String, facts: Dictionary) -> Dictionary:
	if _spec.is_empty() or not target_ids().has(entity):
		return _reject("UNKNOWN_TARGET")
	if not needs_action():
		return _reject("NO_HAZARD_ACTION")
	if _phase == "fault":
		if entity != _target("C") or action != "recover" or \
				not bool(facts.get(str(_profile["guard"]), false)):
			return _reject("HOST_RECOVERY_REQUIRED")
		_fault = ""
		_recoveries += 1
		_pressure = 0
		_exposure = 0
		_step = 0
		_post_step = 0
		_last_proof = -1
		_settling_start = -1
		_phase = "choice"
		_record("RECOVERED_REQUIRES_NEW_MITIGATION")
		return {"ok": true, "state": snapshot()}
	var next: Dictionary = _next()
	if entity != str(next.get("target", "")):
		return _reject("WRONG_SOURCE_STATION")
	if _phase == "choice":
		if not bool(facts.get("worksite_opened", false)) or \
				not bool(facts.get(str(_profile["guard"]), false)):
			return _reject("UPSTREAM_NOT_READY")
		if action == "engineer_control":
			if _materials < 1:
				return _reject("MATERIALS_EXHAUSTED")
			_materials -= 1
			_mode = "engineered"
		elif action == "temporary_bypass":
			_mode = "temporary"
			_liability = mini(6, _liability + 2)
		else:
			return _reject("INVALID_CONTROL_CHOICE")
		_phase = "mitigate"
		_step = 0
		_last_proof = -1
		_record("CONTROL_" + _mode.to_upper())
	elif _phase == "mitigate":
		var stages: Array = _profile["sequence"]
		if _step >= stages.size():
			return _reject("INVALID_STEP")
		var required: Dictionary = stages[_step]
		if action != str(required["action"]) or \
				not bool(facts.get(str(required["guard"]), false)):
			return _reject("EVIDENCE_OR_GUARD_INVALID")
		if _step > 0 and _tick - _last_proof < int(required["gap"]):
			return _reject("INDEPENDENT_PROOF_GAP")
		_step += 1
		_last_proof = _tick
		_record("MITIGATION_PROOF_" + str(_step))
		if _step == stages.size():
			_settling_start = _tick
			_phase = "settle"
	elif _phase == "postcheck":
		if not bool(facts.get("site_intervention_solved", false)) or \
				not bool(facts.get("site_contingency_solved", false)) or \
				str(facts.get("worksite_route", "")) != _route:
			return _reject("RESTORATION_OR_ROUTE_NOT_VERIFIED")
		if _mode == "temporary" and _post_step == 0:
			if action != "retire_temporary_bypass" or \
					not bool(facts.get("logistics_solved", false)):
				return _reject("TEMPORARY_RESIDUE_NOT_REMOVED")
			_post_step = 1
			_last_proof = _tick
			_liability = maxi(0, _liability - 2)
			_record("TEMPORARY_CONTROL_RETIRED")
		elif action == "verify_environment":
			if _mode == "temporary" and _tick - _last_proof < 4:
				return _reject("FINAL_WITNESS_NOT_SETTLED")
			if not bool(facts.get(str(_profile["guard"]), false)):
				return _reject("POSTCHECK_SUPPORT_REQUIRED")
			_solved = true
			_phase = "certified"
			_record("ENVIRONMENT_CERTIFIED")
		else:
			return _reject("POSTCHECK_ACTION_INVALID")
	else:
		return _reject("INVALID_PHASE")
	return {"ok": true, "state": snapshot()}
