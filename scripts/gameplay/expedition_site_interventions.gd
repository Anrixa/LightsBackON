extends RefCounted
## EXP012 A02 — host-owned site-specific intervention runtime.
##
## Every command must arrive through SessionHost's existing operate_worksite
## envelope after peer, sequence, rate, in-range and optional physics-LoS gates.
## Client supplies only (target, action). Never accept an elapsed tick, step
## index, verdict, source identity or recovery outcome from the client.
## This is additive and opt-in: EXP012 A01 and C01-C12 are not rewritten.

const PATH: String = "res://scenes/expeditions/site_interventions_a02.json"
const AUTHORITY: String = "EXP012_A02_HOST_SITE_INTERVENTIONS"
const QUALIFICATION: String = "SOURCE_HEADLESS_ONLY_HUMAN_CONTROLLER_RELEASE_HELD"
const MODES: Array[String] = ["hold", "pulse", "sample", "handoff", "balance"]
const FAILURES: Array[String] = ["step", "backtrack", "restart"]
const MAX_HISTORY: int = 48

var _spec: Dictionary = {}
var _route: String = ""
var _index: int = 0
var _tick: int = 0
var _phase: String = "ready"
var _started_tick: int = -1
var _deadline: int = -1
var _support_count: int = 0
var _support_tick: int = -1
var _fault: String = ""
var _failures: int = 0
var _recoveries: int = 0
var _unsafe_events: int = 0
var _history: Array[Dictionary] = []


static func load_book() -> Dictionary:
    if not FileAccess.file_exists(PATH):
        return {}
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
    return parsed if parsed is Dictionary else {}


static func entry_for(book: Dictionary, level: Dictionary, order: Dictionary) -> Dictionary:
    for raw: Variant in book.get("entries", []):
        if not raw is Dictionary:
            return {}
        var item: Dictionary = raw
        if item.get("level_id") != level.get("id"):
            continue
        var ids: Array[String] = []
        for task: Dictionary in level.get("tasks", []):
            ids.append(str(task["id"]))
        if item.get("location_id") != level.get("location_id") or \
                item.get("source_puzzle_identity") != level.get("puzzle_identity") or \
                item.get("source_title") != level.get("title") or \
                item.get("source_task_ids") != ids or \
                item.get("worksite_encounter_key") != order.get("encounter_key"):
            return {}
        return item.duplicate(true)
    return {}


