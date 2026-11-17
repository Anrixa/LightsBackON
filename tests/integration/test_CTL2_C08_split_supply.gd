extends "res://tests/test_case.gd"
## CT-L2/C08: original blueprint p.20, dual-source safe transfer and diner continuity.
const Runner := preload("res://tests/support/solution_runner.gd")
const Grid := preload("res://scripts/simulation/power_grid.gd")
const Mission := preload("res://scripts/simulation/mission_director.gd")
const C08: String = "res://content/contracts/c08_split_supply"
const EARLIER: Array[String] = [
	"res://content/contracts/c01_alder_street",
	"res://content/contracts/c02_dinner_rush",
	"res://content/contracts/c03_roof_route",
	"res://content/contracts/c04_whole_block",
	"res://content/contracts/c05_canal_pump_access",
	"res://content/contracts/c06_cold_chain",
	"res://content/contracts/c07_wrong_label",
]


func _trace() -> Dictionary:
	return Runner.json(C08.path_join("solution.json"))


func _context() -> Dictionary:
	var t: Dictionary = _trace()
	return Runner.build(C08, t["players"], t["tools"])


func _before_open_tie() -> Array:
	# Replay through the B repair but stop before opening the A tie.
	var prefix: Array = []
	for s: Dictionary in _trace()["steps"]:
		if s.get("entity") == "SW_A_JE_TIE" and (s.get("payload", {}) as Dictionary).get("value") == false:
			break
		prefix.append(s)
	return prefix


func _shed_and_tie(ctx: Dictionary) -> void:
	assert_true(Runner.send(ctx, "P1", "toggle_switch", "SW_LAUNDRETTE", {"value": false}).get("ok", false))
	assert_true(Runner.send(ctx, "P1", "toggle_switch", "SW_ROW_HOUSES", {"value": false}).get("ok", false))
	assert_true(Runner.send(ctx, "P1", "toggle_switch", "SW_A_JE_TIE", {"value": true}).get("ok", false))


func test_CTL2_C08_blueprint_source_and_feeder_baseline() -> void:
	var ctx: Dictionary = _context()
	assert_eq(ctx["errors"], [] as Array[Dictionary], str(ctx["errors"]))
	var st: Dictionary = (ctx["grid"] as Grid).canonical_state()
	assert_eq(st["nodes"]["A"]["capacity"], 18)
	assert_eq(st["nodes"]["B"]["capacity"], 16)
	assert_true(st["nodes"]["A"]["online"])
	assert_false(st["nodes"]["B"]["online"])
	assert_eq(st["edges"]["E_A_JW"]["capacity"], 14)
	assert_eq(st["edges"]["E_B_JE"]["capacity"], 14)
	assert_eq(st["edges"]["E_A_JE_TIE"]["capacity"], 14)
	assert_false(st["edges"]["E_B_JE"]["enabled"])
	assert_false(st["edges"]["E_A_JE_TIE"]["enabled"])
	assert_eq(st["nodes"]["A"]["load"], 13)
	assert_eq(st["nodes"]["B"]["load"], 0)
	for id: String in ["LAUNDRETTE", "DINER", "ROW_HOUSES"]:
		assert_true(st["nodes"][id]["supplied"], id)
	for id: String in ["DEPOT", "COLD_STORE", "PUMP_KIOSK"]:
		assert_false(st["nodes"][id]["supplied"], id)
	var m: Dictionary = Runner.json(C08.path_join("mission.json"))
	assert_eq(m["grid_sources"], ["A", "B"])
	assert_eq(m["required_consumers"].size(), 6)
	assert_eq(m["access_latches"][0]["supplied_ticks"], 100.0)
	assert_eq(m["optional_continuous_supply"]["consumer"], "DINER")


