extends RefCounted
## EXP016 A02: extra source-bound cases on already-authenticated SC stations.
## This machine never accepts job completion, a source graph or a kit balance
## from a client. The original 1000 jobs/economy/save schema remain unchanged.

const BOOK_PATH: String = "res://scenes/expeditions/exp016_casework_a02.json"
const AUTHORITY: String = "EXP016_A02_AUTHENTICATED_CASEWORK"
const QUALIFICATION: String = "SOURCE_HEADLESS_ONLY_HUMAN_CONTROLLER_RELEASE_HELD"
const GUARDS: Array[String] = [
	"faults_solved", "balancing_solved", "logistics_solved", "consequences_solved"
]
const ACTIONS: Array[String] = [
	"trace", "isolate", "crosscheck", "tag", "compare", "meter",
	"repair", "reconcile", "attest", "stabilize"
]

var _spec: Dictionary = {}
var _phase: String = "locked"
var _route: String = ""
var _kits: int = 0
var _liabilities: int = 0
var _faults: int = 0
var _recoveries: int = 0
var _policy_spec: Dictionary = {}
var _policy: String = ""
var _policy_debt: int = 0
var _policy_assurance: bool = false
var _equipment_manifest: Dictionary = {}
var _equipped_tool: String = ""
var _spare_cells: int = 0
var _spares_debited: int = 0
var _hazard_protocol: Dictionary = {}
var _hazard_progress: int = 0
var _hazard_interruptions: int = 0
var _return_phase_after_hazard: String = ""
var _fault_layer: Dictionary = {}
var _layer_probes: Dictionary = {}
var _layer_diagnosed: bool = false
var _tokens: Dictionary = {}
var _probes: Dictionary = {}
var _diagnosed: bool = false
var _recovery_phase: String = "working"
var _completed: Dictionary = {}
var _history: Array[Dictionary] = []


static func _reject(code: String) -> Dictionary:
	return {"ok": false, "code": "EXP016_A02_" + code}


static func load_book() -> Dictionary:
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(BOOK_PATH))
	if not raw is Dictionary or raw.get("schema_version") != 1 or \
			raw.get("authority") != AUTHORITY or \
			raw.get("qualification") != QUALIFICATION or \
			not raw.get("entries") is Array or raw["entries"].size() != 50:
		return {}
	return raw


## Read all existing phase books without requiring future phase files to exist.
static func load_available_books() -> Array[Dictionary]:
	var books: Array[Dictionary] = []
	for path: String in ["res://scenes/expeditions/exp016_casework_a02.json","res://scenes/expeditions/exp016_casework_a03.json","res://scenes/expeditions/exp016_casework_a04.json","res://scenes/expeditions/exp016_casework_a05.json"]:
		if not FileAccess.file_exists(path):
			continue
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not parsed is Dictionary or not parsed.get("entries") is Array:
			return []
		books.append(parsed)
	return books


static func entry_for(book: Dictionary, level_id: String) -> Dictionary:
	var serial: int = int(level_id.trim_prefix("LV_")) if level_id.begins_with("LV_") else -1
	var bounds: Array = book.get("range", [1, 50])
	if bounds.size() != 2 or serial < int(bounds[0]) or serial > int(bounds[1]) or \
			level_id != "LV_%03d" % serial:
		return {}
	var all_entries: Variant = book.get("entries", [])
	if not all_entries is Array or all_entries.size() != 50:
		return {}
	var result: Variant = all_entries[serial - int(bounds[0])]
	if not result is Dictionary or result.get("level_id") != level_id:
		return {}
	return result.duplicate(true)


