extends "res://tests/test_case.gd"
## EXP013 A01 source/headless test: second forty authored worksite encounters.
## Reuses EXP012 A02's host procedure engine, not the original C01-C12 state.
## No physical, controller, GPU, Steam or release verification is implied.

const Atlas := preload("res://scripts/world/dispatch_atlas.gd")
const Worksite := preload("res://scripts/gameplay/expedition_worksite_orders.gd")
const SiteEXP013 := preload("res://scripts/gameplay/expedition_site_exp013.gd")
const SiteEngine := preload("res://scripts/gameplay/expedition_site_interventions.gd")
const Runtime := preload("res://scripts/gameplay/expedition_host_session.gd")

var _position: Vector3 = Vector3(25.0, 0.90, 25.0)


func before_each() -> void:
    _position = Vector3(25.0, 0.90, 25.0)


func _host_position(_player: String) -> Vector3:
    return _position


func _facts(route: String = "priority") -> Dictionary:
    return {"worksite_opened": true, "worksite_route": route,
        "balancing_solved": true, "logistics_solved": true,
        "consequences_solved": true, "faults_solved": true,
        "west_restored": true, "east_on": true, "hazard_active": false}


func _finish_one(site: SiteEngine, facts: Dictionary) -> void:
    var step: Dictionary = site.snapshot()["next"]
    assert_false(step.is_empty(), "Missing EXP013 step")
    if step.is_empty():
        return
    var primary: String = str(step["target"])
    var assistant_target: String = str(step["support_target"])
    assert_true(site.operate(primary, str(step["action"]), facts)["ok"])
    for i: int in range(int(step["dwell_ticks"])):
        site.advance(facts)
    assert_eq(site.snapshot()["phase"], "stable")
    match str(step["mode"]):
        "hold":
            assert_true(site.operate(primary, "confirm", facts)["ok"])
        "pulse":
            assert_true(site.operate(primary, "pulse", facts)["ok"])
        "sample":
            assert_true(site.operate(assistant_target, "read", facts)["ok"])
            for j: int in range(3):
                site.advance(facts)
            assert_true(site.operate(assistant_target, "read", facts)["ok"])
            assert_true(site.operate(primary, "confirm", facts)["ok"])
        "handoff":
            assert_true(site.operate(assistant_target, "transfer", facts)["ok"])
            assert_true(site.operate(primary, "commit", facts)["ok"])
        "balance":
            assert_true(site.operate(assistant_target, "trim", facts)["ok"])
            for j: int in range(4):
                site.advance(facts)
            assert_true(site.operate(primary, "confirm", facts)["ok"])
        _:
            assert_true(false, "Unknown EXP013 operation")


func _wire(run: Runtime, sequence: int, target: String, action: String,
        forged: Dictionary = {}) -> Dictionary:
    var payload: Dictionary = {"action": action}
    payload.merge(forged)
    return run.receive(1, JSON.stringify({
        "session": run.session_id(), "seq": sequence, "type": "operate_worksite",
        "entity": target, "payload": payload}).to_utf8_buffer())


func test_EXP013_A01_40_authored_sites_80_distinct_routes_and_320_steps() -> void:
    var atlas: Dictionary = Atlas.load_catalog()
    var book: Dictionary = SiteEXP013.load_book()
    var audit: Dictionary = SiteEXP013.inspect(atlas, Worksite.load_book(), book)
    assert_true(bool(audit.get("ok", false)), str(audit))
    if not bool(audit.get("ok", false)):
        return
    assert_eq(audit["new_sites"], 40)
    assert_eq(audit["total_individually_scripted"], 80)
    assert_eq(audit["remaining_sites"], 120)
    assert_eq(audit["routes"], 80)
    assert_eq(audit["route_steps"], 320)
    assert_eq(audit["targets"], 120)
    for entry: Dictionary in book["entries"]:
        for route: String in ["priority", "resilience"]:
            var site: SiteEngine = SiteEngine.new()
            assert_true(site.configure(entry)["ok"])
            assert_true(site.choose_route(route)["ok"])
            var facts: Dictionary = _facts(route)
            assert_eq(site.target_ids().size(), 3)
            for step_index: int in range(4):
                _finish_one(site, facts)
                assert_eq(site.snapshot()["step"], step_index + 1)
            assert_true(site.solved(), "Deadlock: " + str(entry["level_id"]) + " " + route)
            assert_eq(site.snapshot()["step_count"], 4)


