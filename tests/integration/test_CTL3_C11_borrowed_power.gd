extends "res://tests/test_case.gd"
## CT-L3/C11: source/headless-only Borrowed Power original blueprint checks.
## Physical Hill Road, real human/controller, GPU, Steam and release remain HOLD.

const Runner := preload("res://tests/support/solution_runner.gd")
const Grid := preload("res://scripts/simulation/power_grid.gd")
const Mission := preload("res://scripts/simulation/mission_director.gd")
const Host := preload("res://scripts/network/session_host.gd")
const Hud := preload("res://scripts/ui/hud_presenter.gd")
const C11: String = "res://content/contracts/c11_borrowed_power"
const EARLIER: Array[String] = [
	"res://content/contracts/c01_alder_street", "res://content/contracts/c02_dinner_rush",
	"res://content/contracts/c03_roof_route", "res://content/contracts/c04_whole_block",
	"res://content/contracts/c05_canal_pump_access", "res://content/contracts/c06_cold_chain",
	"res://content/contracts/c07_wrong_label", "res://content/contracts/c08_split_supply",
	"res://content/contracts/c09_wind_warning", "res://content/contracts/c10_community_night"
]


func _trace() -> Dictionary:
	return Runner.json(C11.path_join("solution.json"))


func _context(players: Array = ["P1"]) -> Dictionary:
	return Runner.build(C11, players, _trace()["tools"])


func _switch(ctx: Dictionary, id: String, value: bool) -> Dictionary:
	return Runner.send(ctx, "P1", "toggle_switch", id, {"value": value})


func _finish(ctx: Dictionary) -> void:
	var m: Mission = ctx["mission"] as Mission
	if not m.verified():
		Runner.ticks(ctx, 100 - int(m.canonical_state()["verify_ticks"]))
	(ctx["host"] as Host).set_in_zone("P1", "ZONE_VAN", true)
	assert_true(Runner.send(ctx, "P1", "request_extract", "ZONE_VAN", {"action": "start"}).get("ok", false))
	Runner.ticks(ctx, 50)
	assert_true(m.is_complete())


func test_CTL3_C11_original_hill_topology_and_50_tick_optional() -> void:
	var ctx: Dictionary = _context()
	assert_eq(ctx["errors"], [] as Array[Dictionary], str(ctx["errors"]))
	var st: Dictionary = (ctx["grid"] as Grid).canonical_state()
	assert_eq(int(st["nodes"]["GRID"]["capacity"]), 28)
	assert_eq(int(st["nodes"]["GEN"]["capacity"]), 6)
	assert_eq(int(st["edges"]["E_GRID_WEST"]["capacity"]), 14)
	assert_eq(int(st["edges"]["E_GRID_EAST"]["capacity"]), 14)
	assert_false(st["nodes"]["WEST"]["tripped"])
	assert_false(st["edges"]["E_GRID_EAST"]["healthy"])
	assert_eq(int(st["nodes"]["GRID"]["load"]), 13)
	assert_eq(int(st["nodes"]["GARAGE_CONTROL"]["demand"]), 4)
	assert_eq(int(st["edges"]["E_WEST_TELECOM"]["capacity"]), 4)
	assert_false(st["edges"]["E_WEST_TELECOM"]["enabled"])
	var mission: Dictionary = Runner.json(C11.path_join("mission.json"))
	assert_eq(int(mission["optional_max_consecutive_outage"]["max_outage_ticks"]), 50)
	assert_eq(int(mission["access_latches"][0]["supplied_ticks"]), 100)
	assert_eq(mission["required_consumers"].size(), 6)


