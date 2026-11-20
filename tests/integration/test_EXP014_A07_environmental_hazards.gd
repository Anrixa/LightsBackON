extends "res://tests/test_case.gd"
## EXP014 A07 — 200 immutable worksite cases x engineered/temporary control.
## Source/headless only, not physical reach, collision, GPU or human playability.

const Atlas := preload("res://scripts/world/dispatch_atlas.gd")
const Plan := preload("res://scripts/world/expedition_layout_plan.gd")
const A02 := preload("res://scripts/gameplay/expedition_site_interventions.gd")
const EXP013 := preload("res://scripts/gameplay/expedition_site_exp013.gd")
const Contingencies := preload("res://scripts/gameplay/expedition_site_contingencies.gd")
const Recon := preload("res://scripts/gameplay/expedition_approach_intelligence.gd")
const Outcomes := preload("res://scripts/gameplay/expedition_operational_consequences.gd")
const Hazards := preload("res://scripts/gameplay/expedition_environment_hazards.gd")
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
	return {"worksite_opened": true, "worksite_route": route,
		"faults_solved": true, "logistics_solved": true,
		"balancing_solved": true, "consequences_solved": true,
		"site_intervention_solved": false, "site_contingency_solved": false}


func _position(_player: String) -> Vector3:
	return Vector3(35.0, 0.9, 35.0)


func _configured(serial: int, atlas: Dictionary, cases: Array[Dictionary],
		contingency_book: Dictionary) -> Array:
	var plan: Dictionary = Plan.make_plan(
		atlas["levels"][serial - 1], atlas["locations"][serial - 1])
	var original: Dictionary = cases[serial - 1]
	var contingency: Dictionary = contingency_book["entries"][serial - 1]
	var recon: Recon = Recon.new()
	assert_true(bool(recon.configure(plan, original).get("ok", false)))
	var outcome: Outcomes = Outcomes.new()
	assert_true(bool(outcome.configure(recon.definition_snapshot(), contingency).get("ok", false)))
	var hazard: Hazards = Hazards.new()
	assert_true(bool(hazard.configure(recon.definition_snapshot(),
		outcome.definition_snapshot(), contingency).get("ok", false)))
	return [hazard, outcome, original, contingency]


func _start(hazard: Hazards, outcome: Outcomes, source: Dictionary,
		mode: String, route: String) -> void:
	var recon: Dictionary = {"level_id": source["level_id"],
		"region_id": source["region_id"], "observed_risk": source["source_risk"],
		"solved": true, "route": route, "approach": "guarded"}
	assert_true(bool(outcome.begin(recon).get("ok", false)))
	var service_choice: String = "buffer_service" if mode == "engineered" else "accept_managed_outage"
	assert_true(bool(outcome.operate("SC_" + str(source["level_id"]).trim_prefix("LV_") + "_A",
		service_choice, _facts(route)).get("ok", false)))
	assert_true(bool(hazard.begin(outcome.snapshot()).get("ok", false)))


func _replay(hazard: Hazards, mode: String, route: String) -> Dictionary:
	var facts: Dictionary = _facts(route)
	var start: Dictionary = hazard.snapshot()["next"]
	assert_false(hazard.can_operate())
	assert_false(hazard.solved())
	assert_true(bool(hazard.operate(str(start["target"]),
		"engineer_control" if mode == "engineered" else "temporary_bypass",
		facts).get("ok", false)))
	assert_false(hazard.can_operate())
	for i: int in range(int(hazard.snapshot()["mitigation_total"])):
		var next: Dictionary = hazard.snapshot()["next"]
		for j: int in range(5):
			hazard.advance(facts)
		assert_true(bool(hazard.operate(str(next["target"]),
			str(next["action"]), facts).get("ok", false)))
	assert_eq(str(hazard.snapshot()["phase"]), "settle")
	for i: int in range(6):
		hazard.advance(facts)
	assert_true(hazard.can_operate())
	assert_false(hazard.solved())
	assert_eq(str(hazard.snapshot()["phase"]), "contained")
	# Completing both original systems is mandatory before postcheck.
	facts["site_intervention_solved"] = true
	hazard.advance(facts)
	assert_eq(str(hazard.snapshot()["phase"]), "contained")
	facts["site_contingency_solved"] = true
	hazard.advance(facts)
	assert_eq(str(hazard.snapshot()["phase"]), "postcheck")
	if mode == "temporary":
		var remove: Dictionary = hazard.snapshot()["next"]
		assert_eq(str(remove["action"]), "retire_temporary_bypass")
		assert_true(bool(hazard.operate(str(remove["target"]),
			str(remove["action"]), facts).get("ok", false)))
		var premature: Dictionary = hazard.snapshot()["next"]
		assert_false(bool(hazard.operate(str(premature["target"]),
			str(premature["action"]), facts).get("ok", false)))
		for i: int in range(4):
			hazard.advance(facts)
	var final: Dictionary = hazard.snapshot()["next"]
	assert_true(bool(hazard.operate(str(final["target"]),
		str(final["action"]), facts).get("ok", false)))
	assert_true(hazard.solved())
	assert_eq(str(hazard.snapshot()["phase"]), "certified")
	assert_eq(hazard.snapshot()["next"], {})
	assert_true(hazard.snapshot()["history"].size() <= 24)
	return hazard.snapshot()


