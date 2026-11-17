extends "res://tests/test_case.gd"
## CT-BP/C06: source-aligned Cold Chain, cumulative outage, generator exclusivity.
## Every command is replayed through the host intent path; real scene/human gates remain separate.

const Runner := preload("res://tests/support/solution_runner.gd")
const Grid := preload("res://scripts/simulation/power_grid.gd")
const Mission := preload("res://scripts/simulation/mission_director.gd")
const C06: String = "res://content/contracts/c06_cold_chain"
const PRIOR: Array[String] = [
	"res://content/contracts/c01_alder_street",
	"res://content/contracts/c02_dinner_rush",
	"res://content/contracts/c03_roof_route",
	"res://content/contracts/c04_whole_block",
	"res://content/contracts/c05_canal_pump_access",
]


func _trace() -> Dictionary:
	return Runner.json(C06.path_join("solution.json"))


func _context() -> Dictionary:
	var trace: Dictionary = _trace()
	return Runner.build(C06, trace["players"], trace["tools"])


func _outage(ctx: Dictionary) -> Dictionary:
	return (ctx["mission"] as Mission).canonical_state()["cumulative_outage"]


func _generator_at_pad(ctx: Dictionary) -> void:
	assert_true(Runner.send(ctx, "P1", "place_item", "GEN_PORTABLE", {"action": "pickup"}).get("ok", false))
	assert_true(Runner.send(ctx, "P1", "place_item", "GEN_PORTABLE",
		{"action": "place", "anchor": "PAD_CANAL_PUMPS"}).get("ok", false))


func _equipment(ctx: Dictionary, action: String, route: String = "") -> Dictionary:
	var payload: Dictionary = {"action": action}
	if route != "":
		payload["route"] = route
	return Runner.send(ctx, "P1", "place_item", "GEN_PORTABLE", payload)


func test_CT_BP_C06_exact_original_topology_and_contract() -> void:
	var ctx: Dictionary = _context()
	assert_eq(ctx["errors"], [] as Array[Dictionary], str(ctx["errors"]))
	var st: Dictionary = (ctx["grid"] as Grid).canonical_state()
	assert_eq(st["nodes"]["GRID"]["capacity"], 30)
	assert_eq(st["nodes"]["GEN"]["capacity"], 8)
	assert_true(st["edges"]["E_GRID_WEST"]["healthy"])
	assert_false(st["edges"]["E_GRID_EAST"]["healthy"])
	assert_eq(st["edges"]["E_GRID_WEST"]["capacity"], 14)
	assert_eq(st["edges"]["E_GRID_EAST"]["capacity"], 14)
	assert_eq(st["nodes"]["GRID"]["load"], 13)
	assert_eq(st["nodes"]["COLD_STORE"]["demand"], 5)
	assert_eq(st["nodes"]["PUMP_EAST"]["demand"], 4)
	assert_false(st["edges"]["E_TEMP_COLD_STORE"]["enabled"])
	var definition: Dictionary = Runner.json(C06.path_join("mission.json"))
	assert_eq(definition["required_consumers"].size(), 6)
	assert_eq(definition["access_latches"].size(), 1)
	assert_eq(definition["access_latches"][0]["supplied_ticks"], 120)
	assert_eq(definition["optional_services"], [] as Array)
	assert_false(definition.has("optional_deadline_ticks"))
	assert_eq(definition["optional_cumulative_outage"]["deadline_ticks"], 1200)
	assert_eq(Runner.json(C06.path_join("repairs.json"))["repairs"].size(), 1)


func test_CT_BP_C06_full_host_solution_restores_six_and_earns_bonus() -> void:
	var ctx: Dictionary = _context()
	var trace: Dictionary = _trace()
	assert_eq(Runner.run(ctx, trace["steps"], int(trace["pace_ticks_per_command"])),
		[] as Array[String])
	var m: Mission = ctx["mission"] as Mission
	assert_true(m.is_complete())
	assert_true(int(ctx["now"]) <= int(trace["max_ticks"]))
	assert_eq(m.results()["required_total"], 6)
	assert_eq(m.results()["required_restored"], 6)
	assert_eq(m.results()["optional_services"], ["COLD_CHAIN"])
	assert_eq(m.results()["optional_total"], 1)
	assert_eq(m.results()["preventable_trips"], 0)
	assert_eq(m.results()["stars"], 3)
	assert_false(_outage(ctx)["missed"])
	assert_true(int(_outage(ctx)["elapsed_ticks"]) > 0)
	var grid: Dictionary = (ctx["grid"] as Grid).canonical_state()
	assert_eq(grid["nodes"]["GRID"]["load"], 25)
	assert_eq(grid["edges"]["E_GRID_WEST"]["flow"], 13)
	assert_eq(grid["edges"]["E_GRID_EAST"]["flow"], 12)


