extends "res://tests/test_case.gd"
## EXP014 A04: all 200 risk-linked visual evidence sequences. Headless/source
## tests only; no physical, controller, render-quality or release acceptance.

const Atlas := preload("res://scripts/world/dispatch_atlas.gd")
const Plan := preload("res://scripts/world/expedition_layout_plan.gd")
const Region := preload("res://scripts/world/expedition_regional_facilities.gd")
const Evidence := preload("res://scripts/world/expedition_environment_feedback.gd")
const SiteA02 := preload("res://scripts/gameplay/expedition_site_interventions.gd")
const SiteEXP013 := preload("res://scripts/gameplay/expedition_site_exp013.gd")


func _cases() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for item: Dictionary in SiteA02.load_book()["entries"]:
		result.append(item)
	for book: Dictionary in SiteEXP013.load_available_books():
		for item: Dictionary in book["entries"]:
			result.append(item)
	return result


func _no_added_physics(node: Node) -> bool:
	if node is CollisionObject3D or node is CollisionShape3D or \
			node is NavigationRegion3D or node is Area3D:
		return false
	for child: Node in node.get_children():
		if not _no_added_physics(child):
			return false
	return true


func _setup_case(serial: int, source: Dictionary) -> Dictionary:
	var atlas: Dictionary = Atlas.load_catalog()
	var level: Dictionary = atlas["levels"][serial - 1]
	var location: Dictionary = atlas["locations"][serial - 1]
	var plan: Dictionary = Plan.make_plan(level, location)
	assert_true(bool(plan.get("ok", false)), "Planning %d" % serial)
	var root: Node3D = Region.build(plan)
	assert_true(root != null, "Region %d" % serial)
	if root == null:
		return {}
	var feedback: Node3D = Evidence.attach(plan, source, root)
	assert_true(feedback != null, "Evidence %d" % serial)
	return {"plan": plan, "regional": root, "feedback": feedback}


func test_EXP014_A04_all_200_sites_and_25_authored_risk_sequences() -> void:
	var sources: Array[Dictionary] = _cases()
	assert_eq(sources.size(), 200)
	var total: int = 0
	var regional: Dictionary = {}
	var clues: Dictionary = {}
	for serial: int in range(1, 201):
		var original: Dictionary = sources[serial - 1].duplicate(true)
		var scene: Dictionary = _setup_case(serial, original)
		if scene.is_empty():
			continue
		var plan: Dictionary = scene["plan"]
		var region: Node3D = scene["regional"]
		var feedback: Node3D = scene["feedback"]
		if feedback == null:
			region.free()
			continue
		assert_eq(feedback.get_child_count(), 3)
		assert_true(_no_added_physics(feedback),
			"No A04 host target, area, collider or navigation nodes")
		assert_eq(str(feedback.get_meta("source_level_id")), "LV_%03d" % serial)
		assert_eq(str(feedback.get_meta("source_risk")), str(plan["hazard"]))
		assert_eq(str(feedback.get_meta("qualification")), Evidence.QUALIFICATION)
		var region_id: String = str(plan["region_id"])
		regional[region_id] = true
		for i: int in range(3):
			var station: Node3D = feedback.get_node("EvidenceStage%d" % i) as Node3D
			var expected: String = str(original["source_task_ids"][[0, 2, 4][i]])
			assert_eq(str(station.get_meta("source_task_id")), expected)
			assert_eq(str(station.get_meta("visual_state")), "unverified")
			var cue: String = str(station.get_meta("evidence_clue"))
			# Every region owns one authored triad, reused at its eight source sites.
			# Duplicates across *different regions* are forbidden.
			if (serial - 1) % 8 == 0:
				assert_false(clues.has(cue), "No reused regional clue: " + cue)
				clues[cue] = true
			else:
				assert_true(clues.has(cue), "Within-region evidence must be stable")
		var host_state: Dictionary = {"level_id": str(plan["id"]),
			"route": "priority", "step": 1, "fault": "", "solved": false}
		var before: Dictionary = host_state.duplicate(true)
		assert_true(bool(Evidence.reflect(feedback, host_state).get("ok", false)))
		assert_eq(str(feedback.get_node("EvidenceStage0").get_meta("visual_state")),
			"host_verified")
		assert_eq(str(feedback.get_node("EvidenceStage1").get_meta("visual_state")),
			"host_in_progress")
		assert_eq(host_state, before, "Presentation may not modify host evidence")
		assert_eq(original, sources[serial - 1], "Original source case is immutable")
		assert_true(Evidence.attach(plan, original, region) == null,
			"Repeated attachment must not add ghost evidence stations")
		region.free()
		total += 1
	assert_eq(total, 200)
	assert_eq(regional.size(), 25)
	assert_eq(clues.size(), 75)


