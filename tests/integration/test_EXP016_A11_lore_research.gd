extends "res://tests/test_case.gd"
## EXP016 A11 optional lore evidence; existing original receipt handler remains.

const Cases := preload("res://scripts/gameplay/expedition_advanced_casework.gd")
const Discoveries := preload("res://scripts/gameplay/expedition_advanced_discoveries.gd")
const Atlas := preload("res://scripts/world/dispatch_atlas.gd")
const Inquiry := preload("res://scripts/gameplay/expedition_investigation_chains.gd")

func _facts() -> Dictionary:
	return {"faults_solved":true,"consequences_solved":true}


func test_EXP016_A11_200_authentic_optional_lore_chains_and_duplicate_denials() -> void:
	var book: Dictionary = Discoveries.load_book()
	assert_true(bool(Discoveries.inspect(Atlas.load_catalog(),Inquiry.load_book(),
		book).get("ok",false)))
	var books: Array[Dictionary] = Cases.load_available_books()
	for serial: int in range(1,201):
		var id: String = "LV_%03d" % serial
		var source: Dictionary = {}
		for prior: Dictionary in books:
			var candidate: Dictionary = Cases.entry_for(prior,id)
			if not candidate.is_empty():
				source = candidate
		var find: Dictionary = Discoveries.entry_for(book,id)
		var host: Cases = Cases.new()
		assert_true(bool(host.configure(source).get("ok",false)))
		assert_true(bool(host.bind_source_discovery(find).get("ok",false)))
		assert_true(bool(host.begin().get("ok",false)))
		assert_false(host.discovery_ready())
		var targets: Dictionary = source["targets"]
		assert_false(bool(host.operate(str(targets["C"]),
			"case_discover_authenticate",_facts()).get("ok",true)))
		assert_true(bool(host.operate(str(targets["A"]),
			"case_discover_trace",_facts()).get("ok",false)))
		assert_false(bool(host.operate(str(targets["B"]),
			"case_discover_crosscheck",{}).get("ok",true)))
		assert_true(bool(host.operate(str(targets["B"]),
			"case_discover_crosscheck",_facts()).get("ok",false)))
		assert_true(bool(host.operate(str(targets["C"]),
			"case_discover_authenticate",_facts()).get("ok",false)))
		assert_true(host.discovery_ready())
		assert_false(bool(host.operate(str(targets["A"]),
			"case_discover_trace",_facts()).get("ok",true)))
		assert_eq(str(host.snapshot()["source_collectible_id"]),str(find["source_collectible_id"]))
