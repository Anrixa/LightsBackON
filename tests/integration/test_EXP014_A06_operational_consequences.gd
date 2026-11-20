extends "res://tests/test_case.gd"
## EXP014 A06 — 200 source-locked scenarios x two plans, five distinct
## risk-driven host evidence graphs, malicious commands and bounded recovery.
## Source/headless only; no human/controller/physical/playability certification.

const Atlas := preload("res://scripts/world/dispatch_atlas.gd")
const Plan := preload("res://scripts/world/expedition_layout_plan.gd")
const A02 := preload("res://scripts/gameplay/expedition_site_interventions.gd")
const EXP013 := preload("res://scripts/gameplay/expedition_site_exp013.gd")
const Contingencies := preload("res://scripts/gameplay/expedition_site_contingencies.gd")
const Recon := preload("res://scripts/gameplay/expedition_approach_intelligence.gd")
const Outcomes := preload("res://scripts/gameplay/expedition_operational_consequences.gd")
const Runtime := preload("res://scripts/gameplay/expedition_host_session.gd")


func _source_cases() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry: Dictionary in A02.load_book()["entries"]:
		result.append(entry)
	for book: Dictionary in EXP013.load_available_books():
		for entry: Dictionary in book["entries"]:
			result.append(entry)
	return result


func _facts(route: String = "priority") -> Dictionary:
	return {"worksite_opened": true, "worksite_route": route,
		"faults_solved": true, "balancing_solved": true,
		"logistics_solved": true, "consequences_solved": true,
		"site_intervention_solved": false,
		"site_contingency_solved": false}


func _recon_proof(source: Dictionary, route: String, approach: String) -> Dictionary:
	# This is a trusted host-state test fixture, not a caller-supplied wire
	# payload. An integration test below also checks actual runtime opt-in.
	return {"level_id": source["level_id"], "region_id": source["region_id"],
		"observed_risk": source["source_risk"], "solved": true,
		"route": route, "approach": approach}


func _host_position(_player: String) -> Vector3:
	return Vector3(35.0, 0.9, 35.0)


func _complete(candidate: Outcomes, mode: String, route: String) -> Dictionary:
	var facts: Dictionary = _facts(route)
	var first: Dictionary = candidate.snapshot()["next"]
	assert_eq(str(first["target"]), "SC_" + str(candidate.definition_snapshot()["level_id"]).trim_prefix("LV_") + "_A")
	var action: String = "buffer_service" if mode == "buffer" else "accept_managed_outage"
	assert_true(bool(candidate.operate(str(first["target"]), action, facts).get("ok", false)))
	assert_true(candidate.prepared())
	assert_false(candidate.solved())
	assert_false(candidate.needs_action(), "Existing intervention must proceed after planning")
	assert_false(bool(candidate.operate(str(first["target"]), "certify_service", facts).get("ok", false)),
		"Cannot finish from plan without source restoration")
	for i: int in range(16):
		candidate.advance(facts)
	facts["site_intervention_solved"] = true
	facts["site_contingency_solved"] = true
	candidate.advance(facts)
	assert_eq(candidate.snapshot()["phase"], "audit")
	var bounded: int = 0
	while not candidate.solved() and bounded < 20:
		var next: Dictionary = candidate.snapshot()["next"]
		assert_false(next.is_empty())
		for i: int in range(5):
			candidate.advance(facts)
		assert_true(bool(candidate.operate(str(next["target"]), str(next["action"]),
			facts).get("ok", false)), "Host refuses expected source evidence")
		bounded += 1
	assert_true(candidate.solved())
	assert_true(bounded >= int(candidate.snapshot()["total_audits"]) + 1)
	assert_eq(candidate.snapshot()["phase"], "certified")
	assert_false(candidate.needs_action())
	assert_true(candidate.snapshot()["history"].size() <= 16)
	return candidate.snapshot()


