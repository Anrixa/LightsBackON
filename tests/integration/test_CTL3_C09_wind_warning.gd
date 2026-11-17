extends "res://tests/test_case.gd"
## CT-L3/C09 original Hill Road Wind Warning source and host-authority regressions.
## Headless only: no human route time, real roof collision, GPU or Steam is certified.

const Runner := preload("res://tests/support/solution_runner.gd")
const Grid := preload("res://scripts/simulation/power_grid.gd")
const Mission := preload("res://scripts/simulation/mission_director.gd")
const C09: String = "res://content/contracts/c09_wind_warning"
const PRIOR: Array[String] = [
	"res://content/contracts/c01_alder_street",
	"res://content/contracts/c02_dinner_rush",
	"res://content/contracts/c03_roof_route",
	"res://content/contracts/c04_whole_block",
	"res://content/contracts/c05_canal_pump_access",
	"res://content/contracts/c06_cold_chain",
	"res://content/contracts/c07_wrong_label",
	"res://content/contracts/c08_split_supply",
]


func _trace() -> Dictionary:
	return Runner.json(C09.path_join("solution.json"))


func _context(players: Array = ["P1"]) -> Dictionary:
	return Runner.build(C09, players, _trace()["tools"])


func _wind(ctx: Dictionary) -> Dictionary:
	return (ctx["mission"] as Mission).canonical_state()["wind_window"]


func _execute(ctx: Dictionary, entity: String, intent: String = "use_ladder", payload: Dictionary = {}) -> Dictionary:
	return Runner.send(ctx, "P1", intent, entity, payload)


func _generator(ctx: Dictionary, action: String, extra: Dictionary = {}) -> Dictionary:
	var payload: Dictionary = {"action": action}
	payload.merge(extra)
	return Runner.send(ctx, "P1", "place_item", "GEN_PORTABLE", payload)


func test_CTL3_C09_source_matches_original_hill_baseline() -> void:
	var ctx: Dictionary = _context()
	assert_eq(ctx["errors"], [] as Array[Dictionary], str(ctx["errors"]))
	var g: Dictionary = (ctx["grid"] as Grid).canonical_state()
	assert_eq(g["nodes"]["GRID"]["capacity"], 28)
	assert_eq(g["nodes"]["GEN"]["capacity"], 6)
	assert_eq(g["edges"]["E_GRID_WEST"]["capacity"], 14)
	assert_eq(g["edges"]["E_GRID_EAST"]["capacity"], 14)
	assert_true(g["nodes"]["WEST"]["failed"])
	assert_true(g["nodes"]["WEST"]["tripped"])
	assert_false(g["edges"]["E_GRID_EAST"]["healthy"])
	assert_eq(g["nodes"]["WORK_LIGHT"]["demand"], 2)
	assert_false(g["nodes"]["WORK_LIGHT"]["enabled"])
	var mission: Dictionary = Runner.json(C09.path_join("mission.json"))
	assert_eq(mission["required_consumers"].size(), 6)
	var total: int = 0
	for id: String in mission["required_consumers"]:
		total += int(g["nodes"][id]["demand"])
	assert_eq(total, 25)
	assert_eq(mission["optional_latch_rewards"], ["LATCH_SHELTER_LIGHT"])
	assert_eq(int(mission["access_latches"][0]["supplied_ticks"]), 100)
	assert_eq(int(mission["wind_window"]["ground_extra_ticks"]), 200)
	assert_eq(Runner.json(C09.path_join("repairs.json"))["repairs"].size(), 2)


