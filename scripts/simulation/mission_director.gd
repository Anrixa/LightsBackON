extends RefCounted
## Mission director (V02; blueprint p.7 C01 known solution, p.18 shared mission rules).
##
## Owns objectives, access latches, the final supply verification and extraction. Host-only and authoritative;
## it reads the grid only through canonical_state() and never changes supply itself. All durations are integer
## ticks at the grid rate (ADR-003). Rules:
## - An access latch counts continuous ticks its consumer is supplied; at the threshold it latches for the rest of
##   the contract (switching the load off later does not undo it) and grants an access flag to the repair service.
## - Final verification counts continuous ticks during which every required consumer is supplied *from the grid
##   source* (not a temporary generator). Any loss resets it to zero (SIM14).
## - Extraction: any connected player may start the countdown once verification holds, every portable item is
##   stowed and every connected player is in the extraction zone. Any player may cancel; leaving the zone, losing
##   verification or unstowing equipment cancels it (MIS04). Disconnected players are not required.
## Excluded loads (C01: the sign) never count toward anything.

const PowerGrid := preload("res://scripts/simulation/power_grid.gd")
const Interaction := preload("res://scripts/interaction/interaction_service.gd")
const Equipment := preload("res://scripts/interaction/equipment_service.gd")

const SCHEMA: int = 1
const STATUS_DONE: String = "done"
const STATUS_ACTIVE: String = "active"
const STATUS_PENDING: String = "pending"

var _grid: PowerGrid
var _interaction: Interaction
var _equipment: Equipment
var _grid_source: String = ""
var _grid_sources: Array[String] = []  # contract-approved permanent sources; legacy uses one
var _required: Array[String] = []
var _excluded: Array[String] = []
var _latches: Dictionary = {}  # latch id -> {"id", "consumer", "supplied_ticks", "grants"}
var _latch_ticks: Dictionary = {}  # latch id -> continuous supplied ticks so far
var _latched: Dictionary = {}  # latch id -> tick it latched
var _fixed_ladders: Dictionary = {}  # ladder id -> access flag
var _ladder_access: Dictionary = {}  # ladder id -> first authoritative use tick
var _verify_needed: int = 0
var _verify_ticks: int = 0
var _zone: String = ""
var _countdown_total: int = 0
var _countdown_left: int = -1  # -1 = no countdown running
var _completed_tick: int = -1
var _objectives: Array[Dictionary] = []
var _max_visible: int = 0
var _optional: Array[String] = []
## C02+: optional services can have a contract-local opening-time cutoff.
## -1 retains C01's original "on grid at completion" behaviour byte-for-byte.
var _optional_deadline_ticks: int = -1
var _optional_first_supplied: Dictionary = {}  # optional ID -> first authoritative supplied tick, if within cutoff
var _continuous_optional: Dictionary = {}  # conditional uninterrupted-service bonus
var _continuous_ok: bool = true
## Optional host-observed meter finding; absent from legacy contracts and saves.
var _meter_evidence: Dictionary = {}
var _evidence_observed: bool = false
var _evidence_reset_attempted: bool = false
var _trip_allowance: int = 0
var _trips: int = 0
var _recoveries: int = 0
var _results: Dictionary = {}  # frozen at completion: later commands cannot change a finished run's report or reward
var _players: Dictionary = {}  # connected player id -> true
var _in_zone: Dictionary = {}  # player id -> true
var _now: int = 0