static func inspect(atlas: Dictionary, investigation_book: Dictionary, book: Dictionary) -> Dictionary:
	var bounds: Array = book.get("range", [])
	if bounds.size() != 2 or int(bounds[0]) < 1 or int(bounds[1]) > 200 or \
			int(bounds[1]) - int(bounds[0]) != 49 or \
			book.get("authority") != "EXP016_%s_AUTHENTICATED_CASEWORK" % ("A%02d" % (int((int(bounds[0]) - 1) / 50.0) + 2)) or \
			book.get("qualification") != QUALIFICATION or \
			not book.get("entries") is Array or book["entries"].size() != 50:
		return _reject("BOOK_HEADER")
	var signatures: Dictionary = {}
	for serial: int in range(int(bounds[0]), int(bounds[1]) + 1):
		var source: Dictionary = atlas["levels"][serial - 1]
		var old: Dictionary = investigation_book["entries"][serial - 1]
		var item: Dictionary = book["entries"][serial - int(bounds[0])]
		if item.get("level_id") != source["id"] or \
				item.get("location_id") != source["location_id"] or \
				item.get("region_id") != source["region_id"] or \
				item.get("source_puzzle_identity") != source["puzzle_identity"] or \
				item.get("source_task_ids") != source["tasks"].map(func(t: Dictionary) -> String: return str(t["id"])) or \
				item.get("source_investigation_serial") != old["case_serial"] or \
				item.get("source_risk") != old["source_risk"] or \
				item.get("targets") != old["targets"] or \
				item.get("recovery_target") != old["recovery_target"]:
			return _reject("SOURCE_DRIFT")
		if item.has("final_signoff_station"):
			var signoff_station: String = str(item["final_signoff_station"])
			if not ["A", "B", "C"].has(signoff_station):
				return _reject("INVALID_SOURCE_SIGNOFF_STATION")
		if item.has("diagnosis"):
			var old_fault: Dictionary = JSON.parse_string(
				FileAccess.get_file_as_string("res://scenes/expeditions/fault_diagnostics.json")
			)["entries"][serial - 1]
			var diagnosis: Dictionary = item["diagnosis"]
			if diagnosis.get("scenario_key") != old_fault["scenario_key"] or \
					diagnosis.get("fault_class") != old_fault["fault_class"] or \
					diagnosis.get("signal_a") != old_fault["signal_a"] or \
					diagnosis.get("signal_b") != old_fault["signal_b"]:
				return _reject("FAULT_SOURCE_DRIFT")
		for mode: String in ["forensic", "field"]:
			var route: Dictionary = item["routes"][mode]
			var steps: Array = route.get("steps", [])
			if steps.size() < 5 or int(route.get("initial_kits", -1)) < 2:
				return _reject("ROUTE_SHAPE")
			var known: Dictionary = {}
			var total_cost: int = 0
			for step: Dictionary in steps:
				var id: String = str(step.get("id", ""))
				if known.has(id) or not ACTIONS.has(str(step.get("kind", ""))) or \
						not ["A", "B", "C"].has(str(step.get("station", ""))) or \
						not GUARDS.has(str(step.get("guard", ""))):
					return _reject("INVALID_STEP")
				for required: String in step.get("requires", []):
					if not known.has(required):
						return _reject("NON_DAG")
				known[id] = true
				total_cost += int(step.get("cost", -1))
			# Source-only static token-consumption proof. No token can be spent
			# unless earned by an earlier source-bound step.
			var held: Dictionary = {}
			for token: String in route.get("initial_tokens", []):
				held[token] = int(held.get(token, 0)) + 1
			for step: Dictionary in steps:
				for required_token: String in step.get("requires_tokens", []):
					if int(held.get(required_token, 0)) < 1:
						return _reject("UNSATISFIABLE_EVIDENCE_TOKEN")
				for token: String in step.get("consumes_tokens", []):
					if int(held.get(token, 0)) < 1:
						return _reject("DOUBLE_SPEND_EVIDENCE_TOKEN")
					held[token] = int(held.get(token, 0)) - 1
				for token: String in step.get("grants_tokens", []):
					held[token] = int(held.get(token, 0)) + 1
			if total_cost > int(route["initial_kits"]) or total_cost < 0:
				return _reject("UNSOLVABLE_KITS")
		# Source-free: station/guards/actions/edges/actual costs, never titles, IDs or clocks.
		var canonical: Array = []
		for route_key: String in ["forensic", "field"]:
			for node: Dictionary in item["routes"][route_key]["steps"]:
				canonical.append([node["kind"], node["station"], node["requires"], node["guard"], node["cost"],
					node.get("requires_tokens", []), node.get("consumes_tokens", []),
					node.get("grants_tokens", [])])
		var fingerprint: String = JSON.stringify(canonical)
		if signatures.has(fingerprint):
			return _reject("MECHANICAL_CLONE")
		signatures[fingerprint] = true
	return {"ok": true, "case_count": 50, "distinct_mechanics": signatures.size(),
		"qualification": QUALIFICATION}