func test_EXP014_A06_200_sites_400_consequence_plans_and_5_risk_graphs() -> void:
	var atlas: Dictionary = Atlas.load_catalog()
	var originals: Array[Dictionary] = _source_cases()
	var contingencies: Dictionary = Contingencies.load_book()
	assert_eq(originals.size(), 200)
	assert_eq(contingencies["entries"].size(), 200)
	var families: Dictionary = {}
	var ids: Dictionary = {}
	for index: int in range(200):
		var source: Dictionary = originals[index]
		var level: Dictionary = atlas["levels"][index]
		var location: Dictionary = atlas["locations"][index]
		var plan: Dictionary = Plan.make_plan(level, location)
		var recon: Recon = Recon.new()
		assert_true(bool(recon.configure(plan, source).get("ok", false)))
		var definition: Dictionary = recon.definition_snapshot()
		var contingency: Dictionary = contingencies["entries"][index]
		var audit: Dictionary = Outcomes.inspect(definition, contingency)
		assert_true(bool(audit.get("ok", false)), str(audit))
		if not bool(audit.get("ok", false)):
			continue
		assert_false(ids.has(source["level_id"]))
		ids[source["level_id"]] = true
		for mode: String in Outcomes.MODES:
			var candidate: Outcomes = Outcomes.new()
			assert_true(bool(candidate.configure(definition, contingency).get("ok", false)))
			var route: String = "priority" if mode == "buffer" else "resilience"
			assert_true(bool(candidate.begin(_recon_proof(source, route,
				"urgent" if mode == "managed" else "guarded")).get("ok", false)))
			assert_false(candidate.solved())
			var final_state: Dictionary = _complete(candidate, mode, route)
			families[str(final_state["risk_class"])] = int(families.get(
				str(final_state["risk_class"]), 0)) + 1
			assert_eq(int(final_state["reserve"]), 1 if mode == "buffer" else 2)
			assert_eq(str(final_state["route"]), route)
			assert_eq(str(final_state["mode"]), mode)
			assert_eq(str(final_state["level_id"]), str(level["id"]))
		assert_eq(source, originals[index], "A06 must never rewrite original source cases")
	assert_eq(ids.size(), 200)
	assert_eq(families.size(), 5)
	assert_eq(int(families.values().reduce(func(a, b): return int(a) + int(b), 0)), 400)


func test_EXP014_A06_fail_closed_sources_and_no_untrusted_recon() -> void:
	var atlas: Dictionary = Atlas.load_catalog()
	var source: Dictionary = _source_cases()[0]
	var plan: Dictionary = Plan.make_plan(atlas["levels"][0], atlas["locations"][0])
	var recon: Recon = Recon.new()
	assert_true(bool(recon.configure(plan, source).get("ok", false)))
	var definition: Dictionary = recon.definition_snapshot()
	var contingency: Dictionary = Contingencies.load_book()["entries"][0]
	for mutation: String in ["level_id", "region_id", "source_risk", "source_task_ids", "targets"]:
		var forged: Dictionary = contingency.duplicate(true)
		if mutation == "source_task_ids":
			forged[mutation] = ["JOB_999_1"]
		elif mutation == "targets":
			forged[mutation] = {"A": "SC_999_A", "B": "SC_999_B", "C": "SC_999_C"}
		else:
			forged[mutation] = "SPLICED"
		assert_false(bool(Outcomes.inspect(definition, forged).get("ok", false)), mutation)
	var candidate: Outcomes = Outcomes.new()
	assert_true(bool(candidate.configure(definition, contingency).get("ok", false)))
	var bad: Dictionary = _recon_proof(source, "priority", "guarded")
	bad["solved"] = false
	assert_false(bool(candidate.begin(bad).get("ok", false)))
	bad = _recon_proof(source, "priority", "guarded")
	bad["observed_risk"] = "FORGED"
	assert_false(bool(candidate.begin(bad).get("ok", false)))
	assert_true(bool(candidate.begin(_recon_proof(source, "priority", "guarded")).get("ok", false)))
	assert_false(bool(candidate.begin(_recon_proof(source, "priority", "guarded")).get("ok", false)))
	var facts: Dictionary = _facts()
	facts["worksite_opened"] = false
	assert_false(bool(candidate.operate("SC_001_A", "buffer_service", facts).get("ok", false)))
	facts["worksite_opened"] = true
	assert_false(bool(candidate.operate("SC_001_B", "buffer_service", facts).get("ok", false)))
	assert_false(bool(candidate.operate("SC_001_A", "certify_service", facts).get("ok", false)))


