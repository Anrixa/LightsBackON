extends "res://tests/test_case.gd"
## CT-L2 C05: independently gated Canal Yard pump latches and host-only supply.
## These headless tests do not certify world geometry, network peers or player pacing.
const Runner := preload("res://tests/support/solution_runner.gd")
const Grid := preload("res://scripts/simulation/power_grid.gd")
const Mission := preload("res://scripts/simulation/mission_director.gd")
const C05: String = "res://content/contracts/c05_canal_pump_access"
const EARLIER: Array[String] = [
	"res://content/contracts/c01_alder_street",
	"res://content/contracts/c02_dinner_rush",
	"res://content/contracts/c03_roof_route",
	"res://content/contracts/c04_whole_block",
]


func _trace() -> Dictionary:
	return Runner.json(C05.path_join("solution.json"))


func _context() -> Dictionary:
	var solution: Dictionary = _trace()
	return Runner.build(C05, solution["players"], solution["tools"])


func _action(ctx: Dictionary, entity: String, action: String, more: Dictionary = {}) -> Dictionary:
	var payload: Dictionary = {"action": action}
	payload.merge(more)
	return Runner.send(ctx, "P1", "place_item", entity, payload)


func _place_generator(ctx: Dictionary) -> void:
	assert_true(_action(ctx, "GEN_PORTABLE", "pickup").get("ok", false))
	assert_true(_action(ctx, "GEN_PORTABLE", "place", {"anchor": "PAD_CANAL_PUMPS"}).get("ok", false))


func test_CTL2_C05_contract_is_valid_and_starts_with_two_independent_flood_gates() -> void:
	var ctx: Dictionary = _context()
	assert_eq(ctx["errors"], [] as Array[Dictionary], str(ctx["errors"]))
	var state: Dictionary = (ctx["grid"] as Grid).canonical_state()
	assert_true(state["nodes"]["DOCK"]["failed"])
	assert_true(state["nodes"]["DOCK"]["tripped"])
	assert_false(state["edges"]["E_GRID_COLD"]["healthy"])
	assert_false(state["nodes"]["PUMP_DOCK"]["supplied"])
	assert_false(state["nodes"]["PUMP_COLD"]["supplied"])
	assert_eq(state["nodes"]["GEN"]["capacity"], 6)
	assert_eq(Runner.json(C05.path_join("mission.json"))["access_latches"].size(), 2)
	assert_eq(Runner.json(C05.path_join("mission.json"))["required_consumers"].size(), 5)
	assert_eq(Runner.send(ctx, "P1", "request_lock", "R_DOCK_FUSE", {}).get("code"), "NO_ACCESS")
	assert_eq(Runner.send(ctx, "P1", "request_lock", "R_COLD_FEED", {}).get("code"), "NO_ACCESS")


func test_CTL2_C05_full_host_solution_restores_all_five_and_optional_beacon() -> void:
	var ctx: Dictionary = _context()
	var solution: Dictionary = _trace()
	assert_eq(Runner.run(ctx, solution["steps"], int(solution["pace_ticks_per_command"])),
		[] as Array[String])
	var mission: Mission = ctx["mission"] as Mission
	assert_true(mission.is_complete())
	assert_true(int(ctx["now"]) <= int(solution["max_ticks"]))
	assert_eq(mission.results()["required_restored"], 5)
	assert_eq(mission.results()["optional_services"], ["BEACON"])
	assert_eq(mission.results()["preventable_trips"], 0)
	assert_eq(mission.results()["stars"], 3)
	var state: Dictionary = (ctx["grid"] as Grid).canonical_state()
	assert_eq(state["nodes"]["GRID"]["load"], 21)
	assert_eq(state["edges"]["E_GRID_DOCK"]["flow"], 10)
	assert_eq(state["edges"]["E_GRID_COLD"]["flow"], 11)
	assert_false(state["nodes"]["TEMP"]["tripped"])
	assert_true(mission.canonical_state()["latched"].has("LATCH_DOCK_DRAIN"))
	assert_true(mission.canonical_state()["latched"].has("LATCH_COLD_DRAIN"))


