extends "res://tests/test_case.gd"
## CT-L1/C03 headless host receipt, grid, repair and solution regression.
const Runner := preload("res://tests/support/solution_runner.gd")
const Grid := preload("res://scripts/simulation/power_grid.gd")
const Mission := preload("res://scripts/simulation/mission_director.gd")
const Host := preload("res://scripts/network/session_host.gd")
const C01: String = "res://content/contracts/c01_alder_street"
const C02: String = "res://content/contracts/c02_dinner_rush"
const C03: String = "res://content/contracts/c03_roof_route"


func _trace() -> Dictionary:
	return Runner.json(C03.path_join("solution.json"))


func _context() -> Dictionary:
	var trace: Dictionary = _trace()
	return Runner.build(C03, trace["players"], trace["tools"])


func test_CTL1_C03_loads_all_content_and_starts_with_damaged_direct_feeder() -> void:
	var ctx: Dictionary = _context()
	assert_eq(ctx["errors"], [] as Array[Dictionary], str(ctx["errors"]))
	var grid: Dictionary = (ctx["grid"] as Grid).canonical_state()
	assert_true(grid["nodes"]["JW"]["energized"])
	assert_false(grid["nodes"]["JE"]["energized"])
	assert_false(grid["edges"]["E_GRID_JE"]["healthy"])
	assert_false(grid["edges"]["E_ROOF_JE"]["healthy"])
	assert_true(grid["nodes"]["TIE"]["isolated"])
	assert_eq(grid["edges"]["E_GRID_ROOF"]["capacity"], 12)
	assert_eq(Runner.json(C03.path_join("mission.json"))["fixed_ladders"].size(), 1)
	assert_eq(Runner.json(C03.path_join("mission.json"))["optional_services"], ["ROOF_BEACON"])
	assert_eq(Runner.json(C03.path_join("repairs.json"))["repairs"][0]["access"], "ROOF_REACHED")


func test_CTL1_C03_ladder_must_be_host_authorized_and_is_idempotent() -> void:
	var ctx: Dictionary = _context()
	var director: Mission = ctx["mission"] as Mission
	var before: String = (ctx["host"] as Host).state_hash()
	assert_eq(Runner.send(ctx, "P1", "request_lock", "R_ROOF_SPLICE", {}).get("code"), "NO_ACCESS")
	assert_eq((ctx["host"] as Host).state_hash(), before)
	assert_eq(Runner.send(ctx, "P1", "use_ladder", "UNKNOWN", {}).get("code"), "UNKNOWN_LADDER")
	assert_eq(Runner.send(ctx, "P1", "use_ladder", "LADDER_WEST", {"grants":"ROOF_REACHED"}).get("code"), "MALFORMED")
	assert_eq(director.use_ladder("LADDER_WEST", false).get("code"), "NOT_IN_RANGE")
	assert_false(director.canonical_state()["ladder_access"].has("LADDER_WEST"))
	assert_true(Runner.send(ctx, "P1", "use_ladder", "LADDER_WEST", {}).get("ok", false))
	var used_at: int = int(director.canonical_state()["ladder_access"]["LADDER_WEST"])
	var again: Dictionary = Runner.send(ctx, "P1", "use_ladder", "LADDER_WEST", {})
	assert_true(again.get("ok", false))
	assert_true(again.get("duplicate", false))
	assert_eq(int(director.canonical_state()["ladder_access"]["LADDER_WEST"]), used_at)
	assert_true(Runner.send(ctx, "P1", "request_lock", "R_ROOF_SPLICE", {}).get("ok", false))


func test_CTL1_C03_full_solution_stable_supply_and_equal_capacity_optional() -> void:
	var ctx: Dictionary = _context()
	assert_eq(ctx["errors"], [] as Array[Dictionary])
	var trace: Dictionary = _trace()
	var failures: Array[String] = Runner.run(ctx, trace["steps"], int(trace["pace_ticks_per_command"]))
	assert_eq(failures, [] as Array[String], str(failures))
	var director: Mission = ctx["mission"] as Mission
	assert_true(director.is_complete())
	assert_true(int(ctx["now"]) <= int(trace["max_ticks"]))
	var result: Dictionary = director.results()
	assert_eq(result["required_restored"], 5)
	assert_eq(result["optional_services"], ["ROOF_BEACON"])
	assert_eq(result["optional_total"], 1)
	assert_eq(result["preventable_trips"], 0)
	assert_eq(result["stars"], 3)
	var grid: Dictionary = (ctx["grid"] as Grid).canonical_state()
	assert_eq(grid["nodes"]["GRID"]["load"], 21)
	assert_eq(grid["edges"]["E_GRID_ROOF"]["flow"], 12)
	assert_false(grid["nodes"]["JW"]["tripped"])
	assert_true(director.canonical_state()["ladder_access"].has("LADDER_WEST"))


