extends "res://tests/test_case.gd"
## CT-BP/C05 Rising Water: original-blueprint host simulation and negative tests.
## These tests do not qualify 3D scenes, humans, controllers, shipped saves or Steam.
const Runner := preload("res://tests/support/solution_runner.gd")
const Grid := preload("res://scripts/simulation/power_grid.gd")
const Mission := preload("res://scripts/simulation/mission_director.gd")
const C05: String = "res://content/contracts/c05_canal_pump_access"
const PRIOR: Array[String] = [
	"res://content/contracts/c01_alder_street",
	"res://content/contracts/c02_dinner_rush",
	"res://content/contracts/c03_roof_route",
	"res://content/contracts/c04_whole_block",
	"res://content/contracts/c06_cold_chain",
	"res://content/contracts/c07_wrong_label",
	"res://content/contracts/c08_split_supply",
]


func _trace() -> Dictionary:
	return Runner.json(C05.path_join("solution.json"))


func _context() -> Dictionary:
	var sol: Dictionary = _trace()
	return Runner.build(C05, sol["players"], sol["tools"])


func _action(ctx: Dictionary, action: String, extra: Dictionary = {}) -> Dictionary:
	var payload: Dictionary = {"action": action}
	payload.merge(extra)
	return Runner.send(ctx, "P1", "place_item", "GEN_PORTABLE", payload)


func _place(ctx: Dictionary) -> void:
	assert_true(_action(ctx, "pickup").get("ok", false))
	assert_true(_action(ctx, "place", {"anchor": "PAD_CANAL_PUMPS"}).get("ok", false))


func _start_pump(ctx: Dictionary, route: String) -> void:
	assert_true(_action(ctx, "connect", {"route": route}).get("ok", false))
	assert_true(_action(ctx, "start").get("ok", false))


func _stop_pump(ctx: Dictionary, route: String) -> void:
	assert_true(_action(ctx, "stop").get("ok", false))
	assert_true(_action(ctx, "disconnect", {"route": route}).get("ok", false))


func test_CT_BP_C05_original_six_services_and_power_ratings() -> void:
	var ctx: Dictionary = _context()
	assert_eq(ctx["errors"], [] as Array[Dictionary], str(ctx["errors"]))
	var st: Dictionary = (ctx["grid"] as Grid).canonical_state()
	var mission: Dictionary = Runner.json(C05.path_join("mission.json"))
	assert_eq(st["nodes"]["GRID"]["capacity"], 30)
	assert_eq(st["nodes"]["GEN"]["capacity"], 8)
	assert_eq(st["edges"]["E_GRID_WEST"]["capacity"], 14)
	assert_eq(st["edges"]["E_GRID_EAST"]["capacity"], 14)
	assert_eq(st["nodes"]["PUMP_WEST"]["demand"], 5)
	assert_eq(st["nodes"]["PUMP_EAST"]["demand"], 4)
	assert_false(st["nodes"]["WEST"]["failed"])
	assert_false(st["edges"]["E_GRID_WEST"]["healthy"])
	assert_false(st["edges"]["E_GRID_EAST"]["healthy"])
	assert_eq(mission["required_consumers"].size(), 6)
	assert_eq(mission["optional_services"].size(), 0)
	assert_eq(mission["optional_pickup_deadline"]["deadline_ticks"], 1800)
	assert_eq(mission["optional_pickup_deadline"]["start_trigger"], "first_equipment_pickup")
	assert_eq(Runner.send(ctx, "P1", "request_lock", "R_WEST_TRUNK", {}).get("code"), "NO_ACCESS")
	assert_eq(Runner.send(ctx, "P1", "request_lock", "R_EAST_TRUNK", {}).get("code"), "NO_ACCESS")


func test_CT_BP_C05_full_solution_cold_store_bonus_and_safe_load() -> void:
	var ctx: Dictionary = _context()
	var sol: Dictionary = _trace()
	assert_eq(Runner.run(ctx, sol["steps"], int(sol["pace_ticks_per_command"])), [] as Array[String])
	var m: Mission = ctx["mission"] as Mission
	assert_true(m.is_complete())
	assert_true(int(ctx["now"]) <= int(sol["max_ticks"]))
	var result: Dictionary = m.results()
	assert_eq(result["required_restored"], 6)
	assert_eq(result["required_total"], 6)
	assert_eq(result["optional_services"], ["COLD_STORE"])
	assert_eq(result["optional_total"], 1)
	assert_eq(result["preventable_trips"], 0)
	assert_eq(result["stars"], 3)
	var st: Dictionary = (ctx["grid"] as Grid).canonical_state()
	assert_eq(st["nodes"]["GRID"]["load"], 25)
	assert_eq(st["edges"]["E_GRID_WEST"]["flow"], 13)
	assert_eq(st["edges"]["E_GRID_EAST"]["flow"], 12)
	assert_true(m.is_latched("LATCH_WEST_DRAIN"))
	assert_true(m.is_latched("LATCH_EAST_DRAIN"))