func test_CTL2_C05_two_distinct_access_latches_unlock_only_their_own_room() -> void:
	var ctx: Dictionary = _context()
	_place_generator(ctx)
	assert_true(_action(ctx, "GEN_PORTABLE", "connect", {"route": "E_TEMP_PUMP_DOCK"}).get("ok", false))
	assert_true(_action(ctx, "GEN_PORTABLE", "start").get("ok", false))
	Runner.ticks(ctx, 79)
	assert_eq(Runner.send(ctx, "P1", "request_lock", "R_DOCK_FUSE", {}).get("code"), "NO_ACCESS")
	Runner.ticks(ctx, 1)
	assert_true(Runner.send(ctx, "P1", "request_lock", "R_DOCK_FUSE", {}).get("ok", false))
	assert_eq(Runner.send(ctx, "P1", "request_lock", "R_COLD_FEED", {}).get("code"), "NO_ACCESS")
	assert_true(_action(ctx, "GEN_PORTABLE", "stop").get("ok", false))
	assert_true(_action(ctx, "GEN_PORTABLE", "disconnect", {"route": "E_TEMP_PUMP_DOCK"}).get("ok", false))
	assert_true(_action(ctx, "GEN_PORTABLE", "connect", {"route": "E_TEMP_PUMP_COLD"}).get("ok", false))
	assert_true(_action(ctx, "GEN_PORTABLE", "start").get("ok", false))
	Runner.ticks(ctx, 99)
	assert_eq(Runner.send(ctx, "P1", "request_lock", "R_COLD_FEED", {}).get("code"), "NO_ACCESS")
	Runner.ticks(ctx, 1)
	assert_true(Runner.send(ctx, "P1", "request_lock", "R_COLD_FEED", {}).get("ok", false))


func test_CTL2_C05_simultaneous_pump_routes_trip_after_fifteen_ticks_and_recover() -> void:
	var ctx: Dictionary = _context()
	_place_generator(ctx)
	assert_true(_action(ctx, "GEN_PORTABLE", "connect", {"route": "E_TEMP_PUMP_DOCK"}).get("ok", false))
	assert_true(_action(ctx, "GEN_PORTABLE", "connect", {"route": "E_TEMP_PUMP_COLD"}).get("ok", false))
	assert_true(_action(ctx, "GEN_PORTABLE", "start").get("ok", false))
	Runner.ticks(ctx, 14)
	assert_false((ctx["grid"] as Grid).canonical_state()["nodes"]["TEMP"]["tripped"])
	Runner.ticks(ctx, 1)
	assert_true((ctx["grid"] as Grid).canonical_state()["nodes"]["TEMP"]["tripped"])
	assert_false((ctx["mission"] as Mission).canonical_state()["latched"].has("LATCH_DOCK_DRAIN"))
	assert_false((ctx["mission"] as Mission).canonical_state()["latched"].has("LATCH_COLD_DRAIN"))
	assert_true(_action(ctx, "GEN_PORTABLE", "disconnect", {"route": "E_TEMP_PUMP_COLD"}).get("ok", false))
	assert_true(_action(ctx, "GEN_PORTABLE", "reset_breaker").get("ok", false))
	assert_false((ctx["grid"] as Grid).canonical_state()["nodes"]["TEMP"]["tripped"])
	Runner.ticks(ctx, 80)
	assert_true((ctx["mission"] as Mission).canonical_state()["latched"].has("LATCH_DOCK_DRAIN"))


