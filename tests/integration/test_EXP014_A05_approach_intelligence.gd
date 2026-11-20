extends "res://tests/test_case.gd"
## EXP014 A05: 400 host-state route rehearsals, 25 real regional protocols,
## source/decision mutation, recovery and non-physics approach projection.
## These are NOT human/controller, reach/collision, GPU or release tests.

const Atlas := preload("res://scripts/world/dispatch_atlas.gd")
const Plan := preload("res://scripts/world/expedition_layout_plan.gd")
const A02 := preload("res://scripts/gameplay/expedition_site_interventions.gd")
const EXP013 := preload("res://scripts/gameplay/expedition_site_exp013.gd")
const Recon := preload("res://scripts/gameplay/expedition_approach_intelligence.gd")
const View := preload("res://scripts/world/expedition_approach_view.gd")
const Runtime := preload("res://scripts/gameplay/expedition_host_session.gd")


func _cases() -> Array[Dictionary]:
	var cases: Array[Dictionary] = []
	for entry: Dictionary in A02.load_book()["entries"]:
		cases.append(entry)
	for book: Dictionary in EXP013.load_available_books():
		for entry: Dictionary in book["entries"]:
			cases.append(entry)
	return cases


func _facts() -> Dictionary:
	return {"worksite_opened": true, "balancing_solved": true,
		"logistics_solved": true, "faults_solved": true,
		"consequences_solved": true}


func _host_position(_player_id: String) -> Vector3:
	return Vector3(35.0, 0.9, 35.0)


func _plan(serial: int, atlas: Dictionary) -> Dictionary:
	return Plan.make_plan(atlas["levels"][serial - 1], atlas["locations"][serial - 1])


func _no_physics(node: Node) -> bool:
	if node is CollisionObject3D or node is CollisionShape3D or \
			node is NavigationRegion3D or node is Area3D:
		return false
	for child: Node in node.get_children():
		if not _no_physics(child):
			return false
	return true


## All actions are computed from the HOST snapshot; the test fixture can
## advance host ticks, but a network caller has no elapsed/phase/verdict field.
func _replay(recon: Recon, route: String, approach: String = "guarded") -> void:
	var facts: Dictionary = _facts()
	var next: Dictionary = recon.snapshot()["next"]
	assert_true(bool(recon.operate(str(next["target"]),
		"approach_" + approach, facts).get("ok", false)))
	for i: int in range(4 if approach == "guarded" else 1):
		recon.advance(facts)
	next = recon.snapshot()["next"]
	assert_true(bool(recon.operate(str(next["target"]),
		"establish_access", facts).get("ok", false)))
	var bounded: int = 0
	while str(recon.snapshot()["phase"]) == "investigate" and bounded < 6:
		next = recon.snapshot()["next"]
		# The first reading is immediate; all subsequent probes demand the
		# source-authored independently timed witness gap.
		if int(recon.snapshot()["step"]) > 0:
			for i: int in range(int(recon.definition_snapshot()["profile"]["gap"])):
				recon.advance(facts)
		assert_true(bool(recon.operate(str(next["target"]),
			str(next["action"]), facts).get("ok", false)))
		bounded += 1
	assert_eq(str(recon.snapshot()["phase"]), "decision")
	next = recon.snapshot()["next"]
	assert_true(bool(recon.operate(str(next["target"]),
		"commit_" + route, facts).get("ok", false)))
	bounded = 0
	while str(recon.snapshot()["phase"]) == "prepare" and bounded < 5:
		next = recon.snapshot()["next"]
		if bounded > 0:
			for i: int in range(3):
				recon.advance(facts)
		assert_true(bool(recon.operate(str(next["target"]),
			str(next["action"]), facts).get("ok", false)))
		bounded += 1
	assert_true(recon.solved(), "Host recon must reach certification")
	assert_eq(recon.selected_route(), route)
	assert_eq(recon.snapshot()["next"], {})


