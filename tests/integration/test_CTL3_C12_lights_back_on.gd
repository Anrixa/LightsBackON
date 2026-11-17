extends "res://tests/test_case.gd"
## CT-L3/C12: original-sheet host-only Hill Road finale qualification.
## This is not physical stage, GPU, controller, save-release or Steam evidence.

const Runner := preload("res://tests/support/solution_runner.gd")
const Grid := preload("res://scripts/simulation/power_grid.gd")
const Mission := preload("res://scripts/simulation/mission_director.gd")
const Host := preload("res://scripts/network/session_host.gd")
const Hud := preload("res://scripts/ui/hud_presenter.gd")

const C12: String = "res://content/contracts/c12_lights_back_on"
const EARLIER: Array[String] = [
	"res://content/contracts/c01_alder_street",
	"res://content/contracts/c02_dinner_rush",
	"res://content/contracts/c03_roof_route",
	"res://content/contracts/c04_whole_block",
	"res://content/contracts/c05_canal_pump_access",
	"res://content/contracts/c06_cold_chain",
	"res://content/contracts/c07_wrong_label",
	"res://content/contracts/c08_split_supply",
	"res://content/contracts/c09_wind_warning",
	"res://content/contracts/c10_community_night",
	"res://content/contracts/c11_borrowed_power",
]


func _trace() -> Dictionary:
	return Runner.json(C12.path_join("solution.json"))


func _context(players: Array = ["P1"]) -> Dictionary:
	return Runner.build(C12, players, _trace()["tools"])


func _switch(ctx: Dictionary, id: String, value: bool) -> Dictionary:
	return Runner.send(ctx, "P1", "toggle_switch", id, {"value": value})


func _prefix_until(ctx: Dictionary, entity: String, intent: String = "request_lock") -> void:
	var steps: Array = []
	for step: Dictionary in _trace()["steps"]:
		if step.get("intent") == intent and step.get("entity") == entity:
			break
		steps.append(step)
	assert_eq(Runner.run(ctx, steps, 1), [] as Array[String])


func _solution_without_beacon() -> Array:
	var steps: Array = []
	var skipping: bool = false
	for original: Dictionary in _trace()["steps"]:
		if original.get("intent") == "request_lock" and original.get("entity") == "R_BEACON_SPUR":
			skipping = true
		if original.get("intent") == "request_lock" and original.get("entity") == "R_EAST_TRUNK":
			skipping = false
		if skipping:
			continue
		if original.get("ticks") == 100:
			steps.append({"ticks": 100, "expect_events": ["verified", "finale_lights_wave", "finale_radio_subtitle"]})
		else:
			steps.append(original)
	return steps


func test_CTL3_C12_original_blueprint_grid_and_latches() -> void:
	var ctx: Dictionary = _context()
	assert_eq(ctx["errors"], [] as Array[Dictionary], str(ctx["errors"]))
	var st: Dictionary = (ctx["grid"] as Grid).canonical_state()
	assert_eq(st["nodes"]["GRID"]["capacity"], 28)
	assert_eq(st["nodes"]["GEN"]["capacity"], 6)
	assert_eq(st["edges"]["E_GRID_WEST"]["capacity"], 14)
	assert_eq(st["edges"]["E_GRID_EAST"]["capacity"], 14)
	assert_true(st["nodes"]["WEST"]["failed"])
	assert_true(st["nodes"]["WEST"]["tripped"])
	assert_false(st["edges"]["E_GRID_EAST"]["healthy"])
	assert_eq(st["nodes"]["BEACON"]["demand"], 3)
	assert_eq(st["nodes"]["DRAIN_CONTROL"]["demand"], 4)
	assert_eq(st["edges"]["E_GRID_BEACON"]["capacity"], 4)
	assert_false(st["edges"]["E_GRID_BEACON"]["enabled"])
	assert_true(st["nodes"]["WEST_BEACON"]["isolated"])
	var mission: Dictionary = Runner.json(C12.path_join("mission.json"))
	assert_eq(int(mission["access_latches"][0]["supplied_ticks"]), 120)
	assert_eq(int(mission["access_latches"][1]["supplied_ticks"]), 100)
	assert_eq(mission["optional_latch_rewards"], ["LATCH_BEACON"])
	assert_eq(int(mission["finale"]["stagger_ticks"]), 20)
	assert_eq(mission["required_consumers"].size(), 6)


