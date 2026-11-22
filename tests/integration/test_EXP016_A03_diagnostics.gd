extends "res://tests/test_case.gd"
## EXP016 A03: conflicting evidence must be gathered before source diagnosis.

const Cases := preload("res://scripts/gameplay/expedition_advanced_casework.gd")
const Atlas := preload("res://scripts/world/dispatch_atlas.gd")
const Inquiry := preload("res://scripts/gameplay/expedition_investigation_chains.gd")


func _facts() -> Dictionary:
	return {"faults_solved": true, "balancing_solved": true,
		"logistics_solved": true, "consequences_solved": true}


func test_EXP016_A03_50_two_probe_diagnoses_and_both_routes() -> void:
	var books: Array[Dictionary] = Cases.load_available_books()
	assert_eq(books.size(), 2)
	var book: Dictionary = books[1]
	var review: Dictionary = Cases.inspect(Atlas.load_catalog(), Inquiry.load_book(), book)
	assert_true(bool(review.get("ok", false)), str(review))
	for case_entry: Dictionary in book["entries"]:
		var targets: Dictionary = case_entry["targets"]
		for mode: String in ["forensic", "field"]:
			var machine: Cases = Cases.new()
			assert_true(bool(machine.configure(case_entry).get("ok", false)))
			assert_true(bool(machine.begin().get("ok", false)))
			assert_eq(str(machine.snapshot()["phase"]), "evidence")
			assert_false(bool(machine.operate(str(targets["C"]),
				"case_identify:" + str(case_entry["diagnosis"]["fault_class"]),
				_facts()).get("ok", true)))
			assert_true(bool(machine.operate(str(targets["A"]), "case_probe_a", _facts()).get("ok", false)))
			assert_true(bool(machine.operate(str(targets["B"]), "case_probe_b", _facts()).get("ok", false)))
			assert_true(bool(machine.operate(str(targets["C"]),
				"case_identify:" + str(case_entry["diagnosis"]["fault_class"]),
				_facts()).get("ok", false)))
			var pick: String = "A" if mode == "forensic" else "B"
			assert_true(bool(machine.operate(str(targets[pick]), "case_" + mode, _facts()).get("ok", false)))
			for step: Dictionary in case_entry["routes"][mode]["steps"]:
				assert_true(bool(machine.operate(str(targets[str(step["station"])]),
					"case_" + str(step["kind"]), _facts()).get("ok", false)))
			assert_true(machine.solved())


func test_EXP016_A03_wrong_diagnosis_has_recoverable_real_penalty() -> void:
	var case_entry: Dictionary = Cases.load_available_books()[1]["entries"][0]
	var machine: Cases = Cases.new()
	assert_true(bool(machine.configure(case_entry).get("ok", false)))
	assert_true(bool(machine.begin().get("ok", false)))
	var targets: Dictionary = case_entry["targets"]
	assert_true(bool(machine.operate(str(targets["A"]), "case_probe_a", _facts()).get("ok", false)))
	assert_true(bool(machine.operate(str(targets["B"]), "case_probe_b", _facts()).get("ok", false)))
	assert_false(bool(machine.operate(str(targets["C"]), "case_identify:incorrect", _facts()).get("ok", true)))
	assert_eq(str(machine.snapshot()["phase"]), "fault")
	assert_eq(int(machine.snapshot()["faults"]), 1)
	assert_false(bool(machine.operate(str(targets["A"]), "case_forensic", _facts()).get("ok", true)))
	assert_true(bool(machine.operate(str(targets["C"]), "case_recover", _facts()).get("ok", false)))
	assert_eq(str(machine.snapshot()["phase"]), "evidence")
	assert_eq(int(machine.snapshot()["liabilities"]), 1)
