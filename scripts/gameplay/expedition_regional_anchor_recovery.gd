extends RefCounted
## EXP015 A12.2: original reserve-anchor feeder incident, host only.
## Only SessionHost's existing authenticated worksite board may expose this.
## Never creates restoration receipts, reserves, rewards, new RPCs or saves.
const Atlas := preload("res://scripts/world/dispatch_atlas.gd")
const Network := preload("res://scripts/gameplay/expedition_regional_network.gd")

const QUALIFICATION: String = "SOURCE_HEADLESS_ONLY_HUMAN_CONTROLLER_RELEASE_HELD"
const ACTIONS: Array[String] = [
	"anchor_audit", "anchor_trip", "anchor_repair", "anchor_reset", "anchor_defer",
	"anchor_verify", "anchor_signoff"
]

var _network: Network
var _source: Dictionary = {}
var _original_feeder: String = ""
var _recovery_feeder: String = ""
var _phase: String = "inactive"
var _policy: String = ""
var _events: Array[Dictionary] = []


static func _fail(code: String) -> Dictionary:
	return {"ok": false, "code": code}


func _path_matches_original(plan: Dictionary) -> bool:
	if not bool(plan.get("ok", false)) or _source.is_empty() or \
			plan.get("root_source_site_id") != _source["root_source_id"] or \
			plan.get("reserve_anchor_site_id") != _source["reserve_anchor_site"] or \
			plan.get("region_id") != _source["region_id"]:
		return false
	var inbound: Dictionary = {}
	for edge: Dictionary in _source["primary_feeders"]:
		inbound[str(edge["to"])] = edge
	var cursor: String = str(_source["reserve_anchor_site"])
	var expected: Array[Dictionary] = []
	var seen: Dictionary = {}
	while cursor != str(_source["root_source_id"]):
		if not inbound.has(cursor) or seen.has(cursor):
			return false
		seen[cursor] = true
		var original: Dictionary = inbound[cursor]
		expected.append(original)
		cursor = str(original["from"])
	expected.reverse()
	var actual: Array = plan.get("original_feeder_path", [])
	if actual.size() != expected.size() or actual.is_empty():
		return false
	for index: int in range(expected.size()):
		if actual[index].get("edge_id") != expected[index]["edge_id"] or \
				actual[index].get("from") != expected[index]["from"] or \
				actual[index].get("to") != expected[index]["to"]:
			return false
	return str(actual[-1]["edge_id"]) == _original_feeder


## A12.3: an isolated feeder is repairable, not a reason to fabricate
## managed restoration. Only missing original EXP04 site receipts can
## authorize the explicitly unresolved managed-source outcome.
func _missing_original_receipt(plan: Dictionary) -> bool:
	for blocker: Dictionary in plan.get("blockers", []):
		if str(blocker.get("code", "")) == "ORIGINAL_RECEIPT_MISSING":
			return true
	return false


func _first_blocked_original_feeder(plan: Dictionary) -> String:
	for original: Dictionary in plan.get("original_feeder_path", []):
		if bool(original.get("isolated", false)):
			return str(original.get("edge_id", ""))
	return ""


## Prevent a generic regional_* board command from bypassing this episode.
## Internally authorized A05/other host-owned operations remain unchanged.
func protects_original_asset(action: String) -> bool:
	if _source.is_empty() or _network == null:
		return false
	var pieces: PackedStringArray = action.split(":")
	if pieces.size() != 2:
		return false
	if ["regional_isolate", "regional_reset"].has(pieces[0]):
		for original: Dictionary in _network.anchor_route_snapshot().get(
				"original_feeder_path", []):
			if str(original["edge_id"]) == pieces[1]:
				return true
	if ["regional_engage", "regional_release"].has(pieces[0]):
		for tie: Dictionary in _source["standby_ties"]:
			if str(tie["edge_id"]) == pieces[1] and \
					str(tie["to"]) == str(_source["reserve_anchor_site"]):
				return true
	return false