func test_CTL3_C11_full_host_solution_and_bonus() -> void:
	var ctx: Dictionary = _context()
	assert_eq(ctx["errors"], [] as Array[Dictionary], str(ctx["errors"]))
	var trace: Dictionary = _trace()
	assert_eq(Runner.run(ctx, trace["steps"], int(trace["pace_ticks_per_command"])), [] as Array[String])
	var m: Mission = ctx["mission"] as Mission
	assert_true(m.is_complete())
	assert_true(int(ctx["now"]) <= int(trace["max_ticks"]))
	assert_true(m.is_latched("LATCH_GARAGE_CONTROL"))
	assert_eq(m.results()["required_restored"], 6)
	assert_eq(m.results()["required_total"], 6)
	assert_eq(m.results()["optional_services"], ["TELECOM_CONTINUITY"])
	assert_eq(m.results()["optional_total"], 1)
	assert_eq(m.results()["preventable_trips"], 0)
	assert_eq(m.results()["stars"], 3)
	var st: Dictionary = (ctx["grid"] as Grid).canonical_state()
	assert_eq(st["nodes"]["GRID"]["load"], 25)
	assert_eq(st["edges"]["E_GRID_WEST"]["flow"], 13)
	assert_eq(st["edges"]["E_GRID_EAST"]["flow"], 12)
	assert_false(st["nodes"]["GEN"]["online"])


func test_CTL3_C11_optional_exact_50_51_initial_darkness_boundary() -> void:
	var ctx: Dictionary = _context()
	var m: Mission = ctx["mission"] as Mission
	Runner.ticks(ctx, 50)
	assert_eq(m.canonical_state()["max_consecutive_outage"]["elapsed_ticks"], 50)
	assert_false(m.canonical_state()["max_consecutive_outage"]["missed"])
	Runner.ticks(ctx, 1)
	assert_true(m.canonical_state()["max_consecutive_outage"]["missed"])
	assert_eq(m.canonical_state()["max_consecutive_outage"]["elapsed_ticks"], 51)
	assert_eq(Runner.run(ctx, _trace()["steps"], 1), [] as Array[String])
	assert_true(m.is_complete())
	assert_eq(m.results()["stars"], 2)
	assert_eq(m.results()["optional_services"], [] as Array[String])


func test_CTL3_C11_break_before_make_refuses_generator_and_west_dual_route() -> void:
	var ctx: Dictionary = _context()
	var prefix: Array[Dictionary] = []
	for step: Dictionary in _trace()["steps"]:
		if step.get("entity") == "SW_GREENHOUSE":
			break
		prefix.append(step)
	assert_eq(Runner.run(ctx, prefix, 1), [] as Array[String])
	assert_true(_switch(ctx, "SW_GREENHOUSE", false).get("ok", false))
	var before: Dictionary = (ctx["grid"] as Grid).canonical_state()
	var response: Dictionary = _switch(ctx, "SW_WEST_TELECOM", true)
	assert_false(response.get("ok", false))
	assert_eq((ctx["grid"] as Grid).canonical_state(), before)


func test_CTL3_C11_generator_4_plus_4_over_6_trips_after_15_ticks() -> void:
	var ctx: Dictionary = _context()
	var prefix: Array[Dictionary] = []
	for step: Dictionary in _trace()["steps"]:
		prefix.append(step)
		if step.get("intent") == "place_item" and step.get("payload", {}).get("action") == "start":
			break
	assert_eq(Runner.run(ctx, prefix, 1), [] as Array[String])
	var response: Dictionary = Runner.send(ctx, "P1", "place_item", "GEN_PORTABLE",
		{"action":"connect","route":"E_TEMP_GARAGE"})
	assert_true(response.get("ok", false))
	var g: Grid = ctx["grid"] as Grid
	assert_eq(g.canonical_state()["edges"]["E_GEN_TEMP"]["flow"], 8)
	Runner.ticks(ctx, 15)
	assert_true(g.canonical_state()["nodes"]["TEMP"]["tripped"])


