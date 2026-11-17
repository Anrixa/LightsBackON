extends "res://tests/test_case.gd"
## CT-BP/C03: original blueprint source correction through host commands.
## No physical ladder, controller, installed cable geometry or Steam qualification implied.
const Runner := preload("res://tests/support/solution_runner.gd")
const Grid := preload("res://scripts/simulation/power_grid.gd")
const Mission := preload("res://scripts/simulation/mission_director.gd")
const Host := preload("res://scripts/network/session_host.gd")
const C03: String = "res://content/contracts/c03_roof_route"
const EARLIER: Array[String] = [
	"res://content/contracts/c01_alder_street",
	"res://content/contracts/c02_dinner_rush"
]


func _trace() -> Dictionary:
	return Runner.json(C03.path_join("solution.json"))


func _context() -> Dictionary:
	var trace: Dictionary = _trace()
	return Runner.build(C03, trace["players"], trace["tools"])


## Replays only the approved fuse repair, not a direct grid mutation.
func _repair_west(ctx: Dictionary) -> void:
	var prefix: Array = []
	var reached: bool = false
	for step: Dictionary in _trace()["steps"]:
		prefix.append(step)
		if step.get("entity", "") == "R_JW_FUSE" and step.get("payload", {}).get("step", "") == "restore":
			reached = true
			break
	assert_true(reached)
	assert_eq(Runner.run(ctx, prefix, 1), [] as Array[String])


func _ready_ladder(ctx: Dictionary) -> void:
	_repair_west(ctx)
	var mission: Mission = ctx["mission"] as Mission
	var left: int = 50 - int(mission.canonical_state()["latch_ticks"]["LATCH_LADDER_LIGHT"])
	if left > 0:
		Runner.ticks(ctx, left)
	assert_true(mission.is_latched("LATCH_LADDER_LIGHT"))


func test_CTBP_C03_content_matches_supply_and_access_blueprint() -> void:
	var ctx: Dictionary = _context()
	assert_eq(ctx["errors"], [] as Array[Dictionary], str(ctx["errors"]))
	var st: Dictionary = (ctx["grid"] as Grid).canonical_state()
	assert_true(st["nodes"]["JW"]["failed"])
	assert_true(st["nodes"]["JW"]["tripped"])
	assert_false(st["nodes"]["LADDER_LIGHT"]["supplied"])
	assert_false(st["edges"]["E_GRID_JE"]["healthy"])
	assert_false(st["edges"]["E_GRID_ROOF"]["enabled"])
	assert_eq(st["edges"]["E_GRID_ROOF"]["capacity"], 12)
	assert_eq(st["nodes"]["LADDER_LIGHT"]["demand"], 1)
	assert_eq(st["nodes"]["ROOF_BEACON"]["demand"], 2)
	assert_eq(st["nodes"]["GEN"]["capacity"], 6)
	assert_eq(st["edges"]["E_TEMP_ROOF_LIGHT"]["capacity"], 2)
	var definition: Dictionary = Runner.json(C03.path_join("mission.json"))
	assert_eq(definition["access_latches"].size(), 2)
	assert_eq(int(definition["access_latches"][0]["supplied_ticks"]), 50)
	assert_eq(int(definition["access_latches"][1]["supplied_ticks"]), 100)
	assert_eq(definition["optional_latch_rewards"], ["LATCH_ROOF_WORK_LIGHT"])
	assert_eq(definition["fixed_ladders"][0]["requires_latch"], "LATCH_LADDER_LIGHT")
	assert_eq(Runner.json(C03.path_join("repairs.json"))["repairs"].size(), 2)