func test_CT_BP_C06_strict_1199_1200_outage_boundary() -> void:
	var ctx: Dictionary = _context()
	Runner.ticks(ctx, 1199)
	assert_eq(_outage(ctx)["elapsed_ticks"], 1199)
	assert_false(_outage(ctx)["missed"])
	Runner.ticks(ctx, 1)
	assert_eq(_outage(ctx)["elapsed_ticks"], 1200)
	assert_true(_outage(ctx)["missed"])
	Runner.ticks(ctx, 100)
	assert_eq(_outage(ctx)["elapsed_ticks"], 1200)


func test_CT_BP_C06_generator_supply_pauses_and_never_resets_outage() -> void:
	var ctx: Dictionary = _context()
	Runner.ticks(ctx, 30)
	_generator_at_pad(ctx)
	assert_true(_equipment(ctx, "connect", "E_TEMP_COLD_STORE").get("ok", false))
	assert_true(_equipment(ctx, "start").get("ok", false))
	Runner.ticks(ctx, 20)
	assert_eq(_outage(ctx)["elapsed_ticks"], 30)
	assert_true(_outage(ctx)["powered"])
	assert_true(_equipment(ctx, "stop").get("ok", false))
	Runner.ticks(ctx, 7)
	assert_eq(_outage(ctx)["elapsed_ticks"], 37)
	assert_true(_equipment(ctx, "start").get("ok", false))
	Runner.ticks(ctx, 10)
	assert_eq(_outage(ctx)["elapsed_ticks"], 37)
	assert_false(_outage(ctx)["missed"])


func test_CT_BP_C06_same_tick_loss_counts_even_if_restored() -> void:
	var ctx: Dictionary = _context()
	_generator_at_pad(ctx)
	assert_true(_equipment(ctx, "connect", "E_TEMP_COLD_STORE").get("ok", false))
	assert_true(_equipment(ctx, "start").get("ok", false))
	Runner.ticks(ctx, 10)
	var before: int = int(_outage(ctx)["elapsed_ticks"])
	assert_true(_equipment(ctx, "stop").get("ok", false))
	assert_true(_equipment(ctx, "start").get("ok", false))
	Runner.ticks(ctx, 1)
	assert_eq(_outage(ctx)["elapsed_ticks"], before + 1)


func test_CT_BP_C06_late_bonus_does_not_block_contract() -> void:
	var ctx: Dictionary = _context()
	Runner.ticks(ctx, 1200)
	assert_true(_outage(ctx)["missed"])
	var trace: Dictionary = _trace()
	assert_eq(Runner.run(ctx, trace["steps"], int(trace["pace_ticks_per_command"])),
		[] as Array[String])
	var m: Mission = ctx["mission"] as Mission
	assert_true(m.is_complete())
	assert_eq(m.results()["required_restored"], 6)
	assert_eq(m.results()["optional_services"], [] as Array[String])
	assert_eq(m.results()["stars"], 2)
	assert_true(_outage(ctx)["missed"])


func test_CT_BP_C06_pump_access_needs_120_consecutive_valid_ticks() -> void:
	var ctx: Dictionary = _context()
	assert_eq(Runner.send(ctx, "P1", "request_lock", "R_EAST_TRUNK", {}).get("code"), "NO_ACCESS")
	_generator_at_pad(ctx)
	assert_true(_equipment(ctx, "connect", "E_TEMP_PUMP_EAST").get("ok", false))
	assert_true(_equipment(ctx, "start").get("ok", false))
	Runner.ticks(ctx, 119)
	assert_eq(Runner.send(ctx, "P1", "request_lock", "R_EAST_TRUNK", {}).get("code"), "NO_ACCESS")
	assert_true(_equipment(ctx, "stop").get("ok", false))
	Runner.ticks(ctx, 1)
	assert_true(_equipment(ctx, "start").get("ok", false))
	Runner.ticks(ctx, 119)
	assert_false((ctx["mission"] as Mission).canonical_state()["latched"].has("LATCH_EAST_DRAIN"))
	Runner.ticks(ctx, 1)
	assert_true((ctx["mission"] as Mission).canonical_state()["latched"].has("LATCH_EAST_DRAIN"))
	assert_true(Runner.send(ctx, "P1", "request_lock", "R_EAST_TRUNK", {}).get("ok", false))


