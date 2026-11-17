extends "res://tests/test_case.gd"
## CT-L3/C10: blueprint-sourced Hill Road Community Night host and safety tests.
## No physical stage, export-GPU, old released save or real Steam certification.

const Runner := preload("res://tests/support/solution_runner.gd")
const Grid := preload("res://scripts/simulation/power_grid.gd")
const Mission := preload("res://scripts/simulation/mission_director.gd")
const Host := preload("res://scripts/network/session_host.gd")
const HudPresenter := preload("res://scripts/ui/hud_presenter.gd")

const C10: String = "res://content/contracts/c10_community_night"
const EARLIER: Array[String] = [
	"res://content/contracts/c01_alder_street",
	"res://content/contracts/c02_dinner_rush",
	"res://content/contracts/c03_roof_route",
	"res://content/contracts/c04_whole_block",
	"res://content/contracts/c05_canal_pump_access",
	"res://content/contracts/c06_cold_chain",
	"res://content/contracts/c07_wrong_label",
	"res://content/contracts/c08_split_supply",
	"res://content/contracts/c09_wind_warning",
]


func _trace() -> Dictionary:
	return Runner.json(C10.path_join("solution.json"))


func _context(players: Array = ["P1"]) -> Dictionary:
	return Runner.build(C10, players, _trace()["tools"])


func _switch(ctx: Dictionary, id: String, value: bool) -> Dictionary:
	return Runner.send(ctx, "P1", "toggle_switch", id, {"value": value})


func _up_to_stage(ctx: Dictionary) -> void:
	var before_wait: Array = []
	for step: Dictionary in _trace()["steps"]:
		if step.has("ticks") and int(step["ticks"]) == 100:
			break
		before_wait.append(step)
	assert_eq(Runner.run(ctx, before_wait, 1), [] as Array[String])
	assert_true((ctx["grid"] as Grid).canonical_state()["nodes"]["STAGE"]["supplied"])


func _west_only(ctx: Dictionary) -> void:
	var prefix: Array = []
	var done: bool = false
	for step: Dictionary in _trace()["steps"]:
		prefix.append(step)
		if step.get("entity", "") == "R_WEST_FUSE" and step.get("payload", {}).get("step", "") == "restore":
			done = true
			break
	assert_true(done)
	assert_eq(Runner.run(ctx, prefix, 1), [] as Array[String])


func _finish(ctx: Dictionary) -> void:
	var m: Mission = ctx["mission"] as Mission
	var needed: int = 100 - int(m.canonical_state()["verify_ticks"])
	if needed > 0:
		Runner.ticks(ctx, needed)
	(ctx["host"] as Host).set_in_zone("P1", "ZONE_VAN", true)
	assert_true(Runner.send(ctx, "P1", "request_extract", "ZONE_VAN", {"action": "start"}).get("ok", false))
	Runner.ticks(ctx, 50)
	assert_true(m.is_complete())


func test_CTL3_C10_original_grid_and_two_safe_stage_routes() -> void:
	var ctx: Dictionary = _context()
	assert_eq(ctx["errors"], [] as Array[Dictionary], str(ctx["errors"]))
	var g: Dictionary = (ctx["grid"] as Grid).canonical_state()
	assert_eq(g["nodes"]["GRID"]["capacity"], 28)
	assert_eq(g["nodes"]["GEN"]["capacity"], 6)
	assert_eq(g["edges"]["E_GRID_WEST"]["capacity"], 14)
	assert_eq(g["edges"]["E_GRID_EAST"]["capacity"], 14)
	assert_true(g["nodes"]["WEST"]["failed"])
	assert_true(g["nodes"]["WEST"]["tripped"])
	assert_true(g["edges"]["E_GRID_EAST"]["healthy"])
	assert_eq(g["nodes"]["GRID"]["load"], 12)
	assert_false(g["nodes"]["STAGE"]["supplied"])
	assert_true(g["nodes"]["STAGE"]["enabled"])
	assert_eq(g["nodes"]["STAGE"]["demand"], 3)
	assert_eq(g["edges"]["E_GRID_STAGE"]["capacity"], 4)
	assert_false(g["edges"]["E_GRID_STAGE"]["enabled"])
	assert_true(g["nodes"]["WEST_STAGE"]["isolated"])
	var mission: Dictionary = Runner.json(C10.path_join("mission.json"))
	assert_eq(mission["required_consumers"].size(), 6)
	assert_eq(int(mission["optional_timed_latch"]["deadline_ticks"]), 2400)
	assert_eq(int(mission["access_latches"][0]["supplied_ticks"]), 100)
	assert_eq(mission["optional_latch_rewards"], ["LATCH_STAGE"])
	assert_eq(mission["optional_services"], [] as Array)