## definition: content/contracts/<c>/mission.json. Returns diagnostics; empty means loaded.
func load_definition(definition: Dictionary, grid: PowerGrid, interaction: Interaction, equipment: Equipment) -> Array[Dictionary]:
	_grid = grid
	_interaction = interaction
	_equipment = equipment
	var nodes: Dictionary = grid.canonical_state()["nodes"]
	var errs: Array[Dictionary] = []
	var src: Variant = definition.get("grid_source")
	if not (src is String and nodes.has(src) and nodes[src]["kind"] == PowerGrid.KIND_SOURCE):
		errs.append(PowerGrid.diag("BAD_MISSION", "grid_source must be a grid source", []))
	else:
		_grid_source = src
	# C08 permits two named permanent sources. Single-source contracts retain their old behavior.
	_grid_sources = [_grid_source] if not _grid_source.is_empty() else [] as Array[String]
	if definition.has("grid_sources"):
		var names: Variant = definition["grid_sources"]
		if not names is Array or (names as Array).is_empty():
			errs.append(PowerGrid.diag("BAD_MISSION", "grid_sources must be a nonempty array", []))
		else:
			_grid_sources = []
			for name: Variant in names:
				if not (name is String and nodes.has(name) and nodes[name]["kind"] == PowerGrid.KIND_SOURCE) or _grid_sources.has(name):
					errs.append(PowerGrid.diag("BAD_MISSION", "grid_sources must name distinct existing sources", []))
				else:
					_grid_sources.append(name)
			if not _grid_sources.has(_grid_source):
				errs.append(PowerGrid.diag("BAD_MISSION", "grid_source must belong to grid_sources", []))
	_required = _consumer_list(definition.get("required_consumers", []), nodes, "required_consumers", errs)
	_excluded = _consumer_list(definition.get("excluded_loads", []), nodes, "excluded_loads", errs)
	for c: String in _excluded:
		if _required.has(c):
			errs.append(PowerGrid.diag("BAD_MISSION", "%s cannot be both required and excluded" % c, [c]))
	for rec: Variant in definition.get("access_latches", []):
		var l: Dictionary = rec if rec is Dictionary else {}
		var n: Variant = PowerGrid.to_int(l.get("supplied_ticks"))
		if not PowerGrid.is_valid_id(l.get("id")) or not (l.get("consumer") is String and nodes.has(l["consumer"])) \
				or n == null or int(n) < 1 or not (l.get("grants") is String):
			errs.append(PowerGrid.diag("BAD_MISSION", "access latch %s needs id, consumer, supplied_ticks >= 1, grants" % str(l.get("id")), []))
		else:
			_latches[l["id"]] = {"id": l["id"], "consumer": l["consumer"], "supplied_ticks": int(n), "grants": l["grants"]}
			_latch_ticks[l["id"]] = 0
	# Fixed ladders are contract access interactions, not electrical nodes.
	for rec: Variant in definition.get("fixed_ladders", []):
		var ladder: Dictionary = rec if rec is Dictionary else {}
		var ladder_id: Variant = ladder.get("id")
		var grant: Variant = ladder.get("grants")
		if not PowerGrid.is_valid_id(ladder_id) or not PowerGrid.is_valid_id(grant) or _fixed_ladders.has(ladder_id):
			errs.append(PowerGrid.diag("BAD_MISSION", "fixed ladder needs unique ID and grant flag", []))
		else:
			_fixed_ladders[ladder_id] = grant
	var verify: Variant = PowerGrid.to_int(definition.get("final_verification_ticks"))
	var ex: Dictionary = definition.get("extraction", {})
	var countdown: Variant = PowerGrid.to_int(ex.get("countdown_ticks"))
	var visible: Variant = PowerGrid.to_int(definition.get("max_visible_objectives"))
	if verify == null or int(verify) < 1 or countdown == null or int(countdown) < 1 or not PowerGrid.is_valid_id(ex.get("zone")) \
			or visible == null or int(visible) < 1:
		errs.append(PowerGrid.diag("BAD_MISSION", "final_verification_ticks, extraction.countdown_ticks, extraction.zone, max_visible_objectives", []))
	else:
		_verify_needed = int(verify)
		_countdown_total = int(countdown)
		_zone = ex["zone"]
		_max_visible = int(visible)
	_optional = _consumer_list(definition.get("optional_services", []), nodes, "optional_services", errs)
	var deadline_raw: Variant = definition.get("optional_deadline_ticks", null)
	if deadline_raw != null:
		var deadline: Variant = PowerGrid.to_int(deadline_raw)
		if deadline == null or int(deadline) < 1 or _optional.is_empty():
			errs.append(PowerGrid.diag("BAD_MISSION",
				"optional_deadline_ticks requires >=1 and an optional service", []))
		else:
			_optional_deadline_ticks = int(deadline)
	# Uninterrupted service is monitored on every accepted host intent AND grid tick;
	# single-source legacy checkpoint shapes are deliberately unchanged.
	var uninterrupted: Variant = definition.get("optional_continuous_supply", null)
	if uninterrupted != null:
		var opt: Dictionary = uninterrupted if uninterrupted is Dictionary else {}
		if not (PowerGrid.is_valid_id(opt.get("id")) and opt.get("consumer") is String
				and _required.has(opt.get("consumer")) and _optional.is_empty()):
			errs.append(PowerGrid.diag("BAD_MISSION", "optional_continuous_supply needs an ID and required consumer", []))
		else:
			_continuous_optional = {"id": opt["id"], "consumer": opt["consumer"]}
			_continuous_ok = _on_grid(opt["consumer"], grid.canonical_state())
	var evidence_raw: Variant = definition.get("optional_meter_evidence", null)
	if evidence_raw != null:
		var evidence: Dictionary = evidence_raw if evidence_raw is Dictionary else {}
		var eid: Variant = evidence.get("edge")
		var breaker: Variant = evidence.get("breaker")
		var label_rating: Variant = PowerGrid.to_int(evidence.get("label_capacity"))
		var real_rating: Variant = PowerGrid.to_int(evidence.get("actual_capacity"))
		var edges: Dictionary = grid.canonical_state()["edges"]
		if not (PowerGrid.is_valid_id(evidence.get("id")) and PowerGrid.is_valid_id(evidence.get("panel"))
				and breaker is String and nodes.has(breaker) and nodes[breaker]["kind"] == PowerGrid.KIND_JUNCTION
				and eid is String and edges.has(eid) and edges[eid]["to"] == breaker
				and label_rating != null and real_rating != null and int(real_rating) >= 1
				and int(label_rating) > int(real_rating) and edges[eid]["capacity"] == int(real_rating)
				and _optional.is_empty()):
			errs.append(PowerGrid.diag("BAD_MISSION", "meter evidence needs a real under-rated feeder and stale larger label", []))
		else:
			_meter_evidence = {"id": evidence["id"], "panel": evidence["panel"], "breaker": breaker,
				"edge": eid, "label_capacity": int(label_rating), "actual_capacity": int(real_rating)}
	var allowance: Variant = PowerGrid.to_int(definition.get("tutorial_trip_allowance", 0))
	if allowance == null or int(allowance) < 0:
		errs.append(PowerGrid.diag("BAD_MISSION", "tutorial_trip_allowance must be an int >= 0", []))
	else:
		_trip_allowance = int(allowance)
	for rec: Variant in definition.get("objectives", []):
		if not (rec is Dictionary and PowerGrid.is_valid_id(rec.get("id")) and rec.get("text_key") is String and rec.get("done_when") is Dictionary):
			errs.append(PowerGrid.diag("BAD_MISSION", "objective needs id, text_key, done_when", []))
		else:
			_objectives.append(rec)
	return errs