func test_CTL3_C09_known_roof_route_host_solution_six_services_and_bonus() -> void:
	var ctx: Dictionary = _context()
	var solution: Dictionary = _trace()
	assert_eq(Runner.run(ctx, solution["steps"], int(solution["pace_ticks_per_command"])),
		[] as Array[String])
	var m: Mission = ctx["mission"] as Mission
	assert_true(m.is_complete())
	assert_true(int(ctx["now"]) <= int(solution["max_ticks"]))
	assert_eq(m.results()["required_total"], 6)
	assert_eq(m.results()["required_restored"], 6)
	assert_eq(m.results()["optional_services"], ["WORK_LIGHT"])
	assert_eq(m.results()["optional_total"], 1)
	assert_eq(m.results()["preventable_trips"], 0)
	assert_eq(m.results()["stars"], 3)
	var grid: Dictionary = (ctx["grid"] as Grid).canonical_state()
	assert_eq(grid["nodes"]["GRID"]["load"], 25)
	assert_eq(grid["edges"]["E_GRID_WEST"]["flow"], 13)
	assert_eq(grid["edges"]["E_GRID_EAST"]["flow"], 12)
	assert_false(grid["nodes"]["GEN"]["online"])


func test_CTL3_C09_warning_closure_exact_600_900_1300_1301() -> void:
	var ctx: Dictionary = _context()
	Runner.ticks(ctx, 599)
	assert_false(_wind(ctx)["warned"])
	assert_false(_wind(ctx)["roof_closed"])
	var events: Array[Dictionary] = Runner.ticks(ctx, 1)
	assert_eq(_wind(ctx)["elapsed_ticks"], 600)
	assert_true(_wind(ctx)["warned"])
	assert_true(_has_event(events, "wind_warning"))
	Runner.ticks(ctx, 299)
	assert_false(_wind(ctx)["roof_closed"])
	events = Runner.ticks(ctx, 1)
	assert_true(_wind(ctx)["roof_closed"])
	assert_true(_has_event(events, "wind_roof_closed"))
	Runner.ticks(ctx, 400)
	assert_eq(_wind(ctx)["elapsed_ticks"], 1300)
	assert_true(_wind(ctx)["roof_closed"])
	events = Runner.ticks(ctx, 1)
	assert_false(_wind(ctx)["roof_closed"])
	assert_true(_has_event(events, "wind_roof_reopened"))


func test_CTL3_C09_wind_closure_refuses_entry_but_never_return_or_ground() -> void:
	var ctx: Dictionary = _context()
	assert_true(_execute(ctx, "ROUTE_ROOF_ENTRY").get("ok", false))
	Runner.ticks(ctx, 900)
	assert_eq(_execute(ctx, "ROUTE_ROOF_ENTRY").get("code"), "WIND_CLOSED",
		"earlier successful entry cannot bypass later closure")
	assert_true(_execute(ctx, "ROUTE_ROOF_RETURN").get("ok", false),
		"already-roofed player must have safe return")
	assert_true(_execute(ctx, "ROUTE_GROUND_SERVICE").get("ok", false),
		"ground service alley cannot be blocked by the roof closure")
	Runner.ticks(ctx, 401)
	assert_true(_execute(ctx, "ROUTE_ROOF_ENTRY").get("ok", false))


func test_CTL3_C09_gust_does_not_mutate_faults_or_reset_repairs() -> void:
	var ctx: Dictionary = _context()
	var before: Dictionary = (ctx["grid"] as Grid).canonical_state()
	Runner.ticks(ctx, 1500)
	var after: Dictionary = (ctx["grid"] as Grid).canonical_state()
	assert_eq(after["nodes"], before["nodes"], "wind must not alter node/fault states")
	assert_eq(after["edges"], before["edges"], "wind must not alter electrical topology")
	assert_eq(after["tick"], 1500, "the host clock itself is expected to advance")


func test_CTL3_C09_east_repair_requires_real_route_access() -> void:
	var ctx: Dictionary = _context()
	assert_eq(_execute(ctx, "R_EAST_TRUNK", "request_lock").get("code"), "NO_ACCESS")
	Runner.ticks(ctx, 950)
	assert_eq(_execute(ctx, "ROUTE_ROOF_ENTRY").get("code"), "WIND_CLOSED")
	assert_true(_execute(ctx, "ROUTE_GROUND_SERVICE").get("ok", false))
	assert_true(_execute(ctx, "R_EAST_TRUNK", "request_lock").get("ok", false))


