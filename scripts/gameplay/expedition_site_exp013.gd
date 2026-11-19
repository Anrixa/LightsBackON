extends RefCounted
## EXP013 A01: independent source audit for LV_041-LV_080 interventions.
## Reuses the proven EXP012 A02 host state machine; no client clock or verdict.
## No physical interaction reach, collisions, real network, or release qualified.

const PATH: String = "res://scenes/expeditions/site_interventions_exp013.json"
const AUTHORITY: String = "EXP013_A01_HOST_SITE_INTERVENTIONS"
const QUALIFICATION: String = "SOURCE_HEADLESS_ONLY_HUMAN_CONTROLLER_RELEASE_HELD"
const MODES: Array[String] = ["hold", "pulse", "sample", "handoff", "balance"]
const FAILURES: Array[String] = ["step", "backtrack", "restart"]


static func load_book() -> Dictionary:
    if not FileAccess.file_exists(PATH):
        return {}
    var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
    return value if value is Dictionary else {}


static func entry_for(book: Dictionary, level: Dictionary, order: Dictionary) -> Dictionary:
    for raw: Variant in book.get("entries", []):
        if not raw is Dictionary:
            return {}
        var item: Dictionary = raw
        if item.get("level_id") != level.get("id"):
            continue
        var task_ids: Array[String] = []
        for task: Dictionary in level.get("tasks", []):
            task_ids.append(str(task["id"]))
        if item.get("location_id") != level.get("location_id") or \
                item.get("source_puzzle_identity") != level.get("puzzle_identity") or \
                item.get("source_title") != level.get("title") or \
                item.get("source_task_ids") != task_ids or \
                item.get("worksite_encounter_key") != order.get("encounter_key"):
            return {}
        return item.duplicate(true)
    return {}


static func _integral_between(value: Variant, minimum: float, maximum: float) -> bool:
    if not [TYPE_INT, TYPE_FLOAT].has(typeof(value)):
        return false
    var number: float = float(value)
    return is_finite(number) and number == float(int(number)) and \
        number >= minimum and number <= maximum


## Refuse any mutation of level pins, 40-case coverage, target ownership,
## route semantics, distinct strategies, authored stakes or station offsets.
static func inspect(atlas: Dictionary, worksite_book: Dictionary, book: Dictionary) -> Dictionary:
    if book.get("schema_version") != 1 or book.get("authority") != AUTHORITY or \
            book.get("qualification") != QUALIFICATION or \
            book.get("atlas_revision") != atlas.get("revision"):
        return {"ok": false, "code": "EXP013_HEADER_INVALID"}
    var entries: Variant = book.get("entries")
    var levels: Array = atlas.get("levels", [])
    var orders: Array = worksite_book.get("entries", [])
    if not entries is Array or entries.size() != 40 or levels.size() != 200 or orders.size() != 200:
        return {"ok": false, "code": "EXP013_COUNT_INVALID"}
    var locations: Dictionary = {}
    for location: Dictionary in atlas.get("locations", []):
        locations[str(location["id"])] = location
    var targets: Dictionary = {}
    var titles: Dictionary = {}
    var signatures: Dictionary = {}
    var modes: Dictionary = {}
    var placements: Dictionary = {}
    for i: int in range(40):
        if not entries[i] is Dictionary:
            return {"ok": false, "code": "EXP013_ENTRY_INVALID", "index": i}
        var item: Dictionary = entries[i]
        var level: Dictionary = levels[i + 40]
        var order: Dictionary = orders[i + 40]
        var loc: Dictionary = locations.get(str(level.get("location_id", "")), {})
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
            return {"ok": false, "code": "EXP013_SOURCE_DRIFT", "index": i}
        var title: String = str(item.get("title", ""))
        var stakes: String = str(item.get("stakes", ""))
        if title.length() < 12 or titles.has(title) or stakes.length() < 65:
            return {"ok": false, "code": "EXP013_AUTHORSHIP_INVALID", "index": i}
        titles[title] = true
        var suffix: String = str(i + 41).pad_zeros(3)
        var expected: Dictionary = {
            "A": "SC_%s_A" % suffix,
            "B": "SC_%s_B" % suffix,
            "C": "SC_%s_C" % suffix}
        if item.get("targets") != expected or item.get("recovery_target") != expected["C"]:
            return {"ok": false, "code": "EXP013_TARGET_DRIFT", "index": i}
        var offsets: Variant = item.get("station_offsets_cm")
        if not offsets is Dictionary or offsets.size() != 3:
            return {"ok": false, "code": "EXP013_POSITION_INVALID"}
        var placement_key: String = ""
        for letter: String in ["A", "B", "C"]:
            var target: String = str(expected[letter])
            if targets.has(target):
                return {"ok": false, "code": "EXP013_DUPLICATE_TARGET"}
            targets[target] = true
            var pair: Variant = offsets.get(letter, [])
            if not pair is Array or pair.size() != 2 or \
                    not _integral_between(pair[0], -300.0, 300.0) or \
                    not _integral_between(pair[1], 70.0, 300.0):
                return {"ok": false, "code": "EXP013_POSITION_INVALID"}
            placement_key += str(pair) + "|"
        if placements.has(placement_key):
            return {"ok": false, "code": "EXP013_REUSED_STATION_PLAN"}
        placements[placement_key] = true
        var routes: Variant = item.get("routes")
        if not routes is Dictionary or routes.size() != 2 or \
                not routes.has("priority") or not routes.has("resilience"):
            return {"ok": false, "code": "EXP013_ROUTE_INVALID"}
        var route_signatures: Array[String] = []
        for route: String in ["priority", "resilience"]:
            var steps: Variant = routes[route]
            if not steps is Array or steps.size() != 4:
                return {"ok": false, "code": "EXP013_STEP_COUNT"}
            var signature: String = ""
            for raw_step: Variant in steps:
                if not raw_step is Dictionary:
                    return {"ok": false, "code": "EXP013_STEP_INVALID"}
                var step: Dictionary = raw_step
                if step.size() != 7 or not MODES.has(str(step.get("mode", ""))) or \
                        not FAILURES.has(str(step.get("failure", ""))) or \
                        not expected.values().has(step.get("target")) or \
                        not expected.values().has(step.get("support_target")) or \
                        step.get("target") == step.get("support_target") or \
                        not _integral_between(step.get("dwell_ticks"), 5.0, 20.0) or \
                        not _integral_between(step.get("window_ticks"), 40.0, 240.0):
                    return {"ok": false, "code": "EXP013_STEP_INVALID"}
                var action: String = str(step.get("action", ""))
                if action.length() < 8 or action.length() > 45 or \
                        not action.is_valid_identifier():
                    return {"ok": false, "code": "EXP013_ACTION_INVALID"}
                modes[str(step["mode"])] = true
                signature += "%s|%s|%s|%s;" % [
                    action, step["mode"], step["target"], step["support_target"]]
            route_signatures.append(signature)
        if route_signatures[0] == route_signatures[1] or signatures.has(route_signatures[0]):
            return {"ok": false, "code": "EXP013_STRATEGY_DUPLICATED"}
        signatures[route_signatures[0]] = true
    if targets.size() != 120 or titles.size() != 40 or signatures.size() != 40 or \
            placements.size() != 40 or modes.size() != MODES.size():
        return {"ok": false, "code": "EXP013_COVERAGE_INVALID"}
    return {"ok": true, "new_sites": 40, "total_individually_scripted": 80,
        "remaining_sites": 120, "routes": 80, "route_steps": 320, "targets": 120}
