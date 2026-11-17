extends "res://tests/test_case.gd"
## CT-L2/C06: original Canal Yard cold-store grace-window content candidate.
## Deadline is a bonus, never a mission-failure condition. Tests use host intents.
const Runner := preload("res://tests/support/solution_runner.gd")
const Grid := preload("res://scripts/simulation/power_grid.gd")
const Mission := preload("res://scripts/simulation/mission_director.gd")

const C06: String = "res://content/contracts/c06_cold_chain"
const EARLIER: Array[String] = [
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


func _parts() -> Dictionary:
	var prefix: Array = []
	var suffix: Array = []
	var found: bool = false
	for step: Dictionary in _trace()["steps"]:
		if step.get("entity", "") == "SW_COLD_STORE" and step.get("intent", "") == "toggle_switch":
			found = true
			continue
		if not found:
			prefix.append(step)
		else:
			suffix.append(step)
	return {"prefix": prefix, "suffix": suffix, "found": found}


func _run_until_optional(ctx: Dictionary) -> Array:
	var split: Dictionary = _parts()
	assert_true(bool(split["found"]))
	assert_eq(Runner.run(ctx, split["prefix"], 1), [] as Array[String])
	return split["suffix"]


func _place_generator(ctx: Dictionary) -> void:
	assert_true(Runner.send(ctx, "P1", "place_item", "GEN_PORTABLE", {"action": "pickup"}).get("ok", false))
	assert_true(Runner.send(ctx, "P1", "place_item", "GEN_PORTABLE",
		{"action": "place", "anchor": "PAD_CANAL_PUMPS"}).get("ok", false))


func test_CTL2_C06_content_loads_and_cold_store_starts_optional_dark() -> void:
	var ctx: Dictionary = _context()
	assert_eq(ctx["errors"], [] as Array[Dictionary], str(ctx["errors"]))
	var grid: Dictionary = (ctx["grid"] as Grid).canonical_state()
	assert_false(grid["nodes"]["COLD_STORE"]["enabled"])
	assert_true(grid["nodes"]["DOCK"]["failed"])
	assert_false(grid["edges"]["E_GRID_COLD"]["healthy"])
	assert_eq(grid["nodes"]["GEN"]["capacity"], 6)
	assert_eq(grid["edges"]["E_GRID_COLD"]["capacity"], 12)
	var mission: Dictionary = Runner.json(C06.path_join("mission.json"))
	assert_eq(mission["optional_services"], ["COLD_STORE"])
	assert_eq(mission["required_consumers"].size(), 4)
	assert_eq(int(mission["optional_deadline_ticks"]), 280)
	assert_eq(mission["access_latches"].size(), 2)
	assert_eq(Runner.json(C06.path_join("repairs.json"))["repairs"].size(), 2)


func test_CTL2_C06_host_solution_earns_on_time_optional_reward() -> void:
	var ctx: Dictionary = _context()
	var trace: Dictionary = _trace()
	assert_eq(Runner.run(ctx, trace["steps"], int(trace["pace_ticks_per_command"])),
		[] as Array[String])
	var mission: Mission = ctx["mission"] as Mission
	assert_true(mission.is_complete())
	assert_true(int(ctx["now"]) <= int(trace["max_ticks"]))
	var result: Dictionary = mission.results()
	assert_eq(result["required_restored"], 4)
	assert_eq(result["required_total"], 4)
	assert_eq(result["optional_services"], ["COLD_STORE"])
	assert_eq(result["optional_total"], 1)
	assert_eq(result["preventable_trips"], 0)
	assert_eq(result["stars"], 3)
	var when: int = int(mission.canonical_state()["optional_first_supplied"]["COLD_STORE"])
	assert_true(when >= 1 and when <= 280, "on-GRID optional first supply must meet deadline")
	var grid: Dictionary = (ctx["grid"] as Grid).canonical_state()
	assert_eq(grid["nodes"]["GRID"]["load"], 19)
	assert_eq(grid["edges"]["E_GRID_DOCK"]["flow"], 8)
	assert_eq(grid["edges"]["E_GRID_COLD"]["flow"], 11)


func test_CTL2_C06_optional_may_remain_dark_and_core_extraction_still_completes() -> void:
	var ctx: Dictionary = _context()
	var all_steps: Array = []
	for step: Dictionary in _trace()["steps"]:
		if step.get("entity", "") == "SW_COLD_STORE":
			continue
		all_steps.append(step)
	assert_eq(Runner.run(ctx, all_steps, 1), [] as Array[String])
	var mission: Mission = ctx["mission"] as Mission
	assert_true(mission.is_complete())
	assert_eq(mission.results()["required_restored"], 4)
	assert_eq(mission.results()["optional_services"], [] as Array[String])
	assert_eq(mission.results()["stars"], 2)
	assert_eq((ctx["grid"] as Grid).canonical_state()["nodes"]["GRID"]["load"], 14)


func test_CTL2_C06_exact_grace_window_last_tick_awards_bonus() -> void:
	var ctx: Dictionary = _context()
	var suffix: Array = _run_until_optional(ctx)
	var deadline: int = int(Runner.json(C06.path_join("mission.json"))["optional_deadline_ticks"])
	assert_true(int(ctx["now"]) < deadline)
	Runner.ticks(ctx, deadline - 1 - int(ctx["now"]))
	assert_true(Runner.send(ctx, "P1", "toggle_switch", "SW_COLD_STORE", {"value": true}).get("ok", false))
	Runner.ticks(ctx, 1)
	var mission: Mission = ctx["mission"] as Mission
	assert_eq(int(mission.canonical_state()["optional_first_supplied"]["COLD_STORE"]), deadline)
	assert_eq(Runner.run(ctx, suffix, 1), [] as Array[String])
	assert_true(mission.is_complete())
	assert_eq(mission.results()["stars"], 3)


func test_CTL2_C06_one_tick_after_grace_window_loses_bonus_not_completion() -> void:
	var ctx: Dictionary = _context()
	var suffix: Array = _run_until_optional(ctx)
	var deadline: int = int(Runner.json(C06.path_join("mission.json"))["optional_deadline_ticks"])
	assert_true(int(ctx["now"]) <= deadline)
	Runner.ticks(ctx, deadline - int(ctx["now"]))
	assert_true(Runner.send(ctx, "P1", "toggle_switch", "SW_COLD_STORE", {"value": true}).get("ok", false))
	Runner.ticks(ctx, 1)
	var mission: Mission = ctx["mission"] as Mission
	assert_false(mission.canonical_state()["optional_first_supplied"].has("COLD_STORE"))
	assert_true((ctx["grid"] as Grid).canonical_state()["nodes"]["COLD_STORE"]["supplied"])
	assert_eq(Runner.run(ctx, suffix, 1), [] as Array[String])
	assert_true(mission.is_complete())
	assert_eq(mission.results()["required_restored"], 4)
	assert_eq(mission.results()["optional_services"], [] as Array[String])
	assert_eq(mission.results()["stars"], 2)


func test_CTL2_C06_pump_overload_is_recoverable_but_not_a_shortcut() -> void:
	var ctx: Dictionary = _context()
	_place_generator(ctx)
	assert_true(Runner.send(ctx, "P1", "place_item", "GEN_PORTABLE",
		{"action": "connect", "route": "E_TEMP_PUMP_DOCK"}).get("ok", false))
	assert_true(Runner.send(ctx, "P1", "place_item", "GEN_PORTABLE",
		{"action": "connect", "route": "E_TEMP_PUMP_COLD"}).get("ok", false))
	assert_true(Runner.send(ctx, "P1", "place_item", "GEN_PORTABLE",
		{"action": "start"}).get("ok", false))
	Runner.ticks(ctx, 14)
	assert_false((ctx["grid"] as Grid).canonical_state()["nodes"]["TEMP"]["tripped"])
	Runner.ticks(ctx, 1)
	assert_true((ctx["grid"] as Grid).canonical_state()["nodes"]["TEMP"]["tripped"])
	assert_true((ctx["mission"] as Mission).canonical_state()["latched"].is_empty())
	assert_true(Runner.send(ctx, "P1", "place_item", "GEN_PORTABLE",
		{"action": "disconnect", "route": "E_TEMP_PUMP_COLD"}).get("ok", false))
	assert_true(Runner.send(ctx, "P1", "place_item", "GEN_PORTABLE",
		{"action": "reset_breaker"}).get("ok", false))
	Runner.ticks(ctx, 80)
	assert_true((ctx["mission"] as Mission).canonical_state()["latched"].has("LATCH_DOCK_DRAIN"))
	assert_false((ctx["mission"] as Mission).canonical_state()["latched"].has("LATCH_COLD_DRAIN"))


func test_CTL2_C06_cold_room_access_does_not_bypass_independent_drain() -> void:
	var ctx: Dictionary = _context()
	assert_eq(Runner.send(ctx, "P1", "request_lock", "R_DOCK_FUSE", {}).get("code"), "NO_ACCESS")
	assert_eq(Runner.send(ctx, "P1", "request_lock", "R_COLD_FEED", {}).get("code"), "NO_ACCESS")
	_place_generator(ctx)
	assert_true(Runner.send(ctx, "P1", "place_item", "GEN_PORTABLE",
		{"action": "connect", "route": "E_TEMP_PUMP_COLD"}).get("ok", false))
	assert_true(Runner.send(ctx, "P1", "place_item", "GEN_PORTABLE", {"action": "start"}).get("ok", false))
	Runner.ticks(ctx, 99)
	assert_eq(Runner.send(ctx, "P1", "request_lock", "R_COLD_FEED", {}).get("code"), "NO_ACCESS")
	Runner.ticks(ctx, 1)
	assert_true(Runner.send(ctx, "P1", "request_lock", "R_COLD_FEED", {}).get("ok", false))
	assert_eq(Runner.send(ctx, "P1", "request_lock", "R_DOCK_FUSE", {}).get("code"), "NO_ACCESS")


func test_CTL2_C06_optional_first_supply_receipt_survives_valid_restore_only() -> void:
	var ctx: Dictionary = _context()
	var split: Dictionary = _parts()
	var prefix: Array = (split["prefix"] as Array).duplicate(true)
	prefix.append({"as": "P1", "intent": "toggle_switch", "entity": "SW_COLD_STORE",
		"payload": {"value": true}, "expect": "ok"})
	assert_eq(Runner.run(ctx, prefix, 1), [] as Array[String])
	var original: Dictionary = (ctx["mission"] as Mission).durable_state()
	assert_true(original["optional_first_supplied"].has("COLD_STORE"))
	assert_eq((original["latched"] as Dictionary).size(), 2)
	var fresh: Dictionary = _context()
	var mission: Mission = fresh["mission"] as Mission
	assert_eq(mission.restore_state(original), [] as Array[Dictionary])
	assert_eq(mission.durable_state(), original)
	var invalid: Dictionary = original.duplicate(true)
	invalid["optional_first_supplied"] = {"COLD_STORE": 281}
	assert_false(mission.restore_state(invalid).is_empty())
	assert_eq(mission.durable_state(), original)
	invalid["optional_first_supplied"] = {"UNKNOWN_SERVICE": 1}
	assert_false(mission.restore_state(invalid).is_empty())
	assert_eq(mission.durable_state(), original)


func test_CTL2_C06_invalid_deadlines_fail_closed_at_content_load() -> void:
	var trace: Dictionary = _trace()
	for bad: Variant in [0, -1, true, "rush", 1.5]:
		var ctx: Dictionary = Runner.build(C06, trace["players"], trace["tools"],
			{"optional_deadline_ticks": bad})
		assert_false((ctx["errors"] as Array).is_empty(), "bad deadline: " + str(bad))
	var none: Dictionary = Runner.build(C06, trace["players"], trace["tools"],
		{"optional_services": [] as Array[String]})
	assert_false((none["errors"] as Array).is_empty())


func test_CTL2_C06_legacy_contract_save_shape_unchanged() -> void:
	for path: String in EARLIER:
		var trace: Dictionary = Runner.json(path.path_join("solution.json"))
		var ctx: Dictionary = Runner.build(path, trace["players"], trace["tools"])
		assert_eq(ctx["errors"], [] as Array[Dictionary], path)
		var mission: Mission = ctx["mission"] as Mission
		var old: Dictionary = mission.durable_state()
		assert_eq(mission.restore_state(old), [] as Array[Dictionary], path)
		assert_eq(mission.durable_state(), old, path)