func test_CTL3_C12_full_70_step_solution_scores_beacon_and_offers_replay() -> void:
	var ctx: Dictionary = _context()
	var trace: Dictionary = _trace()
	assert_eq(Runner.run(ctx, trace["steps"], int(trace["pace_ticks_per_command"])), [] as Array[String])
	var m: Mission = ctx["mission"] as Mission
	assert_true(m.is_complete())
	assert_true(int(ctx["now"]) <= int(trace["max_ticks"]))
	assert_true(m.is_latched("LATCH_DRAIN"))
	assert_true(m.is_latched("LATCH_BEACON"))
	var report: Dictionary = m.results()
	assert_eq(report["required_restored"], 6)
	assert_eq(report["required_total"], 6)
	assert_eq(report["optional_services"], ["BEACON"])
	assert_eq(report["optional_total"], 1)
	assert_eq(report["preventable_trips"], 0)
	assert_eq(report["stars"], 3)
	assert_eq(report["next_actions"], ["replay", "remaining_optional_tasks"])
	var st: Dictionary = (ctx["grid"] as Grid).canonical_state()
	assert_eq(st["nodes"]["GRID"]["load"], 28)
	assert_eq(st["edges"]["E_GRID_WEST"]["flow"], 13)
	assert_eq(st["edges"]["E_GRID_EAST"]["flow"], 12)
	assert_eq(st["edges"]["E_GRID_BEACON"]["flow"], 3)
	assert_false(st["nodes"]["GEN"]["online"])


func test_CTL3_C12_drain_control_requires_120_continuous_generator_ticks() -> void:
	var ctx: Dictionary = _context()
	var steps: Array = []
	for step: Dictionary in _trace()["steps"]:
		if step.get("intent") == "place_item":
			steps.append(step)
			if step.get("payload", {}).get("action") == "start":
				break
	assert_eq(Runner.run(ctx, steps, 1), [] as Array[String])
	var m: Mission = ctx["mission"] as Mission
	# The solution runner advances the host after the start intent.
	# Count until 119 total live supply ticks; do not double-count pacing.
	Runner.ticks(ctx, 119 - int(m.canonical_state()["latch_ticks"]["LATCH_DRAIN"]))
	assert_false(m.is_latched("LATCH_DRAIN"))
	assert_true(Runner.send(ctx, "P1", "place_item", "GEN_PORTABLE", {"action":"stop"}).get("ok", false))
	assert_true(Runner.send(ctx, "P1", "place_item", "GEN_PORTABLE", {"action":"start"}).get("ok", false))
	Runner.ticks(ctx, 119)
	assert_false(m.is_latched("LATCH_DRAIN"))
	Runner.ticks(ctx, 1)
	assert_true(m.is_latched("LATCH_DRAIN"))


func test_CTL3_C12_east_repair_refused_until_control_latches() -> void:
	var ctx: Dictionary = _context()
	assert_eq(Runner.send(ctx, "P1", "request_lock", "R_EAST_TRUNK", {}).get("code"), "NO_ACCESS")
	_prefix_until(ctx, "R_EAST_TRUNK")
	assert_true((ctx["mission"] as Mission).is_latched("LATCH_DRAIN"))
	assert_true(Runner.send(ctx, "P1", "request_lock", "R_EAST_TRUNK", {}).get("ok", false))


func test_CTL3_C12_west_beacon_overload_trips_after_15_host_ticks() -> void:
	var ctx: Dictionary = _context()
	var prefix: Array = []
	for step: Dictionary in _trace()["steps"]:
		prefix.append(step)
		if step.get("entity") == "R_WEST_FUSE" and step.get("payload", {}).get("step") == "restore":
			break
	assert_eq(Runner.run(ctx, prefix, 1), [] as Array[String])
	var grid: Grid = ctx["grid"] as Grid
	assert_eq(grid.canonical_state()["edges"]["E_GRID_WEST"]["flow"], 13)
	assert_true(_switch(ctx, "SW_WEST_BEACON", false).get("ok", false))
	assert_eq(grid.canonical_state()["edges"]["E_GRID_WEST"]["flow"], 16)
	Runner.ticks(ctx, 15)
	assert_true(grid.canonical_state()["nodes"]["WEST"]["tripped"])