func test_EXP014_A06_guard_loss_recovery_witness_and_route_binding() -> void:
	var atlas: Dictionary = Atlas.load_catalog()
	var source: Dictionary = _source_cases()[0]
	var recon: Recon = Recon.new()
	assert_true(bool(recon.configure(Plan.make_plan(
		atlas["levels"][0], atlas["locations"][0]), source).get("ok", false)))
	var candidate: Outcomes = Outcomes.new()
	assert_true(bool(candidate.configure(recon.definition_snapshot(),
		Contingencies.load_book()["entries"][0]).get("ok", false)))
	assert_true(bool(candidate.begin(_recon_proof(source, "priority", "urgent")).get("ok", false)))
	var facts: Dictionary = _facts()
	assert_true(bool(candidate.operate("SC_001_A", "buffer_service", facts).get("ok", false)))
	facts[str(candidate.definition_snapshot()["guard"])] = false
	candidate.advance(facts)
	assert_eq(str(candidate.snapshot()["phase"]), "fault")
	assert_false(bool(candidate.operate("SC_001_A", "recover", facts).get("ok", false)))
	assert_false(bool(candidate.operate("SC_001_C", "recover", facts).get("ok", false)))
	facts[str(candidate.definition_snapshot()["guard"])] = true
	assert_true(bool(candidate.operate("SC_001_C", "recover", facts).get("ok", false)))
	assert_eq(int(candidate.snapshot()["recoveries"]), 1)
	assert_eq(str(candidate.snapshot()["phase"]), "plan")
	assert_true(bool(candidate.operate("SC_001_A", "accept_managed_outage", facts).get("ok", false)))
	facts["site_intervention_solved"] = true
	facts["site_contingency_solved"] = true
	candidate.advance(facts)
	var first: Dictionary = candidate.snapshot()["next"]
	assert_false(bool(candidate.operate("SC_999_A", str(first["action"]), facts).get("ok", false)))
	assert_false(bool(candidate.operate(str(first["target"]), "FORGED", facts).get("ok", false)))
	assert_true(bool(candidate.operate(str(first["target"]), str(first["action"]), facts).get("ok", false)))
	var second: Dictionary = candidate.snapshot()["next"]
	assert_false(bool(candidate.operate(str(second["target"]), str(second["action"]),
		facts).get("ok", false), "Independent host witness requires elapsed ticks")
	for i: int in range(6):
		candidate.advance(facts)
	assert_true(bool(candidate.operate(str(second["target"]), str(second["action"]),
		facts).get("ok", false)))
	var bounded: int = 0
	while not candidate.solved() and bounded < 15:
		var next: Dictionary = candidate.snapshot()["next"]
		for i: int in range(6):
			candidate.advance(facts)
		if str(next["action"]) == "certify_service":
			var forged: Dictionary = facts.duplicate(true)
			forged["worksite_route"] = "resilience"
			assert_false(bool(candidate.operate(str(next["target"]), "certify_service",
				forged).get("ok", false)), "Strategy binding is host-owned")
		assert_true(bool(candidate.operate(str(next["target"]), str(next["action"]), facts).get("ok", false)))
		bounded += 1
	assert_true(candidate.solved())
	assert_eq(int(candidate.snapshot()["incidents"]), 1)


func test_EXP014_A06_runtime_opt_in_revision_and_original_hold() -> void:
	for id: String in ["LV_001", "LV_101", "LV_200"]:
		var prior: Runtime = Runtime.new()
		var old: Dictionary = prior.start(id, Callable(self, "_host_position"),
			Callable(), "", false, "", true, true, true, true, true,
			true, true, true, true, true, true)
		assert_true(bool(old.get("ok", false)), str(old))
		if not bool(old.get("ok", false)):
			continue
		assert_true(prior.site_outcomes == null)
		var current: Runtime = Runtime.new()
		var active: Dictionary = current.start(id, Callable(self, "_host_position"),
			Callable(), "", false, "", true, true, true, true, true,
			true, true, true, true, true, true, true)
		assert_true(bool(active.get("ok", false)), str(active))
		if not bool(active.get("ok", false)):
			continue
		assert_true(current.site_outcomes != null)
		assert_true(str(active["content_revision"]).begins_with("EXP014_A06_"))
		assert_ne(active["content_revision"], old["content_revision"])
		assert_true(current.host.authoritative_state()["exp012_worksite_orders"].has("site_outcomes"))
		var wo: String = str(current.worksite.definition_snapshot()["decision"])
		var bypass: Dictionary = current._operate_worksite(Runtime.PLAYER_ID, wo, "priority")
		assert_eq(str(bypass.get("code", "")), "EXP014_A06_CONSEQUENCE_PLAN_REQUIRED")
		assert_false(current.site_outcomes.solved())
