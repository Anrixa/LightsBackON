extends "res://tests/test_case.gd"
## Source-only EXP016 A02 casework; no controller/hardware/release certification.

const Atlas := preload("res://scripts/world/dispatch_atlas.gd")
const Cases := preload("res://scripts/gameplay/expedition_advanced_casework.gd")
const Investigation := preload("res://scripts/gameplay/expedition_investigation_chains.gd")
const Runtime := preload("res://scripts/gameplay/expedition_host_session.gd")


func _facts() -> Dictionary:
	return {"faults_solved": true, "balancing_solved": true,
		"logistics_solved": true, "consequences_solved": true}


func _position(_player: String) -> Vector3:
	return Vector3(35.0, 0.9, 35.0)


func test_EXP016_A02_50_distinct_host_cases_both_routes() -> void:
	var catalog: Dictionary = Atlas.load_catalog()
	var source: Dictionary = Investigation.load_book()
	var book: Dictionary = Cases.load_book()
	var audit: Dictionary = Cases.inspect(catalog, source, book)
	assert_true(bool(audit.get("ok", false)), str(audit))
	assert_eq(int(audit.get("case_count", -1)), 50)
	assert_eq(int(audit.get("distinct_mechanics", -1)), 50)
	for entry: Dictionary in book["entries"]:
		for route: String in ["forensic", "field"]:
			var machine: Cases = Cases.new()
			assert_true(bool(machine.configure(entry).get("ok", false)))
			assert_false(machine.started())
			assert_true(bool(machine.begin().get("ok", false)))
			var targets: Dictionary = entry["targets"]
			var chooser: String = "A" if route == "forensic" else "B"
			var chosen: Dictionary = machine.operate(str(targets[chooser]), "case_" + route, _facts())
			assert_true(bool(chosen.get("ok", false)), str(chosen))
			var steps: Array = entry["routes"][route]["steps"]
			for step: Dictionary in steps:
				var result: Dictionary = machine.operate(str(targets[str(step["station"])]),
					"case_" + str(step["kind"]), _facts())
				assert_true(bool(result.get("ok", false)), str(result))
			assert_true(machine.solved())
			assert_eq(machine.snapshot()["completed_steps"].size(), steps.size())
			assert_false(bool(machine.operate(str(targets["A"]), "case_trace", _facts()).get("ok", true)))


func test_EXP016_A02_wrong_target_and_fault_do_not_skip_steps() -> void:
	var case_source: Dictionary = Cases.load_book()["entries"][0]
	var machine: Cases = Cases.new()
	assert_true(bool(machine.configure(case_source).get("ok", false)))
	assert_true(bool(machine.begin().get("ok", false)))
	assert_false(bool(machine.operate("SC_FORGED", "case_field", _facts()).get("ok", true)))
	assert_true(bool(machine.operate(str(case_source["targets"]["A"]),
		"case_forensic", _facts()).get("ok", false)))
	var first: Dictionary = case_source["routes"]["forensic"]["steps"][0]
	var rejected: Dictionary = machine.operate(
		str(case_source["targets"][str(first["station"])]), "case_" + str(first["kind"]), {})
	assert_false(bool(rejected.get("ok", true)))
	assert_eq(str(machine.snapshot()["phase"]), "fault")
	assert_eq(machine.snapshot()["completed_steps"].size(), 0)
	assert_false(bool(machine.operate("SC_FORGED", "case_recover", _facts()).get("ok", true)))
	assert_true(bool(machine.operate(str(case_source["recovery_target"]),
		"case_recover", _facts()).get("ok", false)))
	assert_eq(int(machine.snapshot()["recoveries"]), 1)
	assert_true(bool(machine.operate(str(case_source["targets"][str(first["station"])]),
		"case_" + str(first["kind"]), _facts()).get("ok", false)))


func test_EXP016_A02_host_opt_in_is_explicit_and_isolated() -> void:
	var no_puzzle: Runtime = Runtime.new()
	assert_false(bool(no_puzzle.start("LV_001", Callable(self, "_position"),
		Callable(), "", false, "", false, false, false, false, false,
		false, false, false, false, false, false, false, false, false,
		false, true).get("ok", true)))
	for id: String in ["LV_001", "LV_050"]:
		var runtime: Runtime = Runtime.new()
		var started: Dictionary = runtime.start(id, Callable(self, "_position"),
			Callable(), "", false, "", true, true, true, true, true,
			true, true, true, true, true, true, true, true, true,
			false, true)
		assert_true(bool(started.get("ok", false)), str(started))
		if not bool(started.get("ok", false)):
			continue
		assert_true(runtime.advanced_cases != null)
		assert_false(runtime.advanced_cases.solved())
		assert_true(str(started["content_revision"]).begins_with("EXP016_A02_"))
		assert_true(runtime.task_board().has("advanced_cases"))
		var worksite: Dictionary = runtime.worksite.definition_snapshot()
		var blocked: Dictionary = runtime._operate_worksite(Runtime.PLAYER_ID,
			str(worksite["decision"]), "priority")
		assert_false(bool(blocked.get("ok", false)))
