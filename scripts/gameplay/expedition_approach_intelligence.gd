extends RefCounted
## EXP014 A05 — host-authoritative facility approach and investigative decisions.
##
## Reuses only the existing three SC_* targets and SessionHost's validated
## operate_worksite envelope. No client clock, source case, evidence verdict,
## position, inventory, new RPC, save migration or physical collision is trusted.
## The opt-in A05 route must be certified BEFORE the original worksite route
## selection and site intervention. It never rewrites the previous systems.

const QUALIFICATION: String = "SOURCE_HEADLESS_ONLY_HUMAN_CONTROLLER_RELEASE_HELD"
const GUARDS: Array[String] = [
	"logistics_solved", "faults_solved", "balancing_solved", "consequences_solved"
]
const PROTOCOLS: Array[String] = ["paired", "double", "triangulate", "timed", "isolate"]
const ROUTES: Array[String] = ["priority", "resilience"]

## Each regional pattern has a different sequence of real host target roles,
## evidence protocol, precondition and operational risk recommendation.
## Local sites are additionally pinned to their immutable A02/EXP013 source.
const PROFILES: Dictionary = {
	"REG_01": {"entry":"A", "first":"B", "second":"C", "guard":"logistics_solved", "protocol":"timed", "recommend":"resilience", "gap":3, "window":9},
	"REG_02": {"entry":"B", "first":"A", "second":"C", "guard":"faults_solved", "protocol":"isolate", "recommend":"resilience", "gap":3, "window":12},
	"REG_03": {"entry":"C", "first":"A", "second":"B", "guard":"balancing_solved", "protocol":"triangulate", "recommend":"priority", "gap":2, "window":12},
	"REG_04": {"entry":"B", "first":"C", "second":"A", "guard":"logistics_solved", "protocol":"double", "recommend":"resilience", "gap":2, "window":13},
	"REG_05": {"entry":"A", "first":"C", "second":"B", "guard":"consequences_solved", "protocol":"paired", "recommend":"resilience", "gap":4, "window":12},
	"REG_06": {"entry":"C", "first":"B", "second":"A", "guard":"faults_solved", "protocol":"double", "recommend":"priority", "gap":3, "window":13},
	"REG_07": {"entry":"C", "first":"A", "second":"B", "guard":"logistics_solved", "protocol":"paired", "recommend":"resilience", "gap":3, "window":13},
	"REG_08": {"entry":"B", "first":"A", "second":"C", "guard":"balancing_solved", "protocol":"timed", "recommend":"priority", "gap":2, "window":9},
	"REG_09": {"entry":"A", "first":"B", "second":"C", "guard":"faults_solved", "protocol":"triangulate", "recommend":"resilience", "gap":3, "window":12},
	"REG_10": {"entry":"C", "first":"B", "second":"A", "guard":"balancing_solved", "protocol":"isolate", "recommend":"priority", "gap":2, "window":12},
	"REG_11": {"entry":"B", "first":"C", "second":"A", "guard":"balancing_solved", "protocol":"double", "recommend":"resilience", "gap":3, "window":13},
	"REG_12": {"entry":"B", "first":"A", "second":"C", "guard":"faults_solved", "protocol":"timed", "recommend":"resilience", "gap":4, "window":11},
	"REG_13": {"entry":"A", "first":"C", "second":"B", "guard":"logistics_solved", "protocol":"isolate", "recommend":"resilience", "gap":3, "window":14},
	"REG_14": {"entry":"C", "first":"A", "second":"B", "guard":"consequences_solved", "protocol":"double", "recommend":"priority", "gap":2, "window":13},
	"REG_15": {"entry":"A", "first":"B", "second":"C", "guard":"faults_solved", "protocol":"paired", "recommend":"priority", "gap":3, "window":12},
	"REG_16": {"entry":"B", "first":"C", "second":"A", "guard":"logistics_solved", "protocol":"triangulate", "recommend":"priority", "gap":2, "window":13},
	"REG_17": {"entry":"C", "first":"B", "second":"A", "guard":"faults_solved", "protocol":"timed", "recommend":"resilience", "gap":3, "window":10},
	"REG_18": {"entry":"A", "first":"C", "second":"B", "guard":"consequences_solved", "protocol":"triangulate", "recommend":"resilience", "gap":2, "window":13},
	"REG_19": {"entry":"B", "first":"A", "second":"C", "guard":"logistics_solved", "protocol":"isolate", "recommend":"resilience", "gap":4, "window":14},
	"REG_20": {"entry":"B", "first":"C", "second":"A", "guard":"consequences_solved", "protocol":"paired", "recommend":"resilience", "gap":3, "window":11},
	"REG_21": {"entry":"C", "first":"A", "second":"B", "guard":"faults_solved", "protocol":"isolate", "recommend":"priority", "gap":2, "window":12},
	"REG_22": {"entry":"A", "first":"C", "second":"B", "guard":"logistics_solved", "protocol":"timed", "recommend":"priority", "gap":3, "window":10},
	"REG_23": {"entry":"B", "first":"A", "second":"C", "guard":"faults_solved", "protocol":"triangulate", "recommend":"resilience", "gap":2, "window":12},
	"REG_24": {"entry":"C", "first":"B", "second":"A", "guard":"consequences_solved", "protocol":"double", "recommend":"priority", "gap":4, "window":14},
	"REG_25": {"entry":"A", "first":"B", "second":"C", "guard":"logistics_solved", "protocol":"isolate", "recommend":"resilience", "gap":3, "window":12}
}