func _consumer_list(raw: Variant, nodes: Dictionary, what: String, errs: Array[Dictionary]) -> Array[String]:
	var out: Array[String] = []
	for c: Variant in (raw if raw is Array else []):
		if not (c is String and nodes.has(c) and nodes[c]["kind"] == PowerGrid.KIND_CONSUMER):
			errs.append(PowerGrid.diag("BAD_MISSION", "%s: %s is not a grid consumer" % [what, str(c)], []))
		else:
			out.append(c)
	out.sort()
	return out


# ---------- players (host reports joins, leaves and zone presence) ----------

func player_joined(player: String) -> void:
	_players[player] = true


## A disconnected player is no longer required in the zone; if the countdown was waiting only on them it continues.
func player_left(player: String) -> void:
	_players.erase(player)
	_in_zone.erase(player)


## Host movement says whether the player stands in a zone. Leaving the extraction zone cancels a countdown (MIS04).
func set_in_zone(player: String, zone: String, inside: bool) -> Array[Dictionary]:
	if zone != _zone or not _players.has(player):
		return []
	if inside:
		_in_zone[player] = true
		return []
	_in_zone.erase(player)
	return _cancel("player_left_zone")


# ---------- host tick ----------

## Call once per grid tick, after the grid has stepped. Returns this tick's mission events.
func tick(now: int) -> Array[Dictionary]:
	_now = now
	var events: Array[Dictionary] = []
	if _completed_tick >= 0:
		return events
	observe_supply_state()
	var st: Dictionary = _grid.canonical_state()
	for lid: String in _sorted(_latches.keys()):
		if _latched.has(lid):
			continue
		var l: Dictionary = _latches[lid]
		var valid_supply: bool = _on_grid(l["consumer"], st) if _grid_sources.size() > 1 else st["nodes"][l["consumer"]]["supplied"]
		_latch_ticks[lid] = int(_latch_ticks[lid]) + 1 if valid_supply else 0
		if int(_latch_ticks[lid]) >= int(l["supplied_ticks"]):
			_latched[lid] = now
			_interaction.set_access(l["grants"], true)
			events.append({"type": "latch", "id": lid, "grants": l["grants"], "tick": now})
	# An optional opening deadline affects a bonus only, never repair/access,
	# extraction, required supply, or a host's grid state.
	if _optional_deadline_ticks >= 0 and now <= _optional_deadline_ticks:
		for optional_id: String in _optional:
			if not _optional_first_supplied.has(optional_id) and _on_grid(optional_id, st):
				_optional_first_supplied[optional_id] = now
				events.append({"type": "optional_service_on_time", "id": optional_id, "tick": now})
	var was_verified: bool = verified()
	_verify_ticks = mini(_verify_ticks + 1, _verify_needed) if _all_required_on_grid(st) else 0
	if verified() and not was_verified:
		events.append({"type": "verified", "tick": now})
	elif was_verified and not verified():
		events.append({"type": "verification_lost", "tick": now})
	if _countdown_left >= 0:
		var blocker: String = _extract_blocker()
		if blocker != "":
			events.append_array(_cancel(blocker.to_lower()))
		else:
			_countdown_left -= 1
			if _countdown_left <= 0:
				_countdown_left = -1
				_completed_tick = now
				_results = _build_results()
				events.append({"type": "mission_complete", "tick": now})
	return events


