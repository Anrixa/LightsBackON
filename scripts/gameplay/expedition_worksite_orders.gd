extends RefCounted
## EXP012: host-owned worksite order graphs, two authored operating routes,
## finite rapid calibration cells and recoverable unsafe-supply rechecks.
## Source/headless qualification only. No C01-C12 save or economy mutation.

const BOOK_PATH: String = "res://scenes/expeditions/field_work_orders.json"
const AUTHORITY: String = "EXP012_HOST_FIELD_WORK_ORDERS"
const QUALIFICATION: String = "SOURCE_HEADLESS_ONLY_HUMAN_CONTROLLER_RELEASE_HELD"
const MAX_HISTORY: int = 32
const SITE_GRAPHS: Dictionary = {
    "distribution": {"priority": [[], [], [0, 1]], "resilience": [[], [0], [1]]},
    "transport": {"priority": [[], [], [0, 1]], "resilience": [[1], [], [0]]},
    "health": {"priority": [[1], [], [0, 1]], "resilience": [[], [0], [1]]},
    "commerce": {"priority": [[], [0], [0]], "resilience": [[1], [], [0, 1]]},
    "waterworks": {"priority": [[], [0], [1]], "resilience": [[], [], [0, 1]]},
    "communications": {"priority": [[], [], [0]], "resilience": [[2], [0], []]},
    "education": {"priority": [[], [], [0, 1]], "resilience": [[2], [2], []]},
    "shelter": {"priority": [[], [0], [0, 1]], "resilience": [[1], [], [0, 1]]}
}

var _spec: Dictionary = {}
var _states: Dictionary = {}
var _active: Dictionary = {}
var _opened: bool = false
var _route: String = ""
var _started: bool = false
var _certified: bool = false
var _optional_logged: bool = false
var _tick: int = 0
var _cells_left: int = 0
var _aborts: int = 0
var _reopens: int = 0
var _history: Array[Dictionary] = []


static func load_book() -> Dictionary:
    if not FileAccess.file_exists(BOOK_PATH):
        return {}
    var decoded: Variant = JSON.parse_string(FileAccess.get_file_as_string(BOOK_PATH))
    return decoded if decoded is Dictionary else {}


static func entry_for(book: Dictionary, level: Dictionary, balance: Dictionary) -> Dictionary:
    for raw: Variant in book.get("entries", []):
        if not raw is Dictionary:
            return {}
        var entry: Dictionary = raw
        if entry.get("level_id") != level.get("id"):
            continue
        var ids: Array[String] = []
        for task: Dictionary in level.get("tasks", []):
            ids.append(str(task["id"]))
        if entry.get("location_id") != level.get("location_id") or \
                entry.get("source_puzzle_identity") != level.get("puzzle_identity") or \
                entry.get("load_key") != balance.get("load_key") or \
                entry.get("task_ids") != ids:
            return {}
        return entry.duplicate(true)
    return {}


static func _route_is_dag(graph: Array, ids: Array[String]) -> bool:
    if graph.size() != 3:
        return false
    var completed: Dictionary = {}
    for deps: Variant in graph:
        if not deps is Array:
            return false
        for dep: Variant in deps:
            if not dep is String or not ids.has(str(dep)):
                return false
    for _step: int in range(3):
        var progress: bool = false
        for i: int in range(3):
            if completed.has(ids[i]):
                continue
            var ready: bool = true
            for dep: Variant in graph[i]:
                if not completed.has(str(dep)):
                    ready = false
            if ready:
                completed[ids[i]] = true
                progress = true
                break
        if not progress:
            return false
    return completed.size() == 3


