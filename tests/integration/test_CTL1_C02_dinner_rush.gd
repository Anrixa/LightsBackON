extends "res://tests/test_case.gd"
## CT-BP/C02: original Dinner Rush blueprint pp.18–19; two timed venue latches.
## This supersedes the provisional SIGN-first-power / 240s acceptance oracle.
const Runner := preload("res://tests/support/solution_runner.gd")
const Grid := preload("res://scripts/simulation/power_grid.gd")
const Mission := preload("res://scripts/simulation/mission_director.gd")
const C01: String = "res://content/contracts/c01_alder_street"
const C02: String = "res://content/contracts/c02_dinner_rush"


func _trace() -> Dictionary:
	return Runner.json(C02.path_join("solution.json"))


func _context() -> Dictionary:
	var t: Dictionary = _trace()
	return Runner.build(C02, t["players"], t["tools"])


func _begin_venue_gen(ctx: Dictionary, route: String = "E_TEMP_PUB") -> void:
	assert_true(Runner.send(ctx, "P1", "place_item", "GEN_PORTABLE", {"action": "pickup"}).get("ok", false))
	assert_true(Runner.send(ctx, "P1", "place_item", "GEN_PORTABLE", {"action": "place", "anchor": "PAD_VENUES"}).get("ok", false))
	assert_true(Runner.send(ctx, "P1", "place_item", "GEN_PORTABLE", {"action": "connect", "route": route}).get("ok", false))
	assert_true(Runner.send(ctx, "P1", "place_item", "GEN_PORTABLE", {"action": "start"}).get("ok", false))


func _prefix_through_first_venue_latch() -> Array:
	var out: Array = []
	for item: Dictionary in _trace()["steps"]:
		out.append(item)
		if item.has("ticks") and int(item["ticks"]) == 100:
			break
	return out


func _prefix_through_west_repair() -> Array:
	var out: Array = []
	for item: Dictionary in _trace()["steps"]:
		if item.has("ticks") and int(item["ticks"]) == 100 and out.size() > 10:
			break
		out.append(item)
	return out


func test_CT_BP_C02_original_topology_and_venue_contract_exact() -> void:
	var ctx: Dictionary = _context()
	assert_eq(ctx["errors"], [] as Array[Dictionary], str(ctx["errors"]))
	var st: Dictionary = (ctx["grid"] as Grid).canonical_state()
	assert_eq(st["nodes"]["GRID"]["capacity"], 24)
	assert_eq(st["nodes"]["GEN"]["capacity"], 6)
	assert_eq(st["edges"]["E_GRID_JW"]["capacity"], 12)
	assert_eq(st["edges"]["E_GRID_JE"]["capacity"], 12)
	assert_true(st["nodes"]["JW"]["failed"])
	assert_false(st["edges"]["E_GRID_JE"]["healthy"])
	assert_eq(st["nodes"]["MARKET"]["demand"], 5)
	assert_eq(st["nodes"]["PUB"]["demand"], 4)
	assert_eq(st["edges"]["E_TEMP_MARKET"]["capacity"], 5)
	assert_false(st["edges"]["E_TEMP_MARKET"]["enabled"])
	assert_false(st["edges"]["E_TEMP_PUB"]["enabled"])
	assert_false(st["nodes"]["SIGN"]["enabled"])
	var m: Dictionary = Runner.json(C02.path_join("mission.json"))
	assert_eq(m["required_consumers"].size(), 5)
	assert_eq(m["optional_services"], [] as Array)
	assert_false(m.has("optional_deadline_ticks"))
	assert_eq(m["opening_venues"]["consumers"], ["MARKET", "PUB"])
	assert_eq(int(m["opening_venues"]["supplied_ticks"]), 100)
	assert_eq(int(m["opening_venues"]["deadline_ticks"]), 1800)
	assert_eq(m["access_latches"].size(), 0)