var _source: Dictionary = {}
var _profile: Dictionary = {}
var _phase: String = "arrival"
var _approach: String = ""
var _tick: int = 0
var _arrival_tick: int = -1
var _evidence_tick: int = -1
var _first_tick: int = -1
var _step: int = 0
var _route: String = ""
var _preparation_step: int = 0
var _fault: String = ""
var _failures: int = 0
var _recoveries: int = 0
var _solved: bool = false


static func _reject(code: String) -> Dictionary:
	return {"ok": false, "code": code, "qualification": QUALIFICATION}


## The geometry plan is source-validated by EXP02; the intervention case is
## source-validated by EXP012/13. A05 independently protects their join.
static func inspect(plan: Dictionary, source: Dictionary) -> Dictionary:
	if not bool(plan.get("ok", false)) or \
			plan.get("code") != "VISUAL_CANDIDATE_ONLY" or \
			plan.get("not_certified") != "NO_PHYSICAL_PLAYABILITY":
		return _reject("EXP014_A05_INVALID_PLAN")
	var level_id: String = str(plan.get("id", ""))
	var serial: int = int(plan.get("serial", 0))
	if serial < 1 or serial > 200 or level_id != "LV_%03d" % serial:
		return _reject("EXP014_A05_LEVEL_DRIFT")
	var region_id: String = "REG_%02d" % (int((serial - 1) / 8) + 1)
	if str(plan.get("region_id", "")) != region_id or not PROFILES.has(region_id):
		return _reject("EXP014_A05_REGION_DRIFT")
	if source.get("qualification") != QUALIFICATION:
		return _reject("EXP014_A05_UNQUALIFIED_SOURCE")
	if source.get("level_id") != level_id or \
			source.get("location_id") != plan.get("location_id") or \
			source.get("region_id") != region_id or \
			source.get("source_risk") != plan.get("hazard"):
		return _reject("EXP014_A05_SOURCE_IDENTITY_DRIFT")
	var source_tasks: Variant = source.get("source_task_ids")
	var positions: Variant = plan.get("stations")
	if not source_tasks is Array or not positions is Array or \
			source_tasks.size() != 5 or positions.size() != 5:
		return _reject("EXP014_A05_TASK_COVERAGE")
	for index: int in range(5):
		if str(source_tasks[index]) != str(positions[index]["id"]) or \
				str(source_tasks[index]) != "JOB_%03d_%d" % [serial, index + 1]:
			return _reject("EXP014_A05_TASK_SPLICE")
	var targets: Variant = source.get("targets")
	if not targets is Dictionary or targets.size() != 3:
		return _reject("EXP014_A05_TARGET_COVERAGE")
	for letter: String in ["A", "B", "C"]:
		if str(targets.get(letter, "")) != "SC_%03d_%s" % [serial, letter]:
			return _reject("EXP014_A05_TARGET_SPLICE")
	if source.get("recovery_target") != targets["C"]:
		return _reject("EXP014_A05_RECOVERY_DRIFT")
	var profile: Dictionary = PROFILES[region_id]
	if not GUARDS.has(str(profile.get("guard", ""))) or \
			not PROTOCOLS.has(str(profile.get("protocol", ""))) or \
			not ROUTES.has(str(profile.get("recommend", ""))):
		return _reject("EXP014_A05_PROFILE_INVALID")
	for key: String in ["entry", "first", "second"]:
		if not ["A", "B", "C"].has(str(profile.get(key, ""))):
			return _reject("EXP014_A05_ROLE_INVALID")
	if profile["first"] == profile["second"] or \
			int(profile["gap"]) < 2 or int(profile["gap"]) > 5 or \
			int(profile["window"]) < 8 or int(profile["window"]) > 16:
		return _reject("EXP014_A05_EVIDENCE_BOUNDS")
	return {"ok": true, "region_id": region_id, "level_id": level_id,
		"source_tasks": 5, "source_targets": 3, "qualification": QUALIFICATION}