func test_EXP014_A05_200_source_sites_25_protocols_and_400_decisions() -> void:
	var atlas: Dictionary = Atlas.load_catalog()
	var cases: Array[Dictionary] = _cases()
	assert_eq(cases.size(), 200)
	var signatures: Dictionary = {}
	for serial: int in range(1, 201):
		var plan: Dictionary = _plan(serial, atlas)
		var source: Dictionary = cases[serial - 1].duplicate(true)
		var audit: Dictionary = Recon.inspect(plan, source)
		assert_true(bool(audit.get("ok", false)), "%s %s" % [str(plan.get("id")), str(audit)])
		if not bool(audit.get("ok", false)):
			continue
		var profile: Dictionary = Recon.PROFILES[str(plan["region_id"])]
		var signature: String = "%s|%s|%s|%s|%s|%s" % [
			profile["entry"], profile["first"], profile["second"],
			profile["guard"], profile["protocol"], profile["recommend"]]
		if (serial - 1) % 8 == 0:
			assert_false(signatures.has(signature),
				"Each of 25 regional approaches needs a distinct mechanical signature")
			signatures[signature] = true
		for route: String in ["priority", "resilience"]:
			var recon: Recon = Recon.new()
			assert_true(bool(recon.configure(plan, source).get("ok", false)))
			assert_false(recon.solved())
			assert_eq(str(recon.snapshot()["recommended_route"]), "",
				"Do not disclose uninvestigated route intelligence")
			_replay(recon, route)
			assert_true(bool(recon.snapshot()["intel_revealed"]))
		assert_eq(source, cases[serial - 1], "Source book must stay immutable")
	assert_eq(signatures.size(), 25)


func test_EXP014_A05_urgent_entry_and_nonrecommended_route_add_witness_work() -> void:
	var atlas: Dictionary = Atlas.load_catalog()
	var source: Dictionary = _cases()[0]
	var guarded: Recon = Recon.new()
	var urgent: Recon = Recon.new()
	assert_true(bool(guarded.configure(_plan(1, atlas), source).get("ok", false)))
	assert_true(bool(urgent.configure(_plan(1, atlas), source).get("ok", false)))
	_replay(guarded, "resilience", "guarded")
	_replay(urgent, "priority", "urgent")
	assert_eq(guarded.selected_route(), "resilience")
	assert_eq(urgent.selected_route(), "priority")
	assert_true(int(urgent.snapshot()["tick"]) < 20,
		"Urgent procedure is bounded but not free of witness obligations")


func test_EXP014_A05_evidence_gap_expiry_fault_and_authenticated_recovery() -> void:
	var atlas: Dictionary = Atlas.load_catalog()
	var source: Dictionary = _cases()[0]
	var recon: Recon = Recon.new()
	assert_true(bool(recon.configure(_plan(1, atlas), source).get("ok", false)))
	var facts: Dictionary = _facts()
	var start: Dictionary = recon.snapshot()["next"]
	var missing: Dictionary = facts.duplicate(true)
	missing["worksite_opened"] = false
	assert_eq(str(recon.operate(str(start["target"]),
		"approach_guarded", missing)["code"]), "EXP014_A05_OPEN_WORKSITE_FIRST")
	assert_true(bool(recon.operate(str(start["target"]),
		"approach_guarded", facts).get("ok", false)))
	assert_eq(str(recon.operate(str(start["target"]),
		"establish_access", facts)["code"]), "EXP014_A05_APPROACH_NOT_STABLE")
	for i: int in range(4):
		recon.advance(facts)
	assert_true(bool(recon.operate(str(start["target"]),
		"establish_access", facts).get("ok", false)))
	var first: Dictionary = recon.snapshot()["next"]
	assert_true(bool(recon.operate(str(first["target"]),
		str(first["action"]), facts).get("ok", false)))
	var before: Dictionary = recon.snapshot()
	var second: Dictionary = before["next"]
	assert_eq(str(recon.operate(str(second["target"]),
		str(second["action"]), facts)["code"]), "EXP014_A05_WITNESS_GAP")
	assert_eq(recon.snapshot()["step"], before["step"], "No fabricated evidence")
	for i: int in range(11):
		recon.advance(facts)
	assert_eq(str(recon.snapshot()["fault"]), "READOUT_EXPIRED")
	assert_eq(str(recon.operate(str(start["target"]), "recover", facts)["code"]),
		"EXP014_A05_RECOVERY_REQUIRED")
	assert_true(bool(recon.operate(str(source["recovery_target"]),
		"recover", facts).get("ok", false)))
	assert_eq(str(recon.snapshot()["phase"]), "arrival")
	assert_false(bool(recon.snapshot()["intel_revealed"]))
	assert_eq(int(recon.snapshot()["recoveries"]), 1)
	_replay(recon, "resilience")