func test_CTL2_C08_full_host_solution_is_three_stars_and_two_sources() -> void:
	var ctx: Dictionary = _context()
	var t: Dictionary = _trace()
	assert_eq(Runner.run(ctx, t["steps"], int(t["pace_ticks_per_command"])), [] as Array[String])
	var mission: Mission = ctx["mission"] as Mission
	assert_true(mission.is_complete())
	assert_true(int(ctx["now"]) <= int(t["max_ticks"]))
	assert_eq(mission.results()["required_restored"], 6)
	assert_eq(mission.results()["optional_services"], ["DINER_UNINTERRUPTED"])
	assert_eq(mission.results()["optional_total"], 1)
	assert_eq(mission.results()["preventable_trips"], 0)
	assert_eq(mission.results()["stars"], 3)
	assert_true(mission.is_latched("LATCH_DEPOT_ACCESS"))
	var st: Dictionary = (ctx["grid"] as Grid).canonical_state()
	assert_eq(st["nodes"]["A"]["load"], 13)
	assert_eq(st["nodes"]["B"]["load"], 12)
	assert_eq(st["edges"]["E_A_JW"]["flow"], 13)
	assert_eq(st["edges"]["E_B_JE"]["flow"], 12)
	assert_false(st["edges"]["E_A_JE_TIE"]["enabled"])
	assert_true(st["edges"]["E_B_JE"]["enabled"])


func test_CTL2_C08_cabinet_locked_until_depot_has_100_continuous_valid_ticks() -> void:
	var ctx: Dictionary = _context()
	assert_eq(Runner.send(ctx, "P1", "request_lock", "R_B_SOURCE", {}).get("code"), "NO_ACCESS")
	_shed_and_tie(ctx)
	var st: Dictionary = (ctx["grid"] as Grid).canonical_state()
	assert_eq(st["nodes"]["A"]["load"], 16)
	assert_false(st["nodes"]["A"]["overloaded"])
	assert_true(st["nodes"]["DEPOT"]["supplied"])
	Runner.ticks(ctx, 99)
	assert_false((ctx["mission"] as Mission).is_latched("LATCH_DEPOT_ACCESS"))
	assert_eq(Runner.send(ctx, "P1", "request_lock", "R_B_SOURCE", {}).get("code"), "NO_ACCESS")
	Runner.ticks(ctx, 1)
	assert_true((ctx["mission"] as Mission).is_latched("LATCH_DEPOT_ACCESS"))
	assert_true(Runner.send(ctx, "P1", "request_lock", "R_B_SOURCE", {}).get("ok", false))


func test_CTL2_C08_access_timer_resets_on_depot_power_loss() -> void:
	var ctx: Dictionary = _context()
	_shed_and_tie(ctx)
	Runner.ticks(ctx, 60)
	assert_true(Runner.send(ctx, "P1", "toggle_switch", "SW_A_JE_TIE", {"value": false}).get("ok", false))
	Runner.ticks(ctx, 1)
	assert_true(Runner.send(ctx, "P1", "toggle_switch", "SW_A_JE_TIE", {"value": true}).get("ok", false))
	Runner.ticks(ctx, 40)
	assert_false((ctx["mission"] as Mission).is_latched("LATCH_DEPOT_ACCESS"))
	Runner.ticks(ctx, 60)
	assert_true((ctx["mission"] as Mission).is_latched("LATCH_DEPOT_ACCESS"))


func test_CTL2_C08_overloaded_A_cannot_fake_depot_cabinet_access() -> void:
	var ctx: Dictionary = _context()
	assert_true(Runner.send(ctx, "P1", "toggle_switch", "SW_A_JE_TIE", {"value": true}).get("ok", false))
	assert_true((ctx["grid"] as Grid).canonical_state()["nodes"]["A"]["overloaded"])
	assert_eq((ctx["grid"] as Grid).canonical_state()["nodes"]["A"]["load"], 25)
	Runner.ticks(ctx, 100)
	assert_false((ctx["mission"] as Mission).is_latched("LATCH_DEPOT_ACCESS"))
	assert_eq(Runner.send(ctx, "P1", "request_lock", "R_B_SOURCE", {}).get("code"), "NO_ACCESS")
	assert_true(Runner.send(ctx, "P1", "toggle_switch", "SW_LAUNDRETTE", {"value": false}).get("ok", false))
	assert_true(Runner.send(ctx, "P1", "toggle_switch", "SW_ROW_HOUSES", {"value": false}).get("ok", false))
	Runner.ticks(ctx, 100)
	assert_true((ctx["mission"] as Mission).is_latched("LATCH_DEPOT_ACCESS"))