func test_CT_BP_C05_each_pump_requires_exactly_120_continuous_ticks() -> void:
	var ctx: Dictionary = _context()
	_place(ctx)
	_start_pump(ctx, "E_TEMP_PUMP_WEST")
	Runner.ticks(ctx, 119)
	assert_eq(Runner.send(ctx, "P1", "request_lock", "R_WEST_TRUNK", {}).get("code"), "NO_ACCESS")
	Runner.ticks(ctx, 1)
	assert_true(Runner.send(ctx, "P1", "request_lock", "R_WEST_TRUNK", {}).get("ok", false))
	assert_eq(Runner.send(ctx, "P1", "request_lock", "R_EAST_TRUNK", {}).get("code"), "NO_ACCESS")
	_stop_pump(ctx, "E_TEMP_PUMP_WEST")
	_start_pump(ctx, "E_TEMP_PUMP_EAST")
	Runner.ticks(ctx, 119)
	assert_eq(Runner.send(ctx, "P1", "request_lock", "R_EAST_TRUNK", {}).get("code"), "NO_ACCESS")
	Runner.ticks(ctx, 1)
	assert_true(Runner.send(ctx, "P1", "request_lock", "R_EAST_TRUNK", {}).get("ok", false))


func test_CT_BP_C05_both_pumps_overload_9_on_8_after_15_ticks() -> void:
	var ctx: Dictionary = _context()
	_place(ctx)
	assert_true(_action(ctx, "connect", {"route": "E_TEMP_PUMP_WEST"}).get("ok", false))
	assert_true(_action(ctx, "connect", {"route": "E_TEMP_PUMP_EAST"}).get("ok", false))
	assert_true(_action(ctx, "start").get("ok", false))
	var st: Dictionary = (ctx["grid"] as Grid).canonical_state()
	assert_eq(st["nodes"]["GEN"]["load"], 9)
	Runner.ticks(ctx, 14)
	assert_false((ctx["grid"] as Grid).canonical_state()["nodes"]["TEMP"]["tripped"])
	Runner.ticks(ctx, 1)
	assert_true((ctx["grid"] as Grid).canonical_state()["nodes"]["TEMP"]["tripped"])
	assert_false((ctx["mission"] as Mission).is_latched("LATCH_WEST_DRAIN"))
	assert_false((ctx["mission"] as Mission).is_latched("LATCH_EAST_DRAIN"))
	assert_true(_action(ctx, "disconnect", {"route": "E_TEMP_PUMP_EAST"}).get("ok", false))
	assert_true(_action(ctx, "reset_breaker").get("ok", false))
	Runner.ticks(ctx, 120)
	assert_true((ctx["mission"] as Mission).is_latched("LATCH_WEST_DRAIN"))


func test_CT_BP_C05_same_tick_supply_drop_resets_unfinished_latch() -> void:
	var ctx: Dictionary = _context()
	_place(ctx)
	_start_pump(ctx, "E_TEMP_PUMP_WEST")
	Runner.ticks(ctx, 60)
	assert_true(_action(ctx, "stop").get("ok", false))
	assert_true(_action(ctx, "start").get("ok", false))
	Runner.ticks(ctx, 119)
	assert_false((ctx["mission"] as Mission).is_latched("LATCH_WEST_DRAIN"))
	Runner.ticks(ctx, 1)
	assert_true((ctx["mission"] as Mission).is_latched("LATCH_WEST_DRAIN"))
	_stop_pump(ctx, "E_TEMP_PUMP_WEST")
	assert_true((ctx["mission"] as Mission).is_latched("LATCH_WEST_DRAIN"))


func test_CT_BP_C05_reversed_pump_order_solves_same_contract() -> void:
	var sol: Dictionary = _trace()
	var steps: Array = sol["steps"]
	var west: int = -1
	var east: int = -1
	var stow: int = -1
	var repair: int = -1
	for i: int in steps.size():
		var item: Dictionary = steps[i]
		if item.get("note", "") == "West pump":
			west = i
		elif item.get("note", "") == "East pump":
			east = i
		elif east >= 0 and stow < 0 and item.get("intent", "") == "place_item" and (item.get("payload", {}) as Dictionary).get("action", "") == "pickup":
			stow = i
		elif item.get("note", "") == "Repair sequence":
			repair = i
	assert_true(west >= 0 and east > west and stow > east and repair > stow)
	if west < 0 or east < 0 or stow < 0 or repair < 0:
		return
	var reversed: Array = []
	reversed.append_array(steps.slice(0, west))
	reversed.append_array(steps.slice(east, stow))
	reversed.append_array(steps.slice(west, east))
	reversed.append_array(steps.slice(stow, steps.size()))
	var ctx: Dictionary = _context()
	assert_eq(Runner.run(ctx, reversed, 1), [] as Array[String])
	assert_true((ctx["mission"] as Mission).is_complete())
	assert_eq((ctx["mission"] as Mission).results()["stars"], 3)


