extends "res://tests/test_case.gd"
## EXP014 A02: source/headless contingency host replays, spoof rejection and
## opt-in compatibility. No controller, route geometry or GPU certification.

const Atlas := preload("res://scripts/world/dispatch_atlas.gd")
const OriginalA02 := preload("res://scripts/gameplay/expedition_site_interventions.gd")
const OriginalEXP013 := preload("res://scripts/gameplay/expedition_site_exp013.gd")
const Contingency := preload("res://scripts/gameplay/expedition_site_contingencies.gd")
const Runtime := preload("res://scripts/gameplay/expedition_host_session.gd")


func _host_position(_id: String) -> Vector3:
	return Vector3(35.0, 0.9, 35.0)


func _facts(route: String) -> Dictionary:
	return {"worksite_opened": true, "worksite_route": route,
		"site_intervention_solved": true,
		"balancing_solved": true, "logistics_solved": true,
		"consequences_solved": true, "faults_solved": true,
		"west_restored": true, "east_on": true, "hazard_active": false}


func _all_original() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for item: Dictionary in OriginalA02.load_book()["entries"]:
		result.append(item)
	for book: Dictionary in OriginalEXP013.load_available_books():
		for item: Dictionary in book["entries"]:
			result.append(item)
	return result


func _run_step(engine: Contingency, facts: Dictionary) -> void:
	var next: Dictionary = engine.snapshot()["next"]
	assert_false(next.is_empty())
	if next.is_empty():
		return
	var target: String = str(next["target"])
	var support: String = str(next["support"])
	var witness: String = str(next["witness"])
	var mode: String = str(next["mode"])
	var first: String = "read" if mode == "quorum" else \
		"arm" if mode == "reserve_lease" else "isolate"
	var second: String = "attest" if mode == "quorum" else \
		"transfer" if mode == "reserve_lease" else "verify"
	var final: String = "seal" if mode == "quorum" else \
		"release" if mode == "reserve_lease" else "close"
	assert_true(bool(engine.operate(target, str(next["action"]), facts).get("ok", false)),
		"Cannot start: " + str(next))
	for i: int in range(int(next["dwell_ticks"])):
		engine.advance(facts)
	assert_eq(str(engine.snapshot()["phase"]), "stable")
	# The four risk guards must be genuinely different host-side proof paths.
	var guard: String = str(next["guard"])
	if guard == "load_balanced":
		assert_false(bool(engine.operate(support, first, facts).get("ok", true)),
			"Load stability hold was bypassed")
		for i: int in range(3):
			engine.advance(facts)
	else:
		var proof_station: String = support if guard == "supplies_ready" else \
			witness if guard == "cascade_stable" else target
		var proof_action: String = "stock_check" if guard == "supplies_ready" else \
			"relay_ping" if guard == "cascade_stable" else "clearance_probe"
		assert_false(bool(engine.operate(support, first, facts).get("ok", true)),
			"Required domain proof was bypassed")
		assert_true(bool(engine.operate(proof_station, proof_action, facts).get("ok", false)),
			"Source-domain preflight failed")
		assert_false(bool(engine.operate(support, first, facts).get("ok", true)),
			"Guard witness gap was bypassed")
		for i: int in range(3):
			engine.advance(facts)
	assert_true(bool(engine.operate(support, first, facts).get("ok", false)))
	assert_false(bool(engine.operate(witness, second, facts).get("ok", true)),
		"Witness forged before host gap")
	for i: int in range(int(next["witness_gap_ticks"])):
		engine.advance(facts)
	assert_true(bool(engine.operate(witness, second, facts).get("ok", false)))
	assert_false(bool(engine.operate(target, final, facts).get("ok", true)),
		"Premature seal bypassed settling")
	var settling: int = 2 if mode == "quorum" else \
		4 if mode == "reserve_lease" else 3
	for i: int in range(settling):
		engine.advance(facts)
	assert_true(bool(engine.operate(target, final, facts).get("ok", false)),
		"Safe step did not complete: " + str(next))


func test_EXP014_A02_original_catalog_source_pins_and_mechanic_diversity() -> void:
	var originals: Array[Dictionary] = _all_original()
	assert_eq(originals.size(), 200)
	var audit: Dictionary = Contingency.inspect(
		Atlas.load_catalog(), originals, Contingency.load_book())
	assert_true(bool(audit.get("ok", false)), str(audit))
	if bool(audit.get("ok", false)):
		assert_eq(int(audit["cases"]), 200)
		assert_eq(int(audit["routes"]), 400)
		assert_eq(int(audit["steps"]), 1200)
		assert_true(int(audit["distinct"]) >= 150)
		assert_true(int(audit["max_reuse"]) <= 8)