func configure(plan: Dictionary, source: Dictionary) -> Dictionary:
	if not _source.is_empty():
		return _reject("EXP014_A05_ALREADY_CONFIGURED")
	var gate: Dictionary = inspect(plan, source)
	if not bool(gate["ok"]):
		return gate
	_source = source.duplicate(true)
	_profile = PROFILES[str(plan["region_id"])].duplicate(true)
	return {"ok": true, "level_id": str(plan["id"]), "qualification": QUALIFICATION}


func definition_snapshot() -> Dictionary:
	return {"level_id": str(_source.get("level_id", "")),
		"location_id": str(_source.get("location_id", "")),
		"region_id": str(_source.get("region_id", "")),
		"source_risk": str(_source.get("source_risk", "")),
		"source_task_ids": _source.get("source_task_ids", []).duplicate(true),
		"targets": _source.get("targets", {}).duplicate(true),
		"profile": _profile.duplicate(true), "qualification": QUALIFICATION}


func target_ids() -> Array:
	return _source.get("targets", {}).values()


func selected_route() -> String:
	return _route if _solved else ""


func solved() -> bool:
	return _solved


func _target(letter: String) -> String:
	return str((_source["targets"] as Dictionary)[letter])


func _witness() -> String:
	for candidate: String in ["A", "B", "C"]:
		if candidate != str(_profile["first"]) and candidate != str(_profile["second"]):
			return candidate
	return ""


func _steps() -> Array[Dictionary]:
	var first: String = str(_profile["first"])
	var second: String = str(_profile["second"])
	var witness: String = _witness()
	var steps: Array[Dictionary] = [{"letter": first, "action": "read_trace"}]
	match str(_profile["protocol"]):
		"double":
			steps.append({"letter": first, "action": "corroborate"})
		"triangulate":
			steps.append({"letter": witness, "action": "crosscheck"})
		"isolate":
			steps.append({"letter": witness, "action": "isolate_signal"})
	steps.append({"letter": second, "action": "read_trace"})
	return steps


func _next() -> Dictionary:
	if _source.is_empty() or _fault != "" or _solved:
		return {}
	match _phase:
		"arrival":
			return {"target": _target(str(_profile["entry"])),
				"action": "approach_guarded", "alternative": "approach_urgent"}
		"transit":
			return {"target": _target(str(_profile["entry"])), "action": "establish_access"}
		"investigate":
			var steps: Array[Dictionary] = _steps()
			if _step < steps.size():
				return {"target": _target(str(steps[_step]["letter"])),
					"action": str(steps[_step]["action"])}
		"decision":
			return {"target": _target(str(_profile["entry"])), "action": "commit_priority",
				"alternative": "commit_resilience"}
		"prepare":
			var extra: bool = _approach == "urgent" or _route != str(_profile["recommend"])
			if _route == "priority" and extra and _preparation_step == 0:
				return {"target": _target(_witness()), "action": "mitigate_exposure"}
			if _route == "resilience" and _preparation_step == 0:
				return {"target": _target(_witness()), "action": "stabilize_access"}
			return {"target": _target(str(_profile["second"])), "action": "authorize_route"}
	return {}


func snapshot() -> Dictionary:
	var discovered: bool = ["decision", "prepare"].has(_phase) or _solved
	# Every fact is a consequence of accepted host observations. An early
	# examination exposes the site risk and exact upstream guard; a second
	# independent witness exposes the evidence protocol. Only finishing the
	# entire source-specific investigation exposes the safe route guidance.
	var evidence_count: int = _step if _fault == "" else 0
	var observed_risk: String = str(_source.get("source_risk", "")) if evidence_count > 0 else ""
	var observed_guard: String = str(_profile.get("guard", "")) if evidence_count > 0 else ""
	var observed_protocol: String = str(_profile.get("protocol", "")) if evidence_count > 1 else ""
	return {"level_id": str(_source.get("level_id", "")),
		"region_id": str(_source.get("region_id", "")), "phase": _phase,
		"approach": _approach, "route": _route, "solved": _solved,
		"tick": _tick, "step": _step, "total_steps": _steps().size() if not _source.is_empty() else 0,
		"intel_revealed": discovered, "recommended_route": str(_profile.get("recommend", "")) if discovered else "",
		"observed_risk": observed_risk,
		"observed_guard": observed_guard,
		"observed_protocol": observed_protocol,
		"protocol": str(_profile.get("protocol", "")) if discovered else "unverified",
		"risk_guard": str(_profile.get("guard", "")) if discovered else "unverified",
		"fault": _fault, "failures": _failures, "recoveries": _recoveries,
		"next": _next(), "recovery_target": _target("C") if not _source.is_empty() else "",
		"qualification": QUALIFICATION}


func _set_fault(code: String) -> Dictionary:
	_fault = code
	_phase = "fault"
	_failures += 1
	return _reject("EXP014_A05_" + code)