func test_EXP014_A07_200_sites_400_control_routes_and_5_real_mechanisms() -> void:
	var atlas: Dictionary = Atlas.load_catalog()
	var cases: Array[Dictionary] = _cases()
	var contingencies: Dictionary = Contingencies.load_book()
	assert_eq(cases.size(), 200)
	assert_eq(contingencies["entries"].size(), 200)
	var families: Dictionary = {}
	var original_task_ids: Dictionary = {}
	for serial: int in range(1, 201):
		var objects: Array = _configured(serial, atlas, cases, contingencies)
		var hazard: Hazards = objects[0]
		var outcome: Outcomes = objects[1]
		var original: Dictionary = objects[2]
		var audit: Dictionary = Hazards.inspect(
			outcome.definition_snapshot(), outcome.definition_snapshot(),
			objects[3])
		# The audit above deliberately uses wrong A05 proof: it must reject
		# the forged A05/A06 join rather than accepting same-shaped objects.
		assert_false(bool(audit.get("ok", false)))
		for task_id: Variant in original["source_task_ids"]:
			assert_false(original_task_ids.has(str(task_id)))
			original_task_ids[str(task_id)] = true
		for mode: String in Hazards.MODES:
			var run: Array = _configured(serial, atlas, cases, contingencies)
			var instance: Hazards = run[0]
			var operational: Outcomes = run[1]
			var route: String = "priority" if mode == "engineered" else "resilience"
			_start(instance, operational, original, mode, route)
			var terminal: Dictionary = _replay(instance, mode, route)
			var category: String = str(terminal["risk_class"])
			families[category] = int(families.get(category, 0)) + 1
			assert_eq(str(terminal["level_id"]), "LV_%03d" % serial)
			assert_eq(int(terminal["materials"]), 1 if mode == "engineered" else 2)
			assert_eq(str(terminal["mode"]), mode)
			assert_eq(str(terminal["route"]), route)
			assert_true(bool(terminal["solved"]))
	assert_eq(original_task_ids.size(), 1000)
	assert_eq(families.size(), 5)
	var scenario_count: int = 0
	for value: Variant in families.values():
		scenario_count += int(value)
	assert_eq(scenario_count, 400)


func test_EXP014_A07_source_mutations_and_recon_dependency_fail_closed() -> void:
	var atlas: Dictionary = Atlas.load_catalog()
	var cases: Array[Dictionary] = _cases()
	var contingency: Dictionary = Contingencies.load_book()
	var plan: Dictionary = Plan.make_plan(atlas["levels"][0], atlas["locations"][0])
	var recon: Recon = Recon.new()
	assert_true(bool(recon.configure(plan, cases[0]).get("ok", false)))
	var outcome: Outcomes = Outcomes.new()
	assert_true(bool(outcome.configure(recon.definition_snapshot(),
		contingency["entries"][0]).get("ok", false)))
	for field: String in ["level_id", "region_id", "source_risk", "targets", "source_task_ids"]:
		var bad: Dictionary = outcome.definition_snapshot()
		if field == "targets":
			bad[field] = {"A":"SC_999_A", "B":"SC_999_B", "C":"SC_999_C"}
		elif field == "source_task_ids":
			bad[field] = ["JOB_999_1"]
		else:
			bad[field] = "SPLICED"
		assert_false(bool(Hazards.inspect(recon.definition_snapshot(),
			bad, contingency["entries"][0]).get("ok", false)), field)
	var hazard: Hazards = Hazards.new()
	assert_true(bool(hazard.configure(recon.definition_snapshot(),
		outcome.definition_snapshot(), contingency["entries"][0]).get("ok", false)))
	assert_false(bool(hazard.begin({"level_id":"LV_001", "mode":"managed",
		"route":"priority", "phase":"monitor"}).get("ok", false)))
	_start(hazard, outcome, cases[0], "engineered", "priority")
	assert_false(bool(hazard.begin(outcome.snapshot()).get("ok", false)))
	var facts: Dictionary = _facts()
	var start: Dictionary = hazard.snapshot()["next"]
	assert_false(bool(hazard.operate("SC_999_A", "engineer_control", facts).get("ok", false)))
	assert_false(bool(hazard.operate(str(start["target"]), "verify_environment",
		facts).get("ok", false)))
	facts["worksite_opened"] = false
	assert_false(bool(hazard.operate(str(start["target"]), "engineer_control",
		facts).get("ok", false)))


