extends "res://tests/test_case.gd"
## EXP016 A12: 200 source cases * 2 materially distinct full host-machine
## operation routes, plus negative scenarios; human/controller/release held.

const Cases := preload("res://scripts/gameplay/expedition_advanced_casework.gd")
const Atlas := preload("res://scripts/world/dispatch_atlas.gd")
const Faults := preload("res://scripts/gameplay/expedition_advanced_fault_layers.gd")
const Hazards := preload("res://scripts/gameplay/expedition_advanced_hazards.gd")
const Gear := preload("res://scripts/gameplay/expedition_advanced_equipment.gd")
const Policies := preload("res://scripts/gameplay/expedition_advanced_policies.gd")
const Discoveries := preload("res://scripts/gameplay/expedition_advanced_discoveries.gd")
const Cascades := preload("res://scripts/gameplay/expedition_advanced_cascade.gd")
const Runtime := preload("res://scripts/gameplay/expedition_host_session.gd")


func _facts(safe: bool = true) -> Dictionary:
	return {"faults_solved":true,"hazard_safe":safe,
		"balancing_solved":true,"logistics_solved":true,"consequences_solved":true,
		"load_balanced":true,"supplies_ready":true,"cascade_stable":true,
		"fault_clear":true,
		"authorized_tools":["meter","screwdriver","puller","cutter","crimper"]}


func _source(cases: Array[Dictionary], level_id: String) -> Dictionary:
	for book: Dictionary in cases:
		var selected: Dictionary = Cases.entry_for(book,level_id)
		if not selected.is_empty():
			return selected
	return {}


func _hazard_recover(work: Cases, src: Dictionary, hazard: Dictionary) -> void:
	var targets: Dictionary = src["targets"]
	for op: String in ["survey","isolate","clear"]:
		var station: String = str(targets[str(hazard[op + "_station"])])
		var outcome: Dictionary = work.operate(station,"case_hazard_" + op,_facts())
		assert_true(bool(outcome.get("ok",false)),str(outcome))


func _replay(src: Dictionary, layer: Dictionary, hazard: Dictionary,
		gear: Dictionary, policy: Dictionary, discovery: Dictionary,
		choice: String, upstream_pressure: int, inject_failures: bool) -> void:
	var work: Cases = Cases.new()
	assert_true(bool(work.configure(src).get("ok",false)))
	assert_true(bool(work.bind_fault_layer(layer).get("ok",false)))
	assert_true(bool(work.bind_hazard_protocol(hazard).get("ok",false)))
	assert_true(bool(work.bind_equipment_manifest(gear).get("ok",false)))
	assert_true(bool(work.bind_source_policy(policy).get("ok",false)))
	assert_true(bool(work.bind_source_discovery(discovery).get("ok",false)))
	assert_true(bool(work.bind_inherited_pressure(upstream_pressure).get("ok",false)))
	assert_true(bool(work.begin().get("ok",false)))
	assert_eq(str(work.snapshot()["phase"]),"hazard_preflight")
	_hazard_recover(work,src,hazard)
	assert_eq(str(work.snapshot()["phase"]),"layered_evidence")
	var targets: Dictionary = src["targets"]
	var twin_action: String = "case_diagnose_dual:%s:%s" % [
		str(layer["primary_fault_class"]),str(layer["secondary_fault_class"])]
	assert_false(bool(work.operate(str(targets["C"]),twin_action,_facts()).get("ok",true)))
	assert_true(bool(work.operate(str(targets["A"]),"case_fault_primary",_facts()).get("ok",false)))
	assert_true(bool(work.operate(str(targets["B"]),"case_fault_secondary",_facts()).get("ok",false)))
	if inject_failures:
		assert_false(bool(work.operate(str(targets["C"]),
			"case_diagnose_dual:forged:forged",_facts()).get("ok",true)))
		assert_eq(str(work.snapshot()["phase"]),"fault")
		assert_true(bool(work.operate(str(targets["C"]),"case_recover",_facts()).get("ok",false)))
		assert_false(bool(work.operate(str(targets["C"]),twin_action,_facts()).get("ok",true)))
		assert_true(bool(work.operate(str(targets["A"]),"case_fault_primary",_facts()).get("ok",false)))
		assert_true(bool(work.operate(str(targets["B"]),"case_fault_secondary",_facts()).get("ok",false)))
	assert_true(bool(work.operate(str(targets["C"]),twin_action,_facts()).get("ok",false)))
	if src.has("diagnosis"):
		assert_true(bool(work.operate(str(targets["A"]),"case_probe_a",_facts()).get("ok",false)))
		assert_true(bool(work.operate(str(targets["B"]),"case_probe_b",_facts()).get("ok",false)))
		assert_true(bool(work.operate(str(targets["C"]),
			"case_identify:" + str(src["diagnosis"]["fault_class"]),_facts()).get("ok",false)))
	assert_eq(str(work.snapshot()["phase"]),"policy_choose")
	var option: Dictionary = policy["options"][choice]
	assert_false(bool(work.operate(str(targets["A"]),
		"case_forensic",_facts()).get("ok",true)))
	assert_true(bool(work.operate(str(targets[str(option["station"])]),
		"case_policy:" + choice,_facts()).get("ok",false)))
	var route: String = str(option["route"])
	assert_true(bool(work.operate(str(targets["A" if route == "forensic" else "B"]),
		"case_" + route,_facts()).get("ok",false)))
	var steps: Array = src["routes"][route]["steps"]
	var i: int = 0
	for step: Dictionary in steps:
		if inject_failures and i == 1:
			assert_false(bool(work.operate(str(targets[str(step["station"])]),
				"case_" + str(step["kind"]),_facts(false)).get("ok",true)))
			assert_eq(str(work.snapshot()["phase"]),"hazard_preflight")
			_hazard_recover(work,src,hazard)
			assert_eq(str(work.snapshot()["phase"]),"working")
		var required_tool: String = str(gear["required_tools"][str(step["kind"])])
		assert_false(bool(work.operate("SC_FOREIGN",
			"case_equip:" + required_tool,_facts()).get("ok",true)))
		assert_true(bool(work.operate(str(targets["A"]),
			"case_equip:" + required_tool,_facts()).get("ok",false)))
		var step_result: Dictionary = work.operate(str(targets[str(step["station"])]),
			"case_" + str(step["kind"]),_facts())
		assert_true(bool(step_result.get("ok",false)),str(step_result))
		i += 1
	if choice == "resilience":
		assert_eq(str(work.snapshot()["phase"]),"resilience_crosscheck")
		assert_true(bool(work.operate(str(targets["C"]),
			"case_resilience_crosscheck",_facts()).get("ok",false)))
	if upstream_pressure > 0:
		assert_eq(str(work.snapshot()["phase"]),"cascade_settlement")
		assert_false(bool(work.operate(str(targets["C"]),"case_settle_debt",{}).get("ok",true)))
		assert_true(bool(work.operate(str(targets["C"]),
			"case_settle_debt",_facts()).get("ok",false)))
	if src.has("final_signoff_station"):
		assert_eq(str(work.snapshot()["phase"]),"signoff")
		assert_true(bool(work.operate(str(targets[str(src["final_signoff_station"])]),
			"case_signoff",_facts()).get("ok",false)))
	assert_true(work.solved())
	assert_eq(int(work.snapshot()["completed_steps"].size()),steps.size())
	assert_eq(int(work.snapshot()["service_debt"]),int(option["service_debt"]))
	assert_true(bool(work.snapshot()["inherited_pressure_settled"]))
	if inject_failures:
		assert_true(int(work.snapshot()["liabilities"]) >= 1)
		assert_true(int(work.snapshot()["faults"]) >= 1)
	assert_false(bool(work.operate(str(targets["A"]),"case_forensic",_facts()).get("ok",true)))
	assert_false(work.discovery_ready())
	assert_false(bool(work.operate(str(targets["C"]),
		"case_discover_authenticate",_facts()).get("ok",true)))
	assert_true(bool(work.operate(str(targets["A"]),
		"case_discover_trace",_facts()).get("ok",false)))
	assert_true(bool(work.operate(str(targets["B"]),
		"case_discover_crosscheck",_facts()).get("ok",false)))
	assert_true(bool(work.operate(str(targets["C"]),
		"case_discover_authenticate",_facts()).get("ok",false)))
	assert_true(work.discovery_ready())
	assert_eq(str(work.snapshot()["source_collectible_id"]),
		str(discovery["source_collectible_id"]))
	assert_eq(int(work.snapshot()["worksite_spares_debited"]),
		int(gear["reserve_cells"]) - int(work.snapshot()["worksite_spare_cells"]))