## Independent source inspection. Python audit also recomputes authored profiles.
static func inspect(atlas: Dictionary, balance_book: Dictionary, book: Dictionary) -> Dictionary:
    if book.get("schema_version") != 1 or book.get("authority") != AUTHORITY or \
            book.get("atlas_revision") != atlas.get("revision") or \
            book.get("qualification") != QUALIFICATION:
        return {"ok": false, "code": "EXP012_HEADER_INVALID"}
    var entries: Variant = book.get("entries")
    var levels: Array = atlas.get("levels", [])
    var loads: Array = balance_book.get("entries", [])
    if not entries is Array or entries.size() != 200 or levels.size() != 200 or loads.size() != 200:
        return {"ok": false, "code": "EXP012_SOURCE_COUNTS_INVALID"}
    var locations: Dictionary = {}
    for loc: Dictionary in atlas.get("locations", []):
        locations[str(loc["id"])] = loc
    if locations.size() != 200:
        return {"ok": false, "code": "EXP012_LOCATION_COUNT"}
    var load_by_level: Dictionary = {}
    for load: Dictionary in loads:
        load_by_level[str(load["level_id"])] = load
    if load_by_level.size() != 200:
        return {"ok": false, "code": "EXP012_LOAD_COUNT"}
    var targets: Dictionary = {}
    var keys: Dictionary = {}
    var site_pairs: Dictionary = {}
    for i: int in range(200):
        if not entries[i] is Dictionary:
            return {"ok": false, "code": "EXP012_ENTRY_INVALID"}
        var entry: Dictionary = entries[i]
        var level: Dictionary = levels[i]
        var id: String = str(level["id"])
        if not locations.has(str(level["location_id"])) or not load_by_level.has(id):
            return {"ok": false, "code": "EXP012_SOURCE_MISSING"}
        var loc: Dictionary = locations[str(level["location_id"])]
        var load: Dictionary = load_by_level[id]
        var region: int = int(str(level["region_id"]).trim_prefix("REG_"))
        var site: String = str(loc["archetype"])
        if not SITE_GRAPHS.has(site):
            return {"ok": false, "code": "EXP012_UNKNOWN_SITE"}
        var suffix: String = id.trim_prefix("LV_")
        var ids: Array[String] = ["WO_%s_A" % suffix, "WO_%s_B" % suffix, "WO_%s_C" % suffix]
        var expected_tasks: Array[String] = []
        for task: Dictionary in level["tasks"]:
            expected_tasks.append(str(task["id"]))
        if expected_tasks.size() != 5 or entry.get("task_ids") != expected_tasks or \
                entry.get("level_id") != id or \
                entry.get("location_id") != level["location_id"] or \
                entry.get("region_id") != level["region_id"] or \
                entry.get("site") != site or \
                entry.get("source_climate") != loc["climate"] or \
                entry.get("source_puzzle_identity") != level["puzzle_identity"] or \
                entry.get("load_key") != load["load_key"] or \
                entry.get("source_title") != level["title"] or \
                entry.get("encounter_key") != str(load["load_key"]) + "|EXP012|" + site + "|" + str(region) or \
                entry.get("qualification") != QUALIFICATION:
            return {"ok": false, "code": "EXP012_SOURCE_DRIFT", "level": id}
        if entry.get("board") != "WO_%s_BOARD" % suffix or \
                entry.get("decision") != "WO_%s_ROUTE" % suffix or \
                entry.get("console") != "WO_%s_CTRL" % suffix or \
                entry.get("optional_target") != "WO_%s_DISC" % suffix or \
                entry.get("anchors") != {"board": "PANEL_WEST", "decision": "PANEL_SPUR",
                    "console": "R_WEST", "optional_target": "PANEL_SPUR"}:
            return {"ok": false, "code": "EXP012_TARGET_DRIFT", "level": id}
        if int(entry.get("cell_budget", -1)) != 1 + region % 3 or \
                int(entry.get("crew_capacity", -1)) != 1 + region % 2:
            return {"ok": false, "code": "EXP012_RESOURCE_DRIFT", "level": id}
        var checkpoints: Variant = entry.get("checkpoints")
        if not checkpoints is Array or checkpoints.size() != 3:
            return {"ok": false, "code": "EXP012_CHECKPOINT_COUNT"}
        for j: int in range(3):
            if not checkpoints[j] is Dictionary:
                return {"ok": false, "code": "EXP012_CHECKPOINT_INVALID"}
            var cp: Dictionary = checkpoints[j]
            var service: Dictionary = load["services"][j]
            if cp.get("id") != ids[j] or \
                    cp.get("anchor") != ["PANEL_WEST", "PANEL_SPUR", "R_WEST"][j] or \
                    cp.get("linked_service") != service["id"] or \
                    cp.get("source_task_id") != expected_tasks[j] or \
                    cp.get("title") != service["name"] or \
                    int(cp.get("precision_ticks", -1)) != 6 + (int(service["dwell_ticks"]) + region + j) % 7 or \
                    int(cp.get("rapid_ticks", -1)) != 2 + (i + j) % 3:
                return {"ok": false, "code": "EXP012_CHECKPOINT_DRIFT", "level": id}
        if not entry.get("routes") is Dictionary:
            return {"ok": false, "code": "EXP012_ROUTE_TYPE"}
        var routes: Dictionary = entry["routes"]
        if routes.size() != 2:
            return {"ok": false, "code": "EXP012_ROUTE_COUNT"}
        for route: String in ["priority", "resilience"]:
            var expected_graph: Array = []
            for offsets: Array in SITE_GRAPHS[site][route]:
                var prereqs: Array[String] = []
                for offset: int in offsets:
                    prereqs.append(ids[offset])
                expected_graph.append(prereqs)
            if not routes.has(route) or routes[route] != expected_graph or \
                    not _route_is_dag(routes[route], ids):
                return {"ok": false, "code": "EXP012_GRAPH_DRIFT", "level": id}
        if routes["priority"] == routes["resilience"]:
            return {"ok": false, "code": "EXP012_NOT_BRANCHING", "level": id}
        for target: String in [str(entry["board"]), str(entry["decision"]),
                str(entry["console"]), str(entry["optional_target"]), ids[0], ids[1], ids[2]]:
            if targets.has(target):
                return {"ok": false, "code": "EXP012_DUPLICATE_TARGET"}
            targets[target] = true
        var key: String = str(entry["encounter_key"])
        if keys.has(key):
            return {"ok": false, "code": "EXP012_DUPLICATE_ENCOUNTER"}
        keys[key] = true
        site_pairs[str(level["region_id"]) + "|" + site] = true
    if targets.size() != 1400 or keys.size() != 200 or site_pairs.size() != 200:
        return {"ok": false, "code": "EXP012_COVERAGE_INVALID"}
    return {"ok": true, "levels": 200, "task_bindings": 1000,
        "checkpoints": 600, "targets": 1400, "alternative_routes": 400}