func configure(network: Network) -> Dictionary:
	if _network != null or network == null:
		return _fail("ANCHOR_HOST_NETWORK_REQUIRED")
	var state: Dictionary = network.snapshot()
	if state.is_empty():
		return _fail("ANCHOR_NETWORK_NOT_CONFIGURED")
	var source: Dictionary = Network.entry_for(Network.load_book(),
		str(state.get("level_id", "")))
	if source.is_empty() or state.get("region_id") != source.get("region_id") or \
			state.get("level_id") != source.get("shelter_service_site") or \
			not bool(Network.inspect_region(Atlas.load_catalog(), source).get("ok", false)):
		return _fail("ANCHOR_NOT_ORIGINAL_FINALE")
	_source = source.duplicate(true)
	_network = network
	var path: Dictionary = network.anchor_route_snapshot()
	if not bool(path.get("ok", false)) or path.get("original_feeder_path", []).is_empty():
		_source = {}
		_network = null
		return _fail("ANCHOR_ORIGINAL_PATH_MISSING")
	_original_feeder = str(path["original_feeder_path"][-1]["edge_id"])
	if not _path_matches_original(path):
		_source = {}
		_network = null
		return _fail("ANCHOR_SOURCE_PATH_MISMATCH")
	_phase = "audit_pending"
	return {"ok": true, "region_id": source["region_id"],
		"original_anchor": source["reserve_anchor_site"]}


func definition_snapshot() -> Dictionary:
	if _source.is_empty():
		return {}
	return {"region_id": _source["region_id"],
		"original_finale": _source["shelter_service_site"],
		"original_anchor": _source["reserve_anchor_site"],
		"original_incoming_feeder": _original_feeder,
		"original_fault_proof": _source["fault_signature"],
		"original_recovery_proof": _source["recovery_procedure"],
		"risk_class": _source["risk_class"], "qualification": QUALIFICATION}


func _source_valid() -> bool:
	if _network == null or _source.is_empty() or _policy.is_empty():
		return false
	var plan: Dictionary = _network.anchor_route_snapshot()
	if not _path_matches_original(plan):
		return false
	if _policy == "restored_original_feeder":
		var state: Dictionary = _network.snapshot()
		return bool(plan["anchor_energized"]) and not bool(plan["standby_engaged"]) and \
			(plan["blockers"] as Array).is_empty() and \
			str(state["feeders"][_original_feeder]["fault"]).is_empty() and \
			not bool(state["feeders"][_original_feeder]["isolated"])
	if _policy == "managed_dark_source":
		return not bool(plan["anchor_energized"]) and \
			not bool(plan["standby_engaged"]) and \
			_missing_original_receipt(plan)
	return false


func closed() -> bool:
	return _phase == "signed_off" and _source_valid()


func snapshot() -> Dictionary:
	if _source.is_empty() or _network == null:
		return {}
	return {"phase": _phase, "policy": _policy, "closed": closed(),
		"original_region_id": _source["region_id"],
		"original_incoming_feeder": _original_feeder,
		"active_recovery_feeder": _recovery_feeder,
		"original_route": _network.anchor_route_snapshot(),
		"events": _events.duplicate(true), "qualification": QUALIFICATION}


