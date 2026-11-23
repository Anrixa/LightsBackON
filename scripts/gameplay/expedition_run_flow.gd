extends RefCounted
## EXP020 A05 — ephemeral presentation lifecycle, not a new save/host.
## Both replay and returning must first commit and acknowledge real EXP04
## pending receipts. Never reconstructs an uncommitted electrical checkpoint.
const Atlas := preload("res://scripts/world/dispatch_atlas.gd")
const SaveService := preload("res://scripts/persistence/save_service.gd")
const RUNNING: String = "running"
const PAUSED: String = "paused"
const SAVE_HOLD: String = "save_hold"
const RESTARTING: String = "restarting"
const RETURNING: String = "returning"

var _state: String = "uninitialized"
var _level: String = ""
var _account: String = ""
var _denied: int = 0
var _last_code: String = ""


static func _fail(code: String) -> Dictionary:
	return {"ok": false, "code": code}


func begin(level_id: String, account: String, atlas: Dictionary) -> Dictionary:
	if _state != "uninitialized":
		return _fail("ALREADY_STARTED")
	if Atlas.find_level(atlas,level_id).is_empty() or 			(account != "" and not SaveService.is_valid_key(account)):
		return _fail("INVALID_LEVEL_OR_ACCOUNT")
	_level = level_id
	_account = account
	_state = RUNNING
	return {"ok": true, "state": _state}


func paused() -> bool:
	return _state == PAUSED or _state == SAVE_HOLD


func state() -> String:
	return _state


func pause() -> Dictionary:
	if _state != RUNNING:
		return _fail("NOT_RUNNING")
	_state = PAUSED
	return {"ok": true}


func resume() -> Dictionary:
	if not paused():
		return _fail("NOT_PAUSED")
	_state = RUNNING
	return {"ok": true}


func observe_host_reply(reply: Dictionary) -> void:
	if _state != RUNNING:
		return
	if bool(reply.get("ok",false)):
		_last_code = ""
	else:
		_denied += 1
		_last_code = str(reply.get("code","DENIED")).substr(0,96)


func onboarding(board: Dictionary) -> String:
	if not board.get("tasks") is Array:
		return "Host task evidence unavailable."
	var confirmed: int = 0
	for task: Dictionary in board["tasks"]:
		if bool(task.get("completed",false)):
			confirmed += 1
	if confirmed == 0:
		return "M opens field notes. Inspect visible equipment with E; host checks determine valid results."
	if confirmed < 4:
		return "Compare confirmed measurements in the field tablet. Optional finds never block extraction."
	return "Verify restoration before extracting. Replayed tasks cannot repay previously archived score."


func gate_departure(pending: int, save_error: String, intent: String) -> Dictionary:
	if not paused():
		return _fail("PAUSE_REQUIRED")
	if not ["restart","return"].has(intent) or pending < 0:
		return _fail("INVALID_DEPARTURE")
	if save_error != "":
		_state = SAVE_HOLD
		return _fail("EXP04_SAVE_HOLD")
	if pending > 0:
		_state = SAVE_HOLD
		return _fail("UNACKNOWLEDGED_HOST_REWARDS")
	_state = RESTARTING if intent == "restart" else RETURNING
	return {"ok": true, "state": _state, "level_id": _level,
		"account_key": _account, "unbanked_session_resets": intent == "restart"}


## Scene transitions may fail (missing scene/resource). Restore the paused
## state and keep the same host so the player is never stranded.
func abort_departure() -> Dictionary:
	if not [RESTARTING,RETURNING].has(_state):
		return _fail("NO_PENDING_DEPARTURE")
	_state = PAUSED
	return {"ok":true,"state":_state}


func source_snapshot() -> Dictionary:
	return {"state":_state,"level_id":_level,"account_key":_account,
		"denials":_denied,"last_denial":_last_code,
		"solo_local_host":true,"save_schema_changed":false}