## Audit the full authored overlay independently of A01's 200-entry audit.
## This intentionally reports 40, NOT 200 individually authored mechanics.
static func inspect(atlas: Dictionary, worksite_book: Dictionary, book: Dictionary) -> Dictionary:
    if book.get("schema_version") != 1 or book.get("authority") != AUTHORITY or \
            book.get("qualification") != QUALIFICATION or \
            book.get("atlas_revision") != atlas.get("revision"):
        return {"ok": false, "code": "EXP012A02_HEADER_INVALID"}
    var entries: Variant = book.get("entries")
    var levels: Array = atlas.get("levels", [])
    var orders: Array = worksite_book.get("entries", [])
    if not entries is Array or entries.size() != 40 or \
            levels.size() != 200 or orders.size() != 200:
        return {"ok": false, "code": "EXP012A02_COUNT_INVALID"}
    var locations: Dictionary = {}
    for location: Dictionary in atlas.get("locations", []):
        locations[str(location["id"])] = location
    var titles: Dictionary = {}
    var targets: Dictionary = {}
    var signatures: Dictionary = {}
    var modes: Dictionary = {}
    for i: int in range(entries.size()):
        if not entries[i] is Dictionary:
            return {"ok": false, "code": "EXP012A02_ENTRY_TYPE"}
        var item: Dictionary = entries[i]
        var level: Dictionary = levels[i]
        var order: Dictionary = orders[i]
        var loc: Dictionary = locations.get(str(level["location_id"]), {})
        if loc.is_empty() or item.get("level_id") != level.get("id") or \
                item.get("location_id") != level.get("location_id") or \
                item.get("region_id") != level.get("region_id") or \
                item.get("source_puzzle_identity") != level.get("puzzle_identity") or \
                item.get("source_title") != level.get("title") or \
                item.get("source_risk") != loc.get("risk") or \
                item.get("source_climate") != loc.get("climate") or \
                item.get("source_task_ids") != order.get("task_ids") or \
                item.get("worksite_encounter_key") != order.get("encounter_key") or \
                item.get("qualification") != QUALIFICATION:
            return {"ok": false, "code": "EXP012A02_SOURCE_DRIFT", "index": i}
        var title: String = str(item.get("title", ""))
        if title.length() < 12 or titles.has(title) or str(item.get("stakes", "")).length() < 65:
            return {"ok": false, "code": "EXP012A02_UNAUTHORED_TEXT", "index": i}
        titles[title] = true
        var suffix: String = str(i + 1).pad_zeros(3)
        var expected_targets: Dictionary = {
            "A": "SC_%s_A" % suffix, "B": "SC_%s_B" % suffix, "C": "SC_%s_C" % suffix}
        if item.get("targets") != expected_targets or \
                item.get("recovery_target") != expected_targets["C"]:
            return {"ok": false, "code": "EXP012A02_TARGET_DRIFT", "index": i}
        for target: String in expected_targets.values():
            if targets.has(target):
                return {"ok": false, "code": "EXP012A02_DUPLICATE_TARGET"}
            targets[target] = true
        var routes: Variant = item.get("routes")
        if not routes is Dictionary or routes.size() != 2 or \
                not routes.has("priority") or not routes.has("resilience"):
            return {"ok": false, "code": "EXP012A02_ROUTES_INVALID"}
        var signatures_for_item: Array[String] = []
        for route: String in ["priority", "resilience"]:
            var steps: Variant = routes[route]
            if not steps is Array or steps.size() != 4:
                return {"ok": false, "code": "EXP012A02_STEP_COUNT"}
            var signature: String = ""
            for step_value: Variant in steps:
                if not step_value is Dictionary:
                    return {"ok": false, "code": "EXP012A02_STEP_TYPE"}
                var step: Dictionary = step_value
                if step.size() != 7 or not MODES.has(str(step.get("mode", ""))) or \
                        not FAILURES.has(str(step.get("failure", ""))) or \
                        not expected_targets.values().has(step.get("target")) or \
                        not expected_targets.values().has(step.get("support_target")) or \
                        step.get("target") == step.get("support_target") or \
                        not step.get("dwell_ticks") is int or \
                        not step.get("window_ticks") is int or \
                        int(step["dwell_ticks"]) < 5 or int(step["dwell_ticks"]) > 20 or \
                        int(step["window_ticks"]) < 40 or int(step["window_ticks"]) > 240:
                    return {"ok": false, "code": "EXP012A02_MECHANIC_INVALID"}
                var action: String = str(step.get("action", ""))
                if action.length() < 8 or action.length() > 45 or \
                        not action.is_valid_identifier():
                    return {"ok": false, "code": "EXP012A02_ACTION_INVALID"}
                modes[str(step["mode"])] = true
                signature += "%s|%s|%s|%s;" % [
                    action, step["mode"], step["target"], step["support_target"]]
            signatures_for_item.append(signature)
        if signatures_for_item[0] == signatures_for_item[1]:
            return {"ok": false, "code": "EXP012A02_NO_STRATEGY_DIFFERENCE"}
        if signatures.has(signatures_for_item[0]):
            return {"ok": false, "code": "EXP012A02_DUPLICATE_SCRIPT"}
        signatures[signatures_for_item[0]] = true
    if targets.size() != 120 or titles.size() != 40 or \
            signatures.size() != 40 or modes.size() != MODES.size():
        return {"ok": false, "code": "EXP012A02_COVERAGE_INVALID"}
    return {"ok": true, "authored_locations": 40, "remaining_locations": 160,
        "routes": 80, "route_steps": 320, "host_targets": 120,
        "mechanical_modes": modes.size()}


func configure(entry: Dictionary) -> Dictionary:
    if not _spec.is_empty() or not entry.has("routes") or \
            not entry.has("targets") or not entry.has("recovery_target"):
        return {"ok": false, "code": "EXP012A02_CONFIG_INVALID"}
    _spec = entry.duplicate(true)
    return {"ok": true}