func test_CTBP_C03_ladder_refused_until_exact_fifty_consecutive_west_ticks() -> void:
	var ctx: Dictionary = _context()
	var host: Host = ctx["host"] as Host
	var before: String = host.state_hash()
	assert_eq(Runner.send(ctx, "P1", "use_ladder", "LADDER_WEST", {}).get("code"), "ACCESS_NOT_READY")
	assert_eq(Runner.send(ctx, "P1", "request_lock", "R_ROOF_SPLICE", {}).get("code"), "NO_ACCESS")
	assert_eq(host.state_hash(), before)
	_repair_west(ctx)
	var mission: Mission = ctx["mission"] as Mission
	var left: int = 50 - int(mission.canonical_state()["latch_ticks"]["LATCH_LADDER_LIGHT"])
	assert_true(left > 0)
	Runner.ticks(ctx, left - 1)
	assert_false(mission.is_latched("LATCH_LADDER_LIGHT"))
	assert_eq(Runner.send(ctx, "P1", "use_ladder", "LADDER_WEST", {}).get("code"), "ACCESS_NOT_READY")
	Runner.ticks(ctx, 1)
	assert_true(mission.is_latched("LATCH_LADDER_LIGHT"))
	assert_true(Runner.send(ctx, "P1", "use_ladder", "LADDER_WEST", {}).get("ok", false))
	assert_true(Runner.send(ctx, "P1", "use_ladder", "LADDER_WEST", {}).get("duplicate", false))
	assert_true(Runner.send(ctx, "P1", "request_lock", "R_ROOF_SPLICE", {}).get("ok", false))


func test_CTBP_C03_same_tick_light_loss_resets_unsatisfied_access_latch() -> void:
	var ctx: Dictionary = _context()
	_repair_west(ctx)
	Runner.ticks(ctx, 20)
	var mission: Mission = ctx["mission"] as Mission
	assert_true(int(mission.canonical_state()["latch_ticks"]["LATCH_LADDER_LIGHT"]) >= 20)
	assert_true(Runner.send(ctx, "P1", "toggle_switch", "SW_ACCESS_LIGHT", {"value": false}).get("ok", false))
	assert_eq(mission.canonical_state()["latch_ticks"]["LATCH_LADDER_LIGHT"], 0)
	assert_true(Runner.send(ctx, "P1", "toggle_switch", "SW_ACCESS_LIGHT", {"value": true}).get("ok", false))
	Runner.ticks(ctx, 49)
	assert_false(mission.is_latched("LATCH_LADDER_LIGHT"))
	Runner.ticks(ctx, 1)
	assert_true(mission.is_latched("LATCH_LADDER_LIGHT"))


func test_CTBP_C03_known_solution_replay_and_source_qualified_roof_work_light() -> void:
	var ctx: Dictionary = _context()
	var trace: Dictionary = _trace()
	var failures: Array[String] = Runner.run(ctx, trace["steps"], int(trace["pace_ticks_per_command"]))
	assert_eq(failures, [] as Array[String], str(failures))
	var mission: Mission = ctx["mission"] as Mission
	assert_true(mission.is_complete())
	assert_true(int(ctx["now"]) <= int(trace["max_ticks"]))
	assert_true(mission.is_latched("LATCH_LADDER_LIGHT"))
	assert_true(mission.is_latched("LATCH_ROOF_WORK_LIGHT"))
	var result: Dictionary = mission.results()
	assert_eq(result["required_restored"], 5)
	assert_eq(result["optional_services"], ["ROOF_BEACON"])
	assert_eq(result["optional_total"], 1)
	assert_eq(result["preventable_trips"], 0)
	assert_eq(result["stars"], 3)
	var grid: Dictionary = (ctx["grid"] as Grid).canonical_state()
	assert_eq(grid["nodes"]["GRID"]["load"], 21)
	assert_eq(grid["edges"]["E_GRID_JW"]["flow"], 10)
	assert_eq(grid["edges"]["E_GRID_ROOF"]["flow"], 11)
	assert_false(grid["nodes"]["GEN"]["online"])
	assert_false(grid["edges"]["E_GRID_JE"]["healthy"])