## Host passes the tick's grid and recovery events here so the results report can count them.
func note_events(events: Array[Dictionary]) -> void:
	if _completed_tick >= 0:
		return
	for e: Dictionary in events:
		if e.get("type") == "trip":
			_trips += 1
		elif e.get("type") == "player_recovered":
			_recoveries += 1


## Host-side supply observation after each processed command prevents same-tick
## off/on toggles from concealing a DINER interruption from the optional scorer.
func observe_supply_state() -> void:
	if _continuous_optional.is_empty() or not _continuous_ok or _completed_tick >= 0:
		return
	if not _on_grid(_continuous_optional["consumer"], _grid.canonical_state()):
		_continuous_ok = false


## Host-only evidence: a real inspected panel must show the 10 PU component
## capacity and branch demand above that capacity before the first reset attempt.
func note_meter_inspection(panel: String, reading: Dictionary) -> void:
	if _meter_evidence.is_empty() or _evidence_observed or _evidence_reset_attempted or _completed_tick >= 0:
		return
	if panel != _meter_evidence["panel"]:
		return
	var cap: Dictionary = reading.get("capacity_pu", {})
	var demand: Dictionary = reading.get("demand_pu", {})
	if not cap.get("known", false) or not demand.get("known", false):
		return
	var actual: Variant = PowerGrid.to_int(cap.get("value"))
	var pu: Variant = PowerGrid.to_int(demand.get("value"))
	if actual == null or pu == null:
		return
	if int(actual) == int(_meter_evidence["actual_capacity"]) and int(pu) > int(actual):
		_evidence_observed = true


