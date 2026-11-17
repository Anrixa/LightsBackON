extends "res://tests/test_case.gd"
## CT-L3/C09 Wind Warning host-only boundaries, security, persistence and replay.
const Runner := preload("res://tests/support/solution_runner.gd")
const Grid := preload("res://scripts/simulation/power_grid.gd")
const Mission := preload("res://scripts/simulation/mission_director.gd")
const Host := preload("res://scripts/network/session_host.gd")
const C09: String = "res://content/contracts/c09_wind_warning"


func _trace() -> Dictionary:
	return Runner.json(C09.path_join("solution.json"))


func _context() -> Dictionary:
	var t: Dictionary = _trace()
	return Runner.build(C09, t["players"], t["tools"])


func _has(events: Array[Dictionary], kind: String) -> bool:
	for event: Dictionary in events:
		if event.get("type") == kind:
			return true
	return false


func test_CTL3_C09_original_hill_source_and_access_contract() -> void:
	var ctx: Dictionary = _context()
	assert_eq(ctx["errors"], [] as Array[Dictionary], str(ctx["errors"]))
	var st: Dictionary = (ctx["grid"] as Grid).canonical_state()
	assert_eq(st["nodes"]["GRID"]["capacity"], 28)
	assert_eq(st["nodes"]["GEN"]["capacity"], 6)
	assert_eq(st["edges"]["E_GRID_JW"]["capacity"], 14)
	assert_eq(st["edges"]["E_GRID_JE"]["capacity"], 14)
	assert_true(st["nodes"]["JW"]["failed"])
	assert_true(st["nodes"]["JW"]["tripped"])
	assert_false(st["edges"]["E_GRID_JE"]["healthy"])
	assert_eq(st["nodes"]["WORK_LIGHT"]["demand"], 2)
	var m: Dictionary = Runner.json(C09.path_join("mission.json"))
	assert_eq(m["required_consumers"].size(), 6)
	assert_eq(m["wind_routes"]["warning_ticks"], 600.0)
	assert_eq(m["wind_routes"]["close_start_ticks"], 900.0)
	assert_eq(m["wind_routes"]["close_end_ticks"], 1300.0)
	assert_eq(m["access_latches"][0]["supplied_ticks"], 100.0)
	assert_eq(Runner.send(ctx, "P1", "request_lock", "R_EAST_TRUNK", {}).get("code"), "NO_ACCESS")


func test_CTL3_C09_exact_warning_closure_reopen_and_offered_return() -> void:
	var ctx: Dictionary = _context()
	var mission: Mission = ctx["mission"] as Mission
	assert_false(_has(Runner.ticks(ctx, 599), "wind_warning"))
	assert_true(_has(Runner.ticks(ctx, 1), "wind_warning"))
	assert_eq(mission.canonical_state()["wind_routes"]["elapsed_ticks"], 600)
	assert_false(_has(Runner.ticks(ctx, 299), "wind_roof_closed"))
	assert_true(Runner.send(ctx, "P1", "use_route", "ROUTE_ROOF", {}).get("ok", false))
	var closing: Array[Dictionary] = Runner.ticks(ctx, 1)
	assert_true(_has(closing, "wind_roof_closed"))
	assert_true(_has(closing, "wind_safe_return_offered"))
	assert_true(mission.canonical_state()["wind_routes"]["roof_closed"])
	assert_eq(Runner.send(ctx, "P1", "use_route", "ROUTE_ROOF", {}).get("code"), "WIND_ROOF_CLOSED")
	assert_true(Runner.send(ctx, "P1", "use_route", "ROUTE_SAFE_RETURN", {}).get("ok", false))
	assert_eq(Runner.send(ctx, "P1", "use_route", "ROUTE_SAFE_RETURN", {}).get("code"), "NOT_ON_ROOF")
	assert_false(_has(Runner.ticks(ctx, 400), "wind_roof_reopened"))
	assert_true(mission.canonical_state()["wind_routes"]["roof_closed"])
	assert_true(_has(Runner.ticks(ctx, 1), "wind_roof_reopened"))
	assert_false(mission.canonical_state()["wind_routes"]["roof_closed"])
	assert_true(Runner.send(ctx, "P1", "use_route", "ROUTE_ROOF", {}).get("ok", false))