func test_CTBP_C03_optional_work_light_omission_never_blocks_completion() -> void:
	var ctx: Dictionary = _context()
	var without_bonus: Array = []
	for step: Dictionary in _trace()["steps"]:
		if step.get("entity", "") == "GEN_PORTABLE" or step.get("entity", "") == "SW_BEACON":
			continue
		if step.get("ticks", -1) == 100:
			without_bonus.append({"ticks": 100, "expect_events": ["verified"]})
		else:
			without_bonus.append(step)
	assert_eq(Runner.run(ctx, without_bonus, 1), [] as Array[String])
	var mission: Mission = ctx["mission"] as Mission
	assert_true(mission.is_complete())
	assert_false(mission.is_latched("LATCH_ROOF_WORK_LIGHT"))
	assert_eq(mission.results()["optional_services"], [] as Array[String])
	assert_eq(mission.results()["stars"], 2)


func test_CTBP_C03_crossfeed_overloads_protected_west_and_reset_is_recoverable() -> void:
	var ctx: Dictionary = _context()
	_repair_west(ctx)
	assert_true(Runner.send(ctx, "P1", "toggle_switch", "SW_CROSSFEED", {"value": false}).get("ok", false))
	Runner.ticks(ctx, 16)
	assert_true((ctx["grid"] as Grid).canonical_state()["nodes"]["JW"]["tripped"])
	assert_false((ctx["mission"] as Mission).verified())
	assert_true(Runner.send(ctx, "P1", "toggle_switch", "SW_CROSSFEED", {"value": true}).get("ok", false))
	assert_true(Runner.send(ctx, "P1", "toggle_switch", "SW_JW_BREAKER", {"value": false}).get("ok", false))
	assert_false((ctx["grid"] as Grid).canonical_state()["nodes"]["JW"]["tripped"])


func test_CTBP_C03_latch_and_ladder_receipts_save_restore_and_forgery_refused() -> void:
	var ctx: Dictionary = _context()
	_ready_ladder(ctx)
	assert_true(Runner.send(ctx, "P1", "use_ladder", "LADDER_WEST", {}).get("ok", false))
	var saved: Dictionary = (ctx["mission"] as Mission).durable_state()
	var restored: Dictionary = _context()
	var mission: Mission = restored["mission"] as Mission
	assert_eq(mission.restore_state(saved), [] as Array[Dictionary])
	assert_true(mission.is_latched("LATCH_LADDER_LIGHT"))
	assert_true(Runner.send(restored, "P1", "request_lock", "R_ROOF_SPLICE", {}).get("ok", false))
	var snapshot: Dictionary = mission.durable_state()
	for forged: Dictionary in [
		{"latch_ticks": {"LATCH_LADDER_LIGHT": 50, "LATCH_ROOF_WORK_LIGHT": 0}, "latched": {}},
		{"latch_ticks": {"LATCH_LADDER_LIGHT": 999, "LATCH_ROOF_WORK_LIGHT": 0}},
		{"latched": {"LATCH_LADDER_LIGHT": -1}},
		{"ladder_access": {"FORGED_LADDER": 1}}
	]:
		var tampered: Dictionary = saved.duplicate(true)
		tampered.merge(forged, true)
		assert_false(mission.restore_state(tampered).is_empty())
		assert_eq(mission.durable_state(), snapshot)


func test_CTBP_C03_malformed_ladder_and_reward_definitions_fail_closed() -> void:
	var trace: Dictionary = _trace()
	for modification: Dictionary in [
		{"fixed_ladders": [{"id":"LADDER_WEST","grants":"ROOF_REACHED","requires_latch":"INVENTED"}]},
		{"optional_latch_rewards": ["UNKNOWN_LATCH"]},
		{"optional_latch_rewards": ["LATCH_ROOF_WORK_LIGHT", "LATCH_ROOF_WORK_LIGHT"]},
		{"access_latches": [{"id":"BAD","consumer":"LADDER_LIGHT","supplied_ticks":50,"grants":"ACCESS","source":"NO_SOURCE"}]}
	]:
		var bad: Dictionary = Runner.build(C03, trace["players"], trace["tools"], modification)
		assert_false((bad["errors"] as Array).is_empty(), str(modification))