func test_CTL3_C10_full_solution_qualifies_stage_without_overloading_grid() -> void:
	var ctx: Dictionary = _context()
	var trace: Dictionary = _trace()
	assert_eq(Runner.run(ctx, trace["steps"], int(trace["pace_ticks_per_command"])),
		[] as Array[String])
	var m: Mission = ctx["mission"] as Mission
	assert_true(m.is_complete())
	assert_true(int(ctx["now"]) <= int(trace["max_ticks"]))
	assert_eq(m.results()["required_total"], 6)
	assert_eq(m.results()["required_restored"], 6)
	assert_eq(m.results()["optional_services"], ["STAGE"])
	assert_eq(m.results()["optional_total"], 1)
	assert_eq(m.results()["preventable_trips"], 0)
	assert_eq(m.results()["stars"], 3)
	assert_true(m.canonical_state()["timed_latch_bonus"]["on_time"])
	var g: Dictionary = (ctx["grid"] as Grid).canonical_state()
	assert_eq(g["nodes"]["GRID"]["load"], 28)
	assert_eq(g["edges"]["E_GRID_WEST"]["flow"], 13)
	assert_eq(g["edges"]["E_GRID_EAST"]["flow"], 12)
	assert_eq(g["edges"]["E_GRID_STAGE"]["flow"], 3)
	assert_false(g["nodes"]["GEN"]["online"])


func test_CTL3_C10_100_continuous_stage_ticks_reset_on_same_tick_loss() -> void:
	var ctx: Dictionary = _context()
	_up_to_stage(ctx)
	var m: Mission = ctx["mission"] as Mission
	assert_true(_switch(ctx, "SW_STAGE", false).get("ok", false))
	assert_true(_switch(ctx, "SW_STAGE", true).get("ok", false))
	Runner.ticks(ctx, 99)
	assert_false(m.is_latched("LATCH_STAGE"))
	assert_eq(int(m.canonical_state()["latch_ticks"]["LATCH_STAGE"]), 99)
	assert_true(_switch(ctx, "SW_STAGE", false).get("ok", false))
	assert_eq(int(m.canonical_state()["latch_ticks"]["LATCH_STAGE"]), 0)
	assert_true(_switch(ctx, "SW_STAGE", true).get("ok", false))
	Runner.ticks(ctx, 99)
	assert_false(m.is_latched("LATCH_STAGE"))
	Runner.ticks(ctx, 1)
	assert_true(m.is_latched("LATCH_STAGE"))
	assert_true(m.canonical_state()["timed_latch_bonus"]["on_time"])


func test_CTL3_C10_event_exact_tick_2400_awards_bonus() -> void:
	var ctx: Dictionary = _context()
	_up_to_stage(ctx)
	assert_true(_switch(ctx, "SW_STAGE", false).get("ok", false))
	Runner.ticks(ctx, 2300 - int(ctx["now"]))
	assert_false((ctx["mission"] as Mission).canonical_state()["timed_latch_bonus"]["missed"])
	assert_true(_switch(ctx, "SW_STAGE", true).get("ok", false))
	Runner.ticks(ctx, 100)
	var m: Mission = ctx["mission"] as Mission
	assert_eq(int(ctx["now"]), 2400)
	assert_true(m.canonical_state()["timed_latch_bonus"]["on_time"])
	assert_false(m.canonical_state()["timed_latch_bonus"]["missed"])
	assert_true(m.is_latched("LATCH_STAGE"))
	_finish(ctx)
	assert_eq(m.results()["stars"], 3)


func test_CTL3_C10_event_one_tick_late_loses_bonus_only() -> void:
	var ctx: Dictionary = _context()
	_up_to_stage(ctx)
	assert_true(_switch(ctx, "SW_STAGE", false).get("ok", false))
	Runner.ticks(ctx, 2301 - int(ctx["now"]))
	assert_true(_switch(ctx, "SW_STAGE", true).get("ok", false))
	Runner.ticks(ctx, 100)
	var m: Mission = ctx["mission"] as Mission
	assert_eq(int(ctx["now"]), 2401)
	assert_true(m.is_latched("LATCH_STAGE"), "late stage still physically supplies")
	assert_false(m.canonical_state()["timed_latch_bonus"]["on_time"])
	assert_true(m.canonical_state()["timed_latch_bonus"]["missed"])
	_finish(ctx)
	assert_eq(m.results()["required_restored"], 6)
	assert_eq(m.results()["optional_services"], [] as Array[String])
	assert_eq(m.results()["stars"], 2)


