extends "res://tests/test_case.gd"
## CT-L1 C02 Dinner Rush: independent original contract data, optional opening
## deadline, known host-intent solution, unsafe dual-supply refusal and missed
## bonus. Real UI, art, GPU and Steam qualification are separate gates.

const Runner := preload("res://tests/support/solution_runner.gd")
const Grid := preload("res://scripts/simulation/power_grid.gd")
const Mission := preload("res://scripts/simulation/mission_director.gd")

const C01: String = "res://content/contracts/c01_alder_street"
const C02: String = "res://content/contracts/c02_dinner_rush"


func _trace() -> Dictionary:
	return Runner.json(C02.path_join("solution.json"))


func _context() -> Dictionary:
	var trace: Dictionary = _trace()
	return Runner.build(C02, trace["players"], trace["tools"])


func test_CTL1_C02_all_contract_definitions_load_and_preserve_authored_alder_ids() -> void:
	var ctx: Dictionary = _context()
	assert_eq(ctx["errors"], [] as Array[Dictionary], str(ctx["errors"]))
	var grid: Dictionary = (ctx["grid"] as Grid).canonical_state()
	var nodes: Dictionary = grid["nodes"]
	assert_true(nodes.has("GRID") and nodes.has("JW") and nodes.has("JE"))
	assert_true(nodes.has("PUB") and nodes.has("SIGN"))
	assert_eq(nodes["GRID"]["capacity"], 24)
	assert_true(nodes["JW"]["failed"])
	assert_false(grid["edges"]["E_GRID_JE"]["healthy"])
	assert_eq(grid["edges"]["E_GRID_JE"]["capacity"], 15)
	var mission: Dictionary = Runner.json(C02.path_join("mission.json"))
	assert_eq(mission["contract_id"], "C02")
	assert_eq(mission["optional_services"], ["SIGN"])
	assert_eq(int(mission["optional_deadline_ticks"]), 2400)
	assert_eq(mission["access_latches"].size(), 0)
	assert_eq(Runner.json(C02.path_join("repairs.json"))["repairs"].size(), 2)
	assert_eq(Runner.json(C01.path_join("mission.json"))["contract_id"], "C01",
		"the original C01 definition remains a separate contract")


func test_CTL1_C02_solution_is_complete_with_early_optional_venue_and_no_trips() -> void:
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
	assert_eq(result["required_total"], 5)
	assert_eq(result["optional_services"], ["SIGN"])
	assert_eq(result["optional_total"], 1)
	assert_eq(result["preventable_trips"], 0)
	assert_eq(result["stars"], 3)
	var service_tick: int = int(director.canonical_state()["optional_first_supplied"]["SIGN"])
	assert_true(service_tick >= 1 and service_tick <= 2400)
	assert_eq((ctx["grid"] as Grid).canonical_state()["nodes"]["GRID"]["load"], 23)


func test_CTL1_C02_missing_opening_deadline_loses_only_bonus_not_mission() -> void:
	var ctx: Dictionary = _context()
	var trace: Dictionary = _trace()
	var steps: Array = (trace["steps"] as Array).duplicate(true)
	var inserted: bool = false
	for i: int in steps.size():
		var step: Dictionary = steps[i]
		if str(step.get("entity", "")) == "SW_SIGN" and str(step.get("intent", "")) == "toggle_switch":
			steps.insert(i, {"ticks": 2401})
			inserted = true
			break
	assert_true(inserted)
	var failures: Array[String] = Runner.run(ctx, steps, int(trace["pace_ticks_per_command"]))
	assert_eq(failures, [] as Array[String], str(failures))
	assert_true((ctx["mission"] as Mission).is_complete(), "opening deadline is never a hard mission failure")
	var result: Dictionary = (ctx["mission"] as Mission).results()
	assert_eq(result["required_restored"], 5)
	assert_eq(result["optional_services"], [] as Array[String])
	assert_eq(result["optional_total"], 1)
	assert_eq(result["stars"], 2)
	assert_false((ctx["mission"] as Mission).canonical_state()["optional_first_supplied"].has("SIGN"))