func test_CTL3_C09_ground_route_stays_accessible_during_roof_closure() -> void:
	var ctx: Dictionary = _context()
	Runner.ticks(ctx, 1000)
	assert_true((ctx["mission"] as Mission).canonical_state()["wind_routes"]["roof_closed"])
	assert_eq(Runner.send(ctx, "P1", "request_lock", "R_EAST_TRUNK", {}).get("code"), "NO_ACCESS")
	assert_eq(Runner.send(ctx, "P1", "use_route", "ROUTE_ROOF", {}).get("code"), "WIND_ROOF_CLOSED")
	assert_true(Runner.send(ctx, "P1", "use_route", "ROUTE_GROUND", {}).get("ok", false))
	assert_true(Runner.send(ctx, "P1", "request_lock", "R_EAST_TRUNK", {}).get("ok", false))


func test_CTL3_C09_cannot_forge_gust_time_authorization_or_route() -> void:
	var ctx: Dictionary = _context()
	var host: Host = ctx["host"] as Host
	var before: String = host.state_hash()
	assert_eq(Runner.send(ctx, "P1", "use_route", "ROUTE_ROOF", {"force": true}).get("code"), "MALFORMED")
	assert_eq(Runner.send(ctx, "P1", "use_route", "INVENTED", {}).get("code"), "UNKNOWN_ROUTE")
	assert_eq(Runner.send(ctx, "P1", "use_route", "ROUTE_SAFE_RETURN", {}).get("code"), "NOT_ON_ROOF")
	assert_eq(Runner.send(ctx, "NOT_ADMITTED", "use_route", "ROUTE_GROUND", {}).get("code"), "UNKNOWN_PEER")
	assert_eq(host.state_hash(), before)


func test_CTL3_C09_known_host_solution_reaches_all_services_and_three_stars() -> void:
	var ctx: Dictionary = _context()
	var trace: Dictionary = _trace()
	assert_eq(Runner.run(ctx, trace["steps"], int(trace["pace_ticks_per_command"])), [] as Array[String])
	var mission: Mission = ctx["mission"] as Mission
	assert_true(mission.is_complete())
	assert_true(int(ctx["now"]) <= int(trace["max_ticks"]))
	assert_true(mission.is_latched("LATCH_WORK_LIGHT"))
	assert_eq(mission.results()["required_restored"], 6)
	assert_eq(mission.results()["optional_services"], ["WORK_LIGHT"])
	assert_eq(mission.results()["optional_total"], 1)
	assert_eq(mission.results()["preventable_trips"], 0)
	assert_eq(mission.results()["stars"], 3)
	var st: Dictionary = (ctx["grid"] as Grid).canonical_state()
	assert_eq(st["nodes"]["GRID"]["load"], 25)
	assert_eq(st["edges"]["E_GRID_JW"]["flow"], 13)
	assert_eq(st["edges"]["E_GRID_JE"]["flow"], 12)
	assert_false(st["nodes"]["GEN"]["online"])


func test_CTL3_C09_missing_optional_light_never_blocks_extraction() -> void:
	var ctx: Dictionary = _context()
	var steps: Array = []
	for step: Dictionary in _trace()["steps"]:
		if step.get("entity", "") == "GEN_PORTABLE":
			continue
		if step.has("ticks") and int(step["ticks"]) == 100:
			steps.append({"ticks": 100, "expect_events": ["verified"]})
		else:
			steps.append(step)
	assert_eq(Runner.run(ctx, steps, 1), [] as Array[String])
	var mission: Mission = ctx["mission"] as Mission
	assert_true(mission.is_complete())
	assert_false(mission.is_latched("LATCH_WORK_LIGHT"))
	assert_eq(mission.results()["optional_services"], [] as Array[String])
	assert_eq(mission.results()["stars"], 2)


func test_CTL3_C09_gust_never_randomly_changes_grid_causality() -> void:
	var ctx: Dictionary = _context()
	var grid: Grid = ctx["grid"] as Grid
	var initial: Dictionary = grid.canonical_state()
	Runner.ticks(ctx, 1310)
	var final: Dictionary = grid.canonical_state()
	assert_eq(final["nodes"], initial["nodes"])
	assert_eq(final["edges"], initial["edges"])
	assert_true(_has(ctx["events"], "wind_warning"))
	assert_true(_has(ctx["events"], "wind_roof_closed"))
	assert_true(_has(ctx["events"], "wind_roof_reopened"))