func test_EXP014_A02_all_400_host_routes_finish_with_independent_witness() -> void:
	var book: Dictionary = Contingency.load_book()
	assert_eq((book["entries"] as Array).size(), 200)
	for entry: Dictionary in book["entries"]:
		for route: String in ["priority", "resilience"]:
			var engine: Contingency = Contingency.new()
			assert_true(bool(engine.configure(entry).get("ok", false)))
			assert_true(bool(engine.choose_route(route).get("ok", false)))
			var facts: Dictionary = _facts(route)
			for index: int in range(3):
				_run_step(engine, facts)
				assert_eq(int(engine.snapshot()["step"]), index + 1,
					"Step frozen: " + str(entry["level_id"]) + " " + route)
			assert_true(engine.solved(),
				"Contingency deadlocked: " + str(entry["level_id"]) + " " + route)


func test_EXP014_A02_spoofed_source_route_station_and_clock_fail_closed() -> void:
	var book: Dictionary = Contingency.load_book()
	var originals: Array[Dictionary] = _all_original()
	var atlas: Dictionary = Atlas.load_catalog()
	var tampered: Dictionary = book.duplicate(true)
	tampered["entries"][0]["source_task_ids"][0] = "FORGED_TASK"
	assert_false(bool(Contingency.inspect(atlas, originals, tampered)["ok"]))
	tampered = book.duplicate(true)
	tampered["entries"][2]["routes"]["priority"][0]["witness"] = "FORGED_PANEL"
	assert_false(bool(Contingency.inspect(atlas, originals, tampered)["ok"]))
	tampered = book.duplicate(true)
	tampered["entries"][8]["routes"]["priority"][0]["dwell_ticks"] = 7.25
	assert_false(bool(Contingency.inspect(atlas, originals, tampered)["ok"]))
	tampered = book.duplicate(true)
	tampered["entries"][8]["routes"]["priority"][0]["window_ticks"] = true
	assert_false(bool(Contingency.inspect(atlas, originals, tampered)["ok"]))


func test_EXP014_A02_faults_recovery_and_upstream_loss_cannot_be_bypassed() -> void:
	var entry: Dictionary = Contingency.load_book()["entries"][100]
	var engine: Contingency = Contingency.new()
	assert_true(bool(engine.configure(entry).get("ok", false)))
	assert_true(bool(engine.choose_route("priority").get("ok", false)))
	var facts: Dictionary = _facts("priority")
	var source: Dictionary = engine.snapshot()["next"]
	assert_true(bool(engine.operate(str(source["target"]),
		str(source["action"]), facts).get("ok", false)))
	assert_false(bool(engine.operate(str(source["target"]), "seal", facts).get("ok", true)))
	assert_eq(str(engine.snapshot()["fault"]), "PREMATURE_CLOSE")
	assert_false(bool(engine.operate(str(source["target"]), "recover", facts).get("ok", true)))
	assert_true(bool(engine.operate(str(entry["recovery_target"]),
		"recover", facts).get("ok", false)))
	assert_eq(str(engine.snapshot()["fault"]), "")
	assert_eq(int(engine.snapshot()["recoveries"]), 1)
	# The host itself can detect supply loss without receiving any wire action.
	assert_true(bool(engine.operate(str(source["target"]),
		str(source["action"]), facts).get("ok", false)))
	var broken: Dictionary = facts.duplicate(true)
	broken["logistics_solved"] = false
	engine.advance(broken)
	assert_eq(str(engine.snapshot()["fault"]), "SUPPLY_LOST")
	assert_false(engine.solved())
	assert_eq(int(engine.snapshot()["step"]), 0)
	assert_true(bool(engine.operate(str(entry["recovery_target"]),
		"recover", facts).get("ok", false)))


func test_EXP014_A02_optional_activation_preserves_all_old_session_modes() -> void:
	for level: int in [1, 40, 41, 80, 81, 120, 121, 160, 161, 200]:
		var previous: Runtime = Runtime.new()
		var old_result: Dictionary = previous.start("LV_%03d" % level,
			Callable(self, "_host_position"), Callable(), "", false, "",
			true, true, true, true, true, true, true, true, true)
		assert_true(bool(old_result.get("ok", false)), str(old_result))
		if not bool(old_result.get("ok", false)):
			continue
		assert_true(previous.site_contingency == null)
		assert_false(str(old_result["content_revision"]).begins_with("EXP014_"))
		var enhanced: Runtime = Runtime.new()
		var result: Dictionary = enhanced.start("LV_%03d" % level,
			Callable(self, "_host_position"), Callable(), "", false, "",
			true, true, true, true, true, true, true, true, true, true)
		assert_true(bool(result.get("ok", false)), str(result))
		if not bool(result.get("ok", false)):
			continue
		assert_true(enhanced.site_contingency != null)
		assert_true(str(result["content_revision"]).begins_with("EXP014_"))
		assert_eq(str(enhanced.site_contingency.definition_snapshot()["level_id"]),
			"LV_%03d" % level)
		assert_true(enhanced.host.authoritative_state()["exp012_worksite_orders"].has(
			"site_contingency"))
		assert_ne(enhanced.state_hash(), previous.state_hash())