func test_CTL3_C09_ground_detour_solves_during_wind_without_optional_penalty() -> void:
	var ctx: Dictionary = _context()
	Runner.ticks(ctx, 950)
	var detour: Array = _trace()["steps"].duplicate(true)
	for step: Dictionary in detour:
		if step.get("intent", "") == "use_ladder" and step.get("entity", "") == "ROUTE_ROOF_ENTRY":
			step["entity"] = "ROUTE_GROUND_SERVICE"
	assert_eq(Runner.run(ctx, detour, 1), [] as Array[String])
	assert_true((ctx["mission"] as Mission).is_complete())
	assert_eq((ctx["mission"] as Mission).results()["stars"], 3)


func test_CTL3_C09_bonus_99_100_and_mid_tick_reset() -> void:
	var ctx: Dictionary = _context()
	var m: Mission = ctx["mission"] as Mission
	assert_true(_generator(ctx, "pickup").get("ok", false))
	assert_true(_generator(ctx, "place", {"anchor": "PAD_SHELTER"}).get("ok", false))
	assert_true(_generator(ctx, "connect", {"route": "E_TEMP_WORK_LIGHT"}).get("ok", false))
	assert_true(_generator(ctx, "start").get("ok", false))
	assert_true(_execute(ctx, "SW_WORK_LIGHT", "toggle_switch", {"value": true}).get("ok", false))
	Runner.ticks(ctx, 99)
	assert_false(m.is_latched("LATCH_SHELTER_LIGHT"))
	assert_true(_execute(ctx, "SW_WORK_LIGHT", "toggle_switch", {"value": false}).get("ok", false))
	assert_eq(m.canonical_state()["latch_ticks"]["LATCH_SHELTER_LIGHT"], 0)
	assert_true(_execute(ctx, "SW_WORK_LIGHT", "toggle_switch", {"value": true}).get("ok", false))
	Runner.ticks(ctx, 99)
	assert_false(m.is_latched("LATCH_SHELTER_LIGHT"))
	Runner.ticks(ctx, 1)
	assert_true(m.is_latched("LATCH_SHELTER_LIGHT"))


func test_CTL3_C09_optional_omission_does_not_block_required_restoration() -> void:
	var ctx: Dictionary = _context()
	var no_bonus: Array = []
	for step: Dictionary in _trace()["steps"]:
		if step.get("entity", "") == "GEN_PORTABLE" or step.get("entity", "") == "SW_WORK_LIGHT":
			continue
		if step.has("ticks") and int(step["ticks"]) == 100:
			no_bonus.append({"ticks": 100, "expect_events": ["verified"]})
		else:
			no_bonus.append(step)
	assert_eq(Runner.run(ctx, no_bonus, 1), [] as Array[String])
	var m: Mission = ctx["mission"] as Mission
	assert_true(m.is_complete())
	assert_eq(m.results()["required_restored"], 6)
	assert_eq(m.results()["optional_services"], [] as Array[String])
	assert_eq(m.results()["stars"], 2)


func test_CTL3_C09_restore_keeps_mission_relative_wind_clock() -> void:
	var ctx: Dictionary = _context()
	Runner.ticks(ctx, 899)
	var saved: Dictionary = (ctx["mission"] as Mission).durable_state()
	var restored_ctx: Dictionary = _context()
	var m: Mission = restored_ctx["mission"] as Mission
	assert_eq(m.restore_state(saved), [] as Array[Dictionary])
	assert_eq(_wind(restored_ctx)["elapsed_ticks"], 899)
	assert_false(_wind(restored_ctx)["roof_closed"])
	var ev: Array[Dictionary] = Runner.ticks(restored_ctx, 1)
	assert_true(_wind(restored_ctx)["roof_closed"])
	assert_true(_has_event(ev, "wind_roof_closed"))
	assert_eq(_execute(restored_ctx, "ROUTE_ROOF_ENTRY").get("code"), "WIND_CLOSED")