func configure(entry: Dictionary) -> Dictionary:
    if not _spec.is_empty() or not entry.has("encounter_key") or \
            not entry.get("checkpoints") is Array or (entry["checkpoints"] as Array).size() != 3:
        return {"ok": false, "code": "EXP012_CONFIG_INVALID"}
    _spec = entry.duplicate(true)
    _cells_left = int(entry["cell_budget"])
    for checkpoint: Dictionary in entry["checkpoints"]:
        _states[str(checkpoint["id"])] = {
            "status": "pending", "elapsed": 0, "needed": 0, "method": ""}
    return {"ok": true}


func definition_snapshot() -> Dictionary:
    return _spec.duplicate(true)


func target_ids() -> Array[String]:
    if _spec.is_empty():
        return []
    var targets: Array[String] = [str(_spec["board"]), str(_spec["decision"]),
        str(_spec["console"]), str(_spec["optional_target"])]
    for checkpoint: Dictionary in _spec["checkpoints"]:
        targets.append(str(checkpoint["id"]))
    return targets


func _checkpoint(id: String) -> Dictionary:
    for checkpoint: Dictionary in _spec.get("checkpoints", []):
        if checkpoint.get("id") == id:
            return checkpoint
    return {}


func _safe(facts: Dictionary) -> bool:
    return bool(facts.get("balancing_solved", false)) and \
        bool(facts.get("logistics_solved", false)) and \
        bool(facts.get("consequences_solved", false)) and \
        bool(facts.get("faults_solved", false)) and \
        bool(facts.get("west_restored", false)) and \
        bool(facts.get("east_on", false)) and \
        not bool(facts.get("hazard_active", true))


func _log(kind: String, target: String) -> void:
    _history.append({"tick": _tick, "event": kind, "target": target})
    while _history.size() > MAX_HISTORY:
        _history.pop_front()


func _all_latched() -> bool:
    if _states.size() != 3:
        return false
    for state: Dictionary in _states.values():
        if state["status"] != "latched":
            return false
    return true


func _dependencies_met(id: String) -> bool:
    var checkpoints: Array = _spec["checkpoints"]
    for i: int in range(checkpoints.size()):
        if checkpoints[i]["id"] != id:
            continue
        for requires: Variant in _spec["routes"][_route][i]:
            if not _states.has(str(requires)) or _states[str(requires)]["status"] != "latched":
                return false
        return true
    return false