func test_EXP014_A05_source_task_target_region_and_risk_mutations_are_rejected() -> void:
	var atlas: Dictionary = Atlas.load_catalog()
	var source: Dictionary = _cases()[8]
	var plan: Dictionary = _plan(9, atlas)
	var wrong: Dictionary = source.duplicate(true)
	wrong["source_task_ids"][0] = "JOB_200_1"
	assert_eq(str(Recon.inspect(plan, wrong)["code"]), "EXP014_A05_TASK_SPLICE")
	wrong = source.duplicate(true)
	wrong["targets"]["B"] = "SC_008_B"
	assert_eq(str(Recon.inspect(plan, wrong)["code"]), "EXP014_A05_TARGET_SPLICE")
	wrong = source.duplicate(true)
	wrong["source_risk"] = "fabricated evidence"
	assert_eq(str(Recon.inspect(plan, wrong)["code"]), "EXP014_A05_SOURCE_IDENTITY_DRIFT")
	wrong = source.duplicate(true)
	wrong["region_id"] = "REG_01"
	assert_eq(str(Recon.inspect(plan, wrong)["code"]), "EXP014_A05_SOURCE_IDENTITY_DRIFT")
	var original: Recon = Recon.new()
	assert_true(bool(original.configure(plan, source).get("ok", false)))
	assert_eq(str(original.operate("SC_999_A", "approach_guarded", _facts())["code"]),
		"EXP014_A05_UNKNOWN_TARGET")
	assert_false(original.solved())


func test_EXP014_A05_approach_geometry_is_host_observed_and_noncolliding() -> void:
	var atlas: Dictionary = Atlas.load_catalog()
	var cases: Array[Dictionary] = _cases()
	for serial: int in range(1, 201):
		var plan: Dictionary = _plan(serial, atlas)
		var source: Dictionary = cases[serial - 1]
		var positions: Dictionary = {
			str(source["targets"]["A"]): Vector3(17.0, 1.0, 18.0),
			str(source["targets"]["B"]): Vector3(24.0, 1.0, 23.0),
			str(source["targets"]["C"]): Vector3(30.0, 1.0, 29.0)}
		var view: Node3D = View.build(plan, source, positions)
		assert_true(view != null, "View %d" % serial)
		if view == null:
			continue
		assert_true(_no_physics(view), "No added scene collision or interaction")
		assert_eq(str(view.get_meta("source_risk")), str(plan["hazard"]))
		var recon: Recon = Recon.new()
		assert_true(bool(recon.configure(plan, source).get("ok", false)))
		var original: Dictionary = recon.snapshot()
		assert_true(bool(View.reflect(view, original).get("ok", false)))
		assert_eq(recon.snapshot(), original, "Scene cannot mutate the host")
		var forged: Dictionary = original.duplicate(true)
		forged["level_id"] = "LV_999"
		assert_eq(str(View.reflect(view, forged)["code"]), "EXP014_A05_FOREIGN_HOST_STATE")
		assert_eq(str(view.get_meta("host_phase")), "arrival")
		view.free()


func test_EXP014_A05_opt_in_preserves_previous_runtime_and_route_lock() -> void:
	for serial: int in [1, 101, 200]:
		var old: Runtime = Runtime.new()
		var older: Dictionary = old.start("LV_%03d" % serial,
			Callable(self, "_host_position"), Callable(), "", false, "",
			true, true, true, true, true, true, true, true, true, true)
		assert_true(bool(older.get("ok", false)), str(older))
		if not bool(older.get("ok", false)):
			continue
		assert_true(old.site_approach == null)
		var active: Runtime = Runtime.new()
		var newer: Dictionary = active.start("LV_%03d" % serial,
			Callable(self, "_host_position"), Callable(), "", false, "",
			true, true, true, true, true, true, true, true, true, true, true)
		assert_true(bool(newer.get("ok", false)), str(newer))
		if not bool(newer.get("ok", false)):
			continue
		assert_true(active.site_approach != null)
		assert_true(str(newer["content_revision"]).begins_with("EXP014_A05_"))
		assert_ne(newer["content_revision"], older["content_revision"])
		assert_true(active.host.authoritative_state()["exp012_worksite_orders"].has(
			"site_approach"))
		var choice: String = str(active.worksite.definition_snapshot()["decision"])
		var rejected: Dictionary = active._operate_worksite(Runtime.PLAYER_ID,
			choice, "priority")
		assert_eq(str(rejected["code"]), "EXP014_A05_RECON_OR_ROUTE_UNVERIFIED")
		assert_false(active.site_approach.solved())
