extends "res://tests/test_case.gd"
## EXP013 A02-A04: full source/headless collection replays, source pins and
## compatibility. No physical reach, collision, controller or GPU testing.

const Atlas := preload("res://scripts/world/dispatch_atlas.gd")
const Worksite := preload("res://scripts/gameplay/expedition_worksite_orders.gd")
const SiteCatalog := preload("res://scripts/gameplay/expedition_site_exp013.gd")
const SiteEngine := preload("res://scripts/gameplay/expedition_site_interventions.gd")
const Runtime := preload("res://scripts/gameplay/expedition_host_session.gd")


func _host_position(_principal: String) -> Vector3:
    return Vector3(35.0, 0.9, 35.0)


func _facts(route: String) -> Dictionary:
    return {"worksite_opened": true, "worksite_route": route,
        "balancing_solved": true, "logistics_solved": true,
        "consequences_solved": true, "faults_solved": true,
        "west_restored": true, "east_on": true, "hazard_active": false}


func _complete_step(site: SiteEngine, facts: Dictionary) -> void:
    var item: Dictionary = site.snapshot()["next"]
    assert_false(item.is_empty(), "EXP013: missing source step")
    if item.is_empty():
        return
    var target: String = str(item["target"])
    var support: String = str(item["support_target"])
    var reply: Dictionary = site.operate(target, str(item["action"]), facts)
    assert_true(bool(reply.get("ok", false)), str(reply))
    if not bool(reply.get("ok", false)):
        return
    for i: int in range(int(item["dwell_ticks"])):
        site.advance(facts)
    assert_eq(str(site.snapshot()["phase"]), "stable")
    match str(item["mode"]):
        "hold":
            assert_true(bool(site.operate(target, "confirm", facts).get("ok", false)))
        "pulse":
            assert_true(bool(site.operate(target, "pulse", facts).get("ok", false)))
        "sample":
            assert_true(bool(site.operate(support, "read", facts).get("ok", false)))
            for j: int in range(3):
                site.advance(facts)
            assert_true(bool(site.operate(support, "read", facts).get("ok", false)))
            assert_true(bool(site.operate(target, "confirm", facts).get("ok", false)))
        "handoff":
            assert_true(bool(site.operate(support, "transfer", facts).get("ok", false)))
            assert_true(bool(site.operate(target, "commit", facts).get("ok", false)))
        "balance":
            assert_true(bool(site.operate(support, "trim", facts).get("ok", false)))
            for j: int in range(4):
                site.advance(facts)
            assert_true(bool(site.operate(target, "confirm", facts).get("ok", false)))
        _:
            assert_true(false, "Unknown authored EXP013 operation")


func test_EXP013_expansions_each_complete_80_host_routes_without_client_clocks() -> void:
    var books: Array[Dictionary] = SiteCatalog.load_available_books()
    var audit: Dictionary = SiteCatalog.inspect_collection(
        Atlas.load_catalog(), Worksite.load_book(), books)
    assert_true(bool(audit.get("ok", false)), str(audit))
    if not bool(audit.get("ok", false)):
        return
    assert_true(books.size() >= 2, "EXP013 A02 expansion not exported")
    assert_eq(int(audit["cumulative_scripted"]), 40 + books.size() * 40)
    for book_index: int in range(1, books.size()):
        for item: Dictionary in books[book_index]["entries"]:
            for route: String in ["priority", "resilience"]:
                var site: SiteEngine = SiteEngine.new()
                assert_true(bool(site.configure(item).get("ok", false)))
                assert_true(bool(site.choose_route(route).get("ok", false)))
                var facts: Dictionary = _facts(route)
                for stage: int in range(4):
                    _complete_step(site, facts)
                    assert_eq(int(site.snapshot()["step"]), stage + 1)
                assert_true(site.solved(), "Host route deadlocked: " +
                    str(item["level_id"]) + " " + route)


func test_EXP013_expansions_source_splices_are_rejected_before_host_binding() -> void:
    var atlas: Dictionary = Atlas.load_catalog()
    var orders: Dictionary = Worksite.load_book()
    var books: Array[Dictionary] = SiteCatalog.load_available_books()
    var broken: Array[Dictionary] = books.duplicate(true)
    broken[1]["entries"][0]["source_task_ids"][0] = "FORGED_JOB"
    assert_false(SiteCatalog.inspect_collection(atlas, orders, broken)["ok"],
        "Spliced tasks should be denied by the host source catalog")


func test_EXP013_expansions_opt_in_and_uncovered_levels_do_not_change_legacy() -> void:
    var books: Array[Dictionary] = SiteCatalog.load_available_books()
    for source_index: int in range(1, books.size()):
        var serial: int = 41 + source_index * 40
        var requested: String = "LV_%03d" % serial
        var session: Runtime = Runtime.new()
        var start: Dictionary = session.start(requested, Callable(self, "_host_position"),
            Callable(), "", false, "", true, true, true, true, true, true, true, true, true)
        assert_true(bool(start.get("ok", false)), str(start))
        if not bool(start.get("ok", false)):
            return
        assert_true(session.site_exp013 != null, "Missing new site machine: " + requested)
        assert_true(session.site_a02 == null, "EXP012 A02 overlap: " + requested)
        assert_eq(str(session.site_exp013.definition_snapshot()["level_id"]), requested)
        assert_true(str(start["content_revision"]).begins_with("EXP013_"))
        assert_eq(str(session.definition_snapshot().get("site_exp013_phase", "")),
            "A0%d" % (source_index + 1))
        assert_true(session.host.authoritative_state()["exp012_worksite_orders"].has("site_exp013"))
        for id: Variant in session.site_exp013.target_ids():
            assert_true(session._definitions["positions"].has(str(id)), "No host target position: " + str(id))
    var latest: int = 41 + books.size() * 40
    if latest <= 200:
        var uncovered: Runtime = Runtime.new()
        var result: Dictionary = uncovered.start("LV_%03d" % latest,
            Callable(self, "_host_position"), Callable(),
            "", false, "", true, true, true, true, true, true, true, true, true)
        assert_true(bool(result.get("ok", false)), str(result))
        if bool(result.get("ok", false)):
            assert_true(uncovered.site_exp013 == null, "Uncovered site unexpectedly promoted")