func test_EXP016_A12_200_levels_400_real_host_case_replays_and_negative_scenarios() -> void:
	var source: Array[Dictionary] = Cases.load_available_books()
	assert_eq(source.size(),4)
	var faults: Dictionary = Faults.load_book()
	var hazards: Dictionary = Hazards.load_book()
	var equipment: Dictionary = Gear.load_book()
	var policies: Dictionary = Policies.load_book()
	var discoveries: Dictionary = Discoveries.load_book()
	var cascades: Dictionary = Cascades.load_book()
	assert_eq(cascades["regions"].size(),25)
	var iterations: int = 0
	for serial: int in range(1,201):
		var id: String = "LV_%03d" % serial
		var entry: Dictionary = _source(source,id)
		assert_false(entry.is_empty())
		var region: Dictionary = Cascades.entry_for(cascades,id)
		var incoming: int = 1 if region["source_predecessors"][id].size() > 0 else 0
		for policy: String in ["priority","resilience"]:
			_replay(entry,Faults.entry_for(faults,id),
				Hazards.entry_for(hazards,id),Gear.entry_for(equipment,id),
				Policies.entry_for(policies,id),
				Discoveries.entry_for(discoveries,id),
				policy,incoming,serial % 25 == 0 and policy == "priority")
			iterations += 1
	assert_eq(iterations,400)


func _position(_player: String) -> Vector3:
	return Vector3(35.0,0.9,35.0)


func test_EXP016_A12_200_actual_expedition_host_startups_all_opt_in_source_flags() -> void:
	var successes: int = 0
	for serial: int in range(1,201):
		var id: String = "LV_%03d" % serial
		var session: Runtime = Runtime.new()
		var result: Dictionary = session.start_exp016_source_qualification(
			id,Callable(self,"_position"))
		assert_true(bool(result.get("ok",false)),str(result))
		if not bool(result.get("ok",false)):
			continue
		assert_true(session.advanced_cases != null)
		assert_true(session.advanced_cascade == null)
		assert_eq(str(session.advanced_cases.definition_snapshot()["level_id"]),id)
		assert_true(str(result["content_revision"]).begins_with("EXP016_"))
		assert_true(session.task_board().has("advanced_cases"))
		assert_false(session.completed())
		successes += 1
	assert_eq(successes,200)