func test_CTL3_C12_direct_beacon_route_cannot_dual_feed_west() -> void:
	var ctx: Dictionary = _context()
	_prefix_until(ctx, "R_EAST_TRUNK")
	var grid: Grid = ctx["grid"] as Grid
	assert_true(grid.canonical_state()["nodes"]["BEACON"]["supplied"])
	assert_eq(grid.canonical_state()["edges"]["E_GRID_BEACON"]["flow"], 3)
	var before: Dictionary = grid.canonical_state()
	var refused: Dictionary = _switch(ctx, "SW_WEST_BEACON", false)
	assert_false(refused.get("ok", false))
	assert_eq(grid.canonical_state(), before)


func test_CTL3_C12_optional_beacon_skipped_still_completes_core() -> void:
	var ctx: Dictionary = _context()
	var steps: Array = _solution_without_beacon()
	assert_eq(Runner.run(ctx, steps, 1), [] as Array[String])
	var m: Mission = ctx["mission"] as Mission
	assert_true(m.is_complete())
	assert_false(m.is_latched("LATCH_BEACON"))
	assert_eq(m.results()["required_restored"], 6)
	assert_eq(m.results()["optional_total"], 1)
	assert_eq(m.results()["optional_services"], [] as Array[String])
	assert_eq(m.results()["stars"], 2)
	assert_eq((ctx["grid"] as Grid).canonical_state()["nodes"]["GRID"]["load"], 25)


func test_CTL3_C12_finale_wave_is_exactly_20_ticks_without_input_lock() -> void:
	var ctx: Dictionary = _context()
	var prefix: Array = []
	for step: Dictionary in _trace()["steps"]:
		prefix.append(step)
		if step.get("ticks") == 100:
			break
	assert_eq(Runner.run(ctx, prefix, 1), [] as Array[String])
	var m: Mission = ctx["mission"] as Mission
	assert_true(m.verified())
	var elapsed: int = int(m.canonical_state()["finale"]["elapsed_ticks"])
	assert_true(elapsed >= 0 and elapsed < 10)
	assert_false(m.canonical_state()["finale"]["input_locked"])
	assert_true(Runner.send(ctx, "P1", "inspect", "PANEL_WEST", {}).get("ok", false))
	Runner.ticks(ctx, 10 - elapsed)
	assert_eq(m.canonical_state()["finale"]["elapsed_ticks"], 10)
	assert_false(m.canonical_state()["finale"]["complete"])
	Runner.ticks(ctx, 10)
	assert_true(m.canonical_state()["finale"]["complete"])
	var stages: Array = []
	var radio: Array = []
	var ended: Array = []
	for event: Dictionary in ctx["events"]:
		if event.get("type") == "finale_lights_wave":
			stages.append(event)
		if event.get("type") == "finale_radio_subtitle":
			radio.append(event)
		if event.get("type") == "finale_lights_completed":
			ended.append(event)
	assert_eq(stages.size(), 3)
	assert_eq(stages[0]["stage"], 0)
	assert_eq(stages[1]["stage"], 1)
	assert_eq(stages[2]["stage"], 2)
	assert_eq(int(stages[1]["tick"]) - int(stages[0]["tick"]), 10)
	assert_eq(int(stages[2]["tick"]) - int(stages[0]["tick"]), 20)
	assert_eq(radio.size(), 1)
	assert_eq(radio[0]["text_key"], "radio.c12.restored")
	assert_eq(ended.size(), 1)


