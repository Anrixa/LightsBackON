extends "res://tests/test_case.gd"
## EXP016 A08 verify authenticated tool selection and true finite source spares.

const Cases := preload("res://scripts/gameplay/expedition_advanced_casework.gd")
const Gear := preload("res://scripts/gameplay/expedition_advanced_equipment.gd")
const Atlas := preload("res://scripts/world/dispatch_atlas.gd")
const Worksite := preload("res://scripts/gameplay/expedition_worksite_orders.gd")


func _facts() -> Dictionary:
	return {"hazard_safe":true,"faults_solved":true,"consequences_solved":true,
		"balancing_solved":true,"logistics_solved":true,
		"authorized_tools":["meter","screwdriver","puller","cutter","crimper"]}


func test_EXP016_A08_200_equipment_manifests_and_real_step_tool_gates() -> void:
	var gear: Dictionary = Gear.load_book()
	assert_true(bool(Gear.inspect(Atlas.load_catalog(), Worksite.load_book(), gear).get("ok",false)))
	var books: Array[Dictionary] = Cases.load_available_books()
	for serial: int in range(1,201):
		var level_id: String = "LV_%03d" % serial
		var entry: Dictionary = {}
		for source: Dictionary in books:
			var found: Dictionary = Cases.entry_for(source,level_id)
			if not found.is_empty():
				entry = found
		var manifest: Dictionary = Gear.entry_for(gear,level_id)
		var work: Cases = Cases.new()
		assert_true(bool(work.configure(entry).get("ok",false)))
		assert_true(bool(work.bind_equipment_manifest(manifest).get("ok",false)))
		assert_true(bool(work.begin().get("ok",false)))
		# A03 has two original-source probes before any worksite route.
		if entry.has("diagnosis"):
			assert_eq(str(work.snapshot()["phase"]), "evidence")
			assert_true(bool(work.operate(str(entry["targets"]["A"]),
				"case_probe_a", _facts()).get("ok",false)))
			assert_true(bool(work.operate(str(entry["targets"]["B"]),
				"case_probe_b", _facts()).get("ok",false)))
			assert_true(bool(work.operate(str(entry["targets"]["C"]),
				"case_identify:" + str(entry["diagnosis"]["fault_class"]),
				_facts()).get("ok",false)))
		assert_true(bool(work.operate(str(entry["targets"]["A"]),
			"case_forensic",_facts()).get("ok",false)))
		var steps: Array = entry["routes"]["forensic"]["steps"]
		for step: Dictionary in steps:
			var target: String = str(entry["targets"][str(step["station"])])
			var action: String = "case_" + str(step["kind"])
			var tool: String = str(manifest["required_tools"][str(step["kind"])])
			# Previous accepted actions can leave this same tool equipped.
			# Force an intentionally wrong, but admitted, tool first.
			var wrong: String = "meter" if tool != "meter" else "screwdriver"
			assert_true(bool(work.operate(str(entry["targets"]["A"]),
				"case_equip:" + wrong,_facts()).get("ok",false)))
			assert_false(bool(work.operate(target,action,_facts()).get("ok",true)))
			assert_false(bool(work.operate("SC_FORGED","case_equip:" + tool,
				_facts()).get("ok",true)))
			assert_true(bool(work.operate(str(entry["targets"]["A"]),"case_equip:" + tool,
				_facts()).get("ok",false)))
			var accepted: Dictionary = work.operate(target,action,_facts())
			assert_true(bool(accepted.get("ok",false)),str([serial,step,accepted])))
		assert_eq(int(work.snapshot()["worksite_spares_debited"]),
			int(manifest["reserve_cells"]) - int(work.snapshot()["worksite_spare_cells"]))