func test_CTL3_C11_checkpoint_fail_closed_and_relative_clock() -> void:
	var ctx: Dictionary = _context()
	var m: Mission = ctx["mission"] as Mission
	Runner.ticks(ctx, 25)
	var original: Dictionary = m.durable_state()
	assert_eq(original["max_consecutive_outage"]["elapsed_ticks"], 25)
	for wrong: Dictionary in [
		{"elapsed_ticks":-1, "missed":false, "pending_unpowered":false},
		{"elapsed_ticks":true, "missed":false, "pending_unpowered":false},
		{"elapsed_ticks":52, "missed":true, "pending_unpowered":false},
		{"elapsed_ticks":51, "missed":false, "pending_unpowered":false},
		{"elapsed_ticks":25, "missed":true, "pending_unpowered":false},
		{"elapsed_ticks":25, "missed":false, "pending_unpowered":false, "forged":true}
	]:
		var forged: Dictionary = original.duplicate(true)
		forged["max_consecutive_outage"] = wrong
		assert_false(m.restore_state(forged).is_empty(), str(wrong))
		assert_eq(m.durable_state(), original)
	var missing: Dictionary = original.duplicate(true)
	missing.erase("max_consecutive_outage")
	assert_false(m.restore_state(missing).is_empty())
	assert_eq(m.durable_state(), original)
	var restored: Dictionary = _context()
	var other: Mission = restored["mission"] as Mission
	assert_eq(other.restore_state(original), [] as Array[Dictionary])
	assert_eq(other.durable_state(), original)
	Runner.ticks(restored, 25)
	assert_eq(other.canonical_state()["max_consecutive_outage"]["elapsed_ticks"], 50)


func test_CTL3_C11_reject_invalid_optional_definitions() -> void:
	var defn: Dictionary = Runner.json(C11.path_join("mission.json"))["optional_max_consecutive_outage"]
	for bad_limit: Variant in [0, -1, 1.25, true, "50"]:
		var invalid: Dictionary = defn.duplicate(true)
		invalid["max_outage_ticks"] = bad_limit
		var result: Dictionary = Runner.build(C11, _trace()["players"], _trace()["tools"],
			{"optional_max_consecutive_outage":invalid})
		assert_false((result["errors"] as Array).is_empty(), str(bad_limit))
	for bad_source: Array in [["GRID", "GRID"], ["GEN"], ["GRID", "UNKNOWN"]]:
		var invalid: Dictionary = defn.duplicate(true)
		invalid["permitted_sources"] = bad_source
		var result: Dictionary = Runner.build(C11, _trace()["players"], _trace()["tools"],
			{"optional_max_consecutive_outage":invalid})
		assert_false((result["errors"] as Array).is_empty(), str(bad_source))


func test_CTL3_C11_earlier_contract_checkpoint_shapes_unchanged() -> void:
	for directory: String in EARLIER:
		var trace: Dictionary = Runner.json(directory.path_join("solution.json"))
		var ctx: Dictionary = Runner.build(directory, trace["players"], trace["tools"])
		assert_eq(ctx["errors"], [] as Array[Dictionary], directory)
		var m: Mission = ctx["mission"] as Mission
		var durable: Dictionary = m.durable_state()
		assert_false(durable.has("max_consecutive_outage"), directory)
		assert_eq(m.restore_state(durable), [] as Array[Dictionary], directory)
		assert_eq(m.durable_state(), durable, directory)


func test_CTL3_C11_two_player_solution_does_not_skip_extraction() -> void:
	var ctx: Dictionary = _context(["P1","P2"])
	var steps: Array = _trace()["steps"].duplicate(true)
	for i: int in steps.size():
		if steps[i].get("intent") == "request_extract":
			steps.insert(i, {"zone":"ZONE_VAN","as":"P2","inside":true})
			break
	assert_eq(Runner.run(ctx, steps, 1), [] as Array[String])
	assert_true((ctx["mission"] as Mission).is_complete())


func test_CTL3_C11_authoritative_hud_and_localization() -> void:
	var ctx: Dictionary = _context()
	var m: Mission = ctx["mission"] as Mission
	var view: Dictionary = Hud.build((ctx["host"] as Host).authoritative_state(),
		m.objectives(), {"local_player":"P1","tools":[]})
	assert_true(view.has("max_consecutive_outage"))
	assert_eq(view["max_consecutive_outage"]["remaining_ticks"], 51)
	var strings: Dictionary = Runner.json("res://content/ui/strings/en.json")["strings"]
	for node: Dictionary in Runner.json(C11.path_join("tablet.json"))["nodes"]:
		assert_true(strings.has(node["name_key"]), node["name_key"])
	for objective: Dictionary in Runner.json(C11.path_join("mission.json"))["objectives"]:
		assert_true(strings.has(objective["text_key"]), objective["text_key"])
	assert_true(strings.has("repair.c11.east_trunk"))