func test_CTL1_C03_wrong_crossfeed_trips_protection_and_can_be_reset() -> void:
	var ctx: Dictionary = _context()
	var reply: Dictionary = Runner.send(ctx, "P1", "toggle_switch", "SW_CROSSFEED", {"value": false})
	assert_true(reply.get("ok", false), str(reply))
	Runner.ticks(ctx, 16)
	assert_true((ctx["grid"] as Grid).canonical_state()["nodes"]["JW"]["tripped"])
	assert_false((ctx["mission"] as Mission).verified())
	assert_false((ctx["mission"] as Mission).is_complete())
	assert_true(Runner.send(ctx, "P1", "toggle_switch", "SW_CROSSFEED", {"value": true}).get("ok", false))
	assert_true(Runner.send(ctx, "P1", "toggle_switch", "SW_JW_BREAKER", {"value": false}).get("ok", false))
	assert_false((ctx["grid"] as Grid).canonical_state()["nodes"]["JW"]["tripped"])


func test_CTL1_C03_missed_optional_still_completes_with_two_stars() -> void:
	var ctx: Dictionary = _context()
	var trace: Dictionary = _trace()
	var without_beacon: Array = []
	for step: Dictionary in trace["steps"]:
		if str(step.get("entity", "")) != "SW_BEACON":
			without_beacon.append(step)
	var failures: Array[String] = Runner.run(ctx, without_beacon, int(trace["pace_ticks_per_command"]))
	assert_eq(failures, [] as Array[String], str(failures))
	var director: Mission = ctx["mission"] as Mission
	assert_true(director.is_complete())
	assert_eq(director.results()["stars"], 2)
	assert_eq(director.results()["optional_services"], [] as Array[String])
	assert_eq(director.results()["required_restored"], 5)


func test_CTL1_C03_ladder_receipt_restores_and_save_forgery_fails_closed() -> void:
	var ctx: Dictionary = _context()
	assert_true(Runner.send(ctx, "P1", "use_ladder", "LADDER_WEST", {}).get("ok", false))
	var saved: Dictionary = (ctx["mission"] as Mission).durable_state()
	var fresh: Dictionary = _context()
	var director: Mission = fresh["mission"] as Mission
	assert_eq(director.restore_state(saved), [] as Array[Dictionary])
	assert_true(Runner.send(fresh, "P1", "request_lock", "R_ROOF_SPLICE", {}).get("ok", false))
	var snapshot: Dictionary = director.durable_state()
	var forged: Dictionary = saved.duplicate(true)
	forged["ladder_access"] = {"UNLISTED": 2}
	assert_false(director.restore_state(forged).is_empty())
	assert_eq(director.durable_state(), snapshot)
	forged["ladder_access"] = {"LADDER_WEST": -1}
	assert_false(director.restore_state(forged).is_empty())
	assert_eq(director.durable_state(), snapshot)


func test_CTL1_C03_malformed_ladders_rejected_and_legacy_shapes_stable() -> void:
	var trace: Dictionary = _trace()
	for records: Variant in [
		[{"id":"bad-id","grants":"ROOF_REACHED"}],
		[{"id":"LADDER_WEST","grants":"bad-flag"}],
		[{"id":"LADDER_WEST","grants":"ROOF_REACHED"},{"id":"LADDER_WEST","grants":"DUPLICATE"}]
	]:
		var bad: Dictionary = Runner.build(C03, trace["players"], trace["tools"], {"fixed_ladders": records})
		assert_false((bad["errors"] as Array).is_empty(), str(records))
	for old: String in [C01, C02]:
		var original: Dictionary = Runner.json(old.path_join("solution.json"))
		var prior: Dictionary = Runner.build(old, original["players"], original["tools"])
		assert_eq(prior["errors"], [] as Array[Dictionary])
		var mission: Mission = prior["mission"] as Mission
		assert_false(mission.canonical_state().has("ladder_access"))
		assert_false(mission.durable_state().has("ladder_access"))
		assert_eq(mission.restore_state(mission.durable_state()), [] as Array[Dictionary])
		assert_eq(Runner.send(prior, "P1", "use_ladder", "LADDER_WEST", {}).get("code"), "UNKNOWN_LADDER")