func test_CT_BP_C02_host_solution_restores_20_and_both_optional_latches() -> void:
	var ctx: Dictionary = _context()
	var trace: Dictionary = _trace()
	assert_eq(Runner.run(ctx, trace["steps"], int(trace["pace_ticks_per_command"])), [] as Array[String])
	var mission: Mission = ctx["mission"] as Mission
	assert_true(mission.is_complete())
	assert_true(int(ctx["now"]) <= int(trace["max_ticks"]))
	var result: Dictionary = mission.results()
	assert_eq(result["required_restored"], 5)
	assert_eq(result["required_total"], 5)
	assert_eq(result["optional_services"], ["MARKET", "PUB"])
	assert_eq(result["optional_total"], 2)
	assert_eq(result["preventable_trips"], 0)
	assert_eq(result["stars"], 3)
	var st: Dictionary = (ctx["grid"] as Grid).canonical_state()
	assert_eq(st["nodes"]["GRID"]["load"], 20)
	assert_eq(st["edges"]["E_GRID_JW"]["flow"], 9)
	assert_eq(st["edges"]["E_GRID_JE"]["flow"], 11)
	assert_false(st["nodes"]["GEN"]["online"])
	assert_false(st["nodes"]["SIGN"]["supplied"])
	assert_false(mission.canonical_state()["opening_venues"]["failed"])


func test_CT_BP_C02_host_clock_waits_for_explicit_briefing_and_all_loaded() -> void:
	var t: Dictionary = _trace()
	var ctx: Dictionary = Runner.build(C02, t["players"], t["tools"], {}, false)
	assert_eq(ctx["errors"], [] as Array[Dictionary])
	Runner.ticks(ctx, 2200)
	var mission: Mission = ctx["mission"] as Mission
	assert_false(mission.canonical_state()["opening_venues"]["started"])
	assert_eq(mission.canonical_state()["opening_venues"]["elapsed"], 0)
	assert_false(mission.canonical_state()["opening_venues"]["failed"])
	assert_true(ctx["host"].begin_after_briefing().get("ok", false))
	assert_true(ctx["host"].begin_after_briefing().get("duplicate", false))
	Runner.ticks(ctx, 1)
	assert_eq(mission.canonical_state()["opening_venues"]["elapsed"], 1)


func test_CT_BP_C02_gen_pub_runs_100_ticks_and_is_a_valid_bonus_source() -> void:
	var ctx: Dictionary = _context()
	_begin_venue_gen(ctx)
	Runner.ticks(ctx, 99)
	assert_false((ctx["mission"] as Mission).canonical_state()["opening_venues"]["latched"].has("PUB"))
	Runner.ticks(ctx, 1)
	var state: Dictionary = (ctx["mission"] as Mission).canonical_state()["opening_venues"]
	assert_eq(state["latched"]["PUB"], 100)
	assert_eq(state["progress"]["PUB"], 100)
	assert_false(state["latched"].has("MARKET"))


func test_CT_BP_C02_temporary_pub_route_blocks_grid_dual_supply_atomically() -> void:
	var ctx: Dictionary = _context()
	_begin_venue_gen(ctx)
	var grid: Grid = ctx["grid"] as Grid
	var original: String = Grid.serialize(grid.canonical_state())
	var res: Dictionary = grid.apply({"op": "set", "id": "E_GRID_JE", "field": "healthy", "value": true})
	assert_eq(res.get("code"), "DUAL_SUPPLY")
	assert_eq(Grid.serialize(grid.canonical_state()), original)
	assert_true(grid.canonical_state()["nodes"]["PUB"]["supplied"])


func test_CT_BP_C02_wrong_pad_cannot_connect_venue_cable() -> void:
	var ctx: Dictionary = _context()
	assert_true(Runner.send(ctx, "P1", "place_item", "GEN_PORTABLE", {"action": "pickup"}).get("ok", false))
	assert_true(Runner.send(ctx, "P1", "place_item", "GEN_PORTABLE", {"action": "place", "anchor": "PAD_PUMP"}).get("ok", false))
	var reply: Dictionary = Runner.send(ctx, "P1", "place_item", "GEN_PORTABLE",
		{"action": "connect", "route": "E_TEMP_PUB"})
	assert_eq(reply.get("code"), "NO_SOCKET")
	assert_false((ctx["grid"] as Grid).canonical_state()["edges"]["E_TEMP_PUB"]["enabled"])


func test_CT_BP_C02_gen_overload_nine_pu_cannot_earn_valid_supply() -> void:
	var ctx: Dictionary = _context()
	_begin_venue_gen(ctx)
	assert_true(Runner.send(ctx, "P1", "place_item", "GEN_PORTABLE",
		{"action": "connect", "route": "E_TEMP_MARKET"}).get("ok", false))
	var st: Dictionary = (ctx["grid"] as Grid).canonical_state()
	assert_eq(st["nodes"]["GEN"]["load"], 9)
	assert_true(st["nodes"]["GEN"]["overloaded"])
	Runner.ticks(ctx, 15)
	assert_true((ctx["grid"] as Grid).canonical_state()["nodes"]["TEMP"]["tripped"])
	assert_eq((ctx["mission"] as Mission).canonical_state()["opening_venues"]["latched"].size(), 0)