func test_EXP014_A07_pressure_failure_authenticated_recovery_and_no_refund() -> void:
	var atlas: Dictionary = Atlas.load_catalog()
	var cases: Array[Dictionary] = _cases()
	var objects: Array = _configured(1, atlas, cases, Contingencies.load_book())
	var hazard: Hazards = objects[0]
	var outcome: Outcomes = objects[1]
	_start(hazard, outcome, cases[0], "engineered", "priority")
	var facts: Dictionary = _facts()
	var first: Dictionary = hazard.snapshot()["next"]
	assert_true(bool(hazard.operate(str(first["target"]), "engineer_control",
		facts).get("ok", false)))
	assert_eq(int(hazard.snapshot()["materials"]), 1)
	facts["logistics_solved"] = false
	hazard.advance(facts)
	assert_eq(str(hazard.snapshot()["phase"]), "fault")
	assert_false(hazard.can_operate())
	assert_false(bool(hazard.operate("SC_001_A", "recover", facts).get("ok", false)))
	assert_false(bool(hazard.operate("SC_001_C", "recover", facts).get("ok", false)))
	facts["logistics_solved"] = true
	assert_true(bool(hazard.operate("SC_001_C", "recover", facts).get("ok", false)))
	assert_eq(int(hazard.snapshot()["recoveries"]), 1)
	assert_eq(int(hazard.snapshot()["materials"]), 1,
		"An incident cannot refund spent site engineering materials")
	assert_eq(str(hazard.snapshot()["phase"]), "choice")
	# Continued failures are recoverable through temporary mode even if
	# the finite material stock has already been spent.
	var next: Dictionary = hazard.snapshot()["next"]
	assert_true(bool(hazard.operate(str(next["target"]), "temporary_bypass",
		facts).get("ok", false)))
	var guard: Dictionary = facts.duplicate(true)
	guard["balancing_solved"] = false
	var current: Dictionary = hazard.snapshot()["next"]
	assert_false(bool(hazard.operate(str(current["target"]),
		str(current["action"]), guard).get("ok", false)))
	assert_eq(int(hazard.snapshot()["step"]), 0)
	assert_true(bool(hazard.operate(str(current["target"]),
		str(current["action"]), facts).get("ok", false)))
	# A still-open field with temporary containment can escalate from real
	# host ticks; recovery requires re-proving the environmental procedure.
	for i: int in range(130):
		hazard.advance(facts)
		if str(hazard.snapshot()["phase"]) == "fault":
			break
	assert_eq(str(hazard.snapshot()["phase"]), "fault")
	assert_false(hazard.solved())
	assert_true(bool(hazard.operate("SC_001_C", "recover", facts).get("ok", false)))
	assert_eq(str(hazard.snapshot()["phase"]), "choice")


func test_EXP014_A07_runtime_opt_in_preserves_legacy_and_blocks_unsafe_work() -> void:
	for id: String in ["LV_001", "LV_101", "LV_200"]:
		var prior: Runtime = Runtime.new()
		var older: Dictionary = prior.start(id, Callable(self, "_position"),
			Callable(), "", false, "", true, true, true, true, true,
			true, true, true, true, true, true, true)
		assert_true(bool(older.get("ok", false)), str(older))
		if not bool(older.get("ok", false)):
			continue
		assert_true(prior.site_hazards == null)
		var active: Runtime = Runtime.new()
		var started: Dictionary = active.start(id, Callable(self, "_position"),
			Callable(), "", false, "", true, true, true, true, true,
			true, true, true, true, true, true, true, true)
		assert_true(bool(started.get("ok", false)), str(started))
		if not bool(started.get("ok", false)):
			continue
		assert_true(active.site_hazards != null)
		assert_true(str(started["content_revision"]).begins_with("EXP014_A07_"))
		assert_ne(str(started["content_revision"]), str(older["content_revision"]))
		assert_true(active.host.authoritative_state()["exp012_worksite_orders"].has("site_hazards"))
		var board: String = str(active.worksite.definition_snapshot()["board"])
		var decision: String = str(active.worksite.definition_snapshot()["decision"])
		assert_false(bool(active._operate_worksite("FORGED_PEER", board, "open").get("ok", false)))
		var blocked: Dictionary = active._operate_worksite(Runtime.PLAYER_ID,
			decision, "priority")
		assert_eq(str(blocked.get("code", "")), "EXP014_A07_HAZARD_LOCKED")
		assert_false(active.site_hazards.solved())