func configure(entry: Dictionary) -> Dictionary:
	if entry.is_empty() or not entry.has("routes"):
		return _reject("UNPINNED_CASE")
	_spec = entry.duplicate(true)
	return {"ok": true}


func bind_source_policy(policy: Dictionary) -> Dictionary:
	if _spec.is_empty() or not _policy_spec.is_empty() or \
			policy.get("level_id") != _spec.get("level_id") or \
			not policy.has("options"):
		return _reject("POLICY_SOURCE_MISMATCH")
	_policy_spec = policy.duplicate(true)
	return {"ok": true, "code": "SOURCE_POLICY_BOUND"}


func bind_equipment_manifest(manifest: Dictionary) -> Dictionary:
	if _spec.is_empty() or not _equipment_manifest.is_empty() or \
			manifest.get("level_id") != _spec.get("level_id") or \
			not manifest.has("required_tools"):
		return _reject("EQUIPMENT_SOURCE_MISMATCH")
	_equipment_manifest = manifest.duplicate(true)
	_spare_cells = int(manifest.get("reserve_cells", 0))
	return {"ok": true, "code": "ORIGINAL_WORKSITE_EQUIPMENT_BOUND"}


func bind_hazard_protocol(protocol: Dictionary) -> Dictionary:
	if _spec.is_empty() or not _hazard_protocol.is_empty() or \
			protocol.get("level_id") != _spec.get("level_id") or \
			not protocol.has("source_blocked_operations"):
		return _reject("ENVIRONMENT_SOURCE_MISMATCH")
	_hazard_protocol = protocol.duplicate(true)
	return {"ok": true, "code": "ENVIRONMENT_PROTOCOL_BOUND"}


func bind_fault_layer(layer: Dictionary) -> Dictionary:
	if _spec.is_empty() or not _fault_layer.is_empty() or \
			layer.get("level_id") != _spec.get("level_id") or \
			not layer.has("primary_fault_class") or \
			not layer.has("secondary_fault_class"):
		return _reject("FAULT_LAYER_SOURCE_MISMATCH")
	_fault_layer = layer.duplicate(true)
	return {"ok": true, "code": "SOURCE_DUAL_FAULT_BOUND"}


func definition_snapshot() -> Dictionary:
	var copy: Dictionary = _spec.duplicate(true)
	if not _fault_layer.is_empty():
		copy["source_fault_layer"] = _fault_layer.duplicate(true)
	if not _policy_spec.is_empty():
		copy["source_service_policy"] = _policy_spec.duplicate(true)
	if not _equipment_manifest.is_empty():
		copy["source_equipment_manifest"] = _equipment_manifest.duplicate(true)
	if not _hazard_protocol.is_empty():
		copy["source_hazard_protocol"] = _hazard_protocol.duplicate(true)
	return copy


func target_ids() -> Array:
	return _spec.get("targets", {}).values()


func started() -> bool:
	return _phase != "locked"


func needs_action() -> bool:
	return _phase != "solved"


func solved() -> bool:
	return _phase == "solved"


func begin() -> Dictionary:
	if _spec.is_empty() or _phase != "locked":
		return _reject("BEGIN_UNAVAILABLE")
	var next_phase: String = "layered_evidence" if not _fault_layer.is_empty() else \
		"evidence" if _spec.has("diagnosis") else \
		"policy_choose" if not _policy_spec.is_empty() else "choose"
	_return_phase_after_hazard = next_phase
	_phase = "hazard_preflight" if not _hazard_protocol.is_empty() else next_phase
	return {"ok": true, "code": "CASE_OPEN"}


func _record(event: String) -> void:
	_history.append({"event": event, "route": _route, "steps": _completed.size(),
		"kits": _kits, "liabilities": _liabilities})
	if _history.size() > 32:
		_history.pop_front()