func test_CT_BP_C02_venue_counter_resets_if_power_lost_and_restored_in_same_tick() -> void:
	var ctx: Dictionary = _context()
	_begin_venue_gen(ctx)
	Runner.ticks(ctx, 60)
	assert_true(Runner.send(ctx, "P1", "place_item", "GEN_PORTABLE", {"action": "stop"}).get("ok", false))
	assert_true(Runner.send(ctx, "P1", "place_item", "GEN_PORTABLE", {"action": "start"}).get("ok", false))
	Runner.ticks(ctx, 40)
	assert_false((ctx["mission"] as Mission).canonical_state()["opening_venues"]["latched"].has("PUB"))
	Runner.ticks(ctx, 60)
	assert_eq((ctx["mission"] as Mission).canonical_state()["opening_venues"]["latched"]["PUB"], 160)


func test_CT_BP_C02_market_latches_at_exact_opening_deadline() -> void:
	var ctx: Dictionary = _context()
	Runner.ticks(ctx, 1700)
	var grid: Grid = ctx["grid"] as Grid
	assert_true(grid.apply({"op": "set", "id": "JW", "field": "failed", "value": false})["ok"])
	assert_true(grid.apply({"op": "set", "id": "JW", "field": "tripped", "value": false})["ok"])
	Runner.ticks(ctx, 100)
	assert_eq((ctx["mission"] as Mission).canonical_state()["opening_venues"]["latched"]["MARKET"], 1800)
	assert_false((ctx["mission"] as Mission).canonical_state()["opening_venues"]["failed"])


func test_CT_BP_C02_first_100_supplied_ticks_after_1800_do_not_earn_bonus() -> void:
	var ctx: Dictionary = _context()
	Runner.ticks(ctx, 1701)
	var grid: Grid = ctx["grid"] as Grid
	assert_true(grid.apply({"op": "set", "id": "JW", "field": "failed", "value": false})["ok"])
	assert_true(grid.apply({"op": "set", "id": "JW", "field": "tripped", "value": false})["ok"])
	Runner.ticks(ctx, 100)
	assert_false((ctx["mission"] as Mission).canonical_state()["opening_venues"]["latched"].has("MARKET"))
	assert_true((ctx["mission"] as Mission).canonical_state()["opening_venues"]["failed"])


func test_CT_BP_C02_missed_both_openings_fails_optional_only_and_emits_feedback() -> void:
	var ctx: Dictionary = _context()
	var events: Array[Dictionary] = Runner.ticks(ctx, 1801)
	var missed: bool = false
	for e: Dictionary in events:
		if e.get("type") == "opening_deadline_missed":
			missed = true
	assert_true(missed)
	var steps: Array = (_trace()["steps"] as Array).duplicate(true)
	for item: Dictionary in steps:
		if item.has("expect_events") and item["expect_events"] == ["venue_opening_latched"]:
			item["expect_events"] = [] as Array[String]
	assert_eq(Runner.run(ctx, steps, 1), [] as Array[String])
	assert_true((ctx["mission"] as Mission).is_complete())
	assert_eq((ctx["mission"] as Mission).results()["required_restored"], 5)
	assert_eq((ctx["mission"] as Mission).results()["stars"], 2)
	assert_eq((ctx["mission"] as Mission).results()["optional_services"], [] as Array[String])


func test_CT_BP_C02_durable_partial_progress_and_latched_venue_round_trip() -> void:
	var ctx: Dictionary = _context()
	assert_eq(Runner.run(ctx, _prefix_through_west_repair(), 1), [] as Array[String])
	Runner.ticks(ctx, 50)
	var mission: Mission = ctx["mission"] as Mission
	var saved: Dictionary = mission.durable_state()
	# The runner advances one host tick after the west restore command.
	assert_eq(saved["opening_venues"]["progress"]["MARKET"], 51)
	assert_eq(saved["opening_venues"]["progress"]["PUB"], 100)
	assert_true(saved["opening_venues"]["latched"].has("PUB"))
	var fresh: Dictionary = _context()
	var dest: Mission = fresh["mission"] as Mission
	assert_eq(dest.restore_state(saved), [] as Array[Dictionary])
	assert_eq(dest.durable_state(), saved)
	assert_true(dest.begin_after_briefing().get("duplicate", false),
		"reloading a started clock cannot extend the deadline")
	assert_eq(dest.durable_state(), saved)


