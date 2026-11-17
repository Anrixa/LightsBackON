extends "res://tests/test_case.gd"
## CT-L1/C04: host-authorized feeder and optional direct-sign-spur regressions.
## Hardware, network, art and cross-version persistence are separate gates.
const Runner := preload("res://tests/support/solution_runner.gd")
const Grid := preload("res://scripts/simulation/power_grid.gd")
const Mission := preload("res://scripts/simulation/mission_director.gd")
const C04: String = "res://content/contracts/c04_whole_block"
const C01: String = "res://content/contracts/c01_alder_street"
const C02: String = "res://content/contracts/c02_dinner_rush"
const C03: String = "res://content/contracts/c03_roof_route"


func _trace() -> Dictionary:
	return Runner.json(C04.path_join("solution.json"))


func _context() -> Dictionary:
	var trace: Dictionary = _trace()
	return Runner.build(C04, trace["players"], trace["tools"])


func _until(ctx: Dictionary, stop_entity: String) -> void:
	var partial: Array = []
	for step: Dictionary in _trace()["steps"]:
		if step.get("entity", "") == stop_entity:
			break
		partial.append(step)
	assert_eq(Runner.run(ctx, partial, 1), [] as Array[String])


func test_CTL1_C04_schema_loads_and_direct_spur_is_independent() -> void:
	var ctx: Dictionary = _context()
	assert_eq(ctx["errors"], [] as Array[Dictionary], str(ctx["errors"]))
	var state: Dictionary = (ctx["grid"] as Grid).canonical_state()
	assert_eq(state["nodes"]["GRID"]["capacity"], 24)
	assert_true(state["nodes"]["JW"]["failed"])
	assert_false(state["edges"]["E_GRID_JE"]["healthy"])
	assert_eq(state["edges"]["E_GRID_JE"]["capacity"], 12)
	assert_true(state["nodes"]["EAST_SIGN"]["isolated"])
	assert_false(state["edges"]["E_SPUR_SIGN"]["healthy"])
	assert_eq(state["edges"]["E_GRID_SPUR"]["capacity"], 3)
	assert_eq(Runner.json(C04.path_join("repairs.json"))["repairs"].size(), 3)
	assert_eq(Runner.json(C04.path_join("mission.json"))["optional_services"], ["SIGN"])


func test_CTL1_C04_host_solution_restores_five_plus_optional_without_trip() -> void:
	var ctx: Dictionary = _context()
	assert_eq(ctx["errors"], [] as Array[Dictionary])
	var trace: Dictionary = _trace()
	var failed: Array[String] = Runner.run(ctx, trace["steps"], int(trace["pace_ticks_per_command"]))
	assert_eq(failed, [] as Array[String], str(failed))
	var mission: Mission = ctx["mission"] as Mission
	assert_true(mission.is_complete())
	assert_true(int(ctx["now"]) <= int(trace["max_ticks"]))
	assert_eq(mission.results()["required_restored"], 5)
	assert_eq(mission.results()["optional_services"], ["SIGN"])
	assert_eq(mission.results()["preventable_trips"], 0)
	assert_eq(mission.results()["stars"], 3)
	var grid: Dictionary = (ctx["grid"] as Grid).canonical_state()
	assert_eq(grid["nodes"]["GRID"]["load"], 23)
	assert_eq(grid["edges"]["E_GRID_JE"]["flow"], 11)
	assert_eq(grid["edges"]["E_GRID_SPUR"]["flow"], 3)
	assert_false(grid["nodes"]["JE"]["tripped"])


func test_CTL1_C04_east_sign_wrong_route_overloads_after_fifteen_ticks() -> void:
	var ctx: Dictionary = _context()
	_until(ctx, "R_JW_FUSE")
	assert_true(Runner.send(ctx, "P1", "toggle_switch", "SW_EAST_SIGN", {"value": false}).get("ok", false))
	assert_true(Runner.send(ctx, "P1", "toggle_switch", "SW_SIGN", {"value": true}).get("ok", false))
	Runner.ticks(ctx, 14)
	assert_false((ctx["grid"] as Grid).canonical_state()["nodes"]["JE"]["tripped"])
	Runner.ticks(ctx, 1)
	assert_true((ctx["grid"] as Grid).canonical_state()["nodes"]["JE"]["tripped"])
	assert_false((ctx["mission"] as Mission).is_complete())


func test_CTL1_C04_dual_route_rejected_atomically() -> void:
	var ctx: Dictionary = _context()
	_until(ctx, "SW_SIGN")
	assert_true(Runner.send(ctx, "P1", "toggle_switch", "SW_SIGN", {"value": true}).get("ok", false))
	var grid: Grid = ctx["grid"] as Grid
	var before: String = Grid.serialize(grid.canonical_state())
	var refused: Dictionary = Runner.send(ctx, "P1", "toggle_switch", "SW_EAST_SIGN", {"value": false})
	assert_false(refused.get("ok", false))
	assert_eq(Grid.serialize(grid.canonical_state()), before)


func test_CTL1_C04_optional_repair_can_be_skipped_without_blocking_completion() -> void:
	var ctx: Dictionary = _context()
	var reduced: Array = []
	for step: Dictionary in _trace()["steps"]:
		if step.get("entity", "") in ["R_SIGN_SPUR", "PANEL_SPUR", "SW_SIGN"]:
			continue
		reduced.append(step)
	var failures: Array[String] = Runner.run(ctx, reduced, 1)
	assert_eq(failures, [] as Array[String], str(failures))
	var mission: Mission = ctx["mission"] as Mission
	assert_true(mission.is_complete())
	assert_eq(mission.results()["required_restored"], 5)
	assert_eq(mission.results()["optional_services"], [] as Array[String])
	assert_eq(mission.results()["stars"], 2)


func test_CTL1_C04_bad_optional_spur_definition_fails_closed() -> void:
	var data: Dictionary = Runner.json(C04.path_join("repairs.json"))
	var ids: Dictionary = {}
	for repair: Dictionary in data["repairs"]:
		assert_false(ids.has(repair["id"]))
		ids[repair["id"]] = true
	assert_eq(int(data["supplies"]["CABLE_SPLICE"]), 2)
	assert_eq((data["repairs"] as Array)[2]["fix"]["id"], "E_SPUR_SIGN")
	assert_eq((data["repairs"] as Array)[2]["isolate"], "SPUR")
	var ctx: Dictionary = _context()
	var mission: Mission = ctx["mission"] as Mission
	var old: Dictionary = mission.durable_state()
	assert_eq(mission.restore_state(old), [] as Array[Dictionary])
	assert_eq(mission.durable_state(), old)


func test_CTL1_C04_prior_contract_rules_and_checkpoint_shapes_unchanged() -> void:
	for path: String in [C01, C02, C03]:
		var trace: Dictionary = Runner.json(path.path_join("solution.json"))
		var ctx: Dictionary = Runner.build(path, trace["players"], trace["tools"])
		assert_eq(ctx["errors"], [] as Array[Dictionary], path)
		var mission: Mission = ctx["mission"] as Mission
		var before: Dictionary = mission.durable_state()
		assert_eq(mission.restore_state(before), [] as Array[Dictionary], path)
		assert_eq(mission.durable_state(), before, path)