func _reset_after_recovery() -> void:
	_phase = "arrival"
	_approach = ""
	_arrival_tick = -1
	_evidence_tick = -1
	_first_tick = -1
	_step = 0
	_route = ""
	_preparation_step = 0
	_fault = ""
	_solved = false


## Host tick only. Losing upstream authority after access was established
## invalidates the intelligence, never automatically grants a new route.
func advance(facts: Dictionary) -> void:
	if _source.is_empty() or _solved:
		return
	_tick += 1
	if _fault != "":
		return
	if ["investigate", "decision", "prepare"].has(_phase) and \
			not bool(facts.get(str(_profile["guard"]), false)):
		_set_fault("SUPPORT_LOST")
		return
	if _phase == "investigate" and str(_profile["protocol"]) == "timed" and \
			_step > 0 and _tick - _first_tick > int(_profile["window"]):
		_set_fault("READOUT_EXPIRED")
	if _phase == "prepare" and _approach == "urgent" and \
			_route == "priority" and _tick - _evidence_tick > int(_profile["window"]) + 6:
		_set_fault("EXPOSURE_WINDOW_EXPIRED")


## Accepted only from authenticated SessionHost operate_worksite ingress.
## Source-target and stage identity are checked BEFORE changing host state.
func operate(entity: String, action: String, facts: Dictionary) -> Dictionary:
	if _source.is_empty() or not target_ids().has(entity):
		return _reject("EXP014_A05_UNKNOWN_TARGET")
	if _fault != "":
		if action != "recover" or entity != _target("C"):
			return _reject("EXP014_A05_RECOVERY_REQUIRED")
		_reset_after_recovery()
		_recoveries += 1
		return {"ok": true, "state": snapshot()}
	if _solved:
		return _reject("EXP014_A05_ALREADY_CERTIFIED")
	var next: Dictionary = _next()
	if entity != str(next.get("target", "")):
		return _reject("EXP014_A05_WRONG_STATION")
	if _phase == "arrival":
		if not bool(facts.get("worksite_opened", false)):
			return _reject("EXP014_A05_OPEN_WORKSITE_FIRST")
		if action not in ["approach_guarded", "approach_urgent"]:
			return _reject("EXP014_A05_INVALID_APPROACH")
		_approach = "guarded" if action == "approach_guarded" else "urgent"
		_arrival_tick = _tick
		_phase = "transit"
	elif _phase == "transit":
		if action != "establish_access":
			return _reject("EXP014_A05_INVALID_TRANSIT")
		var required: int = 4 if _approach == "guarded" else 1
		if _tick - _arrival_tick < required:
			return _reject("EXP014_A05_APPROACH_NOT_STABLE")
		if not bool(facts.get(str(_profile["guard"]), false)):
			return _reject("EXP014_A05_UPSTREAM_GUARD_NOT_READY")
		_phase = "investigate"
	elif _phase == "investigate":
		if not bool(facts.get(str(_profile["guard"]), false)):
			return _set_fault("SUPPORT_LOST")
		if action != str(next.get("action", "")):
			return _reject("EXP014_A05_FALSE_EVIDENCE_ACTION")
		if _step > 0 and _tick - _evidence_tick < int(_profile["gap"]):
			return _reject("EXP014_A05_WITNESS_GAP")
		if str(_profile["protocol"]) == "timed" and _step > 0 and \
				_tick - _first_tick > int(_profile["window"]):
			return _set_fault("READOUT_EXPIRED")
		if _step == 0:
			_first_tick = _tick
		_evidence_tick = _tick
		_step += 1
		if _step == _steps().size():
			_phase = "decision"
	elif _phase == "decision":
		if action not in ["commit_priority", "commit_resilience"]:
			return _reject("EXP014_A05_INVALID_DECISION")
		_route = "priority" if action == "commit_priority" else "resilience"
		_phase = "prepare"
		_preparation_step = 0
		_evidence_tick = _tick
	elif _phase == "prepare":
		if action != str(next.get("action", "")):
			return _reject("EXP014_A05_PREPARATION_BYPASS")
		if _preparation_step == 0 and action != "authorize_route":
			_preparation_step = 1
			_evidence_tick = _tick
		else:
			# Urgent and nonrecommended routes demand an independent source
			# witness, and resilient access must settle for 3 host ticks.
			var needed: int = 3 if _route == "resilience" else 2
			if _preparation_step > 0 and _tick - _evidence_tick < needed:
				return _reject("EXP014_A05_FINAL_WITNESS_NOT_SETTLED")
			_solved = true
			_phase = "certified"
	else:
		return _reject("EXP014_A05_INVALID_PHASE")
	return {"ok": true, "state": snapshot()}