func test_EXP013_A01_host_selection_respects_opt_in_and_previous_40_sites() -> void:
    # EXP012 A02-only continues to leave 041 uncovered.
    var old: Runtime = Runtime.new()
    var earlier: Dictionary = old.start("LV_041", Callable(self, "_host_position"),
        Callable(), "", false, "", true, true, true, true, true, true, true, true)
    assert_true(earlier["ok"], str(earlier))
    if not earlier["ok"]:
        return
    assert_true(old.site_a02 == null, "Old LV_041 opt-in unexpectedly instantiated A02")
    assert_true(old.site_exp013 == null, "Old LV_041 opt-in unexpectedly instantiated EXP013")
    assert_false(old.host.authoritative_state()["exp012_worksite_orders"].has("site_exp013"))

    var next: Runtime = Runtime.new()
    var started: Dictionary = next.start("LV_041", Callable(self, "_host_position"),
        Callable(), "", false, "", true, true, true, true, true, true, true, true, true)
    assert_true(started["ok"], str(started))
    if not started["ok"]:
        return
    assert_true(next.site_a02 == null, "New LV_041 unexpectedly matched A02")
    assert_true(next.site_exp013 != null, "New LV_041 did not instantiate EXP013")
    assert_eq(str(next.site_exp013.definition_snapshot()["level_id"]), "LV_041")
    assert_true(next.host.authoritative_state()["exp012_worksite_orders"].has("site_exp013"), "Host snapshot missing EXP013")
    assert_true(str(started["content_revision"]).begins_with("EXP013_"), "EXP013 revision namespace wrong")
    assert_true(next._definitions["positions"].has("SC_041_A"), "Missing A position")
    assert_true(next._definitions["positions"].has("SC_041_B"), "Missing B position")
    assert_true(next._definitions["positions"].has("SC_041_C"), "Missing C position")
    var old_hash: String = old.state_hash()
    var new_hash: String = next.state_hash()
    assert_true(old_hash != new_hash, "Full expedition session hashes must bind the authored source overlay")

    # The same opt-in never changes LV_001's original A02 source.
    var first: Runtime = Runtime.new()
    var first_start: Dictionary = first.start("LV_001", Callable(self, "_host_position"),
        Callable(), "", false, "", true, true, true, true, true, true, true, true)
    assert_true(first_start["ok"], str(first_start))
    if first_start["ok"]:
        assert_true(first.site_a02 != null, "LV_001 A02 not active under both flags")
        assert_true(first.site_exp013 == null, "LV_001 unexpectedly activated EXP013")

    # The next uncovered location must remain A01-only even with EXP013 enabled.
    var uncovered: Runtime = Runtime.new()
    var uncovered_start: Dictionary = uncovered.start("LV_081", Callable(self, "_host_position"),
        Callable(), "", false, "", true, true, true, true, true, true, true, true)
    assert_true(uncovered_start["ok"], str(uncovered_start))
    if uncovered_start["ok"]:
        assert_true(uncovered.site_a02 == null, "LV_081 incorrectly matched A02")
        assert_true(uncovered.site_exp013 == null, "LV_081 incorrectly matched EXP013")


func test_EXP013_A01_authority_refuses_forged_commands_and_unreachable_targets() -> void:
    var run: Runtime = Runtime.new()
    var result: Dictionary = run.start("LV_044", Callable(self, "_host_position"),
        Callable(), "", false, "", true, true, true, true, true, true, true, true, true)
    assert_true(result["ok"], str(result))
    if not result["ok"]:
        return
    var target: String = str(run.site_exp013.definition_snapshot()["targets"]["A"])
    var pristine: String = run.host.state_hash()
    assert_false(bool(_wire(run, 1, target, "confirm", {"host_tick": 999})["ok"]))
    assert_eq(run.host.state_hash(), pristine)
    assert_true(bool(_wire(run, 1, target, "confirm").get("duplicate", false)))
    assert_eq(run.host.state_hash(), pristine)
    assert_eq(_wire(run, 2, target, "confirm").get("code"), "NOT_IN_RANGE")
    assert_eq(run.host.state_hash(), pristine)


func test_EXP013_A01_source_splice_and_host_fault_recovery() -> void:
    var atlas: Dictionary = Atlas.load_catalog()
    var orders: Dictionary = Worksite.load_book()
    var book: Dictionary = SiteEXP013.load_book()
    var forged: Dictionary = book.duplicate(true)
    forged["entries"][0]["source_task_ids"][0] = "JOB_999_1"
    assert_false(SiteEXP013.inspect(atlas, orders, forged)["ok"])

    var entry: Dictionary = book["entries"][0]
    var site: SiteEngine = SiteEngine.new()
    assert_true(site.configure(entry)["ok"])
    assert_true(site.choose_route("priority")["ok"])
    var facts: Dictionary = _facts()
    _finish_one(site, facts)
    var unsafe: Dictionary = facts.duplicate()
    unsafe["east_on"] = false
    site.advance(unsafe)
    assert_eq(site.snapshot()["fault"], "SUPPLY_LOST")
    assert_eq(site.snapshot()["step"], 0)
    assert_false(site.solved())
    assert_eq(site.operate(str(entry["recovery_target"]), "recover", unsafe)["code"],
        "EXP012A02_UPSTREAM_INTERLOCK")
    assert_true(site.operate(str(entry["recovery_target"]), "recover", facts)["ok"])
    for i: int in range(4):
        _finish_one(site, facts)
    assert_true(site.solved())