func test_CTL3_C12_finale_save_restore_and_forgery_refusal() -> void:
	var ctx: Dictionary = _context()
	var prefix: Array = []
	for step: Dictionary in _trace()["steps"]:
		prefix.append(step)
		if step.get("ticks") == 100:
			break
	assert_eq(Runner.run(ctx, prefix, 1), [] as Array[String])
	var m: Mission = ctx["mission"] as Mission
	var elapsed: int = int(m.canonical_state()["finale"]["elapsed_ticks"])
	assert_true(elapsed >= 0 and elapsed < 7)
	Runner.ticks(ctx, 7 - elapsed)
	var original: Dictionary = m.durable_state()
	assert_eq(original["finale"], {"started":true,"elapsed_ticks":7})
	for bad: Dictionary in [
		{"started":true,"elapsed_ticks":-1},
		{"started":true,"elapsed_ticks":21},
		{"started":false,"elapsed_ticks":2},
		{"started":1,"elapsed_ticks":7},
		{"started":true,"elapsed_ticks":true},
		{"started":true,"elapsed_ticks":7,"forged":true}
	]:
		var forged: Dictionary = original.duplicate(true)
		forged["finale"] = bad
		assert_false(m.restore_state(forged).is_empty(), str(bad))
		assert_eq(m.durable_state(), original)
	var missing: Dictionary = original.duplicate(true)
	missing.erase("finale")
	assert_false(m.restore_state(missing).is_empty())
	assert_eq(m.durable_state(), original)
	var ctx2: Dictionary = _context()
	var restored: Mission = ctx2["mission"] as Mission
	assert_eq(restored.restore_state(original), [] as Array[Dictionary])
	assert_eq(restored.durable_state(), original)
	Runner.ticks(ctx2, 13)
	assert_true(restored.canonical_state()["finale"]["complete"])


func test_CTL3_C12_malformed_finale_definitions_refused() -> void:
	var template: Dictionary = Runner.json(C12.path_join("mission.json"))["finale"]
	for bad: Dictionary in [
		{"stagger_ticks":19},
		{"stagger_ticks":true},
		{"stagger_ticks":"20"},
		{"trigger":"client_verified"},
		{"radio_subtitle_key":""},
		{"radio_subtitle_key":"raw text"},
		{"results_actions":["endless_game"]},
		{"results_actions":["replay","replay"]}
	]:
		var defn: Dictionary = template.duplicate(true)
		defn.merge(bad, true)
		var ctx: Dictionary = Runner.build(C12, _trace()["players"], _trace()["tools"], {"finale":defn})
		assert_false((ctx["errors"] as Array).is_empty(), str(bad))


func test_CTL3_C12_two_players_can_finish_shared_finale() -> void:
	var ctx: Dictionary = _context(["P1", "P2"])
	var steps: Array = _trace()["steps"].duplicate(true)
	for i: int in steps.size():
		if steps[i].get("intent") == "request_extract":
			steps.insert(i, {"zone":"ZONE_VAN","as":"P2","inside":true})
			break
	assert_eq(Runner.run(ctx, steps, 1), [] as Array[String])
	assert_true((ctx["mission"] as Mission).is_complete())
	assert_eq((ctx["mission"] as Mission).results()["stars"], 3)


func test_CTL3_C12_legacy_checkpoint_shapes_and_hud_are_isolated() -> void:
	for contract: String in EARLIER:
		var trace: Dictionary = Runner.json(contract.path_join("solution.json"))
		var ctx: Dictionary = Runner.build(contract, trace["players"], trace["tools"])
		assert_eq(ctx["errors"], [] as Array[Dictionary], contract)
		var m: Mission = ctx["mission"] as Mission
		var saved: Dictionary = m.durable_state()
		assert_false(saved.has("finale"), contract)
		assert_eq(m.restore_state(saved), [] as Array[Dictionary], contract)
		assert_eq(m.durable_state(), saved, contract)
	var ctx: Dictionary = _context()
	var m: Mission = ctx["mission"] as Mission
	var view: Dictionary = Hud.build((ctx["host"] as Host).authoritative_state(), m.objectives(), {"local_player":"P1","tools":[]})
	assert_true(view.has("finale"))
	assert_false(view["finale"]["input_locked"])
	assert_false(view["finale"]["started"])


func test_CTL3_C12_all_tablet_objectives_and_radio_localized() -> void:
	var strings: Dictionary = Runner.json("res://content/ui/strings/en.json")["strings"]
	for node: Dictionary in Runner.json(C12.path_join("tablet.json"))["nodes"]:
		assert_true(strings.has(node["name_key"]), node["name_key"])
	for obj: Dictionary in Runner.json(C12.path_join("mission.json"))["objectives"]:
		assert_true(strings.has(obj["text_key"]), obj["text_key"])
	for key: String in ["repair.c12.west_fuse", "repair.c12.east_trunk",
		"repair.c12.beacon_spur", "radio.c12.restored", "finale.c12.replay",
		"finale.c12.remaining"]:
		assert_true(strings.has(key))