func test_CT_BP_C06_pump_and_cold_store_overload_gen8_at_9_pu() -> void:
	var ctx: Dictionary = _context()
	_generator_at_pad(ctx)
	assert_true(_equipment(ctx, "connect", "E_TEMP_PUMP_EAST").get("ok", false))
	assert_true(_equipment(ctx, "connect", "E_TEMP_COLD_STORE").get("ok", false))
	assert_true(_equipment(ctx, "start").get("ok", false))
	Runner.ticks(ctx, 14)
	assert_false((ctx["grid"] as Grid).canonical_state()["nodes"]["TEMP"]["tripped"])
	Runner.ticks(ctx, 1)
	assert_true((ctx["grid"] as Grid).canonical_state()["nodes"]["TEMP"]["tripped"])
	assert_false((ctx["mission"] as Mission).canonical_state()["latched"].has("LATCH_EAST_DRAIN"))


func test_CT_BP_C06_durable_outage_restores_only_valid_counters() -> void:
	var ctx: Dictionary = _context()
	Runner.ticks(ctx, 37)
	var m: Mission = ctx["mission"] as Mission
	var saved: Dictionary = m.durable_state()
	var newctx: Dictionary = _context()
	var recovered: Mission = newctx["mission"] as Mission
	assert_eq(recovered.restore_state(saved), [] as Array[Dictionary])
	assert_eq(recovered.durable_state(), saved)
	Runner.ticks(newctx, 3)
	assert_eq(_outage(newctx)["elapsed_ticks"], 40)
	var before: Dictionary = recovered.durable_state()
	for invalid: Variant in [
		{"elapsed_ticks": 1200, "missed": false, "pending_unpowered": true},
		{"elapsed_ticks": -1, "missed": false, "pending_unpowered": false},
		{"elapsed_ticks": 1201, "missed": true, "pending_unpowered": false},
		{"elapsed_ticks": true, "missed": false, "pending_unpowered": false},
	]:
		var forged: Dictionary = before.duplicate(true)
		forged["cumulative_outage"] = invalid
		assert_false(recovered.restore_state(forged).is_empty())
		assert_eq(recovered.durable_state(), before)
	var omitted: Dictionary = before.duplicate(true)
	omitted.erase("cumulative_outage")
	assert_false(recovered.restore_state(omitted).is_empty())
	assert_eq(recovered.durable_state(), before)


func test_CT_BP_C06_malformed_content_rejected_fail_closed() -> void:
	var trace: Dictionary = _trace()
	var original: Dictionary = Runner.json(C06.path_join("mission.json"))["optional_cumulative_outage"]
	for deadline: Variant in [0, -1, true, "bad", 1.5]:
		var broken: Dictionary = original.duplicate(true)
		broken["deadline_ticks"] = deadline
		var ctx: Dictionary = Runner.build(C06, trace["players"], trace["tools"],
			{"optional_cumulative_outage": broken})
		assert_false((ctx["errors"] as Array).is_empty(), str(deadline))
	for broken_sources: Array in [["GRID", "GRID"], ["GRID", "UNKNOWN"], []]:
		var broken: Dictionary = original.duplicate(true)
		broken["permitted_sources"] = broken_sources
		var ctx: Dictionary = Runner.build(C06, trace["players"], trace["tools"],
			{"optional_cumulative_outage": broken})
		assert_false((ctx["errors"] as Array).is_empty(), str(broken_sources))


func test_CT_BP_C06_prior_contract_checkpoint_shapes_unchanged() -> void:
	for contract_dir: String in PRIOR:
		var trace: Dictionary = Runner.json(contract_dir.path_join("solution.json"))
		var ctx: Dictionary = Runner.build(contract_dir, trace["players"], trace["tools"])
		assert_eq(ctx["errors"], [] as Array[Dictionary], contract_dir)
		var mission: Mission = ctx["mission"] as Mission
		var old: Dictionary = mission.durable_state()
		assert_false(old.has("cumulative_outage"))
		assert_eq(mission.restore_state(old), [] as Array[Dictionary], contract_dir)
		assert_eq(mission.durable_state(), old, contract_dir)