func test_CTL2_C08_atomic_wrong_close_refused_even_when_b_is_online() -> void:
	var ctx: Dictionary = _context()
	assert_eq(Runner.run(ctx, _before_open_tie(), 1), [] as Array[String])
	var grid: Grid = ctx["grid"] as Grid
	assert_true(grid.canonical_state()["nodes"]["B"]["online"])
	assert_true(grid.canonical_state()["edges"]["E_A_JE_TIE"]["enabled"])
	assert_false(grid.canonical_state()["edges"]["E_B_JE"]["enabled"])
	var before: String = Grid.serialize(grid.canonical_state())
	var bad: Dictionary = Runner.send(ctx, "P1", "toggle_switch", "SW_B_JE_FEED", {"value": true})
	assert_eq(bad.get("code"), "GRID_REFUSED")
	assert_eq(bad.get("grid_code"), "DUAL_SUPPLY")
	assert_eq(Grid.serialize(grid.canonical_state()), before, "refused tie cannot mutate the grid")
	Runner.ticks(ctx, 1)
	assert_false(grid.canonical_state()["edges"]["E_B_JE"]["enabled"])
	assert_true((ctx["mission"] as Mission).canonical_state()["optional_continuous_supply"]["ok"])


func test_CTL2_C08_break_before_make_has_no_one_tick_dual_supply() -> void:
	var ctx: Dictionary = _context()
	assert_eq(Runner.run(ctx, _before_open_tie(), 1), [] as Array[String])
	var grid: Grid = ctx["grid"] as Grid
	assert_true(Runner.send(ctx, "P1", "toggle_switch", "SW_A_JE_TIE", {"value": false}).get("ok", false))
	Runner.ticks(ctx, 1)
	assert_false(grid.canonical_state()["edges"]["E_A_JE_TIE"]["energized"])
	assert_false(grid.canonical_state()["nodes"]["DEPOT"]["supplied"])
	assert_true(grid.canonical_state()["nodes"]["DINER"]["supplied"])
	assert_true(Runner.send(ctx, "P1", "toggle_switch", "SW_B_JE_FEED", {"value": true}).get("ok", false))
	Runner.ticks(ctx, 1)
	var st: Dictionary = grid.canonical_state()
	assert_true(st["nodes"]["DEPOT"]["supplied"])
	assert_true(st["nodes"]["DINER"]["supplied"])
	assert_eq(st["nodes"]["A"]["load"], 4)
	assert_eq(st["nodes"]["B"]["load"], 12)
	assert_true(grid.validate().is_empty())
	assert_true((ctx["mission"] as Mission).canonical_state()["optional_continuous_supply"]["ok"])


func test_CTL2_C08_diner_momentary_power_loss_fails_only_optional_reward() -> void:
	var ctx: Dictionary = _context()
	assert_true(Runner.send(ctx, "P1", "toggle_switch", "SW_DINER", {"value": false}).get("ok", false))
	assert_true(Runner.send(ctx, "P1", "toggle_switch", "SW_DINER", {"value": true}).get("ok", false))
	assert_false((ctx["mission"] as Mission).canonical_state()["optional_continuous_supply"]["ok"])
	assert_eq(Runner.run(ctx, _trace()["steps"], 1), [] as Array[String])
	assert_true((ctx["mission"] as Mission).is_complete())
	assert_eq((ctx["mission"] as Mission).results()["stars"], 2)
	assert_eq((ctx["mission"] as Mission).results()["required_restored"], 6)
	assert_eq((ctx["mission"] as Mission).results()["optional_services"], [] as Array[String])