func test_CTL3_C09_clock_checkpoint_and_route_access_resume_fail_closed() -> void:
	var ctx: Dictionary = _context()
	Runner.ticks(ctx, 945)
	assert_true(Runner.send(ctx, "P1", "use_route", "ROUTE_GROUND", {}).get("ok", false))
	var saved: Dictionary = (ctx["mission"] as Mission).durable_state()
	var restored: Dictionary = _context()
	var mission: Mission = restored["mission"] as Mission
	assert_eq(mission.restore_state(saved), [] as Array[Dictionary])
	assert_eq(mission.canonical_state()["wind_routes"]["elapsed_ticks"], 945)
	assert_true(mission.canonical_state()["wind_routes"]["roof_closed"])
	assert_eq(mission.canonical_state()["wind_routes"]["roof_players"], [] as Array[String])
	assert_true(Runner.send(restored, "P1", "request_lock", "R_EAST_TRUNK", {}).get("ok", false))
	var before: Dictionary = mission.durable_state()
	for record: Dictionary in [
		{"elapsed_ticks": -1, "access_route": "ROUTE_GROUND"},
		{"elapsed_ticks": 945, "access_route": "ROUTE_FALSE"},
		{"elapsed_ticks": "945", "access_route": "ROUTE_GROUND"},
		{"elapsed_ticks": 945, "access_route": "ROUTE_GROUND", "roof_players": ["P1"]}
	]:
		var forged: Dictionary = saved.duplicate(true)
		forged["wind_routes"] = record
		assert_false(mission.restore_state(forged).is_empty())
		assert_eq(mission.durable_state(), before)


func test_CTL3_C09_rejects_bad_gust_timing_and_duplicate_routes() -> void:
	var t: Dictionary = _trace()
	var base: Dictionary = Runner.json(C09.path_join("mission.json"))["wind_routes"]
	for mutation: Dictionary in [
		{"close_end_ticks": 899},
		{"warning_ticks": 900},
		{"ground_route": "ROUTE_ROOF"},
		{"safe_return": "ROUTE_GROUND"},
		{"grants": ""}
	]:
		var corrupted: Dictionary = base.duplicate(true)
		corrupted.merge(mutation, true)
		var check: Dictionary = Runner.build(C09, t["players"], t["tools"], {"wind_routes": corrupted})
		assert_false((check["errors"] as Array).is_empty(), str(mutation))


func test_CTL3_C09_prior_contract_mission_save_shapes_stay_unchanged() -> void:
	for contract: String in [
		"c01_alder_street", "c02_dinner_rush", "c03_roof_route", "c04_whole_block",
		"c05_canal_pump_access", "c06_cold_chain", "c07_wrong_label", "c08_split_supply"
	]:
		var path: String = "res://content/contracts/" + contract
		var trace: Dictionary = Runner.json(path.path_join("solution.json"))
		var ctx: Dictionary = Runner.build(path, trace["players"], trace["tools"])
		assert_eq(ctx["errors"], [] as Array[Dictionary])
		var mission: Mission = ctx["mission"] as Mission
		assert_false(mission.durable_state().has("wind_routes"))
		assert_false(mission.canonical_state().has("wind_routes"))
		assert_eq(mission.restore_state(mission.durable_state()), [] as Array[Dictionary])


func test_CTL3_C09_objectives_and_network_nodes_are_localized() -> void:
	var strings: Dictionary = Runner.json("res://content/ui/strings/en.json")["strings"]
	for key: String in [
		"objective.c09.access", "objective.c09.west", "objective.c09.east", "objective.c09.work_light",
		"repair.c09.west_fuse", "repair.c09.east_trunk", "wind.c09.warning",
		"wind.c09.roof_closed", "wind.c09.safe_return", "wind.c09.roof_reopened"
	]:
		assert_true(strings.has(key), key)
		assert_false(str(strings.get(key, "")).is_empty(), key)
	for item: Dictionary in Runner.json(C09.path_join("tablet.json"))["nodes"]:
		assert_true(strings.has(item["name_key"]), str(item))
