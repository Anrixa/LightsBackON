extends "res://tests/test_case.gd"
## CT-L2/C07: original PDF Wrong Label; host-only capacity module and first-reset evidence.
const Runner := preload("res://tests/support/solution_runner.gd")
const Grid := preload("res://scripts/simulation/power_grid.gd")
const Mission := preload("res://scripts/simulation/mission_director.gd")
const C07: String = "res://content/contracts/c07_wrong_label"
const EARLIER: Array[String] = [
	"res://content/contracts/c01_alder_street", "res://content/contracts/c02_dinner_rush",
	"res://content/contracts/c03_roof_route", "res://content/contracts/c04_whole_block",
	"res://content/contracts/c05_canal_pump_access", "res://content/contracts/c06_cold_chain",
]


func _trace() -> Dictionary:
	return Runner.json(C07.path_join("solution.json"))


func _context() -> Dictionary:
	var t: Dictionary = _trace()
	return Runner.build(C07, t["players"], t["tools"])


func _repair_steps() -> Array:
	var seq: Array = []
	var found: bool = false
	for step: Dictionary in _trace()["steps"]:
		if step.get("entity", "") == "R_JE_MODULE":
			found = true
		if found and not step.has("ticks"):
			if step.get("entity", "") == "R_JE_MODULE":
				seq.append(step)
	return seq


func _repair(ctx: Dictionary) -> void:
	assert_eq(Runner.run(ctx, _repair_steps(), 1), [] as Array[String])


func test_CTL2_C07_canal_baseline_and_module_rating_are_blueprint_exact() -> void:
	var ctx: Dictionary = _context()
	assert_eq(ctx["errors"], [] as Array[Dictionary], str(ctx["errors"]))
	var state: Dictionary = (ctx["grid"] as Grid).canonical_state()
	assert_eq(state["nodes"]["GRID"]["capacity"], 30)
	assert_eq(state["nodes"]["GEN"]["capacity"], 8)
	assert_eq(state["edges"]["E_GRID_JW"]["capacity"], 14)
	assert_eq(state["edges"]["E_GRID_JW"]["flow"], 13)
	assert_eq(state["edges"]["E_GRID_JE"]["capacity"], 10)
	assert_true(state["nodes"]["JE"]["tripped"])
	assert_false(state["nodes"]["JE"]["failed"])
	for id: String in ["LAUNDRETTE", "DINER", "ROW_HOUSES"]:
		assert_true(state["nodes"][id]["supplied"], id)
	for id: String in ["DEPOT", "COLD_STORE", "PUMP_KIOSK"]:
		assert_false(state["nodes"][id]["supplied"], id)
	var m: Dictionary = Runner.json(C07.path_join("mission.json"))
	assert_eq(m["required_consumers"].size(), 6)
	assert_eq(m["optional_services"], [] as Array[String])
	assert_eq(int(m["optional_meter_evidence"]["label_capacity"]), 14)
	assert_eq(Runner.json(C07.path_join("repairs.json"))["supplies"]["MODULE_14PU"], 1.0)


func test_CTL2_C07_correct_host_solution_restores_six_with_three_stars() -> void:
	var ctx: Dictionary = _context()
	var t: Dictionary = _trace()
	assert_eq(Runner.run(ctx, t["steps"], int(t["pace_ticks_per_command"])), [] as Array[String])
	var mission: Mission = ctx["mission"] as Mission
	assert_true(mission.is_complete())
	assert_true(int(ctx["now"]) <= int(t["max_ticks"]))
	assert_eq(mission.results()["required_restored"], 6)
	assert_eq(mission.results()["required_total"], 6)
	assert_eq(mission.results()["optional_services"], ["EVIDENCE_MISMATCH"])
	assert_eq(mission.results()["optional_total"], 1)
	assert_eq(mission.results()["preventable_trips"], 0)
	assert_eq(mission.results()["stars"], 3)
	var st: Dictionary = (ctx["grid"] as Grid).canonical_state()
	assert_eq(st["nodes"]["GRID"]["load"], 25)
	assert_eq(st["edges"]["E_GRID_JW"]["flow"], 13)
	assert_eq(st["edges"]["E_GRID_JE"]["flow"], 12)
	assert_eq(st["edges"]["E_GRID_JE"]["capacity"], 14)
	assert_false(st["nodes"]["JE"]["tripped"])
	assert_eq(int(ctx["interaction"].canonical_state()["supplies"]["MODULE_14PU"]), 0)