func test_CTL2_C05_pump_interruption_resets_partial_count_but_completed_latch_persists() -> void:
	var ctx: Dictionary = _context()
	_place_generator(ctx)
	assert_true(_action(ctx, "GEN_PORTABLE", "connect", {"route": "E_TEMP_PUMP_DOCK"}).get("ok", false))
	assert_true(_action(ctx, "GEN_PORTABLE", "start").get("ok", false))
	Runner.ticks(ctx, 40)
	assert_true(_action(ctx, "GEN_PORTABLE", "stop").get("ok", false))
	Runner.ticks(ctx, 1)
	assert_true(_action(ctx, "GEN_PORTABLE", "start").get("ok", false))
	Runner.ticks(ctx, 79)
	assert_false((ctx["mission"] as Mission).canonical_state()["latched"].has("LATCH_DOCK_DRAIN"))
	Runner.ticks(ctx, 1)
	assert_true((ctx["mission"] as Mission).canonical_state()["latched"].has("LATCH_DOCK_DRAIN"))
	assert_true(_action(ctx, "GEN_PORTABLE", "stop").get("ok", false))
	Runner.ticks(ctx, 2)
	assert_true((ctx["mission"] as Mission).canonical_state()["latched"].has("LATCH_DOCK_DRAIN"))


func test_CTL2_C05_optional_beacon_can_be_skipped_for_two_star_completion() -> void:
	var ctx: Dictionary = _context()
	var steps: Array = []
	for step: Dictionary in _trace()["steps"]:
		if step.get("entity", "") == "SW_BEACON":
			continue
		steps.append(step)
	assert_eq(Runner.run(ctx, steps, 1), [] as Array[String])
	var mission: Mission = ctx["mission"] as Mission
	assert_true(mission.is_complete())
	assert_eq(mission.results()["required_restored"], 5)
	assert_eq(mission.results()["optional_services"], [] as Array[String])
	assert_eq(mission.results()["stars"], 2)


func test_CTL2_C05_durable_two_latch_state_round_trips_and_rejects_forgery() -> void:
	var ctx: Dictionary = _context()
	var solution: Dictionary = _trace()
	var prefix: Array = []
	for step: Dictionary in solution["steps"]:
		if step.get("entity", "") == "R_DOCK_FUSE" and step.get("intent", "") == "request_lock" and prefix.size() > 12:
			break
		prefix.append(step)
	assert_eq(Runner.run(ctx, prefix, 1), [] as Array[String])
	var mission: Mission = ctx["mission"] as Mission
	var saved: Dictionary = mission.durable_state()
	assert_eq((saved["latched"] as Dictionary).size(), 2)
	var fresh: Dictionary = _context()
	var director: Mission = fresh["mission"] as Mission
	assert_eq(director.restore_state(saved), [] as Array[Dictionary])
	assert_eq(director.durable_state(), saved)
	var forged: Dictionary = saved.duplicate(true)
	forged["latched"] = {"UNKNOWN_LATCH": 1}
	assert_false(director.restore_state(forged).is_empty())
	assert_eq(director.durable_state(), saved)


func test_CTL2_C05_bad_latch_schema_fails_without_rescuing_access() -> void:
	var trace: Dictionary = _trace()
	for invalid: Variant in [0, -1, "forever", true]:
		var broken: Dictionary = Runner.build(C05, trace["players"], trace["tools"], {
			"access_latches": [
				{"id": "LATCH_DOCK_DRAIN", "consumer": "PUMP_DOCK",
				"supplied_ticks": invalid, "grants": "DOCK_DRAINED"},
			],
		})
		assert_false((broken["errors"] as Array).is_empty(), str(invalid))


func test_CTL2_C05_prior_contract_logic_and_durable_shapes_still_load() -> void:
	for path: String in EARLIER:
		var trace: Dictionary = Runner.json(path.path_join("solution.json"))
		var ctx: Dictionary = Runner.build(path, trace["players"], trace["tools"])
		assert_eq(ctx["errors"], [] as Array[Dictionary], path)
		var mission: Mission = ctx["mission"] as Mission
		var old: Dictionary = mission.durable_state()
		assert_eq(mission.restore_state(old), [] as Array[Dictionary], path)
		assert_eq(mission.durable_state(), old, path)
