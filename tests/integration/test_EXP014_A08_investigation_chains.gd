extends "res://tests/test_case.gd"
## EXP014 A08: 200 source-pinned DAGs x two meaningful investigation
## routes; no human/controller, physical, GPU, networking or release testing.

const Atlas := preload("res://scripts/world/dispatch_atlas.gd")
const Plan := preload("res://scripts/world/expedition_layout_plan.gd")
const A02 := preload("res://scripts/gameplay/expedition_site_interventions.gd")
const EXP013 := preload("res://scripts/gameplay/expedition_site_exp013.gd")
const Contingencies := preload("res://scripts/gameplay/expedition_site_contingencies.gd")
const Recon := preload("res://scripts/gameplay/expedition_approach_intelligence.gd")
const Outcomes := preload("res://scripts/gameplay/expedition_operational_consequences.gd")
const Hazards := preload("res://scripts/gameplay/expedition_environment_hazards.gd")
const Puzzles := preload("res://scripts/gameplay/expedition_investigation_chains.gd")
const Runtime := preload("res://scripts/gameplay/expedition_host_session.gd")


func _cases() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry: Dictionary in A02.load_book()["entries"]:
		result.append(entry)
	for book: Dictionary in EXP013.load_available_books():
		for entry: Dictionary in book["entries"]:
			result.append(entry)
	return result


func _facts(route: String = "priority") -> Dictionary:
	return {"hazard_safe": true, "worksite_opened": true, "recon_route": route,
		"faults_solved": true, "balancing_solved": true,
		"logistics_solved": true, "consequences_solved": true}


func _position(_player: String) -> Vector3:
	return Vector3(35.0, 0.9, 35.0)


func _configure(serial: int, atlas: Dictionary, originals: Array[Dictionary],
		contingencies: Dictionary, book: Dictionary) -> Puzzles:
	var source: Dictionary = contingencies["entries"][serial - 1]
	var original: Dictionary = originals[serial - 1]
	var plan: Dictionary = Plan.make_plan(
		atlas["levels"][serial - 1], atlas["locations"][serial - 1])
	var recon: Recon = Recon.new()
	assert_true(bool(recon.configure(plan, original).get("ok", false)))
	var outcome: Outcomes = Outcomes.new()
	assert_true(bool(outcome.configure(recon.definition_snapshot(), source).get("ok", false)))
	var hazard: Hazards = Hazards.new()
	assert_true(bool(hazard.configure(recon.definition_snapshot(),
		outcome.definition_snapshot(), source).get("ok", false)))
	var puzzle: Puzzles = Puzzles.new()
	assert_true(bool(puzzle.configure(source, Puzzles.entry_for(book, str(source["level_id"])),
		hazard.definition_snapshot()).get("ok", false)))
	return puzzle


func _contained(puzzle: Puzzles, route: String) -> Dictionary:
	var spec: Dictionary = puzzle.definition_snapshot()
	return {"level_id": spec["level_id"], "region_id": spec["region_id"],
		"risk_class": spec["risk_class"], "qualification": Puzzles.QUALIFICATION,
		"phase": "contained", "fault": "", "route": route}


func _replay(puzzle: Puzzles, mode: String, route: String,
		reverse_frontier: bool = false) -> Dictionary:
	var facts: Dictionary = _facts(route)
	assert_false(puzzle.started())
	assert_false(puzzle.solved())
	assert_true(bool(puzzle.begin(_contained(puzzle, route)).get("ok", false)))
	assert_eq(str(puzzle.snapshot()["phase"]), "choose")
	var choices: Array = puzzle.snapshot()["choices"]
	assert_eq(choices.size(), 2)
	var selected: Dictionary = {}
	for item: Dictionary in choices:
		if str(item["mode"]) == mode:
			selected = item
			break
	assert_false(selected.is_empty())
	assert_true(bool(puzzle.operate(str(selected["target"]), str(selected["action"]),
		facts).get("ok", false)))
	assert_eq(str(puzzle.snapshot()["phase"]), "running")
	assert_eq(str(puzzle.snapshot()["mode"]), mode)
	assert_false(puzzle.solved())
	var completed: int = 0
	var saw_parallel: bool = false
	var limit: int = 0
	while not puzzle.solved() and limit < 12:
		var frontier: Array = puzzle.snapshot()["available"]
		assert_false(frontier.is_empty(), "A08 must have a live dependency frontier")
		if frontier.is_empty():
			break
		saw_parallel = saw_parallel or frontier.size() >= 2
		var option: Dictionary = frontier[frontier.size() - 1 if reverse_frontier else 0]
		if completed > 0:
			for i: int in range(4):
				puzzle.advance(facts)
		assert_true(bool(puzzle.operate(str(option["target"]), str(option["action"]),
			facts).get("ok", false)), "Site proof should be accepted once dependencies settle")
		completed += 1
		limit += 1
	assert_true(puzzle.solved(), "The host must certify the entire DAG")
	assert_true(saw_parallel, "At least two evidence operations must be independently orderable")
	assert_eq(int(puzzle.snapshot()["completed"]), 6 if mode == "forensic" else 7)
	assert_eq(str(puzzle.snapshot()["phase"]), "certified")
	assert_eq(puzzle.snapshot()["available"], [])
	assert_true(puzzle.snapshot()["history"].size() <= 20)
	return puzzle.snapshot()