func test_EXP014_A04_host_fault_recovery_and_completion_are_visual_only() -> void:
	var sources: Array[Dictionary] = _cases()
	var scene: Dictionary = _setup_case(101, sources[100])
	var feedback: Node3D = scene["feedback"]
	var site: SiteA02 = SiteA02.new()
	assert_true(bool(site.configure(sources[100]).get("ok", false)))
	var original: Dictionary = site.snapshot()
	assert_true(bool(Evidence.reflect(feedback, original).get("ok", false)))
	assert_eq(site.snapshot(), original)
	assert_true(bool(site.choose_route("priority").get("ok", false)))
	var chosen: Dictionary = site.snapshot()
	assert_true(bool(Evidence.reflect(feedback, chosen).get("ok", false)))
	assert_eq(str(feedback.get_node("EvidenceStage0").get_meta("visual_state")),
		"host_in_progress")
	var next: Dictionary = chosen["next"]
	var facts: Dictionary = {"worksite_opened": true, "worksite_route": "priority",
		"balancing_solved": true, "logistics_solved": true,
		"consequences_solved": true, "faults_solved": true,
		"west_restored": true, "east_on": true, "hazard_active": false}
	assert_true(bool(site.operate(str(next["target"]),
		str(next["action"]), facts).get("ok", false)))
	assert_false(bool(site.operate(str(next["target"]),
		"confirm", facts).get("ok", true)))
	var faulted: Dictionary = site.snapshot()
	assert_ne(str(faulted["fault"]), "")
	assert_true(bool(Evidence.reflect(feedback, faulted).get("ok", false)))
	assert_eq(str(feedback.get_node("EvidenceStage0").get_meta("visual_state")),
		"fault")
	assert_eq(site.snapshot(), faulted, "A04 may never clear a host fault")
	assert_true(bool(site.operate(str(sources[100]["recovery_target"]),
		"recover", facts).get("ok", false)))
	var recovered: Dictionary = site.snapshot()
	assert_true(bool(Evidence.reflect(feedback, recovered).get("ok", false)))
	assert_eq(str(feedback.get_node("EvidenceStage0").get_meta("visual_state")),
		"host_in_progress")
	# Synthetic snapshots test the visual mapper, NOT an authenticated
	# host success. Real authentication is covered by EXP012/A02 host tests.
	var completed: Dictionary = recovered.duplicate(true)
	completed["solved"] = true
	completed["step"] = 4
	assert_true(bool(Evidence.reflect(feedback, completed).get("ok", false)))
	assert_eq(str(feedback.get_node("EvidenceStage2").get_meta("visual_state")),
		"host_verified")
	var contingency: Dictionary = {"level_id": "LV_101", "route": "resilience",
		"step": 1, "fault": "", "solved": false}
	assert_true(bool(Evidence.reflect(feedback, completed, contingency).get("ok", false)))
	assert_eq(str(feedback.get_meta("last_host_phase")), "contingency")
	assert_eq(str(feedback.get_node("EvidenceStage1").get_meta("visual_state")),
		"host_in_progress")
	scene["regional"].free()


func test_EXP014_A04_risk_task_scene_and_foreign_host_splices_fail_closed() -> void:
	var source: Dictionary = _cases()[0]
	var atlas: Dictionary = Atlas.load_catalog()
	var plan: Dictionary = Plan.make_plan(atlas["levels"][0], atlas["locations"][0])
	var region: Node3D = Region.build(plan)
	assert_true(region != null)
	if region == null:
		return
	var cross: Dictionary = source.duplicate(true)
	cross["source_task_ids"][0] = "JOB_200_1"
	assert_eq(str(Evidence.inspect(plan, cross, region)["code"]),
		"EXP014_A04_TASK_SPLICE")
	cross = source.duplicate(true)
	cross["source_risk"] = "fabricated hazard"
	assert_eq(str(Evidence.inspect(plan, cross, region)["code"]),
		"EXP014_A04_SOURCE_RISK_DRIFT")
	cross = source.duplicate(true)
	cross["level_id"] = "LV_099"
	assert_eq(str(Evidence.inspect(plan, cross, region)["code"]),
		"EXP014_A04_CASE_IDENTITY_DRIFT")
	var feedback: Node3D = Evidence.attach(plan, source, region)
	assert_true(feedback != null)
	if feedback != null:
		var before: String = str(feedback.get_node("EvidenceStage0").get_meta("visual_state"))
		var foreign: Dictionary = {"level_id": "LV_002", "route": "priority",
			"step": 2, "fault": "", "solved": false}
		assert_eq(str(Evidence.reflect(feedback, foreign)["code"]),
			"EXP014_A04_HOST_LEVEL_MISMATCH")
		var spoof: Dictionary = {"level_id": "LV_001", "route": "invented",
			"step": 2, "fault": "", "solved": false}
		assert_eq(str(Evidence.reflect(feedback, spoof)["code"]),
			"EXP014_A04_INVALID_HOST_ROUTE")
		assert_eq(str(feedback.get_node("EvidenceStage0").get_meta("visual_state")),
			before, "Untrusted inputs cannot mutate even a visual indicator")
	region.free()