func test_CTBP_C03_original_C01_C02_mission_saves_keep_their_field_shapes() -> void:
	for previous: String in EARLIER:
		var trace: Dictionary = Runner.json(previous.path_join("solution.json"))
		var ctx: Dictionary = Runner.build(previous, trace["players"], trace["tools"])
		assert_eq(ctx["errors"], [] as Array[Dictionary])
		var mission: Mission = ctx["mission"] as Mission
		assert_false(mission.canonical_state().has("optional_latch_rewards"))
		assert_false(mission.durable_state().has("optional_latch_rewards"))
		assert_false(mission.durable_state().has("ladder_requires"))
		assert_eq(mission.restore_state(mission.durable_state()), [] as Array[Dictionary])

func test_CTBP_C03_generator_work_light_requires_exact_hundred_uninterrupted_ticks() -> void:
	var ctx: Dictionary = _context()
	_ready_ladder(ctx)
	var mission: Mission = ctx["mission"] as Mission
	assert_true(Runner.send(ctx, "P1", "place_item", "GEN_PORTABLE", {"action": "pickup"}).get("ok", false))
	assert_true(Runner.send(ctx, "P1", "place_item", "GEN_PORTABLE",
		{"action": "place", "anchor": "PAD_PUMP"}).get("ok", false))
	assert_true(Runner.send(ctx, "P1", "place_item", "GEN_PORTABLE",
		{"action": "connect", "route": "E_TEMP_ROOF_LIGHT"}).get("ok", false))
	assert_true(Runner.send(ctx, "P1", "place_item", "GEN_PORTABLE", {"action": "start"}).get("ok", false))
	assert_true(Runner.send(ctx, "P1", "toggle_switch", "SW_BEACON", {"value": true}).get("ok", false))
	Runner.ticks(ctx, 99)
	assert_false(mission.is_latched("LATCH_ROOF_WORK_LIGHT"))
	assert_eq(int(mission.canonical_state()["latch_ticks"]["LATCH_ROOF_WORK_LIGHT"]), 99)
	assert_true(Runner.send(ctx, "P1", "toggle_switch", "SW_BEACON", {"value": false}).get("ok", false))
	assert_eq(int(mission.canonical_state()["latch_ticks"]["LATCH_ROOF_WORK_LIGHT"]), 0)
	assert_true(Runner.send(ctx, "P1", "toggle_switch", "SW_BEACON", {"value": true}).get("ok", false))
	Runner.ticks(ctx, 99)
	assert_false(mission.is_latched("LATCH_ROOF_WORK_LIGHT"))
	Runner.ticks(ctx, 1)
	assert_true(mission.is_latched("LATCH_ROOF_WORK_LIGHT"))
	assert_eq(int(mission.canonical_state()["latch_ticks"]["LATCH_ROOF_WORK_LIGHT"]), 100)


func test_CTBP_C03_new_objective_labels_resolve_without_placeholder_keys() -> void:
	var strings: Dictionary = Runner.json("res://content/ui/strings/en.json")["strings"]
	for key: String in ["objective.c03.power_ladder", "objective.c03.roof_work_light", "node.c03.ladder_light"]:
		assert_true(strings.has(key), key)
		assert_false(str(strings.get(key, "")).is_empty())
	var positions: Dictionary = {}
	for item: Dictionary in Runner.json(C03.path_join("tablet.json"))["nodes"]:
		assert_false(positions.has(item["id"]), "duplicate tablet node")
		positions[item["id"]] = true
	assert_true(positions.has("LADDER_LIGHT"))