func test_CT_BP_C05_clock_starts_only_on_successful_first_pickup() -> void:
	var ctx: Dictionary = _context()
	Runner.ticks(ctx, 500)
	var m: Mission = ctx["mission"] as Mission
	assert_false(m.canonical_state()["pickup_deadline"]["started"])
	assert_eq(m.canonical_state()["pickup_deadline"]["elapsed"], 0)
	assert_false(Runner.send(ctx, "P1", "place_item", "BAD_EQUIPMENT", {"action": "pickup"}).get("ok", false))
	assert_false(m.canonical_state()["pickup_deadline"]["started"])
	assert_true(_action(ctx, "pickup").get("ok", false))
	assert_true(m.canonical_state()["pickup_deadline"]["started"])
	assert_eq(m.canonical_state()["pickup_deadline"]["elapsed"], 0)
	assert_false(_action(ctx, "pickup").get("ok", false))
	Runner.ticks(ctx, 17)
	assert_eq(m.canonical_state()["pickup_deadline"]["elapsed"], 17)


func test_CT_BP_C05_missed_optional_deadline_never_blocks_main_completion() -> void:
	var ctx: Dictionary = _context()
	assert_true(_action(ctx, "pickup").get("ok", false))
	Runner.ticks(ctx, 1801)
	var m: Mission = ctx["mission"] as Mission
	assert_true(m.canonical_state()["pickup_deadline"]["missed"])
	assert_false(m.canonical_state()["pickup_deadline"]["on_time"])
	var steps: Array = []
	var skipped_pickup: bool = false
	for item: Dictionary in _trace()["steps"]:
		if not skipped_pickup and item.get("entity", "") == "GEN_PORTABLE" and (item.get("payload", {}) as Dictionary).get("action", "") == "pickup":
			skipped_pickup = true
			continue
		steps.append(item)
	assert_true(skipped_pickup)
	assert_eq(Runner.run(ctx, steps, 1), [] as Array[String])
	assert_true(m.is_complete())
	assert_eq(m.results()["required_restored"], 6)
	assert_eq(m.results()["optional_services"], [] as Array[String])
	assert_eq(m.results()["stars"], 2)


func test_CT_BP_C05_durable_clock_and_two_latches_reject_forgery() -> void:
	var ctx: Dictionary = _context()
	_place(ctx)
	_start_pump(ctx, "E_TEMP_PUMP_WEST")
	Runner.ticks(ctx, 37)
	var original: Dictionary = (ctx["mission"] as Mission).durable_state()
	assert_eq(original["pickup_deadline"]["elapsed"], 37)
	var fresh: Dictionary = _context()
	var m: Mission = fresh["mission"] as Mission
	assert_eq(m.restore_state(original), [] as Array[Dictionary])
	assert_eq(m.durable_state(), original)
	for change: Dictionary in [
		{"elapsed": 1802}, {"elapsed": -1}, {"elapsed": "37"},
		{"on_time": true}, {"missed": true}, {"started": false}
	]:
		var forged: Dictionary = original.duplicate(true)
		(forged["pickup_deadline"] as Dictionary).merge(change, true)
		assert_false(m.restore_state(forged).is_empty(), str(change))
		assert_eq(m.durable_state(), original)
	var absent: Dictionary = original.duplicate(true)
	absent.erase("pickup_deadline")
	assert_false(m.restore_state(absent).is_empty())
	assert_eq(m.durable_state(), original)
	var fake_latch: Dictionary = original.duplicate(true)
	fake_latch["latched"] = {"UNKNOWN": 1}
	assert_false(m.restore_state(fake_latch).is_empty())
	assert_eq(m.durable_state(), original)


func test_CT_BP_C05_malformed_pickup_deadline_content_is_rejected() -> void:
	var sol: Dictionary = _trace()
	for invalid: Variant in [
		{}, {"consumer": "COLD_STORE", "deadline_ticks": 0, "start_trigger": "first_equipment_pickup"},
		{"consumer": "PUMP_WEST", "deadline_ticks": 1800, "start_trigger": "first_equipment_pickup"},
		{"consumer": "COLD_STORE", "deadline_ticks": 1800, "start_trigger": "client_button"},
		{"consumer": "NOT_A_NODE", "deadline_ticks": 1800, "start_trigger": "first_equipment_pickup"}
	]:
		var ctx: Dictionary = Runner.build(C05, sol["players"], sol["tools"], {"optional_pickup_deadline": invalid})
		assert_false((ctx["errors"] as Array).is_empty(), str(invalid))


func test_CT_BP_C05_prior_and_later_contract_checkpoint_shapes_unchanged() -> void:
	for path: String in PRIOR:
		var sol: Dictionary = Runner.json(path.path_join("solution.json"))
		var ctx: Dictionary = Runner.build(path, sol["players"], sol["tools"])
		assert_eq(ctx["errors"], [] as Array[Dictionary], path)
		var m: Mission = ctx["mission"] as Mission
		var saved: Dictionary = m.durable_state()
		assert_false(saved.has("pickup_deadline"), path)
		assert_false(m.canonical_state().has("pickup_deadline"), path)
		assert_eq(m.restore_state(saved), [] as Array[Dictionary], path)
		assert_eq(m.durable_state(), saved, path)