func operate(entity: String, action: String, facts: Dictionary) -> Dictionary:
	if _phase == "locked" or _phase == "solved":
		return _reject("ACTION_UNAVAILABLE")
	var targets: Dictionary = _spec["targets"]
	if not targets.values().has(entity):
		return _reject("FOREIGN_TARGET")
	if _phase == "working" and action.begins_with("case_equip:") and \
			not _equipment_manifest.is_empty():
		var requested: String = action.get_slice(":", 1)
		if entity != str(targets["A"]) or \
				not _equipment_manifest["authorized_tools"].has(requested) or \
				not facts.get("authorized_tools", []).has(requested):
			return _reject("UNADMITTED_TOOL_OR_WRONG_STATION")
		_equipped_tool = requested
		_record("host_selected_" + requested)
		return {"ok": true, "code": "HOST_TOOL_SELECTED", "tool": requested}
	if _phase == "hazard_preflight":
		var sequence: Array[String] = [
			"survey_station", "isolate_station", "clear_station"]
		var operations: Array[String] = [
			"case_hazard_survey", "case_hazard_isolate", "case_hazard_clear"]
		var expected_station: String = str(targets[str(_hazard_protocol[sequence[_hazard_progress]])])
		if entity != expected_station or action != operations[_hazard_progress]:
			return _reject("HAZARD_ORDER_OR_ACCESS_REQUIRED")
		if _hazard_progress == 2 and not bool(facts.get("hazard_safe", false)):
			return _reject("SOURCE_HAZARD_NOT_CONTAINED")
		if _hazard_progress == 2 and not bool(facts.get("consequences_solved", false)):
			return _reject("SOURCE_HAZARD_RECHECK_REQUIRED")
		_hazard_progress += 1
		_record("source_hazard_operation_" + str(_hazard_progress))
		if _hazard_progress == 3:
			_phase = _return_phase_after_hazard
			_hazard_progress = 0
		return {"ok": true, "code": "HAZARD_ACCESS_RESTORED" if _hazard_progress == 0 else \
			"HAZARD_SEQUENCE_ADVANCED"}
	if _phase == "resilience_crosscheck":
		if action != "case_resilience_crosscheck" or \
				entity != str(targets["C"]) or \
				not bool(facts.get("balancing_solved", false)) or \
				not bool(facts.get("consequences_solved", false)):
			return _reject("RESILIENCE_ASSURANCE_SOURCE_REQUIRED")
		_policy_assurance = true
		_phase = "signoff" if _spec.has("final_signoff_station") else "solved"
		_record("resilience_rechecked")
		return {"ok": true, "code": "SOURCE_RESILIENCE_ASSURED"}
	if _phase == "signoff":
		var required: String = str(_spec.get("final_signoff_station", ""))
		if entity != str(targets.get(required, "")) or action != "case_signoff":
			return _reject("SOURCE_SIGNOFF_STATION_REQUIRED")
		if not bool(facts.get("faults_solved", false)) or \
				not bool(facts.get("consequences_solved", false)):
			return _reject("SOURCE_SIGNOFF_GUARDS_REQUIRED")
		_phase = "solved"
		_record("source_signed_off")
		return {"ok": true, "code": "CASE_SOURCE_SIGNOFF", "liabilities": _liabilities}
	if _phase == "layered_evidence":
		if action == "case_fault_primary" and entity == str(targets["A"]):
			_layer_probes["primary"] = str(_fault_layer["primary_signal"])
			_record("host_primary_fault_evidence")
			return {"ok": true, "code": "SOURCE_PRIMARY_EVIDENCE"}
		if action == "case_fault_secondary" and entity == str(targets["B"]):
			_layer_probes["secondary"] = str(_fault_layer["secondary_signal"])
			_record("host_secondary_fault_evidence")
			return {"ok": true, "code": "SOURCE_SECONDARY_EVIDENCE"}
		if action.begins_with("case_diagnose_dual:") and entity == str(targets["C"]):
			if _layer_probes.size() != 2 or \
					not bool(facts.get("faults_solved", false)) or \
					not bool(facts.get("hazard_safe", false)):
				return _reject("DUAL_FAULT_SOURCE_EVIDENCE_REQUIRED")
			var expected: String = "case_diagnose_dual:%s:%s" % [
				str(_fault_layer["primary_fault_class"]),
				str(_fault_layer["secondary_fault_class"])]
			if action != expected:
				_recovery_phase = "layered_evidence"
				_phase = "fault"
				_faults += 1
				_liabilities += 1
				_record("incorrect_dual_fault")
				return _reject("DUAL_FAULT_DIAGNOSIS_RECOVERABLE")
			_layer_diagnosed = true
			_phase = "evidence" if _spec.has("diagnosis") else \
				"policy_choose" if not _policy_spec.is_empty() else "choose"
			_record("source_dual_fault_accepted")
			return {"ok": true, "code": "DUAL_FAULT_SOURCE_VERIFIED"}
		return _reject("DUAL_FAULT_ACTION_REQUIRED")
	if _phase == "evidence":
		if action == "case_probe_a" and entity == str(targets["A"]):
			_probes["A"] = str(_spec["diagnosis"]["signal_a"])
			_record("probe_a")
			return {"ok": true, "code": "SOURCE_PROBE_A"}
		if action == "case_probe_b" and entity == str(targets["B"]):
			_probes["B"] = str(_spec["diagnosis"]["signal_b"])
			_record("probe_b")
			return {"ok": true, "code": "SOURCE_PROBE_B"}
		if action.begins_with("case_identify:") and entity == str(targets["C"]):
			if _probes.size() != 2 or not bool(facts.get("faults_solved", false)):
				return _reject("SOURCE_PROBES_REQUIRED")
			if action.get_slice(":", 1) != str(_spec["diagnosis"]["fault_class"]):
				_recovery_phase = "evidence"
				_phase = "fault"
				_faults += 1
				_liabilities += 1
				_record("incorrect_diagnosis")
				return _reject("INCORRECT_DIAGNOSIS_RECOVERABLE")
			_diagnosed = true
			_phase = "policy_choose" if not _policy_spec.is_empty() else "choose"
			_record("source_diagnosis_verified")
			return {"ok": true, "code": "CASE_DIAGNOSIS_VERIFIED"}
		return _reject("EVIDENCE_ACTION_REQUIRED")
	if _phase == "policy_choose":
		var choice: String = action.trim_prefix("case_policy:")
		if not ["priority", "resilience"].has(choice) or \
				action != "case_policy:" + choice:
			return _reject("ORIGINAL_SOURCE_POLICY_REQUIRED")
		var policy_option: Dictionary = _policy_spec["options"][choice]
		if entity != str(targets[str(policy_option["station"])]) or \
				not bool(facts.get(str(_policy_spec["original_guard"]), false)):
			return _reject("POLICY_SOURCE_GUARD_OR_STATION_INVALID")
		_policy = choice
		_policy_debt = int(policy_option["service_debt"])
		_policy_assurance = false
		_phase = "choose"
		_record("committed_service_" + choice)
		return {"ok": true, "code": "SOURCE_POLICY_COMMITTED",
			"service_debt": _policy_debt, "policy": choice}
	if _phase == "choose":
		var chosen: String = action.trim_prefix("case_")
		if not ["forensic", "field"].has(chosen) or \
				entity != str(targets["A" if chosen == "forensic" else "B"]):
			return _reject("INVALID_ROUTE")
		if not _policy_spec.is_empty() and \
				str(_policy_spec["options"][_policy]["route"]) != chosen:
			return _reject("POLICY_ROUTE_CONSEQUENCE_MISMATCH")
		_route = chosen
		var route: Dictionary = _spec["routes"][_route]
		_kits = int(route["initial_kits"])
		_liabilities = int(route["liability_on_select"])
		_tokens.clear()
		for item: String in route.get("initial_tokens", []):
			_tokens[item] = int(_tokens.get(item, 0)) + 1
		_phase = "working"
		_record("choose_" + chosen)
		return {"ok": true, "code": "CASE_ROUTE_SELECTED", "route": chosen}
	if _phase == "fault":
		if entity != str(_spec["recovery_target"]) or action != "case_recover":
			return _reject("RECOVERY_TARGET_REQUIRED")
		if _recovery_phase == "working":
			if _kits < 1:
				return _reject("RECOVERY_KIT_EXHAUSTED")
			_kits -= 1
		else:
			# Before route choice there is no allocated kit; incorrect diagnosis
			# already debits one safety liability and is recoverable once re-probed.
			_probes.clear()
		_recoveries += 1
		_phase = _recovery_phase
		_record("recovered")
		return {"ok": true, "code": "CASE_RECOVERED"}
	if not _hazard_protocol.is_empty() and not bool(facts.get("hazard_safe", false)):
		_hazard_interruptions += 1
		_liabilities += 1
		_return_phase_after_hazard = _phase
		_hazard_progress = 0
		_phase = "hazard_preflight"
		_record("environment_interrupted_work")
		return _reject("ENVIRONMENT_PREEMPTED_OPERATIONS")
	if _phase != "working":
		return _reject("BAD_PHASE")
	var steps: Array = _spec["routes"][_route]["steps"]
	var frontier: Array = []
	for step: Dictionary in steps:
		if _completed.has(str(step["id"])):
			continue
		var available: bool = true
		for requirement: String in step["requires"]:
			if not _completed.has(requirement):
				available = false
		if available:
			frontier.append(step)
	for step: Dictionary in frontier:
		if entity != str(targets[str(step["station"])]) or \
				action != "case_" + str(step["kind"]):
			continue
		if not _equipment_manifest.is_empty():
			var required_tool: String = str(_equipment_manifest["required_tools"].get(
				str(step["kind"]), ""))
			if required_tool == "" or _equipped_tool != required_tool or \
					not facts.get("authorized_tools", []).has(required_tool):
				return _reject("AUTHENTICATED_TOOL_REQUIRED")
			if _equipment_manifest["charged_operations"].has(str(step["kind"])) and \
					int(step["cost"]) > 0 and _spare_cells < 1:
				return _reject("FINITE_WORKSITE_SPARES_EXHAUSTED")
		for needed: String in step.get("requires_tokens", []):
			if int(_tokens.get(needed, 0)) < 1:
				return _reject("EVIDENCE_TOKEN_UNAVAILABLE")
		if not bool(facts.get(str(step["guard"]), false)):
			_recovery_phase = "working"
			_phase = "fault"
			_faults += 1
			_liabilities += 1
			_record("unsafe_guard")
			return _reject("GUARD_FAULT_RECOVERABLE")
		var cost: int = int(step["cost"])
		if _kits < cost:
			return _reject("INSUFFICIENT_KITS")
		# Consume and grant tokens only after all gates and kit checks pass.
		for used: String in step.get("consumes_tokens", []):
			_tokens[used] = int(_tokens.get(used, 0)) - 1
		for earned: String in step.get("grants_tokens", []):
			_tokens[earned] = int(_tokens.get(earned, 0)) + 1
		if not _equipment_manifest.is_empty() and \
				_equipment_manifest["charged_operations"].has(str(step["kind"])) and \
				cost > 0:
			_spare_cells -= 1
			_spares_debited += 1
		_kits -= cost
		_completed[str(step["id"])] = true
		_record("verified_" + str(step["kind"]))
		if _completed.size() == steps.size():
			_phase = "resilience_crosscheck" if _policy == "resilience" else \
				"signoff" if _spec.has("final_signoff_station") else "solved"
		return {"ok": true, "code": "CASE_SOLVED" if solved() else "CASE_STEP_VERIFIED",
			"completed": _completed.size(), "kits": _kits}
	return _reject("STEP_OR_DEPENDENCY_LOCKED")


func snapshot() -> Dictionary:
	return {"qualification": QUALIFICATION, "level_id": _spec.get("level_id", ""),
		"phase": _phase, "route": _route, "kits": _kits, "liabilities": _liabilities,
		"faults": _faults, "recoveries": _recoveries,
		"completed_steps": _completed.keys().duplicate(),
		"probes": _probes.duplicate(true), "diagnosed": _diagnosed,
		"layer_probes": _layer_probes.duplicate(true), "layer_diagnosed": _layer_diagnosed,
		"evidence_tokens": _tokens.duplicate(true),
		"hazard_progress": _hazard_progress, "hazard_interruptions": _hazard_interruptions,
		"source_hazard_kind": _hazard_protocol.get("source_hazard_kind", ""),
		"equipped_tool": _equipped_tool, "worksite_spare_cells": _spare_cells,
		"service_policy": _policy, "service_debt": _policy_debt,
		"source_resilience_assured": _policy_assurance,
		"worksite_spares_debited": _spares_debited,
		"history": _history.duplicate(true)}
