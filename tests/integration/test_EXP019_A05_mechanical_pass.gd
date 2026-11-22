extends "res://tests/test_case.gd"
const Atlas := preload("res://scripts/world/dispatch_atlas.gd")
const Plan := preload("res://scripts/world/expedition_layout_plan.gd")
const Mechanics := preload("res://scripts/gameplay/exp019_mechanical_pass.gd")
const Runtime := preload("res://scripts/gameplay/expedition_host_session.gd")
const Stage := preload("res://scenes/expeditions/mission_stage.tscn")


func _facts(good: bool = true, risk: String = "depth") -> Dictionary:
	return {"risk_class":risk, "grid_verified":good, "worksite_solved":good,
		"environment_safe":good, "east_enabled":good,
		"west_restored":good, "mission_completed":good,
		"diagnosis_confirmed":good}


func test_EXP019_A05_200_distinct_normalized_procedures_have_host_replay() -> void:
	var atlas: Dictionary = Atlas.load_catalog()
	var unique: Dictionary = {}
	var total: int = 0
	for index: int in range(200):
		var plan: Dictionary = Plan.make_plan(atlas["levels"][index], atlas["locations"][index])
		var audit: Dictionary = Mechanics.inspect(plan)
		assert_true(audit.get("ok", false), "source mechanism LV_%03d" % (index + 1))
		if not audit.get("ok", false):
			continue
		var structure: String = str(audit["structure"])
		assert_false(unique.has(structure), "no cosmetic-only duplicate solution")
		unique[structure] = true
		var mechanic: Mechanics = Mechanics.new()
		assert_true(mechanic.configure(plan).get("ok", false))
		for action: String in audit["sequence"]:
			var denied: Dictionary = mechanic.operate("invalid_order", _facts(true, str(audit["risk_class"])))
			assert_false(denied.get("ok", false))
			assert_true(mechanic.operate(action, _facts(true, str(audit["risk_class"]))).get("ok", false),
				"host action %s for LV_%03d" % [action, index + 1])
			total += 1
		assert_true(mechanic.solved())
		assert_false(mechanic.operate("prove", _facts(true, str(audit["risk_class"]))).get("ok", false))
	assert_eq(unique.size(), 200)
	assert_eq(total, 1280)


func test_EXP019_A05_cannot_forge_progress_and_recovers_without_rewards() -> void:
	var atlas: Dictionary = Atlas.load_catalog()
	var plan: Dictionary = Plan.make_plan(atlas["levels"][120], atlas["locations"][120])
	var machine: Mechanics = Mechanics.new()
	assert_true(machine.configure(plan).get("ok", false))
	var before: Dictionary = machine.snapshot()
	var risk: String = str(Mechanics.inspect(plan)["risk_class"])
	assert_false(machine.operate("refit", _facts(true, risk)).get("ok", false) if \
		str(machine.next_operation().get("action", "")) != "refit" else \
		machine.operate("bad_step", _facts(true, risk)).get("ok", false))
	assert_eq(machine.snapshot(), before)
	var first: String = str(machine.next_operation()["action"])
	assert_false(machine.operate(first, _facts(false, risk)).get("ok", false))
	assert_true(str(machine.snapshot()["fault"]) != "")
	assert_false(machine.operate(first, _facts(true, risk)).get("ok", false))
	# Recovery must not reset stock, worksite fault, or progress if it has a
	# foreign hazard-source classification—even when the other facts are safe.
	var before_foreign_recovery: Dictionary = machine.snapshot()
	var foreign_risk: String = "weather" if risk != "weather" else "depth"
	var rejected_recovery: Dictionary = machine.operate("recover", _facts(true, foreign_risk))
	assert_false(rejected_recovery.get("ok", false))
	assert_eq(str(rejected_recovery.get("code", "")), "EXP019_A05_HOST_SOURCE_RISK_MISMATCH")
	assert_eq(machine.snapshot(), before_foreign_recovery)
	assert_true(machine.operate("recover", _facts(true, risk)).get("ok", false))
	assert_eq(int(machine.snapshot()["recoveries"]), 1)
	assert_eq((machine.snapshot()["completed"] as Array).size(), 0)


func test_EXP019_A05_actual_stage_registers_host_worksite_not_new_rpc() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var root: Node3D = Node3D.new()
	tree.root.add_child(root)
	var stage: Node3D = Stage.instantiate()
	stage.set("level_id", "LV_140")
	root.add_child(stage)
	var session: Runtime = stage.get("runtime") as Runtime
	assert_true(session != null)
	if session != null:
		assert_true(session.site_mechanics != null)
		assert_true(session.task_board()["worksite"].has("site_mechanics"))
		assert_eq((session.site_mechanics.snapshot()["completed"] as Array).size(), 0)
		assert_false(session.site_mechanics.solved())
		# SessionHost must reject extraction before source-authoritative A05
		# procedure completion, regardless of a client completion claim.
		var refused_extract: Dictionary = stage.call(
			"_send", "request_extract", "ZONE_EXTRACT", {"action": "start"})
		assert_false(refused_extract.get("ok", false))
		assert_eq(str(refused_extract.get("code", "")), "EXP019_A05_MECHANICAL_PROOF_REQUIRED")
		# A client cannot reroute site actions onto another worksite board.
		var refused_board: Dictionary = stage.call(
			"_send", "operate_worksite", "WO_FORGED", {"action": "site_trace"})
		assert_false(refused_board.get("ok", false))
		assert_eq(str(refused_board.get("code", "")), "EXP019_A05_WRONG_AUTHORIZED_WORKSITE_BOARD")
		assert_eq(int(session.site_mechanics.snapshot()["revision"]), 0)
	root.remove_child(stage)
	stage.free()
	root.get_parent().remove_child(root)
	root.free()