func definition_snapshot() -> Dictionary:
    return _spec.duplicate(true)


func target_ids() -> Array[String]:
    var result: Array[String] = []
    for id: Variant in _spec.get("targets", {}).values():
        result.append(str(id))
    return result


func _facts_safe(facts: Dictionary) -> bool:
    return bool(facts.get("worksite_opened", false)) and \
        bool(facts.get("balancing_solved", false)) and \
        bool(facts.get("logistics_solved", false)) and \
        bool(facts.get("consequences_solved", false)) and \
        bool(facts.get("faults_solved", false)) and \
        bool(facts.get("west_restored", false)) and \
        bool(facts.get("east_on", false)) and \
        not bool(facts.get("hazard_active", true))


func _log(event: String, target: String) -> void:
    _history.append({"tick": _tick, "event": event, "target": target,
        "step": _index, "route": _route})
    while _history.size() > MAX_HISTORY:
        _history.pop_front()


func _current() -> Dictionary:
    if _route == "" or _spec.is_empty():
        return {}
    var steps: Array = _spec["routes"][_route]
    return steps[_index] if _index < steps.size() else {}


func _reset_clock() -> void:
    _phase = "ready"
    _started_tick = -1
    _deadline = -1
    _support_count = 0
    _support_tick = -1


func _break_workflow(reason: String, scope: String) -> Dictionary:
    _failures += 1
    if scope == "restart":
        _index = 0
    elif scope == "backtrack":
        _index = maxi(0, _index - 1)
    _reset_clock()
    _fault = reason
    _log("FAULT_" + reason, str(_spec["recovery_target"]))
    return {"ok": false, "code": "EXP012A02_" + reason,
        "needs_recovery": true, "next_step": _index}


func _finish_step() -> Dictionary:
    var step: Dictionary = _current()
    _log("STEP_COMPLETED_" + str(step["mode"]).to_upper(), str(step["target"]))
    _index += 1
    _reset_clock()
    var finished: bool = solved()
    if finished:
        _phase = "done"
        _log("SITE_INTERVENTION_CERTIFIED", str(_spec["recovery_target"]))
    return {"ok": true, "completed_step": _index, "solved": finished}


func solved() -> bool:
    return not _spec.is_empty() and _route != "" and _fault == "" and \
        _index == 4


