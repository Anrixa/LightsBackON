extends RefCounted
## EXP019 A03: opt-in host-owned five-tool worksite procedure.
## Commands use existing authenticated operate_worksite on R_WEST.
const QUALIFICATION: String = "SOURCE_HEADLESS_FIVE_TOOL_REPAIR_CONTROLLER_RELEASE_HELD"
const ACTION_TO_TOOL: Dictionary = {
	"measure": "meter", "secure": "screwdriver", "cut": "cutter",
	"extract": "puller", "crimp": "crimper", "verify": "meter"
}
const STEP_TO_TOOL: Dictionary = {
	"diagnose": "meter", "isolate": "screwdriver", "open": "screwdriver",
	"remove": "puller", "install": "puller", "close": "screwdriver",
	"test": "meter", "restore": "meter"
}
const PREREQUISITES: Dictionary = {
	"diagnose": ["measure"], "remove": ["secure", "cut"],
	"install": ["extract"], "close": ["crimp"], "restore": ["verify"]
}
var _level: String = ""
var _equipped: String = ""
var _attested: Dictionary = {}
var _history: Array[Dictionary] = []
var _revision: int = 0


func configure(level_id: String) -> Dictionary:
	if not level_id.begins_with("LV_") or level_id.length() != 6 or \
			not level_id.trim_prefix("LV_").is_valid_int():
		return {"ok": false, "code": "EXP019_A03_BAD_LEVEL_ID"}
	var n: int = int(level_id.trim_prefix("LV_"))
	if n < 1 or n > 200:
		return {"ok": false, "code": "EXP019_A03_BAD_LEVEL_ID"}
	_level = level_id
	return {"ok": true, "qualification": QUALIFICATION}


## The host accepts an explicit empty equip to put the tool away. Mirror that
## accepted transition too: retaining the previous item would authorize
## a field action after a successful unequip.
func accepted_equip(tool: String) -> void:
	if tool == "" or ACTION_TO_TOOL.values().has(tool):
		_equipped = tool


static func required_for_step(step: String) -> String:
	return str(STEP_TO_TOOL.get(step, ""))


func _deny(code: String) -> Dictionary:
	return {"ok": false, "code": code, "qualification": QUALIFICATION}


## These facts are reconstructed from the real Grid, Meter and Interaction,
## never from a network payload. Failed checks never change state.
func preflight_action(action: String, facts: Dictionary) -> Dictionary:
	if not ACTION_TO_TOOL.has(action):
		return _deny("EXP019_A03_UNKNOWN_ACTION")
	if _attested.has(action):
		return _deny("EXP019_A03_ALREADY_ATTESTED")
	if _equipped != str(ACTION_TO_TOOL[action]):
		return _deny("EXP019_A03_WRONG_TOOL")
	if action != "measure" and not bool(facts.get("isolated", false)):
		return _deny("EXP019_A03_LIVE_WORK_DENIED")
	var state: String = str(facts.get("repair_state", ""))
	match action:
		"measure":
			if not bool(facts.get("inspected", false)) or \
					typeof(facts.get("west_failed")) != TYPE_BOOL:
				return _deny("EXP019_A03_METER_SOURCE_MISSING")
		"secure":
			if state != "opened" or not _attested.has("measure"):
				return _deny("EXP019_A03_PANEL_NOT_READY")
		"cut":
			if state != "opened" or not _attested.has("secure"):
				return _deny("EXP019_A03_CUT_SAFETY_GUARD")
		"extract":
			if state != "component_removed" or not _attested.has("cut"):
				return _deny("EXP019_A03_EXTRACT_GUARD")
		"crimp":
			if state != "replacement_installed" or not _attested.has("extract"):
				return _deny("EXP019_A03_CRIMP_GUARD")
		"verify":
			if state != "tested" or not _attested.has("crimp"):
				return _deny("EXP019_A03_VERIFICATION_GUARD")
	return {"ok": true}


func preflight_step(step: String) -> Dictionary:
	if STEP_TO_TOOL.has(step) and _equipped != str(STEP_TO_TOOL[step]):
		return _deny("EXP019_A03_REPAIR_TOOL_MISMATCH")
	for requirement: String in PREREQUISITES.get(step, []):
		if not _attested.has(requirement):
			return _deny("EXP019_A03_MISSING_" + requirement.to_upper())
	return {"ok": true}


## Called after SessionHost peer/session/seq/dedupe/rate/range and guard.
func operate(action: String, facts: Dictionary) -> Dictionary:
	var valid: Dictionary = preflight_action(action, facts)
	if not valid.get("ok", false):
		return valid
	_revision += 1
	_attested[action] = true
	_history.append({"step": action, "tool": _equipped,
		"repair_state": facts["repair_state"], "revision": _revision})
	return {"ok": true, "operation": action, "revision": _revision}


func next_action(state: String) -> Dictionary:
	var actions: Array[String] = []
	match state:
		"undiagnosed": actions = ["measure"]
		"opened": actions = ["secure", "cut"]
		"component_removed": actions = ["extract"]
		"replacement_installed": actions = ["crimp"]
		"tested": actions = ["verify"]
	for action: String in actions:
		if not _attested.has(action):
			return {"action": action, "tool": ACTION_TO_TOOL[action]}
	return {}


func snapshot() -> Dictionary:
	return {"level_id": _level, "equipped": _equipped,
		"attestations": _attested.duplicate(true),
		"history": _history.duplicate(true),
		"revision": _revision, "completed_operations": _attested.size(),
		"required_operations": ACTION_TO_TOOL.size(),
		"qualification": QUALIFICATION}
