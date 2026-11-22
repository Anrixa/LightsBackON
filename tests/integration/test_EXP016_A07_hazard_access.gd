extends "res://tests/test_case.gd"
## A07 200 source-anchored hazard operations; actual world LOS held.

const Cases := preload("res://scripts/gameplay/expedition_advanced_casework.gd")
const Hazards := preload("res://scripts/gameplay/expedition_advanced_hazards.gd")
const Atlas := preload("res://scripts/world/dispatch_atlas.gd")
const Encounters := preload("res://scripts/gameplay/expedition_bespoke_mechanics.gd")
const Contingencies := preload("res://scripts/gameplay/expedition_site_contingencies.gd")


func _facts(safe: bool) -> Dictionary:
	return {"hazard_safe":safe,"faults_solved":true,"consequences_solved":true}


func test_EXP016_A07_200_hazard_order_and_unsafe_denial() -> void:
	var book: Dictionary = Hazards.load_book()
	assert_true(bool(Hazards.inspect(Atlas.load_catalog(),Encounters.load_book(),
		Contingencies.load_book(),book).get("ok",false)))
	var books: Array[Dictionary] = Cases.load_available_books()
	for id: int in range(1,201):
		var level_id: String = "LV_%03d" % id
		var original: Dictionary = {}
		for src: Dictionary in books:
			var maybe: Dictionary = Cases.entry_for(src,level_id)
			if not maybe.is_empty():
				original = maybe
		var policy: Dictionary = Hazards.entry_for(book,level_id)
		var work: Cases = Cases.new()
		assert_true(bool(work.configure(original).get("ok",false)))
		assert_true(bool(work.bind_hazard_protocol(policy).get("ok",false)))
		assert_true(bool(work.begin().get("ok",false)))
		assert_eq(str(work.snapshot()["phase"]),"hazard_preflight")
		var targets: Dictionary = original["targets"]
		assert_false(bool(work.operate(str(targets[policy["clear_station"]]),
			"case_hazard_clear", _facts(true)).get("ok",true)))
		for op: String in ["survey","isolate"]:
			var station: String = str(policy[op + "_station"])
			assert_true(bool(work.operate(str(targets[station]),
				"case_hazard_" + op,_facts(false)).get("ok",false)))
		assert_false(bool(work.operate(str(targets[policy["clear_station"]]),
			"case_hazard_clear",_facts(false)).get("ok",true)))
		assert_eq(str(work.snapshot()["phase"]),"hazard_preflight")
		assert_true(bool(work.operate(str(targets[policy["clear_station"]]),
			"case_hazard_clear",_facts(true)).get("ok",false)))
		assert_ne(str(work.snapshot()["phase"]),"hazard_preflight")