func test_CTL2_C08_durable_latch_and_continuity_round_trip_fail_closed() -> void:
	var ctx: Dictionary = _context()
	_shed_and_tie(ctx)
	Runner.ticks(ctx, 100)
	var mission: Mission = ctx["mission"] as Mission
	var saved: Dictionary = mission.durable_state()
	assert_true(saved["optional_continuous_supply"]["ok"])
	assert_true(saved["latched"].has("LATCH_DEPOT_ACCESS"))
	var fresh: Dictionary = _context()
	var dest: Mission = fresh["mission"] as Mission
	assert_eq(dest.restore_state(saved), [] as Array[Dictionary])
	assert_eq(dest.durable_state(), saved)
	var bad: Dictionary = saved.duplicate(true)
	bad["optional_continuous_supply"] = {"ok": "true"}
	assert_false(dest.restore_state(bad).is_empty())
	assert_eq(dest.durable_state(), saved)
	bad["optional_continuous_supply"] = {"ok": true, "invented": false}
	assert_false(dest.restore_state(bad).is_empty())
	assert_eq(dest.durable_state(), saved)
	var losses: Dictionary = _context()
	assert_true(Runner.send(losses, "P1", "toggle_switch", "SW_DINER", {"value": false}).get("ok", false))
	var lost_save: Dictionary = (losses["mission"] as Mission).durable_state()
	assert_false(lost_save["optional_continuous_supply"]["ok"])
	var fresh_loss: Dictionary = _context()
	assert_eq((fresh_loss["mission"] as Mission).restore_state(lost_save), [] as Array[Dictionary])
	assert_false((fresh_loss["mission"] as Mission).durable_state()["optional_continuous_supply"]["ok"])


func test_CTL2_C08_malformed_mission_source_or_bonus_definition_is_rejected() -> void:
	var t: Dictionary = _trace()
	var cases: Array[Dictionary] = [
		{"grid_sources": ["A", "A"]},
		{"grid_sources": ["A", "MISSING"]},
		{"grid_sources": ["B"]},
		{"grid_sources": []},
		{"optional_continuous_supply": {"id": "BAD", "consumer": "NO_SUCH_CONSUMER"}},
		{"optional_continuous_supply": {"id": "", "consumer": "DINER"}},
	]
	for fields: Dictionary in cases:
		var candidate: Dictionary = Runner.build(C08, t["players"], t["tools"], fields)
		assert_false((candidate["errors"] as Array).is_empty(), str(fields))


func test_CTL2_C08_two_player_host_replay_keeps_personal_authority_and_requires_both_extract() -> void:
	var t: Dictionary = _trace()
	var ctx: Dictionary = Runner.build(C08, ["P1", "P2"], t["tools"])
	assert_eq(ctx["errors"], [] as Array[Dictionary])
	var modified: Array = (t["steps"] as Array).duplicate(true)
	for s: Dictionary in modified:
		if s.get("entity") == "SW_LAUNDRETTE":
			s["as"] = "P2"
			break
	var last_zone: Dictionary = {"zone": "ZONE_VAN", "as": "P2", "inside": true}
	for i: int in modified.size():
		if modified[i].get("intent") == "request_extract":
			modified.insert(i, last_zone)
			break
	assert_eq(Runner.run(ctx, modified, 1), [] as Array[String])
	assert_true((ctx["mission"] as Mission).is_complete())
	assert_eq((ctx["mission"] as Mission).results()["stars"], 3)


func test_CTL2_C08_all_earlier_contract_save_shapes_unchanged() -> void:
	for path: String in EARLIER:
		var trace: Dictionary = Runner.json(path.path_join("solution.json"))
		var ctx: Dictionary = Runner.build(path, trace["players"], trace["tools"])
		assert_eq(ctx["errors"], [] as Array[Dictionary], path)
		var mission: Mission = ctx["mission"] as Mission
		var old: Dictionary = mission.durable_state()
		assert_false(old.has("optional_continuous_supply"), path)
		assert_eq(mission.restore_state(old), [] as Array[Dictionary], path)
		assert_eq(mission.durable_state(), old, path)