## Caller MUST be SessionHost after peer admission, sequence/dedupe and range/LoS.
## The wire can only provide a source-defined target ID and one action string.
func operate(id: String, action: String, facts: Dictionary) -> Dictionary:
    if _spec.is_empty():
        return {"ok": false, "code": "EXP012_NOT_CONFIGURED"}
    if not target_ids().has(id):
        return {"ok": false, "code": "EXP012_UNKNOWN_TARGET"}
    if id == str(_spec["board"]):
        if action != "open" or _opened or not _safe(facts) or \
                not bool(facts.get("investigation_solved", false)) or \
                not bool(facts.get("routing_solved", false)) or \
                not bool(facts.get("repair_solved", false)):
            return {"ok": false, "code": "EXP012_SOURCE_EVIDENCE_REQUIRED"}
        _opened = true
        _log("WORKSITE_OPENED", id)
        return {"ok": true, "crew_capacity": int(_spec["crew_capacity"]),
            "cells_left": _cells_left}
    if not _opened or not _safe(facts):
        return {"ok": false, "code": "EXP012_UNSAFE_OR_CLOSED"}
    if id == str(_spec["decision"]):
        if not ["priority", "resilience"].has(action) or _started or _certified:
            return {"ok": false, "code": "EXP012_ROUTE_LOCKED"}
        _route = action
        _log("ROUTE_SELECTED_" + action.to_upper(), id)
        return {"ok": true, "route": _route}
    if id == str(_spec["optional_target"]):
        if action != "log" or _optional_logged or \
                not bool(facts.get("discovery_solved", false)):
            return {"ok": false, "code": "EXP012_DISCOVERY_EVIDENCE_REQUIRED"}
        _optional_logged = true
        _log("OPTIONAL_DISCOVERY_LOGGED", id)
        return {"ok": true, "optional_logged": true}
    if id == str(_spec["console"]):
        if action != "certify" or _certified or _route == "" or \
                not _active.is_empty() or not _all_latched():
            return {"ok": false, "code": "EXP012_CERTIFICATION_INTERLOCK"}
        _certified = true
        _log("FIELD_WORK_ORDER_CERTIFIED", id)
        return {"ok": true, "certified": true, "route": _route}
    if _route == "":
        return {"ok": false, "code": "EXP012_ROUTE_REQUIRED"}
    var status: String = str(_states[id]["status"])
    if action == "recheck" and status == "recheck":
        _states[id]["status"] = "latched"
        _log("WORKSITE_RECHECKED", id)
        return {"ok": true, "rechecked": id}
    if action == "confirm" and _active.has(id):
        _active.erase(id)
        if status == "stable":
            _states[id]["status"] = "latched"
            _log("CHECKPOINT_CONFIRMED", id)
            return {"ok": true, "latched": id}
        _states[id] = {"status": "pending", "elapsed": 0, "needed": 0, "method": ""}
        _aborts += 1
        _log("PREMATURE_CONFIRM_RESTART", id)
        return {"ok": true, "aborted": id}
    if not ["precision", "rapid"].has(action) or status != "pending":
        return {"ok": false, "code": "EXP012_ACTION_INVALID"}
    if not _dependencies_met(id):
        return {"ok": false, "code": "EXP012_DEPENDENCY_UNMET"}
    if _active.size() >= int(_spec["crew_capacity"]):
        return {"ok": false, "code": "EXP012_CREW_CAPACITY"}
    if action == "rapid":
        if _cells_left <= 0:
            return {"ok": false, "code": "EXP012_NO_CALIBRATION_CELLS"}
        _cells_left -= 1
    var checkpoint: Dictionary = _checkpoint(id)
    _states[id] = {"status": "warming", "elapsed": 0,
        "needed": int(checkpoint["rapid_ticks"] if action == "rapid" else checkpoint["precision_ticks"]),
        "method": action}
    _active[id] = true
    _started = true
    _log("CHECKPOINT_STARTED_" + action.to_upper(), id)
    return {"ok": true, "started": id, "method": action, "cells_left": _cells_left}


## Single 10 Hz authoritative clock. A loss of real grid/host safety invalidates
## active tests and marks latched work for a nonconsumable, repeatable recheck.
func advance(facts: Dictionary) -> void:
    if _spec.is_empty() or not _opened:
        return
    if not _safe(facts):
        var changed: bool = _certified
        if _certified:
            _certified = false
            _reopens += 1
        for id: String in _states:
            var status: String = str(_states[id]["status"])
            if status == "latched":
                _states[id]["status"] = "recheck"
                changed = true
            elif status == "warming" or status == "stable":
                _states[id] = {"status": "pending", "elapsed": 0, "needed": 0, "method": ""}
                changed = true
        _active.clear()
        if changed:
            _log("UNSAFE_WORKSITE_REOPENED", str(_spec["console"]))
        return
    if _certified:
        return
    _tick += 1
    for id: String in _active:
        if _states[id]["status"] != "warming":
            continue
        _states[id]["elapsed"] = int(_states[id]["elapsed"]) + 1
        if int(_states[id]["elapsed"]) >= int(_states[id]["needed"]):
            _states[id]["status"] = "stable"
            _log("CHECKPOINT_STABILIZED", id)


func solved() -> bool:
    return _opened and _certified and _all_latched() and _active.is_empty()


func snapshot() -> Dictionary:
    return {"ok": not _spec.is_empty(), "level_id": _spec.get("level_id", ""),
        "encounter_key": _spec.get("encounter_key", ""), "opened": _opened,
        "route": _route, "started": _started, "certified": _certified,
        "solved": solved(), "tick": _tick, "cells_left": _cells_left,
        "crew_capacity": int(_spec.get("crew_capacity", 0)),
        "active_crews": _active.size(), "aborts": _aborts, "reopens": _reopens,
        "optional_logged": _optional_logged, "states": _states.duplicate(true),
        "history": _history.duplicate(true), "qualification": QUALIFICATION}