func operate(action: String) -> Dictionary:
	if _source.is_empty() or _network == null:
		return _fail("ANCHOR_NOT_CONFIGURED")
	if not ACTIONS.has(action) and \
			action != "anchor_proof:" + str(_source["recovery_procedure"]):
		return _fail("ANCHOR_UNKNOWN_OR_FORGED_PROOF")
	if _phase == "signed_off":
		if _source_valid():
			return _fail("ANCHOR_ALREADY_SIGNED_OFF")
		# Later authentic feeder/receipt changes invalidate signoff. Reaudit
		# from source without replaying the prior fault or duplicating debit.
		_phase = "audit_pending"
		_policy = ""
		_recovery_feeder = ""
		_events.append({"action": "source_invalidation", "phase": _phase})
	var plan: Dictionary = _network.anchor_route_snapshot()
	if not _path_matches_original(plan) or \
			plan.get("level_id") != _source["shelter_service_site"]:
		return _fail("ANCHOR_SOURCE_CHANGED")
	match action:
		"anchor_audit":
			if _phase != "audit_pending":
				return _fail("ANCHOR_AUDIT_ORDER")
			_phase = "choice_pending"
		"anchor_trip":
			if _phase != "choice_pending" or \
					not bool(plan["anchor_energized"]) or \
					bool(plan["standby_engaged"]) or \
					not (plan["blockers"] as Array).is_empty():
				return _fail("ANCHOR_LIVE_ORIGINAL_PATH_REQUIRED")
			var tripped: Dictionary = _network.host_transition("trip_feeder",
				_original_feeder, str(_source["fault_signature"]))
			if not bool(tripped.get("ok", false)):
				return tripped
			_recovery_feeder = _original_feeder
			_phase = "faulted"
		"anchor_repair":
			if _phase != "choice_pending" or bool(plan["standby_engaged"]) or \
					_missing_original_receipt(plan):
				return _fail("ANCHOR_ORIGINAL_FEEDER_REPAIR_REQUIRED")
			var blocked: String = _first_blocked_original_feeder(plan)
			if blocked.is_empty():
				return _fail("ANCHOR_ORIGINAL_FEEDER_REPAIR_REQUIRED")
			_recovery_feeder = blocked
			_phase = "faulted"
		"anchor_defer":
			if _phase != "choice_pending" or bool(plan["anchor_energized"]) or \
					bool(plan["standby_engaged"]) or \
					not _missing_original_receipt(plan):
				return _fail("ANCHOR_REAL_DARK_SOURCE_REQUIRED")
			_policy = "managed_dark_source"
			_phase = "verification_pending"
		"anchor_reset":
			if _phase != "fault_cleared":
				return _fail("ANCHOR_ORIGINAL_CLEARANCE_REQUIRED")
			if _recovery_feeder.is_empty() or \
					not _path_matches_original(plan):
				return _fail("ANCHOR_SOURCE_RECOVERY_TARGET_INVALID")
			var reset: Dictionary = _network.host_transition("reset_feeder",
				_recovery_feeder)
			if not bool(reset.get("ok", false)):
				return reset
			var updated: Dictionary = _network.anchor_route_snapshot()
			if not _path_matches_original(updated):
				return _fail("ANCHOR_ORIGINAL_PATH_CHANGED_DURING_RESET")
			_recovery_feeder = ""
			if (updated["blockers"] as Array).is_empty() and \
					bool(updated["anchor_energized"]) and \
					not bool(updated["standby_engaged"]):
				_policy = "restored_original_feeder"
				_phase = "verification_pending"
			else:
				_policy = ""
				_phase = "choice_pending"
		"anchor_verify":
			if _phase != "verification_pending" or not _source_valid():
				return _fail("ANCHOR_LIVE_SOURCE_PROOF_REQUIRED")
			_phase = "verified"
		"anchor_signoff":
			if _phase != "verified" or not _source_valid():
				return _fail("ANCHOR_STABLE_SOURCE_REQUIRED")
			_phase = "signed_off"
		_:
			if _phase != "faulted" or \
					action != "anchor_proof:" + str(_source["recovery_procedure"]):
				return _fail("ANCHOR_ORIGINAL_RISK_PROOF_REQUIRED")
			if _recovery_feeder.is_empty():
				return _fail("ANCHOR_ORIGINAL_RECOVERY_TARGET_MISSING")
			var original_state: Dictionary = {}
			for original: Dictionary in plan["original_feeder_path"]:
				if str(original["edge_id"]) == _recovery_feeder:
					original_state = original
			if original_state.is_empty() or \
					not bool(original_state.get("isolated", false)) or \
					_missing_original_receipt(plan):
				return _fail("ANCHOR_RECOVERY_REQUIRES_REAL_ISOLATION")
			var active_fault: String = str(original_state.get("fault", ""))
			if not active_fault.is_empty():
				if active_fault != str(_source["fault_signature"]):
					return _fail("ANCHOR_FOREIGN_FAULT_SIGNATURE")
				var cleared: Dictionary = _network.host_transition("clear_fault",
					_recovery_feeder, str(_source["recovery_procedure"]))
				if not bool(cleared.get("ok", false)):
					return cleared
			_phase = "fault_cleared"
	_events.append({"sequence": _events.size() + 1,
		"action": action, "phase": _phase, "policy": _policy})
	return {"ok": true, "snapshot": snapshot()}