func test_EXP014_A08_200_exact_source_cases_400_branch_replays_and_non_linear_frontiers() -> void:
	var atlas: Dictionary = Atlas.load_catalog()
	var originals: Array[Dictionary] = _cases()
	var contingencies: Dictionary = Contingencies.load_book()
	var book: Dictionary = Puzzles.load_book()
	assert_eq(originals.size(), 200)
	assert_eq(contingencies["entries"].size(), 200)
	assert_eq(book["entries"].size(), 200)
	var tasks: Dictionary = {}
	var site_ids: Dictionary = {}
	for serial: int in range(1, 201):
		var case: Dictionary = contingencies["entries"][serial - 1]
		for task: Variant in case["source_task_ids"]:
			assert_false(tasks.has(str(task)))
			tasks[str(task)] = true
		site_ids[str(case["level_id"])] = true
		var puzzle: Puzzles = _configure(serial, atlas, originals, contingencies, book)
		for mode: String in Puzzles.MODES:
			var independent: Puzzles = _configure(serial, atlas, originals, contingencies, book)
			var route: String = "priority" if mode == "forensic" else "resilience"
			var result: Dictionary = _replay(independent, mode, route, serial % 2 == 0)
			assert_eq(str(result["level_id"]), "LV_%03d" % serial)
			assert_eq(str(result["route"]), route)
			assert_eq(str(result["mode"]), mode)
			if mode == "field":
				assert_eq(int(result["kits"]), 3)
				assert_true(int(result["liabilities"]) > 0)
			else:
				assert_true(int(result["kits"]) < 3)
		assert_false(puzzle.started())
	assert_eq(site_ids.size(), 200)
	assert_eq(tasks.size(), 1000)


func test_EXP014_A08_locked_evidence_wrong_station_stale_and_source_mutation_rejections() -> void:
	var atlas: Dictionary = Atlas.load_catalog()
	var originals: Array[Dictionary] = _cases()
	var contingencies: Dictionary = Contingencies.load_book()
	var book: Dictionary = Puzzles.load_book()
	var puzzle: Puzzles = _configure(1, atlas, originals, contingencies, book)
	var fixture: Dictionary = _contained(puzzle, "priority")
	fixture["phase"] = "settle"
	assert_false(bool(puzzle.begin(fixture).get("ok", false)))
	fixture["phase"] = "contained"
	fixture["level_id"] = "LV_999"
	assert_false(bool(puzzle.begin(fixture).get("ok", false)))
	var source: Dictionary = contingencies["entries"][0]
	var hazard: Dictionary = {
		"level_id": source["level_id"], "location_id": source["location_id"],
		"region_id": source["region_id"], "source_risk": source["source_risk"],
		"source_task_ids": source["source_task_ids"].duplicate(true),
		"targets": source["targets"].duplicate(true),
		"risk_class": puzzle.definition_snapshot()["risk_class"],
		"qualification": Puzzles.QUALIFICATION}
	for key: String in ["source_task_ids", "targets", "source_puzzle_identity",
			"worksite_encounter_key", "source_route_actions"]:
		var forged: Dictionary = Puzzles.entry_for(book, "LV_001")
		if key == "source_task_ids":
			forged[key] = ["JOB_999_1"]
		elif key == "targets":
			forged[key] = {"A":"SC_999_A", "B":"SC_999_B", "C":"SC_999_C"}
		elif key == "source_route_actions":
			forged[key] = {"priority":[], "resilience":[]}
		else:
			forged[key] = "FORGED"
		assert_false(bool(Puzzles.inspect(source, forged, hazard).get("ok", false)), key)
	assert_true(bool(puzzle.begin(_contained(puzzle, "priority")).get("ok", false)))
	assert_false(bool(puzzle.operate("SC_999_A", "begin_forensic", _facts()).get("ok", false)))
	var entry: Dictionary = puzzle.snapshot()["choices"][0]
	assert_true(bool(puzzle.operate(str(entry["target"]), str(entry["action"]), _facts()).get("ok", false)))
	var frontier: Array = puzzle.snapshot()["available"]
	assert_eq(frontier.size(), 1)
	assert_false(bool(puzzle.operate(str(frontier[0]["target"]), "prove_P3_sample",
		_facts()).get("ok", false)), "Locked graph node cannot skip prerequisites")
	assert_true(bool(puzzle.operate(str(frontier[0]["target"]), str(frontier[0]["action"]),
		_facts()).get("ok", false)))
	frontier = puzzle.snapshot()["available"]
	assert_true(frontier.size() >= 2)
	assert_false(bool(puzzle.operate(str(frontier[0]["target"]), str(frontier[0]["action"]),
		_facts()).get("ok", false)), "Evidence requires independent host dwell ticks")
	for i: int in range(71):
		puzzle.advance(_facts())
	assert_eq(str(puzzle.snapshot()["fault"]), "EVIDENCE_STALE")
	assert_false(puzzle.solved())


