extends "res://tests/test_case.gd"
## EXP016 A06: all 200 sourced primary + environmental fault conditions.

const Cases := preload("res://scripts/gameplay/expedition_advanced_casework.gd")
const FaultLayers := preload("res://scripts/gameplay/expedition_advanced_fault_layers.gd")
const Atlas := preload("res://scripts/world/dispatch_atlas.gd")
const OriginalFaults := preload("res://scripts/gameplay/expedition_fault_diagnostics.gd")
const Encounters := preload("res://scripts/gameplay/expedition_bespoke_mechanics.gd")

func _facts() -> Dictionary:
	return {"faults_solved":true,"hazard_safe":true,
		"balancing_solved":true,"logistics_solved":true,"consequences_solved":true}


func test_EXP016_A06_200_true_source_dual_fault_cases() -> void:
	var book: Dictionary = FaultLayers.load_book()
	var audit: Dictionary = FaultLayers.inspect(Atlas.load_catalog(),
		OriginalFaults.load_book(), Encounters.load_book(), book)
	assert_true(bool(audit.get("ok", false)), str(audit))
	var cases: Array[Dictionary] = Cases.load_available_books()
	assert_eq(cases.size(), 4)
	for j: int in range(200):
		var level_id: String = "LV_%03d" % (j + 1)
		var original: Dictionary = {}
		for casebook: Dictionary in cases:
			var candidate: Dictionary = Cases.entry_for(casebook, level_id)
			if not candidate.is_empty():
				original = candidate
		assert_false(original.is_empty())
		var work: Cases = Cases.new()
		assert_true(bool(work.configure(original).get("ok", false)))
		var layer: Dictionary = FaultLayers.entry_for(book, level_id)
		assert_true(bool(work.bind_fault_layer(layer).get("ok", false)))
		assert_true(bool(work.begin().get("ok", false)))
		var targets: Dictionary = original["targets"]
		assert_false(bool(work.operate(str(targets["C"]), "case_diagnose_dual:" +
			str(layer["primary_fault_class"]) + ":" + str(layer["secondary_fault_class"]),
			_facts()).get("ok", true)))
		assert_true(bool(work.operate(str(targets["A"]), "case_fault_primary", _facts()).get("ok", false)))
		assert_true(bool(work.operate(str(targets["B"]), "case_fault_secondary", _facts()).get("ok", false)))
		assert_true(bool(work.operate(str(targets["C"]), "case_diagnose_dual:" +
			str(layer["primary_fault_class"]) + ":" + str(layer["secondary_fault_class"]),
			_facts()).get("ok", false)))
		assert_true(bool(work.snapshot()["layer_diagnosed"]))
		assert_eq(str(work.snapshot()["phase"]), "evidence" if original.has("diagnosis") else "choose")
