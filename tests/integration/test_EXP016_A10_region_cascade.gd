extends "res://tests/test_case.gd"
## EXP016 A10 cross-location host consequence flow; no durable save claims.

const Cascade := preload("res://scripts/gameplay/expedition_advanced_cascade.gd")
const Atlas := preload("res://scripts/world/dispatch_atlas.gd")
const Networks := preload("res://scripts/gameplay/expedition_regional_network.gd")
const Cases := preload("res://scripts/gameplay/expedition_advanced_casework.gd")

func _source_result(level_id: String, debt: int, settled: bool = true) -> Dictionary:
	return {"level_id":level_id,"phase":"solved","service_policy":"priority",
		"service_debt":debt,"faults":0,"inherited_pressure_settled":settled}


func test_EXP016_A10_25_source_regions_flow_and_owner_isolation() -> void:
	Cascade.reset_for_test()
	var source: Dictionary = Cascade.load_book()
	assert_true(bool(Cascade.inspect(Atlas.load_catalog(),Networks.load_book(),
		source).get("ok",false)))
	for region: Dictionary in source["regions"]:
		var root_id: String = str(region["site_ids"][0])
		var second_id: String = str(region["site_ids"][1])
		var separate_id: String = str(region["site_ids"][2])
		var account: String = "ACCOUNT_" + str(region["region_id"])
		var root: Cascade = Cascade.new()
		assert_true(bool(root.configure(region, account, root_id).get("ok",false)))
		assert_eq(int(root.snapshot()["inherited_pressure"]),0)
		assert_false(bool(root.record_host_completion({"phase":"solved"}).get("ok",true)))
		var earned: Dictionary = _source_result(root_id,1)
		assert_true(bool(root.record_host_completion(earned).get("ok",false)))
		assert_eq(str(root.record_host_completion(earned)["code"]),"IDEMPOTENT_HOST_RESULT")
		assert_false(bool(root.record_host_completion(_source_result(root_id,0)).get("ok",true)))
		var later: Cascade = Cascade.new()
		assert_true(bool(later.configure(region, account, second_id).get("ok",false)))
		assert_eq(int(later.snapshot()["inherited_pressure"]),1)
		assert_false(bool(later.record_host_completion(
			_source_result(second_id,0,false)).get("ok",true)))
		assert_true(bool(later.record_host_completion(
			_source_result(second_id,0,true)).get("ok",false)))
		var sibling: Cascade = Cascade.new()
		assert_true(bool(sibling.configure(region, account, separate_id).get("ok",false)))
		assert_eq(int(sibling.snapshot()["inherited_pressure"]),1)
		var other: Cascade = Cascade.new()
		assert_true(bool(other.configure(region, account + "_OTHER", second_id).get("ok",false)))
		assert_eq(int(other.snapshot()["inherited_pressure"]),0)
	Cascade.reset_for_test()


func test_EXP016_A10_region_pressure_requires_new_source_settlement() -> void:
	var cases: Array[Dictionary] = Cases.load_available_books()
	var entry: Dictionary = Cases.entry_for(cases[0],"LV_001")
	var work: Cases = Cases.new()
	assert_true(bool(work.configure(entry).get("ok",false)))
	assert_true(bool(work.bind_inherited_pressure(1).get("ok",false)))
	assert_false(bool(work.snapshot()["inherited_pressure_settled"]))
	assert_false(bool(work.operate(str(entry["targets"]["C"]),
		"case_settle_debt",{}).get("ok",true)))