func test_CTL3_C10_unsafe_west_stage_16_over_14_causes_protection_trip() -> void:
	var ctx: Dictionary = _context()
	_west_only(ctx)
	assert_eq((ctx["grid"] as Grid).canonical_state()["nodes"]["GRID"]["load"], 25)
	assert_true(_switch(ctx, "SW_WEST_STAGE", false).get("ok", false))
	var before: Dictionary = (ctx["grid"] as Grid).canonical_state()
	assert_eq(before["edges"]["E_GRID_WEST"]["flow"], 16)
	Runner.ticks(ctx, 15)
	assert_true((ctx["grid"] as Grid).canonical_state()["nodes"]["WEST"]["tripped"])
	assert_true(_switch(ctx, "SW_WEST_STAGE", true).get("ok", false))
	assert_true(_switch(ctx, "SW_WEST_BREAKER", false).get("ok", false))
	assert_false((ctx["grid"] as Grid).canonical_state()["nodes"]["WEST"]["tripped"])


func test_CTL3_C10_dual_stage_paths_refused_before_mutation() -> void:
	var ctx: Dictionary = _context()
	_up_to_stage(ctx)
	var before: Dictionary = (ctx["grid"] as Grid).canonical_state()
	var reply: Dictionary = _switch(ctx, "SW_WEST_STAGE", false)
	assert_false(reply.get("ok", false), "cannot energize both routes into stage")
	assert_eq((ctx["grid"] as Grid).canonical_state(), before,
		"invalid topology must not partially switch any circuit")


func test_CTL3_C10_optional_stage_skipped_core_still_completes() -> void:
	var ctx: Dictionary = _context()
	_west_only(ctx)
	_finish(ctx)
	var m: Mission = ctx["mission"] as Mission
	assert_false(m.is_latched("LATCH_STAGE"))
	assert_eq(m.results()["required_restored"], 6)
	assert_eq(m.results()["optional_services"], [] as Array[String])
	assert_eq(m.results()["stars"], 2)
	assert_eq((ctx["grid"] as Grid).canonical_state()["nodes"]["GRID"]["load"], 25)


func test_CTL3_C10_optional_deadline_expiry_before_repair_never_fails_mission() -> void:
	var ctx: Dictionary = _context()
	Runner.ticks(ctx, 2401)
	assert_true((ctx["mission"] as Mission).canonical_state()["timed_latch_bonus"]["missed"])
	_west_only(ctx)
	_finish(ctx)
	assert_true((ctx["mission"] as Mission).is_complete())
	assert_eq((ctx["mission"] as Mission).results()["stars"], 2)


func test_CTL3_C10_persisted_event_clock_resumes_relative_to_save() -> void:
	var ctx: Dictionary = _context()
	Runner.ticks(ctx, 1000)
	var original: Dictionary = (ctx["mission"] as Mission).durable_state()
	var other: Dictionary = _context()
	var m: Mission = other["mission"] as Mission
	assert_eq(m.restore_state(original), [] as Array[Dictionary])
	assert_eq(m.durable_state(), original)
	Runner.ticks(other, 15)
	assert_eq(int(m.canonical_state()["timed_latch_bonus"]["elapsed_ticks"]), 1015)


func test_CTL3_C10_bad_event_checkpoint_rejected_unchanged() -> void:
	var ctx: Dictionary = _context()
	Runner.ticks(ctx, 50)
	var m: Mission = ctx["mission"] as Mission
	var original: Dictionary = m.durable_state()
	for invalid: Dictionary in [
		{"elapsed_ticks": -1, "on_time": false, "missed": false},
		{"elapsed_ticks": true, "on_time": false, "missed": false},
		{"elapsed_ticks": 2402, "on_time": false, "missed": true},
		{"elapsed_ticks": 200, "on_time": true, "missed": false},
		{"elapsed_ticks": 2401, "on_time": false, "missed": false},
		{"elapsed_ticks": 2401, "on_time": false, "missed": true, "forged": true}
	]:
		var forged: Dictionary = original.duplicate(true)
		forged["timed_latch_bonus"] = invalid
		assert_false(m.restore_state(forged).is_empty(), str(invalid))
		assert_eq(m.durable_state(), original)
	var missing: Dictionary = original.duplicate(true)
	missing.erase("timed_latch_bonus")
	assert_false(m.restore_state(missing).is_empty())
	assert_eq(m.durable_state(), original)