## The first *attempt* matters, not just the first successful reset. A genuine
## in-range reset intent is counted even if the grid correctly refuses overload.
func note_breaker_reset_attempt(target: String, field: String, value: bool) -> void:
	if _meter_evidence.is_empty() or _evidence_reset_attempted or _completed_tick >= 0:
		return
	if target == _meter_evidence["breaker"] and field == "tripped" and not value:
		_evidence_reset_attempted = true


## Results report (blueprint p.12 scoring): required restored, optional services restored, trips, crew recoveries,
## time and equipment collected; stars: 1 completion, 2 every optional service restored (granted when the contract has
## none), 3 no preventable branch trips after the tutorial allowance. No speed star. Empty until the mission is
## complete, then frozen: it is captured on the completion tick, so commands after completion cannot change it.
func results() -> Dictionary:
	return _results.duplicate(true)


func _build_results() -> Dictionary:
	var st: Dictionary = _grid.canonical_state()
	var restored: int = 0
	for c: String in _required:
		if _on_grid(c, st):
			restored += 1
	var optional_restored: Array[String] = []
	for c: String in _optional:  # already sorted by _consumer_list
		if _on_grid(c, st) and (_optional_deadline_ticks < 0 or _optional_first_supplied.has(c)):
			optional_restored.append(c)
	if not _meter_evidence.is_empty() and _evidence_observed:
		optional_restored.append(_meter_evidence["id"])
	if not _continuous_optional.is_empty() and _continuous_ok and _on_grid(_continuous_optional["consumer"], st):
		optional_restored.append(_continuous_optional["id"])
	var optional_total: int = _optional.size() + (1 if not _meter_evidence.is_empty() else 0) + (1 if not _continuous_optional.is_empty() else 0)
	var preventable: int = maxi(0, _trips - _trip_allowance)
	var stars: int = 1 + (1 if optional_restored.size() == optional_total else 0) + (1 if preventable == 0 else 0)
	return {"required_restored": restored, "required_total": _required.size(), "optional_services": optional_restored,
		"optional_total": optional_total, "trips": _trips, "preventable_trips": preventable, "crew_recoveries": _recoveries,
		"ticks": _completed_tick, "equipment_collected": _equipment.all_stowed(), "stars": stars}


# ---------- extraction ----------

## action "start" or "cancel". Any connected player may do either (blueprint p.7; HANDOFF issue 5: both rules apply).
func request_extract(player: String, action: String) -> Dictionary:
	if not _players.has(player):
		return _refuse("UNKNOWN_PLAYER", "player is not in this mission", [])
	if _completed_tick >= 0:
		return _refuse("ALREADY_COMPLETE", "the contract is already complete", [])
	if action == "cancel":
		if _countdown_left < 0:
			return _refuse("NO_COUNTDOWN", "no departure countdown is running", [])
		return {"ok": true, "events": _cancel("cancelled_by_player")}
	if action != "start":
		return _refuse("UNKNOWN_ACTION", "extraction action must be start or cancel", [])
	if _countdown_left >= 0:
		return {"ok": true, "duplicate": true}
	var blocker: String = _extract_blocker()
	if blocker != "":
		return _refuse(blocker, _blocker_message(blocker), [])
	_countdown_left = _countdown_total
	return {"ok": true, "events": [{"type": "countdown_started", "ticks": _countdown_total, "tick": _now}]}


## First reason extraction cannot start or continue, as a refusal code; "" when it can.
func _extract_blocker() -> String:
	if not verified():
		return "NOT_VERIFIED"
	if not _equipment.all_stowed():
		return "EQUIPMENT_NOT_STOWED"
	if _players.is_empty():
		return "NO_PLAYERS"
	for p: String in _players:
		if not _in_zone.has(p):
			return "CREW_NOT_IN_ZONE"
	return ""