func test_CTL2_C07_meter_reports_10_capacity_vs_12_demand_not_stale_14_label() -> void:
	var ctx: Dictionary = _context()
	var meter: Variant = ctx["meter"]
	var unknown: Dictionary = meter.readings("PANEL_JE", ctx["grid"])
	assert_false(unknown["capacity_pu"]["known"])
	assert_eq(Runner.json(C07.path_join("meter.json"))["stale_panel_label_pu"]["PANEL_JE"], 14.0)
	assert_true(Runner.send(ctx, "P1", "inspect", "PANEL_GRID", {}).get("ok", false))
	assert_false((ctx["mission"] as Mission).canonical_state()["optional_meter_evidence"]["observed"])
	assert_true(Runner.send(ctx, "P1", "inspect", "PANEL_JE", {}).get("ok", false))
	var r: Dictionary = meter.readings("PANEL_JE", ctx["grid"])
	assert_true(r["capacity_pu"]["known"])
	assert_eq(int(r["capacity_pu"]["value"]), 10)
	assert_eq(int(r["demand_pu"]["value"]), 12)
	assert_true((ctx["mission"] as Mission).canonical_state()["optional_meter_evidence"]["observed"])


func test_CTL2_C07_wrong_reset_refused_but_disqualifies_missed_evidence_only() -> void:
	var ctx: Dictionary = _context()
	var grid: Grid = ctx["grid"] as Grid
	var previous: String = Grid.serialize(grid.canonical_state())
	var reply: Dictionary = Runner.send(ctx, "P1", "toggle_switch", "SW_JE_BREAKER", {"value": false})
	assert_false(reply.get("ok", false))
	assert_eq(reply.get("grid_code"), "RESET_OVERLOADED")
	assert_eq(Grid.serialize(grid.canonical_state()), previous, "wrong reset must not alter grid")
	assert_true((ctx["mission"] as Mission).canonical_state()["optional_meter_evidence"]["reset_attempted"])
	assert_true(Runner.send(ctx, "P1", "inspect", "PANEL_JE", {}).get("ok", false))
	assert_false((ctx["mission"] as Mission).canonical_state()["optional_meter_evidence"]["observed"])
	_repair(ctx)
	Runner.ticks(ctx, 100)
	(ctx["host"]).set_in_zone("P1", "ZONE_VAN", true)
	assert_true(Runner.send(ctx, "P1", "request_extract", "ZONE_VAN", {"action": "start"}).get("ok", false))
	Runner.ticks(ctx, 50)
	assert_true((ctx["mission"] as Mission).is_complete())
	assert_eq((ctx["mission"] as Mission).results()["stars"], 2)
	assert_eq((ctx["mission"] as Mission).results()["required_restored"], 6)


func test_CTL2_C07_repeated_reset_not_solution_and_shedding_restores_only_partial_east() -> void:
	var ctx: Dictionary = _context()
	var grid: Grid = ctx["grid"] as Grid
	for _i: int in 3:
		assert_eq(Runner.send(ctx, "P1", "toggle_switch", "SW_JE_BREAKER", {"value": false}).get("grid_code"), "RESET_OVERLOADED")
	assert_eq(grid.canonical_state()["edges"]["E_GRID_JE"]["capacity"], 10)
	assert_true(Runner.send(ctx, "P1", "toggle_switch", "SW_COLD_STORE", {"value": false}).get("ok", false))
	assert_true(Runner.send(ctx, "P1", "toggle_switch", "SW_JE_BREAKER", {"value": false}).get("ok", false))
	assert_eq(grid.canonical_state()["edges"]["E_GRID_JE"]["flow"], 7)
	assert_true(Runner.send(ctx, "P1", "toggle_switch", "SW_COLD_STORE", {"value": true}).get("ok", false))
	Runner.ticks(ctx, 14)
	assert_false(grid.canonical_state()["nodes"]["JE"]["tripped"])
	Runner.ticks(ctx, 1)
	assert_true(grid.canonical_state()["nodes"]["JE"]["tripped"])
	assert_false((ctx["mission"] as Mission).is_complete())


func test_CTL2_C07_only_isolated_whitelisted_exact_module_may_change_capacity() -> void:
	var ctx: Dictionary = _context()
	var grid: Grid = ctx["grid"] as Grid
	var original: String = Grid.serialize(grid.canonical_state())
	assert_eq(grid.apply({"op":"replace_module","id":"E_GRID_JE","capacity":14})["code"], "MODULE_NOT_ISOLATED")
	assert_eq(grid.apply({"op":"set","id":"E_GRID_JE","field":"capacity","value":14})["code"], "FIELD_NOT_SETTABLE")
	assert_eq(grid.apply({"op":"replace_module","id":"E_GRID_JW","capacity":14})["code"], "MODULE_NOT_AUTHORIZED")
	assert_eq(Grid.serialize(grid.canonical_state()), original)
	assert_true(grid.apply({"op":"set","id":"JE","field":"isolated","value":true})["ok"])
	assert_eq(grid.apply({"op":"replace_module","id":"E_GRID_JE","capacity":13})["code"], "MODULE_RATING_REFUSED")
	assert_eq(grid.canonical_state()["edges"]["E_GRID_JE"]["capacity"], 10)
	assert_true(grid.apply({"op":"replace_module","id":"E_GRID_JE","capacity":14})["ok"])
	assert_eq(grid.apply({"op":"replace_module","id":"E_GRID_JE","capacity":14})["code"], "MODULE_ALREADY_REPLACED")