func test_CTL3_C10_invalid_event_rules_fail_closed_at_content_load() -> void:
	var trace: Dictionary = _trace()
	var definition: Dictionary = Runner.json(C10.path_join("mission.json"))["optional_timed_latch"]
	for invalid: Variant in [0, -1, true, "deadline", 1.5, 99]:
		var overridden: Dictionary = definition.duplicate(true)
		overridden["deadline_ticks"] = invalid
		var broken: Dictionary = Runner.build(C10, trace["players"], trace["tools"],
			{"optional_timed_latch": overridden})
		assert_false((broken["errors"] as Array).is_empty(), str(invalid))
	for wrong: Dictionary in [{"latch":"UNKNOWN_LATCH"}, {"start_trigger":"client_clock"}]:
		var overridden: Dictionary = definition.duplicate(true)
		overridden.merge(wrong, true)
		var broken: Dictionary = Runner.build(C10, trace["players"], trace["tools"],
			{"optional_timed_latch": overridden})
		assert_false((broken["errors"] as Array).is_empty(), str(wrong))


func test_CTL3_C10_authoritative_hud_projection_contains_no_local_timer() -> void:
	var ctx: Dictionary = _context()
	var m: Mission = ctx["mission"] as Mission
	var state: Dictionary = (ctx["host"] as Host).authoritative_state()
	var view: Dictionary = HudPresenter.build(state, m.objectives(), {"local_player":"P1", "tools":[]})
	assert_true(view.has("timed_latch_bonus"))
	assert_eq(view["timed_latch_bonus"]["remaining_ticks"], 2400)
	Runner.ticks(ctx, 17)
	state = (ctx["host"] as Host).authoritative_state()
	view = HudPresenter.build(state, m.objectives(), {"local_player":"P1", "tools":[]})
	assert_eq(view["timed_latch_bonus"]["remaining_ticks"], 2383)


func test_CTL3_C10_two_players_can_complete_solo_solvable_contract() -> void:
	var ctx: Dictionary = _context(["P1", "P2"])
	var steps: Array = _trace()["steps"].duplicate(true)
	for i: int in steps.size():
		if steps[i].get("intent", "") == "request_extract":
			steps.insert(i, {"zone":"ZONE_VAN","as":"P2","inside":true})
			break
	assert_eq(Runner.run(ctx, steps, 1), [] as Array[String])
	assert_true((ctx["mission"] as Mission).is_complete())
	assert_eq((ctx["mission"] as Mission).results()["stars"], 3)


func test_CTL3_C10_earlier_contract_saves_have_no_new_fields() -> void:
	for directory: String in EARLIER:
		var trace: Dictionary = Runner.json(directory.path_join("solution.json"))
		var ctx: Dictionary = Runner.build(directory, trace["players"], trace["tools"])
		assert_eq(ctx["errors"], [] as Array[Dictionary], directory)
		var m: Mission = ctx["mission"] as Mission
		var saved: Dictionary = m.durable_state()
		assert_false(saved.has("timed_latch_bonus"), directory)
		assert_eq(m.restore_state(saved), [] as Array[Dictionary], directory)
		assert_eq(m.durable_state(), saved, directory)


func test_CTL3_C10_all_objective_and_tablet_text_is_localized() -> void:
	var strings: Dictionary = Runner.json("res://content/ui/strings/en.json")["strings"]
	var visited: Dictionary = {}
	for record: Dictionary in Runner.json(C10.path_join("tablet.json"))["nodes"]:
		assert_false(visited.has(record["id"]))
		visited[record["id"]] = true
		assert_true(strings.has(record["name_key"]), str(record["name_key"]))
	for objective: Dictionary in Runner.json(C10.path_join("mission.json"))["objectives"]:
		assert_true(strings.has(objective["text_key"]), str(objective["text_key"]))
	for key: String in ["hud.stage_deadline.remaining", "hud.stage_deadline.achieved",
		"hud.stage_deadline.missed"]:
		assert_true(strings.has(key))
	assert_eq(visited.size(), 14)