## A02 is reachable only from SessionHost's validated operate_worksite
## command and from an existing EXP012 A01 explicitly opt-in session.
func operate(entity: String, action: String, facts: Dictionary) -> Dictionary:
    if _spec.is_empty() or not target_ids().has(entity):
        return {"ok": false, "code": "EXP012A02_UNKNOWN_TARGET"}
    if not _facts_safe(facts):
        return {"ok": false, "code": "EXP012A02_UPSTREAM_INTERLOCK"}
    var chosen: String = str(facts.get("worksite_route", ""))
    if not ["priority", "resilience"].has(chosen):
        return {"ok": false, "code": "EXP012A02_A01_ROUTE_REQUIRED"}
    if _route != "" and chosen != _route:
        return {"ok": false, "code": "EXP012A02_ROUTE_CHANGED"}
    if _route == "":
        _route = chosen
    if _fault != "":
        if entity != str(_spec["recovery_target"]) or action != "recover":
            return {"ok": false, "code": "EXP012A02_RECOVERY_REQUIRED"}
        _fault = ""
        _recoveries += 1
        _log("FAULT_RECOVERED", entity)
        return {"ok": true, "recovered": true, "step": _index}
    if solved():
        return {"ok": false, "code": "EXP012A02_ALREADY_CERTIFIED"}
    var step: Dictionary = _current()
    var target: String = str(step["target"])
    var support: String = str(step["support_target"])
    var mode: String = str(step["mode"])
    if _phase == "ready":
        if entity != target or action != str(step["action"]):
            return {"ok": false, "code": "EXP012A02_ORDER_REQUIRED",
                "expected_target": target}
        _phase = "warming"
        _started_tick = _tick
        _log("START_" + mode.to_upper(), entity)
        return {"ok": true, "warming": true, "step": _index,
            "host_dwell_ticks": int(step["dwell_ticks"])}
    if _phase == "warming":
        if entity == target and ["confirm", "pulse", "commit"].has(action):
            return _break_workflow("PREMATURE_COMMIT", str(step["failure"]))
        return {"ok": false, "code": "EXP012A02_WAIT_FOR_HOST_DWELL"}
    if _phase != "stable":
        return {"ok": false, "code": "EXP012A02_INVALID_PHASE"}
    if _tick > _deadline:
        return _break_workflow("WINDOW_EXPIRED", str(step["failure"]))
    if mode == "hold" and entity == target and action == "confirm":
        return _finish_step()
    if mode == "pulse" and entity == target and action == "pulse":
        return _finish_step()
    if mode == "sample":
        if entity == support and action == "read":
            if _support_count == 1 and _tick - _support_tick < 3:
                return {"ok": false, "code": "EXP012A02_SAMPLE_GAP_REQUIRED"}
            if _support_count >= 2:
                return {"ok": false, "code": "EXP012A02_SAMPLE_ALREADY_COMPLETE"}
            _support_count += 1
            _support_tick = _tick
            _log("READ_SAMPLE_" + str(_support_count), entity)
            return {"ok": true, "samples": _support_count}
        if entity == target and action == "confirm" and _support_count == 2:
            return _finish_step()
        return {"ok": false, "code": "EXP012A02_TWO_SAMPLES_REQUIRED"}
    if mode == "handoff":
        if entity == support and action == "transfer" and _support_count == 0:
            _support_count = 1
            _log("SECOND_STATION_HANDOFF", entity)
            return {"ok": true, "transferred": true}
        if entity == target and action == "commit" and _support_count == 1:
            return _finish_step()
        return {"ok": false, "code": "EXP012A02_HANDOFF_REQUIRED"}
    if mode == "balance":
        if entity == support and action == "trim" and _support_count == 0:
            _support_count = 1
            _support_tick = _tick
            _log("BALANCE_TRIM_SET", entity)
            return {"ok": true, "trimmed": true}
        if entity == target and action == "confirm" and _support_count == 1:
            if _tick - _support_tick < 4:
                return {"ok": false, "code": "EXP012A02_BALANCE_SETTLING"}
            return _finish_step()
        return {"ok": false, "code": "EXP012A02_BALANCE_TRIM_REQUIRED"}
    return {"ok": false, "code": "EXP012A02_UNSUPPORTED_MECHANIC"}


## Fixed 10 Hz host tick. Missed windows and unsafe grid state reopen the
## encounter through an explicit recovery target; no item or save is consumed.
func advance(facts: Dictionary) -> void:
    if _spec.is_empty() or _route == "" or solved():
        return
    if not _facts_safe(facts):
        if _fault == "":
            _unsafe_events += 1
            _break_workflow("SUPPLY_LOST", "restart")
        return
    if _fault != "":
        return
    _tick += 1
    if _phase == "warming":
        var step: Dictionary = _current()
        if _tick - _started_tick >= int(step["dwell_ticks"]):
            _phase = "stable"
            var duration: int = int(step["window_ticks"])
            if step["mode"] == "pulse":
                duration = mini(duration, 18)
            _deadline = _tick + duration
            _log("HOST_STABLE", str(step["target"]))
    elif _phase == "stable" and _tick > _deadline:
        _break_workflow("WINDOW_EXPIRED", str(_current()["failure"]))


func snapshot() -> Dictionary:
    var step: Dictionary = _current()
    return {"ok": not _spec.is_empty(), "level_id": _spec.get("level_id", ""),
        "title": _spec.get("title", ""), "stakes": _spec.get("stakes", ""),
        "route": _route, "step": _index, "step_count": 4, "phase": _phase,
        "fault": _fault, "tick": _tick, "started_tick": _started_tick,
        "deadline": _deadline, "support_count": _support_count,
        "support_tick": _support_tick, "failures": _failures,
        "recoveries": _recoveries, "unsafe_events": _unsafe_events,
        "next": step.duplicate(true), "recovery_target": _spec.get("recovery_target", ""),
        "solved": solved(), "history": _history.duplicate(true),
        "qualification": QUALIFICATION}
