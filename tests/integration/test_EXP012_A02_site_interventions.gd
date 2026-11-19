extends "res://tests/test_case.gd"
## EXP012 A02 source/headless qualification: 40 individually scripted sites,
## 80 operable strategies, five real host-transition modes, recoverable faults.
## Human/controller collision, reach, GPU and release remain explicitly held.

const Atlas := preload("res://scripts/world/dispatch_atlas.gd")
const Worksite := preload("res://scripts/gameplay/expedition_worksite_orders.gd")
const Balancing := preload("res://scripts/gameplay/expedition_critical_loads.gd")
const Site := preload("res://scripts/gameplay/expedition_site_interventions.gd")
const Runtime := preload("res://scripts/gameplay/expedition_host_session.gd")

var _position: Vector3 = Vector3(25.0, 0.90, 25.0)


func before_each() -> void:
    _position = Vector3(25.0, 0.90, 25.0)


func _host_position(_player: String) -> Vector3:
    return _position


func _wire(run: Runtime, seq: int, id: String, payload: Dictionary) -> Dictionary:
    return run.receive(1, JSON.stringify({
        "session": run.session_id(), "seq": seq, "type": "operate_worksite",
        "entity": id, "payload": payload}).to_utf8_buffer())


func _facts(route: String = "priority") -> Dictionary:
    return {"worksite_opened": true, "worksite_route": route,
        "balancing_solved": true, "logistics_solved": true,
        "consequences_solved": true, "faults_solved": true,
        "west_restored": true, "east_on": true, "hazard_active": false}


## Exact host operations used by the A02 HUD: physically different support
## target actions, delayed samples, trim settling and bounded pulse window.
func _complete_one(machine: Site, facts: Dictionary) -> void:
    var state: Dictionary = machine.snapshot()
    var step: Dictionary = state["next"]
    if step.is_empty():
        assert_true(false, "Missing source intervention step")
        return
    var start: String = str(step["target"])
    var helper: String = str(step["support_target"])
    var response: Dictionary = machine.operate(start, str(step["action"]), facts)
    assert_true(bool(response.get("ok", false)), str(response))
    if not bool(response.get("ok", false)):
        return
    for _i: int in range(int(step["dwell_ticks"])):
        machine.advance(facts)
    assert_eq(machine.snapshot()["phase"], "stable")
    var mode: String = str(step["mode"])
    match mode:
        "hold":
            assert_true(machine.operate(start, "confirm", facts)["ok"])
        "pulse":
            assert_true(machine.operate(start, "pulse", facts)["ok"])
        "handoff":
            assert_true(machine.operate(helper, "transfer", facts)["ok"])
            assert_true(machine.operate(start, "commit", facts)["ok"])
        "sample":
            assert_true(machine.operate(helper, "read", facts)["ok"])
            assert_eq(machine.operate(helper, "read", facts)["code"],
                "EXP012A02_SAMPLE_GAP_REQUIRED")
            for _t: int in range(3):
                machine.advance(facts)
            assert_true(machine.operate(helper, "read", facts)["ok"])
            assert_true(machine.operate(start, "confirm", facts)["ok"])
        "balance":
            assert_true(machine.operate(helper, "trim", facts)["ok"])
            assert_eq(machine.operate(start, "confirm", facts)["code"],
                "EXP012A02_BALANCE_SETTLING")
            for _t: int in range(4):
                machine.advance(facts)
            assert_true(machine.operate(start, "confirm", facts)["ok"])
        _:
            assert_true(false, "Unimplemented authored mechanical mode")


func test_EXP012_A02_40_source_bound_sites_80_routes_and_320_steps() -> void:
    var atlas: Dictionary = Atlas.load_catalog()
    var book: Dictionary = Site.load_book()
    var audit: Dictionary = Site.inspect(atlas, Worksite.load_book(), book)
    assert_true(bool(audit.get("ok", false)), str(audit))
    if not bool(audit.get("ok", false)):
        return
    assert_eq(audit["authored_locations"], 40)
    assert_eq(audit["remaining_locations"], 160)
    assert_eq(audit["routes"], 80)
    assert_eq(audit["route_steps"], 320)
    assert_eq(audit["host_targets"], 120)
    assert_eq(audit["mechanical_modes"], 5)
    for entry: Dictionary in book["entries"]:
        for route: String in ["priority", "resilience"]:
            var machine: Site = Site.new()
            assert_true(machine.configure(entry)["ok"])
            assert_eq(machine.target_ids().size(), 3)
            var facts: Dictionary = _facts(route)
            var next: Dictionary = machine.snapshot()
            assert_eq(machine.operate(str(entry["targets"]["A"]),
                "cheat", facts)["code"], "EXP012A02_ORDER_REQUIRED")
            for i: int in range(4):
                _complete_one(machine, facts)
                assert_eq(machine.snapshot()["step"], i + 1)
            assert_true(machine.solved(), "A02 route deadlocked: " +
                str(entry["level_id"]) + " " + route)
            var prior: String = JSON.stringify(machine.snapshot())
            machine.advance(facts)
            assert_eq(JSON.stringify(machine.snapshot()), prior)