func test_EXP014_A08_host_recovery_preserves_spent_kits_and_allows_field_fallback() -> void:
	var atlas: Dictionary = Atlas.load_catalog()
	var puzzle: Puzzles = _configure(1, atlas, _cases(), Contingencies.load_book(),
		Puzzles.load_book())
	assert_true(bool(puzzle.begin(_contained(puzzle, "priority")).get("ok", false)))
	var choice: Dictionary = puzzle.snapshot()["choices"][0]
	assert_true(bool(puzzle.operate(str(choice["target"]), str(choice["action"]),
		_facts()).get("ok", false)))
	var facts: Dictionary = _facts()
	var first: Dictionary = puzzle.snapshot()["available"][0]
	assert_true(bool(puzzle.operate(str(first["target"]), str(first["action"]), facts).get("ok", false)))
	for i: int in range(4):
		puzzle.advance(facts)
	var second: Dictionary = puzzle.snapshot()["available"][0]
	assert_true(bool(puzzle.operate(str(second["target"]), str(second["action"]), facts).get("ok", false)))
	var spent: int = int(puzzle.snapshot()["kits"])
	assert_true(spent < 3)
	facts["hazard_safe"] = false
	puzzle.advance(facts)
	assert_eq(str(puzzle.snapshot()["phase"]), "fault")
	assert_false(bool(puzzle.operate("SC_001_A", "recover", facts).get("ok", false)))
	assert_false(bool(puzzle.operate("SC_001_C", "recover", facts).get("ok", false)))
	facts["hazard_safe"] = true
	assert_true(bool(puzzle.operate("SC_001_C", "recover", facts).get("ok", false)))
	assert_eq(int(puzzle.snapshot()["kits"]), spent)
	assert_eq(int(puzzle.snapshot()["recoveries"]), 1)
	var option: Dictionary = puzzle.snapshot()["choices"][1]
	assert_true(bool(puzzle.operate(str(option["target"]), str(option["action"]), facts).get("ok", false)))
	var remaining: int = 0
	while not puzzle.solved() and remaining < 10:
		var frontier: Array = puzzle.snapshot()["available"]
		assert_false(frontier.is_empty())
		for i: int in range(4):
			puzzle.advance(facts)
		var step: Dictionary = frontier[frontier.size() - 1]
		assert_true(bool(puzzle.operate(str(step["target"]), str(step["action"]), facts).get("ok", false)))
		remaining += 1
	assert_true(puzzle.solved())
	assert_eq(int(puzzle.snapshot()["kits"]), spent)
	assert_true(int(puzzle.snapshot()["liabilities"]) >= 2)


func test_EXP014_A08_runtime_opt_in_has_distinct_revision_and_blocks_worksite() -> void:
	for id: String in ["LV_001", "LV_101", "LV_200"]:
		var predecessor: Runtime = Runtime.new()
		var old: Dictionary = predecessor.start(id, Callable(self, "_position"),
			Callable(), "", false, "", true, true, true, true, true,
			true, true, true, true, true, true, true, true)
		assert_true(bool(old.get("ok", false)), str(old))
		if not bool(old.get("ok", false)):
			continue
		assert_true(predecessor.site_puzzles == null)
		var runtime: Runtime = Runtime.new()
		var upgraded: Dictionary = runtime.start(id, Callable(self, "_position"),
			Callable(), "", false, "", true, true, true, true, true,
			true, true, true, true, true, true, true, true, true)
		assert_true(bool(upgraded.get("ok", false)), str(upgraded))
		if not bool(upgraded.get("ok", false)):
			continue
		assert_true(runtime.site_puzzles != null)
		assert_true(str(upgraded["content_revision"]).begins_with("EXP014_A08_"))
		assert_ne(str(upgraded["content_revision"]), str(old["content_revision"]))
		assert_true(runtime.host.authoritative_state()["exp012_worksite_orders"].has("site_puzzles"))
		var worksite: Dictionary = runtime.worksite.definition_snapshot()
		var illegal: Dictionary = runtime._operate_worksite(Runtime.PLAYER_ID,
			str(worksite["decision"]), "priority")
		assert_false(bool(illegal.get("ok", false)))
		assert_false(runtime.site_puzzles.solved())