func test_CTL3_C09_bad_wind_checkpoint_rejected_without_mutation() -> void:
	var ctx: Dictionary = _context()
	Runner.ticks(ctx, 44)
	var m: Mission = ctx["mission"] as Mission
	var original: Dictionary = m.durable_state()
	for bad: Variant in [
		{"elapsed_ticks": -1},
		{"elapsed_ticks": true},
		{"elapsed_ticks": "forty"},
		{"elapsed_ticks": 1, "forged": true}
	]:
		var save: Dictionary = original.duplicate(true)
		save["wind_window"] = bad
		assert_false(m.restore_state(save).is_empty())
		assert_eq(m.durable_state(), original)
	var missing: Dictionary = original.duplicate(true)
	missing.erase("wind_window")
	assert_false(m.restore_state(missing).is_empty())
	assert_eq(m.durable_state(), original)


func test_CTL3_C09_invalid_authored_route_windows_fail_closed() -> void:
	var trace: Dictionary = _trace()
	var valid: Dictionary = Runner.json(C09.path_join("mission.json"))["wind_window"]
	for changes: Dictionary in [
		{"warning_ticks": 0}, {"warning_ticks": true},
		{"closed_from_ticks": 600}, {"closed_through_ticks": 899},
		{"roof_entry": "ROUTE_GROUND_SERVICE"},
		{"roof_return": "MISSING_ROUTE"}, {"ground_extra_ticks": -1}
	]:
		var mutated: Dictionary = valid.duplicate(true)
		mutated.merge(changes, true)
		var ctx: Dictionary = Runner.build(C09, trace["players"], trace["tools"],
			{"wind_window": mutated})
		assert_false((ctx["errors"] as Array).is_empty(), str(changes))


func test_CTL3_C09_two_connected_players_can_complete_host_trace() -> void:
	var ctx: Dictionary = _context(["P1", "P2"])
	var coop_steps: Array = _trace()["steps"].duplicate(true)
	for step: Dictionary in coop_steps:
		if step.get("entity", "") == "ROUTE_ROOF_ENTRY" or step.get("entity", "") == "R_EAST_TRUNK":
			step["as"] = "P2"
		if step.get("intent", "") == "request_extract":
			break
	var extract_index: int = -1
	for i: int in coop_steps.size():
		if coop_steps[i].get("intent", "") == "request_extract":
			extract_index = i
			break
	assert_true(extract_index >= 0)
	coop_steps.insert(extract_index, {"zone": "ZONE_VAN", "as": "P2", "inside": true})
	assert_eq(Runner.run(ctx, coop_steps, 1), [] as Array[String])
	assert_true((ctx["mission"] as Mission).is_complete())
	assert_eq((ctx["mission"] as Mission).results()["stars"], 3)


func test_CTL3_C09_older_eight_contract_checkpoint_shapes_stable() -> void:
	for folder: String in PRIOR:
		var trace: Dictionary = Runner.json(folder.path_join("solution.json"))
		var ctx: Dictionary = Runner.build(folder, trace["players"], trace["tools"])
		assert_eq(ctx["errors"], [] as Array[Dictionary], folder)
		var m: Mission = ctx["mission"] as Mission
		var saved: Dictionary = m.durable_state()
		assert_false(saved.has("wind_window"), folder)
		assert_eq(m.restore_state(saved), [] as Array[Dictionary], folder)
		assert_eq(m.durable_state(), saved, folder)


func test_CTL3_C09_source_strings_and_tablet_have_unique_keys() -> void:
	var strings: Dictionary = Runner.json("res://content/ui/strings/en.json")["strings"]
	var places: Dictionary = {}
	for item: Dictionary in Runner.json(C09.path_join("tablet.json"))["nodes"]:
		assert_false(places.has(item["id"]), "duplicate tablet node " + str(item["id"]))
		places[item["id"]] = true
		assert_true(strings.has(item["name_key"]), str(item["name_key"]))
	for obj: Dictionary in Runner.json(C09.path_join("mission.json"))["objectives"]:
		assert_true(strings.has(obj["text_key"]), str(obj["text_key"]))
	assert_eq(places.size(), 12)


func _has_event(events: Array[Dictionary], kind: String) -> bool:
	for event: Dictionary in events:
		if event.get("type", "") == kind:
			return true
	return false