func test_CTL2_C07_missing_meter_diagnosis_blocks_repair() -> void:
	var ctx: Dictionary = _context()
	assert_true(Runner.send(ctx, "P1", "request_lock", "R_JE_MODULE", {}).get("ok", false))
	assert_eq(Runner.send(ctx, "P1", "repair_step", "R_JE_MODULE", {"step":"diagnose"}).get("code"), "NOT_INSPECTED")
	assert_eq((ctx["grid"] as Grid).canonical_state()["edges"]["E_GRID_JE"]["capacity"], 10)
	assert_eq(int(ctx["interaction"].canonical_state()["supplies"]["MODULE_14PU"]), 1)


func test_CTL2_C07_module_capacity_survives_causes_restore_and_forgery_is_refused() -> void:
	var ctx: Dictionary = _context()
	assert_eq(Runner.run(ctx, _trace()["steps"], 1), [] as Array[String])
	var src: Grid = ctx["grid"] as Grid
	var saved: Dictionary = src.causes()
	var fresh: Dictionary = _context()
	var dest: Grid = fresh["grid"] as Grid
	assert_eq(dest.restore_causes(saved), [] as Array[Dictionary])
	assert_eq(dest.canonical_state(), src.canonical_state())
	var forged: Dictionary = saved.duplicate(true)
	forged["edges"]["E_GRID_JE"]["capacity"] = 99
	var before: String = Grid.serialize(dest.canonical_state())
	assert_false(dest.restore_causes(forged).is_empty())
	assert_eq(Grid.serialize(dest.canonical_state()), before, "forged save must not mutate restored grid")


func test_CTL2_C07_meter_evidence_durable_receipt_round_trip_and_rejects_wrong_shape() -> void:
	var ctx: Dictionary = _context()
	assert_true(Runner.send(ctx, "P1", "inspect", "PANEL_JE", {}).get("ok", false))
	var mission: Mission = ctx["mission"] as Mission
	var saved: Dictionary = mission.durable_state()
	assert_true(saved["optional_meter_evidence"]["observed"])
	assert_false(saved["optional_meter_evidence"]["reset_attempted"])
	var fresh: Dictionary = _context()
	var dest: Mission = fresh["mission"] as Mission
	assert_eq(dest.restore_state(saved), [] as Array[Dictionary])
	assert_eq(dest.durable_state(), saved)
	var bad: Dictionary = saved.duplicate(true)
	bad["optional_meter_evidence"] = {"observed": "true", "reset_attempted": false}
	assert_false(dest.restore_state(bad).is_empty())
	assert_eq(dest.durable_state(), saved)
	bad["optional_meter_evidence"] = {"observed": false, "reset_attempted": false, "invented": true}
	assert_false(dest.restore_state(bad).is_empty())


func test_CTL2_C07_invalid_module_definitions_fail_closed() -> void:
	## Any other positive authored rating above the original is allowed by the generic engine;
	## malformed/non-upgrade values alone must be rejected at content load.
	for invalid: int in [0, 9, 10]:
		var g: Dictionary = Runner.json(C07.path_join("grid.json"))
		g["module_upgrades"][0]["to_capacity"] = invalid
		var candidate: Grid = Grid.new()
		assert_false(candidate.load_definition(g).is_empty())
	var g: Dictionary = Runner.json(C07.path_join("grid.json"))
	g["module_upgrades"][0]["breaker"] = "JW"
	var candidate: Grid = Grid.new()
	assert_false(candidate.load_definition(g).is_empty())
	var repair_def: Dictionary = Runner.json(C07.path_join("repairs.json"))
	repair_def["repairs"][0]["fix"]["capacity"] = 99
	assert_ne(repair_def["repairs"][0]["fix"]["capacity"], 14)
	# The interacting service rejects any replacement that is not in the grid's whitelist.
	var ctx: Dictionary = _context()
	var inter: Variant = ctx["interaction"]
	var errors: Array[Dictionary] = inter.load_definition(Runner.json("res://content/interaction.json"),
		repair_def, ctx["grid"], ctx["meter"])
	assert_false(errors.is_empty())


func test_CTL2_C07_six_earlier_mission_checkpoints_keep_legacy_field_shapes() -> void:
	for path: String in EARLIER:
		var trace: Dictionary = Runner.json(path.path_join("solution.json"))
		var ctx: Dictionary = Runner.build(path, trace["players"], trace["tools"])
		assert_eq(ctx["errors"], [] as Array[Dictionary], path)
		var mission: Mission = ctx["mission"] as Mission
		var old: Dictionary = mission.durable_state()
		assert_false(old.has("optional_meter_evidence"), path)
		assert_eq(mission.restore_state(old), [] as Array[Dictionary], path)
		assert_eq(mission.durable_state(), old, path)