func _blocker_message(code: String) -> String:
	match code:
		"NOT_VERIFIED":
			return "every required building needs grid supply for the full verification time"
		"EQUIPMENT_NOT_STOWED":
			return "stow the deployed equipment at a storage point first"
		"CREW_NOT_IN_ZONE":
			return "everyone still connected must be at the van"
	return "extraction is not possible yet"


func _cancel(reason: String) -> Array[Dictionary]:
	if _countdown_left < 0:
		return []
	_countdown_left = -1
	return [{"type": "countdown_cancelled", "reason": reason, "tick": _now}]


# ---------- state ----------

func verified() -> bool:
	return _verify_needed > 0 and _verify_ticks >= _verify_needed


func is_latched(latch_id: String) -> bool:
	return _latched.has(latch_id)


## The host supplies range and identity. Presentation movement to an authored
## rooftop landing is separate; this is only the durable authorization receipt.
func use_ladder(ladder_id: String, in_range: bool) -> Dictionary:
	if not _fixed_ladders.has(ladder_id):
		return _refuse("UNKNOWN_LADDER", "unknown ladder %s" % ladder_id, [ladder_id])
	if not in_range:
		return _refuse("NOT_IN_RANGE", "move closer to %s" % ladder_id, [ladder_id])
	if _completed_tick >= 0:
		return _refuse("ALREADY_COMPLETE", "mission already complete", [])
	if _ladder_access.has(ladder_id):
		return {"ok": true, "duplicate": true}
	_ladder_access[ladder_id] = _now
	var grant: String = _fixed_ladders[ladder_id]
	_interaction.set_access(grant, true)
	return {"ok": true, "events": [{"type": "ladder_access", "id": ladder_id, "grants": grant, "tick": _now}]}


func is_complete() -> bool:
	return _completed_tick >= 0


## Objective rows for the HUD: every objective with its status; "visible" marks the first max_visible_objectives
## not yet done (blueprint p.11: at most three rows). Status is computed from host state only.
func objectives() -> Array[Dictionary]:
	var st: Dictionary = _grid.canonical_state()
	var out: Array[Dictionary] = []
	var shown: int = 0
	for o: Dictionary in _objectives:
		var done: bool = _objective_done(o["done_when"], st)
		var row: Dictionary = {"id": o["id"], "text_key": o["text_key"], "status": STATUS_DONE if done else STATUS_PENDING, "visible": false}
		if not done and shown < _max_visible:
			row["status"] = STATUS_ACTIVE
			row["visible"] = true
			shown += 1
		out.append(row)
	return out


func _objective_done(cond: Dictionary, st: Dictionary) -> bool:
	if cond.has("supplied_from_grid"):
		for c: Variant in cond["supplied_from_grid"]:
			if not _on_grid(str(c), st):
				return false
		return true
	if cond.has("latch"):
		return _latched.has(cond["latch"])
	if cond.has("ladder"):
		return _ladder_access.has(cond["ladder"])
	if cond.has("continuous_supply"):
		return not _continuous_optional.is_empty() and cond["continuous_supply"] == _continuous_optional["id"] \
			and _completed_tick >= 0 and _continuous_ok and _on_grid(_continuous_optional["consumer"], st)
	if cond.has("meter_evidence"):
		return not _meter_evidence.is_empty() and cond["meter_evidence"] == _meter_evidence["id"] and _evidence_observed
	if cond.has("verified"):
		return verified()
	if cond.has("stowed"):
		return _equipment.all_stowed() and verified()  # stowing counts once the site is verified, so the row order reads right
	if cond.has("completed"):
		return is_complete()
	return false


