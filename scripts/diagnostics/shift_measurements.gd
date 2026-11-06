extends RefCounted
## Opt-in, in-memory C01 playtest observations. This never uploads telemetry,
## accesses an account or network ID, or mutates authoritative game state.
## Only enumerated event kinds, host ticks and bounded integer values are stored.

const SCHEMA_VERSION: int = 1
const TICKS_PER_SECOND: int = 10
const KINDS: Array[String] = [
	"session_started", "session_left", "session_completed", "results_opened",
	"objective_visible", "objective_completed", "idle_started", "idle_ended",
	"first_repair", "protection_trip", "hint_requested", "drain_latched",
	"supply_verified", "verification_lost", "extraction_requested",
	"extraction_cancelled", "player_recovered", "connection_lost"
]

var _enabled: bool = false
var _closed: bool = false
var _limit: int = 0
var _idle_ticks: int = 0
var _max_objectives: int = 0
var _last_tick: int = 0
var _dropped: int = 0
var _events: Array[Dictionary] = []
var _objective_states: Dictionary = {}
var _last_activity_tick: int = 0
var _idle_since_tick: int = -1


## No recording is possible until a valid policy AND explicit consent are supplied.
## Passing false deliberately keeps the same production code path without data.
func begin(opted_in: bool, policy: Dictionary) -> bool:
	_enabled = false
	_closed = false
	_events.clear()
	_last_tick = 0
	_dropped = 0
	_objective_states.clear()
	_last_activity_tick = 0
	_idle_since_tick = -1
	if not (policy.get("max_events") is int and policy.get("idle_threshold_ticks") is int
			and policy.get("max_objectives") is int):
		return false
	_limit = int(policy["max_events"])
	_idle_ticks = int(policy["idle_threshold_ticks"])
	_max_objectives = int(policy["max_objectives"])
	if _limit < 16 or _limit > 4096 or _idle_ticks < 10 or _idle_ticks > 36000 \
			or _max_objectives < 1 or _max_objectives > 32:
		return false
	_enabled = opted_in
	if _enabled:
		note("session_started", 0)
	return true


func enabled() -> bool:
	return _enabled


## No caller-supplied strings, dictionary payloads, positions or IDs reach a report.
## Out-of-order timestamps are refused rather than silently misrepresented.
func note(kind: String, tick: int, objective: int = -1, value: int = 0) -> bool:
	if not _enabled or _closed or not KINDS.has(kind) or tick < _last_tick \
			or tick < 0 or objective < -1 or objective >= _max_objectives \
			or value < 0 or value > 360000:
		return false
	if kind.begins_with("objective_") != (objective >= 0):
		return false
	_last_tick = tick
	if _events.size() >= _limit:
		_dropped += 1
		return false
	var row: Dictionary = {"kind": kind, "tick": tick}
	if objective >= 0:
		row["objective_index"] = objective
	if value > 0:
		row["value_ticks"] = value
	_events.append(row)
	return true


## Reports can be inspected without granting access to live internal arrays.
func snapshot() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"contract": "C01", "tick_rate_hz": TICKS_PER_SECOND,
		"opted_in": _enabled,
		"events": _events.duplicate(true),
		"dropped_events": _dropped
	}


## Observe the host's objective rows by ordinal alone, never by text_key or ID.
## The initial snapshot is a baseline: resumed, already-done work is not
## attributed to this playtest as a new completion.
func observe_tick(tick: int, objectives: Array[Dictionary]) -> void:
	if not _enabled or _closed or tick < _last_tick:
		return
	for index: int in range(mini(objectives.size(), _max_objectives)):
		var row: Dictionary = objectives[index]
		var status: String = str(row.get("status", ""))
		if not ["pending", "active", "done"].has(status):
			continue
		var visible: bool = bool(row.get("visible", false))
		var key: int = index
		if _objective_states.has(key):
			var previous: Dictionary = _objective_states[key]
			if status == "done" and str(previous["status"]) != "done":
				note("objective_completed", tick, index)
			elif visible and not bool(previous["visible"]) and status != "done":
				note("objective_visible", tick, index)
		elif visible and status != "done":
			note("objective_visible", tick, index)
		_objective_states[key] = {"status": status, "visible": visible}
	if _idle_since_tick < 0 and tick - _last_activity_tick >= _idle_ticks:
		_idle_since_tick = tick
		note("idle_started", tick)
	_last_tick = tick


## Movement, accepted interactions and explicit hint requests end idle spans.
## Pausing the host pauses its clock; no wall-clock idle time is fabricated.
func mark_activity(tick: int) -> void:
	if not _enabled or _closed or tick < _last_tick:
		return
	if _idle_since_tick >= 0:
		note("idle_ended", tick, -1, mini(tick - _idle_since_tick, 360000))
		_idle_since_tick = -1
	_last_activity_tick = tick
	_last_tick = tick
