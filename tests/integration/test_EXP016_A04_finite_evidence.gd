extends "res://tests/test_case.gd"
## EXP016 A04: one-shot finite evidence tokens across 50 source cases.

const Cases := preload("res://scripts/gameplay/expedition_advanced_casework.gd")
const Atlas := preload("res://scripts/world/dispatch_atlas.gd")
const Inquiry := preload("res://scripts/gameplay/expedition_investigation_chains.gd")

func _facts() -> Dictionary:
	return {"faults_solved": true, "balancing_solved": true,
		"logistics_solved": true, "consequences_solved": true}


func test_EXP016_A04_50_finite_resource_cases_and_both_routes() -> void:
	var available: Array[Dictionary] = Cases.load_available_books()
	assert_true(available.size() >= 3)
	var book: Dictionary = available[2]
	assert_true(bool(Cases.inspect(Atlas.load_catalog(), Inquiry.load_book(), book).get("ok", false)))
	for entry: Dictionary in book["entries"]:
		var targets: Dictionary = entry["targets"]
		for mode: String in ["forensic", "field"]:
			var work: Cases = Cases.new()
			assert_true(bool(work.configure(entry).get("ok", false)))
			assert_true(bool(work.begin().get("ok", false)))
			var route_station: String = "A" if mode == "forensic" else "B"
			assert_true(bool(work.operate(str(targets[route_station]),
				"case_" + mode, _facts()).get("ok", false)))
			var steps: Array = entry["routes"][mode]["steps"]
			for step: Dictionary in steps:
				var reply: Dictionary = work.operate(str(targets[str(step["station"])]),
					"case_" + str(step["kind"]), _facts())
				assert_true(bool(reply.get("ok", false)), str(reply))
			assert_true(work.solved())
			var held: Dictionary = work.snapshot()["evidence_tokens"]
			for token: String in held:
				assert_eq(int(held[token]), 0)


func test_EXP016_A04_foreign_step_rejected_without_consuming_permit() -> void:
	var entry: Dictionary = Cases.load_available_books()[2]["entries"][0]
	var work: Cases = Cases.new()
	assert_true(bool(work.configure(entry).get("ok", false)))
	assert_true(bool(work.begin().get("ok", false)))
	assert_true(bool(work.operate(str(entry["targets"]["A"]), "case_forensic", _facts()).get("ok", false)))
	var before: Dictionary = work.snapshot()["evidence_tokens"]
	assert_false(bool(work.operate("SC_FORGED", "case_trace", _facts()).get("ok", true)))
	assert_eq(work.snapshot()["evidence_tokens"], before)
