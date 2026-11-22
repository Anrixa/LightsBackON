extends "res://tests/test_case.gd"
## EXP016 A09: two original source policies produce distinct real host state.

const Cases := preload("res://scripts/gameplay/expedition_advanced_casework.gd")
const Policy := preload("res://scripts/gameplay/expedition_advanced_policies.gd")
const Atlas := preload("res://scripts/world/dispatch_atlas.gd")
const Contingencies := preload("res://scripts/gameplay/expedition_site_contingencies.gd")

func _facts() -> Dictionary:
	return {"faults_solved":true,"consequences_solved":true,
		"balancing_solved":true,"logistics_solved":true,
		"load_balanced":true,"supplies_ready":true,"cascade_stable":true,"fault_clear":true}


func test_EXP016_A09_200_real_nonlinear_service_policies() -> void:
	var book: Dictionary = Policy.load_book()
	assert_true(bool(Policy.inspect(Atlas.load_catalog(),
		Contingencies.load_book(),book).get("ok",false)))
	var available: Array[Dictionary] = Cases.load_available_books()
	for serial: int in range(1,201):
		var level_id: String = "LV_%03d" % serial
		var case_source: Dictionary = {}
		for source: Dictionary in available:
			var found: Dictionary = Cases.entry_for(source,level_id)
			if not found.is_empty():
				case_source = found
		var policy: Dictionary = Policy.entry_for(book,level_id)
		var targets: Dictionary = case_source["targets"]
		for choice: String in ["priority","resilience"]:
			var work: Cases = Cases.new()
			assert_true(bool(work.configure(case_source).get("ok",false)))
			assert_true(bool(work.bind_source_policy(policy).get("ok",false)))
			assert_true(bool(work.begin().get("ok",false)))
			if case_source.has("diagnosis"):
				assert_true(bool(work.operate(str(targets["A"]),
					"case_probe_a",_facts()).get("ok",false)))
				assert_true(bool(work.operate(str(targets["B"]),
					"case_probe_b",_facts()).get("ok",false)))
				assert_true(bool(work.operate(str(targets["C"]),
					"case_identify:" + str(case_source["diagnosis"]["fault_class"]),
					_facts()).get("ok",false)))
			assert_eq(str(work.snapshot()["phase"]),"policy_choose")
			var mode: String = str(policy["options"][choice]["route"])
			assert_false(bool(work.operate(str(targets["A"]),
				"case_" + mode,_facts()).get("ok",true)))
			var option: Dictionary = policy["options"][choice]
			var station: String = str(targets[str(option["station"])])
			assert_false(bool(work.operate(station,"case_policy:" + choice,{}).get("ok",true)))
			assert_true(bool(work.operate(station,"case_policy:" + choice,_facts()).get("ok",false)))
			assert_eq(int(work.snapshot()["service_debt"]),int(option["service_debt"]))
			var opposite: String = "field" if mode == "forensic" else "forensic"
			var wrong_station: String = str(targets["A" if opposite == "forensic" else "B"])
			assert_false(bool(work.operate(wrong_station,
				"case_" + opposite,_facts()).get("ok",true)))
			assert_true(bool(work.operate(str(targets["A" if mode == "forensic" else "B"]),
				"case_" + mode,_facts()).get("ok",false)))
			for step: Dictionary in case_source["routes"][mode]["steps"]:
				assert_true(bool(work.operate(str(targets[str(step["station"])]),
					"case_" + str(step["kind"]),_facts()).get("ok",false)))
			if choice == "resilience":
				assert_eq(str(work.snapshot()["phase"]),"resilience_crosscheck")
				assert_false(work.solved())
				assert_true(bool(work.operate(str(targets["C"]),
					"case_resilience_crosscheck",_facts()).get("ok",false)))
			if case_source.has("final_signoff_station"):
				assert_true(bool(work.operate(str(targets[str(case_source["final_signoff_station"])]),
					"case_signoff",_facts()).get("ok",false)))
			assert_true(work.solved())
