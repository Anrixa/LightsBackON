extends "res://tests/test_case.gd"
## EXP016 A05 all 50 2-route casework completions require separate host signoff.

const Cases := preload("res://scripts/gameplay/expedition_advanced_casework.gd")
const Atlas := preload("res://scripts/world/dispatch_atlas.gd")
const Inquiry := preload("res://scripts/gameplay/expedition_investigation_chains.gd")

func _facts() -> Dictionary:
	return {"faults_solved": true, "balancing_solved": true,
		"logistics_solved": true, "consequences_solved": true}


func test_EXP016_A05_50_held_signoffs_two_routes() -> void:
	var books: Array[Dictionary] = Cases.load_available_books()
	assert_eq(books.size(), 4)
	var book: Dictionary = books[3]
	assert_true(bool(Cases.inspect(Atlas.load_catalog(), Inquiry.load_book(), book).get("ok", false)))
	for spec: Dictionary in book["entries"]:
		var targets: Dictionary = spec["targets"]
		for mode: String in ["forensic", "field"]:
			var work: Cases = Cases.new()
			assert_true(bool(work.configure(spec).get("ok", false)))
			assert_true(bool(work.begin().get("ok", false)))
			var choice: String = "A" if mode == "forensic" else "B"
			assert_true(bool(work.operate(str(targets[choice]), "case_" + mode, _facts()).get("ok", false)))
			for step: Dictionary in spec["routes"][mode]["steps"]:
				assert_true(bool(work.operate(str(targets[str(step["station"])]),
					"case_" + str(step["kind"]), _facts()).get("ok", false)))
			assert_eq(str(work.snapshot()["phase"]), "signoff")
			assert_false(work.solved())
			assert_false(bool(work.operate("SC_FORGED", "case_signoff", _facts()).get("ok", true)))
			var signoff: String = str(targets[str(spec["final_signoff_station"])])
			assert_false(bool(work.operate(signoff, "case_signoff", {}).get("ok", true)))
			assert_true(bool(work.operate(signoff, "case_signoff", _facts()).get("ok", false)))
			assert_true(work.solved())