func canonical_state() -> Dictionary:
	var latch_ticks: Dictionary = {}
	for lid: String in _latch_ticks:
		latch_ticks[lid] = _latch_ticks[lid]
	var out: Dictionary = {"schema": SCHEMA, "latch_ticks": latch_ticks, "latched": _latched.duplicate(), "verify_ticks": _verify_ticks,
		"trips": _trips, "recoveries": _recoveries,
		"countdown_left": _countdown_left, "completed_tick": _completed_tick, "in_zone": _sorted(_in_zone.keys())}
	if _optional_deadline_ticks >= 0:
		out["optional_first_supplied"] = _optional_first_supplied.duplicate()
	if not _meter_evidence.is_empty():
		out["optional_meter_evidence"] = {"observed": _evidence_observed, "reset_attempted": _evidence_reset_attempted}
	if not _continuous_optional.is_empty():
		out["optional_continuous_supply"] = {"ok": _continuous_ok}
	if not _continuous_optional.is_empty():
		out["optional_continuous_supply"] = {"ok": _continuous_ok}
	if not _fixed_ladders.is_empty():
		out["ladder_access"] = _ladder_access.duplicate()
	return out


## Durable mission progress for host checkpoints: latches, continuous-supply counters, scoring counters and the frozen
## results. Not stored: the extraction countdown and zone presence (players re-enter the zone after a load and restart
## the countdown), and anything derived from the grid (recomputed from its saved causes).
func durable_state() -> Dictionary:
	var latch_ticks: Dictionary = {}
	for lid: String in _latch_ticks:
		latch_ticks[lid] = _latch_ticks[lid]
	var out: Dictionary = {"schema": SCHEMA, "latch_ticks": latch_ticks, "latched": _latched.duplicate(), "verify_ticks": _verify_ticks,
		"trips": _trips, "recoveries": _recoveries, "completed_tick": _completed_tick, "results": _results.duplicate(true)}
	if _optional_deadline_ticks >= 0:
		out["optional_first_supplied"] = _optional_first_supplied.duplicate()
	if not _meter_evidence.is_empty():
		out["optional_meter_evidence"] = {"observed": _evidence_observed, "reset_attempted": _evidence_reset_attempted}
	if not _fixed_ladders.is_empty():
		out["ladder_access"] = _ladder_access.duplicate()
	return out