func test_CT_BP_C02_forged_opening_save_fails_closed_without_mutation() -> void:
	var ctx: Dictionary = _context()
	assert_eq(Runner.run(ctx, _prefix_through_first_venue_latch(), 1), [] as Array[String])
	var saved: Dictionary = (ctx["mission"] as Mission).durable_state()
	var dest: Mission = (_context()["mission"] as Mission)
	assert_eq(dest.restore_state(saved), [] as Array[Dictionary])
	var before: Dictionary = dest.durable_state()
	var invalid: Array[Dictionary] = []
	var rec: Dictionary = saved.duplicate(true)
	rec["opening_venues"]["progress"]["MARKET"] = -1
	invalid.append(rec)
	rec = saved.duplicate(true)
	rec["opening_venues"]["latched"]["FAKE"] = 100
	invalid.append(rec)
	rec = saved.duplicate(true)
	rec["opening_venues"]["latched"]["PUB"] = 1900
	invalid.append(rec)
	rec = saved.duplicate(true)
	rec["opening_venues"]["started"] = "yes"
	invalid.append(rec)
	rec = saved.duplicate(true)
	rec["opening_venues"]["progress"].erase("MARKET")
	invalid.append(rec)
	rec = saved.duplicate(true)
	rec["opening_venues"]["invented"] = 42
	invalid.append(rec)
	for bad: Dictionary in invalid:
		assert_false(dest.restore_state(bad).is_empty())
		assert_eq(dest.durable_state(), before)


func test_CT_BP_C02_invalid_opening_definition_rejected() -> void:
	var t: Dictionary = _trace()
	var bad: Array[Dictionary] = [
		{"opening_venues": {"consumers": ["MARKET", "MARKET"], "supplied_ticks": 100,
			"deadline_ticks": 1800, "start_trigger": "briefing_dismissed_all_loaded", "permitted_sources": ["GRID", "GEN"]}},
		{"opening_venues": {"consumers": ["MARKET", "PUB"], "supplied_ticks": 0,
			"deadline_ticks": 1800, "start_trigger": "briefing_dismissed_all_loaded", "permitted_sources": ["GRID", "GEN"]}},
		{"opening_venues": {"consumers": ["MARKET", "PUB"], "supplied_ticks": 100,
			"deadline_ticks": 99, "start_trigger": "briefing_dismissed_all_loaded", "permitted_sources": ["GRID", "GEN"]}},
		{"opening_venues": {"consumers": ["MARKET", "PUB"], "supplied_ticks": 100,
			"deadline_ticks": 1800, "start_trigger": "client_button", "permitted_sources": ["GRID", "GEN"]}},
		{"opening_venues": {"consumers": ["MARKET", "PUB"], "supplied_ticks": 100,
			"deadline_ticks": 1800, "start_trigger": "briefing_dismissed_all_loaded", "permitted_sources": ["GRID", "GRID"]}},
	]
	for variant: Dictionary in bad:
		var ctx: Dictionary = Runner.build(C02, t["players"], t["tools"], variant)
		assert_false((ctx["errors"] as Array).is_empty(), str(variant))


func test_CT_BP_C02_two_player_host_trace_requires_both_players_at_van() -> void:
	var t: Dictionary = _trace()
	var ctx: Dictionary = Runner.build(C02, ["P1", "P2"], t["tools"])
	assert_eq(ctx["errors"], [] as Array[Dictionary])
	var steps: Array = (t["steps"] as Array).duplicate(true)
	for i: int in steps.size():
		if steps[i].get("intent") == "request_extract":
			steps.insert(i, {"zone": "ZONE_VAN", "as": "P2", "inside": true})
			break
	assert_eq(Runner.run(ctx, steps, 1), [] as Array[String])
	assert_true((ctx["mission"] as Mission).is_complete())
	assert_eq((ctx["mission"] as Mission).results()["stars"], 3)


func test_CT_BP_C02_C01_legacy_checkpoint_remains_byte_shaped() -> void:
	var t: Dictionary = Runner.json(C01.path_join("solution.json"))
	var ctx: Dictionary = Runner.build(C01, t["players"], t["tools"])
	assert_eq(ctx["errors"], [] as Array[Dictionary])
	var mission: Mission = ctx["mission"] as Mission
	assert_false(mission.canonical_state().has("opening_venues"))
	assert_false(mission.durable_state().has("opening_venues"))
	var before: Dictionary = mission.durable_state()
	assert_eq(mission.restore_state(before), [] as Array[Dictionary])
	assert_eq(mission.durable_state(), before)