func test_CTL1_C02_refuses_unsafe_second_energized_route_without_mutation() -> void:
	var ctx: Dictionary = _context()
	var trace: Dictionary = _trace()
	var prefix: Array = []
	for step: Dictionary in trace["steps"]:
		if str(step.get("entity", "")) == "SW_SIGN":
			break
		prefix.append(step)
	var failures: Array[String] = Runner.run(ctx, prefix, 1)
	assert_eq(failures, [] as Array[String], str(failures))
	var grid: Grid = ctx["grid"] as Grid
	assert_true(grid.canonical_state()["nodes"]["PUB"]["supplied"])
	var started: Dictionary = grid.apply({"op": "set", "id": "GEN", "field": "online", "value": true})
	assert_true(bool(started.get("ok", false)))
	var canonical_before: String = Grid.serialize(grid.canonical_state())
	var unsafe: Dictionary = grid.apply({"op": "set", "id": "E_TEMP_PUB", "field": "enabled", "value": true})
	assert_false(bool(unsafe.get("ok", false)), "cannot feed a pub from grid and generator at once")
	assert_eq(Grid.serialize(grid.canonical_state()), canonical_before,
		"a rejected route must never mutate the host's canonical power grid")


func test_CTL1_C02_rejects_invalid_deadline_instead_of_silently_promoting_award() -> void:
	var trace: Dictionary = _trace()
	for bad: Variant in [0, -1, true, "fast", 1.5]:
		var ctx: Dictionary = Runner.build(C02, trace["players"], trace["tools"], {"optional_deadline_ticks": bad})
		assert_true(not (ctx["errors"] as Array).is_empty(), "bad deadline: " + str(bad))
	var no_optional: Dictionary = Runner.build(C02, trace["players"], trace["tools"],
		{"optional_services": [] as Array[String]})
	assert_true(not (no_optional["errors"] as Array).is_empty())


func test_CTL1_C02_persists_only_valid_host_observed_optional_first_supply_tick() -> void:
	var ctx: Dictionary = _context()
	var trace: Dictionary = _trace()
	var steps: Array = []
	for step: Dictionary in trace["steps"]:
		steps.append(step)
		if str(step.get("entity", "")) == "SW_SIGN":
			break
	assert_eq(Runner.run(ctx, steps, 1), [] as Array[String])
	var mission: Mission = ctx["mission"] as Mission
	var saved: Dictionary = mission.durable_state()
	assert_true(saved.has("optional_first_supplied"))
	assert_true(saved["optional_first_supplied"].has("SIGN"))
	var fresh: Dictionary = _context()
	assert_eq((fresh["mission"] as Mission).restore_state(saved), [] as Array[Dictionary])
	assert_eq((fresh["mission"] as Mission).durable_state()["optional_first_supplied"],
		saved["optional_first_supplied"])
	var forged: Dictionary = saved.duplicate(true)
	forged["optional_first_supplied"] = {"SIGN": 2401}
	var snapshot: Dictionary = (fresh["mission"] as Mission).durable_state()
	assert_false((fresh["mission"] as Mission).restore_state(forged).is_empty())
	assert_eq((fresh["mission"] as Mission).durable_state(), snapshot,
		"invalid first-service tick must fail closed without partial restore")
	forged["optional_first_supplied"] = {"INVENTED": 1}
	assert_false((fresh["mission"] as Mission).restore_state(forged).is_empty())


func test_CTL1_C02_original_C01_mission_checkpoint_shape_stays_backward_compatible() -> void:
	var original: Dictionary = Runner.json(C01.path_join("solution.json"))
	var ctx: Dictionary = Runner.build(C01, original["players"], original["tools"])
	assert_eq(ctx["errors"], [] as Array[Dictionary])
	var director: Mission = ctx["mission"] as Mission
	assert_false(director.canonical_state().has("optional_first_supplied"))
	assert_false(director.durable_state().has("optional_first_supplied"))
	assert_eq(director.restore_state(director.durable_state()), [] as Array[Dictionary])