## Restores durable_state() onto a freshly loaded director. Refuses (without change) anything that does not match this
## contract's latches or is not a non-negative int. Granted access flags are restored by the interaction service.
func restore_state(d: Dictionary) -> Array[Dictionary]:
	var bad: Array[Dictionary] = [PowerGrid.diag("BAD_SAVE", "mission state does not match this contract", [])]
	if d.get("schema") != SCHEMA or not (d.get("latch_ticks") is Dictionary and d.get("latched") is Dictionary and d.get("results") is Dictionary):
		return bad
	var counters: Dictionary = {}
	for key: String in ["verify_ticks", "trips", "recoveries", "completed_tick"]:
		var v: Variant = PowerGrid.to_int(d.get(key))
		if v == null or int(v) < (-1 if key == "completed_tick" else 0):
			return bad
		counters[key] = int(v)
	var latch_ticks: Dictionary = {}
	for lid: Variant in d["latch_ticks"]:
		var v: Variant = PowerGrid.to_int(d["latch_ticks"][lid])
		if not _latches.has(lid) or v == null or int(v) < 0:
			return bad
		latch_ticks[lid] = int(v)
	var latched: Dictionary = {}
	for lid: Variant in d["latched"]:
		var v: Variant = PowerGrid.to_int(d["latched"][lid])
		if not _latches.has(lid) or v == null:
			return bad
		latched[lid] = int(v)
	# C01 legacy checkpoint dictionaries remain unchanged. Deadline contracts
	# require validated persisted first-supply ticks, or reject without mutation.
	var optional_first: Dictionary = {}
	if _optional_deadline_ticks >= 0:
		if not d.get("optional_first_supplied") is Dictionary:
			return bad
		for id: Variant in d["optional_first_supplied"]:
			var when: Variant = PowerGrid.to_int(d["optional_first_supplied"][id])
			if not (id is String and _optional.has(id)) or when == null \
					or int(when) < 1 or int(when) > _optional_deadline_ticks:
				return bad
			optional_first[id] = int(when)
	# Evidence state is saved only by contracts that declare this objective.
	# Verify the complete shape before mutating mission data (fail closed).
	var observed: bool = false
	var reset_attempted: bool = false
	if not _meter_evidence.is_empty():
		var record: Variant = d.get("optional_meter_evidence")
		if not (record is Dictionary and (record as Dictionary).size() == 2
				and record.get("observed") is bool and record.get("reset_attempted") is bool):
			return bad
		observed = record["observed"]
		reset_attempted = record["reset_attempted"]
	var continuous_ok: bool = true
	if not _continuous_optional.is_empty():
		var rec: Variant = d.get("optional_continuous_supply")
		if not (rec is Dictionary and (rec as Dictionary).size() == 1 and rec.get("ok") is bool):
			return bad
		continuous_ok = rec["ok"]
	# Validate all ladder keys before any state mutation. Legacy missions omit them.
	var ladder_access: Dictionary = {}
	if not _fixed_ladders.is_empty():
		if not d.get("ladder_access") is Dictionary:
			return bad
		for ladder_id: Variant in d["ladder_access"]:
			var first_tick: Variant = PowerGrid.to_int(d["ladder_access"][ladder_id])
			if not (ladder_id is String and _fixed_ladders.has(ladder_id)) or first_tick == null or int(first_tick) < 0:
				return bad
			ladder_access[ladder_id] = int(first_tick)
	if (counters["completed_tick"] >= 0) == (d["results"] as Dictionary).is_empty():
		return bad  # a finished run must carry its frozen results, an unfinished one none
	for lid: String in latch_ticks:
		_latch_ticks[lid] = latch_ticks[lid]
	_latched = latched
	_verify_ticks = mini(counters["verify_ticks"], _verify_needed)
	_trips = counters["trips"]
	_recoveries = counters["recoveries"]
	_completed_tick = counters["completed_tick"]
	_results = (d["results"] as Dictionary).duplicate(true)
	_optional_first_supplied = optional_first
	_evidence_observed = observed
	_evidence_reset_attempted = reset_attempted
	_continuous_ok = continuous_ok
	_ladder_access = ladder_access
	for ladder_id: String in _ladder_access:
		_interaction.set_access(_fixed_ladders[ladder_id], true)
	_countdown_left = -1
	_in_zone = {}
	return []


# ---------- supply attribution ----------

func _all_required_on_grid(st: Dictionary) -> bool:
	for c: String in _required:
		if not _on_grid(c, st):
			return false
	return true


## Supplied, and the live path above it reaches the grid source (not a temporary generator).
func _on_grid(consumer: String, st: Dictionary) -> bool:
	if not st["nodes"][consumer]["supplied"]:
		return false
	var root: String = _root_of(consumer, st)
	if not _grid_sources.has(root):
		return false
	# A multi-source contract cannot treat an over-capacity source as valid
	# supply for access, verification or a continuity reward.
	return _grid_sources.size() == 1 or not st["nodes"][root]["overloaded"]


## Walks live incoming edges up to the source. The energized graph is a tree (dual supply is refused), so there is
## at most one live incoming edge per node.
func _root_of(nid: String, st: Dictionary) -> String:
	var node: String = nid
	for _guard: int in st["nodes"].size() + 1:
		if st["nodes"][node]["kind"] == PowerGrid.KIND_SOURCE:
			return node
		var up: String = ""
		for eid: String in st["edges"]:
			var e: Dictionary = st["edges"][eid]
			if e["to"] == node and e["energized"]:
				up = e["from"]
				break
		if up == "":
			return ""
		node = up
	return ""


static func _refuse(code: String, message: String, ids: Array) -> Dictionary:
	var d: Dictionary = PowerGrid.diag(code, message, ids)
	return {"ok": false, "code": code, "key": "mission.refused." + code.to_lower(), "message": message, "ids": d["ids"]}


static func _sorted(keys: Array) -> Array[String]:
	var out: Array[String] = []
	out.assign(keys)
	out.sort()
	return out