func test_EXP012_A02_premature_confirmation_causes_bounded_recoverable_fault() -> void:
    var entry: Dictionary = Site.load_book()["entries"][0]
    var machine: Site = Site.new()
    assert_true(machine.configure(entry)["ok"])
    var facts: Dictionary = _facts()
    var start: String = str(entry["routes"]["priority"][0]["target"])
    assert_true(machine.operate(start,
        str(entry["routes"]["priority"][0]["action"]), facts)["ok"])
    var premature: Dictionary = machine.operate(start, "confirm", facts)
    assert_eq(premature["code"], "EXP012A02_PREMATURE_COMMIT")
    assert_true(bool(premature["needs_recovery"]))
    assert_eq(machine.operate(start,
        str(entry["routes"]["priority"][0]["action"]), facts)["code"],
        "EXP012A02_RECOVERY_REQUIRED")
    assert_true(machine.operate(str(entry["recovery_target"]), "recover", facts)["ok"])
    assert_eq(machine.snapshot()["step"], 0)
    assert_eq(machine.snapshot()["recoveries"], 1)
    _complete_one(machine, facts)


func test_EXP012_A02_missed_pulse_window_and_loss_of_supply_restart() -> void:
    var entry: Dictionary = Site.load_book()["entries"][0]
    var machine: Site = Site.new()
    assert_true(machine.configure(entry)["ok"])
    var facts: Dictionary = _facts()
    _complete_one(machine, facts)
    var unsafe: Dictionary = facts.duplicate()
    unsafe["east_on"] = false
    machine.advance(unsafe)
    assert_eq(machine.snapshot()["fault"], "SUPPLY_LOST")
    assert_eq(machine.snapshot()["step"], 0)
    assert_eq(machine.operate(str(entry["recovery_target"]), "recover", unsafe)["code"],
        "EXP012A02_UPSTREAM_INTERLOCK")
    assert_true(machine.operate(str(entry["recovery_target"]), "recover", facts)["ok"])
    # Reach the source pulse stage, then miss the narrow host pulse window.
    _complete_one(machine, facts)
    _complete_one(machine, facts)
    var step: Dictionary = machine.snapshot()["next"]
    assert_eq(step["mode"], "pulse")
    assert_true(machine.operate(str(step["target"]), str(step["action"]), facts)["ok"])
    for _i: int in range(int(step["dwell_ticks"]) + 20):
        machine.advance(facts)
    assert_eq(machine.snapshot()["fault"], "WINDOW_EXPIRED")
    assert_true(machine.operate(str(entry["recovery_target"]), "recover", facts)["ok"])
    assert_eq(machine.snapshot()["step"], 0)


func test_EXP012_A02_rejects_source_splices_and_forged_route_payloads() -> void:
    var atlas: Dictionary = Atlas.load_catalog()
    var a01: Dictionary = Worksite.load_book()
    var book: Dictionary = Site.load_book()
    var wrong: Dictionary = book.duplicate(true)
    wrong["entries"][0]["source_task_ids"][0] = "JOB_FORGED"
    assert_false(Site.inspect(atlas, a01, wrong)["ok"])
    var machine: Site = Site.new()
    assert_true(machine.configure(book["entries"][0])["ok"])
    var facts: Dictionary = _facts()
    var first: Dictionary = book["entries"][0]["routes"]["priority"][0]
    assert_eq(machine.operate(str(first["target"]), str(first["action"]),
        {"balancing_solved": true})["code"], "EXP012A02_UPSTREAM_INTERLOCK")
    assert_true(machine.operate(str(first["target"]), str(first["action"]), facts)["ok"])
    facts["worksite_route"] = "resilience"
    assert_eq(machine.operate(str(first["target"]), "confirm", facts)["code"],
        "EXP012A02_ROUTE_CHANGED")


func test_EXP012_A02_opt_in_dedupe_range_and_unaffected_160_levels() -> void:
    # Earlier EXP012 sessions keep the old serialized hash/target surface.
    var old: Runtime = Runtime.new()
    var old_start: Dictionary = old.start("LV_001", Callable(self, "_host_position"),
        Callable(), "", false, "", true, true, true, true, true, true, true)
    assert_true(old_start["ok"], str(old_start))
    if not old_start["ok"]:
        return
    assert_true(old.site_a02 == null)
    assert_false(old.host.authoritative_state()["exp012_worksite_orders"].has("site_a02"))
    var a02: Runtime = Runtime.new()
    var begun: Dictionary = a02.start("LV_001", Callable(self, "_host_position"),
        Callable(), "", false, "", true, true, true, true, true, true, true, true)
    assert_true(begun["ok"], str(begun))
    if not begun["ok"]:
        return
    assert_true(a02.site_a02 != null)
    assert_true(a02.host.authoritative_state()["exp012_worksite_orders"].has("site_a02"))
    var target: String = str(a02.site_a02.definition_snapshot()["targets"]["A"])
    var pristine: String = a02.host.state_hash()
    var bad: Dictionary = _wire(a02, 1, target, {"action": "confirm", "tick": 999})
    assert_false(bool(bad.get("ok", false)))
    assert_eq(a02.host.state_hash(), pristine)
    assert_true(bool(_wire(a02, 1, target, {"action": "confirm"}).get("duplicate", false)))
    assert_eq(a02.host.state_hash(), pristine)
    assert_eq(_wire(a02, 2, target, {"action": "confirm"}).get("code"), "NOT_IN_RANGE")
    assert_eq(a02.host.state_hash(), pristine)
    # Coverage honesty: LV_041 has no A02 script; opt-in degrades to A01 only.
    var uncovered: Runtime = Runtime.new()
    var next: Dictionary = uncovered.start("LV_041", Callable(self, "_host_position"),
        Callable(), "", false, "", true, true, true, true, true, true, true, true)
    assert_true(next["ok"], str(next))
    if next["ok"]:
        assert_true(uncovered.site_a02 == null)
        assert_false(uncovered.host.authoritative_state()["exp012_worksite_orders"].has("site_a02"))
