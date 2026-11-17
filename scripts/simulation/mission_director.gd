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
var _latches: Dictionary = {}  # latch id -> definition, optional source restricts qualifying power
var _optional_latch_rewards: Array[String] = []  # only authored contracts add latched bonuses
var _latch_ticks: Dictionary = {}  # latch id -> continuous supplied ticks so far
var _latched: Dictionary = {}  # latch id -> tick it latched
var _fixed_ladders: Dictionary = {}  # ladder id -> access flag
var _ladder_requires: Dictionary = {}  # ladder id -> required completed supply latch
var _ladder_access: Dictionary = {}  # ladder id -> first authoritative use tick
## C09-only host wind-event state; legacy contract snapshots remain unchanged.
var _wind_routes: Dictionary = {}
var _wind_elapsed: int = 0
var _wind_access_route: String = ""
var _wind_roof_players: Dictionary = {}

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
## Original C02 optional opening-time venue latches (not a mission completion gate).
## Elapsed clock is durable/relative, never inferred from resumed host absolute ticks.
var _opening_venues: Array[String] = []
var _opening_sources: Array[String] = []
var _opening_needed: int = 0
var _opening_deadline: int = 0
var _opening_started: bool = false
var _opening_elapsed: int = 0
var _opening_ticks: Dictionary = {}
var _opening_latched: Dictionary = {}  # consumer -> relative host elapsed tick
var _opening_failed: bool = false
## C10: mission-relative deadline for a continuously supplied optional latch.
## A late latch may complete, but never recovers its missed event award.
var _timed_latch_option: Dictionary = {}
var _timed_latch_elapsed: int = 0
var _timed_latch_on_time: bool = false
var _timed_latch_missed: bool = false
## C05 deadline: first successful host equipment pickup starts the clock.
## It is durable, never reset by unloading, and cannot block mandatory completion.
var _pickup_option: Dictionary = {}
var _pickup_started: bool = false
var _pickup_elapsed: int = 0
var _pickup_on_time: bool = false
var _pickup_missed: bool = false
## C06 optional: cumulative outage across all host ticks; latching a miss cannot undo it.
var _outage_option: Dictionary = {}
var _outage_ticks: int = 0
var _outage_failed: bool = false
var _outage_unsupplied: bool = false
var _outage_last_valid: bool = false  # transition-only same-tick interruption detector
## C11 only: a telecom outage is optional and fails after 50 consecutive
## unsupplied host ticks. Its clock never trusts client-reported time or routes.
var _interruption_option: Dictionary = {}
var _interruption_ticks: int = 0
var _interruption_failed: bool = false
var _interruption_pending: bool = false
var _interruption_last_valid: bool = false
## C12-only host-authored finale event sequence. Presentation events do not
## lock input, change electrical state or certify the physical level.
var _finale: Dictionary = {}
var _finale_started: bool = false
var _finale_elapsed: int = 0
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
	_grid_sources = []
	if not _grid_source.is_empty():
		_grid_sources.append(_grid_source)
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
			var source: Variant = l.get("source", "")
			if not (source is String) or (source != "" and (not nodes.has(source) or nodes[source]["kind"] != PowerGrid.KIND_SOURCE)):
				errs.append(PowerGrid.diag("BAD_MISSION", "access latch source must be a real power source", [l["id"]]))
			else:
				_latches[l["id"]] = {"id": l["id"], "consumer": l["consumer"], "supplied_ticks": int(n), "grants": l["grants"]}
				if source != "":
					_latches[l["id"]]["source"] = source
				_latch_ticks[l["id"]] = 0
	var reward_raw: Variant = definition.get("optional_latch_rewards", [])
	if not reward_raw is Array:
		errs.append(PowerGrid.diag("BAD_MISSION", "optional_latch_rewards must be an array", []))
	else:
		for reward: Variant in reward_raw:
			if not (reward is String and _latches.has(reward)) or _optional_latch_rewards.has(reward):
				errs.append(PowerGrid.diag("BAD_MISSION", "optional latch reward must name one unique access latch", []))
			else:
				_optional_latch_rewards.append(reward)
	var timed_raw: Variant = definition.get("optional_timed_latch", null)
	if timed_raw != null:
		var timed: Dictionary = timed_raw if timed_raw is Dictionary else {}
		var lid: Variant = timed.get("latch")
		var limit: Variant = PowerGrid.to_int(timed.get("deadline_ticks"))
		if not (timed.size() == 3 and lid is String and _latches.has(lid)
				and _optional_latch_rewards.has(lid) and limit != null and
				int(limit) >= int(_latches[lid]["supplied_ticks"]) and
				timed.get("start_trigger") == "mission_first_tick"):
			errs.append(PowerGrid.diag("BAD_MISSION",
				"timed optional latch needs a rewarded latch, valid deadline and mission clock", []))
		else:
			_timed_latch_option = {"latch": lid, "deadline_ticks": int(limit)}
	# Verification-triggered ending: exactly 20 authoritative 10 Hz ticks,
	# two safe replay/remaining-work actions, and a localized radio subtitle.
	# Other contracts retain their original state and result dictionary shape.
	var finale_raw: Variant = definition.get("finale", null)
	if finale_raw != null:
		var finale: Dictionary = finale_raw if finale_raw is Dictionary else {}
		var stagger: Variant = PowerGrid.to_int(finale.get("stagger_ticks"))
		var actions: Variant = finale.get("results_actions")
		var key: Variant = finale.get("radio_subtitle_key")
		if not (finale.size() == 4 and finale.get("trigger") == "first_verified"
				and stagger != null and int(stagger) == 20
				and key is String and str(key).begins_with("radio.") and str(key).length() > 6
				and actions is Array and actions == ["replay", "remaining_optional_tasks"]):
			errs.append(PowerGrid.diag("BAD_MISSION",
				"verification finale requires 20 ticks, localized subtitle and replay/remaining tasks", []))
		else:
			_finale = {"stagger_ticks": int(stagger),
				"radio_subtitle_key": key, "results_actions": actions.duplicate()}
	# Fixed ladders are contract access interactions, not electrical nodes.
	for rec: Variant in definition.get("fixed_ladders", []):
		var ladder: Dictionary = rec if rec is Dictionary else {}
		var ladder_id: Variant = ladder.get("id")
		var grant: Variant = ladder.get("grants")
		if not PowerGrid.is_valid_id(ladder_id) or not PowerGrid.is_valid_id(grant) or _fixed_ladders.has(ladder_id):
			errs.append(PowerGrid.diag("BAD_MISSION", "fixed ladder needs unique ID and grant flag", []))
		else:
			var required_latch: Variant = ladder.get("requires_latch", "")
			if not (required_latch is String) or (required_latch != "" and not _latches.has(required_latch)):
				errs.append(PowerGrid.diag("BAD_MISSION", "fixed ladder requires a declared supply latch", [ladder_id]))
			else:
				_fixed_ladders[ladder_id] = grant
				if required_latch != "":
					_ladder_requires[ladder_id] = required_latch
	# Access route identifiers represent host-approved travel, not electrical nodes.
	if definition.has("wind_routes"):
		var raw_wind: Variant = definition["wind_routes"]
		var w: Dictionary = raw_wind if raw_wind is Dictionary else {}
		var warn: Variant = PowerGrid.to_int(w.get("warning_ticks"))
		var start: Variant = PowerGrid.to_int(w.get("close_start_ticks"))
		var finish: Variant = PowerGrid.to_int(w.get("close_end_ticks"))
		var route_names: Array[String] = []
		for key: String in ["roof_route", "ground_route", "safe_return"]:
			var value: Variant = w.get(key)
			if value is String and PowerGrid.is_valid_id(value) and not route_names.has(value):
				route_names.append(value)
		if not (w.size() == 7 and warn != null and start != null and finish != null
				and int(warn) >= 1 and int(warn) < int(start) and int(start) <= int(finish)
				and route_names.size() == 3 and PowerGrid.is_valid_id(w.get("grants"))
				and not definition.has("fixed_ladders")):
			errs.append(PowerGrid.diag("BAD_MISSION", "wind routes require unique IDs, a grant and ordered tick windows", []))
		else:
			_wind_routes = {"roof_route": w["roof_route"], "ground_route": w["ground_route"],
				"safe_return": w["safe_return"], "grants": w["grants"],
				"warning_ticks": int(warn), "close_start_ticks": int(start),
				"close_end_ticks": int(finish)}
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
	# Unlike the legacy first-on-grid optional, C02 requires sustained supply
	# from either a valid grid route or a safe portable GEN route for BOTH venues.
	var opening_raw: Variant = definition.get("opening_venues", null)
	if opening_raw != null:
		var opening: Dictionary = opening_raw if opening_raw is Dictionary else {}
		var needed: Variant = PowerGrid.to_int(opening.get("supplied_ticks"))
		var limit: Variant = PowerGrid.to_int(opening.get("deadline_ticks"))
		var sources: Variant = opening.get("permitted_sources")
		var venue_list: Variant = opening.get("consumers")
		if not (venue_list is Array and sources is Array and
				needed != null and limit != null and int(needed) >= 1 and int(limit) >= int(needed) and
				opening.get("start_trigger") == "briefing_dismissed_all_loaded" and _optional.is_empty()):
			errs.append(PowerGrid.diag("BAD_MISSION", "opening_venues requires venues, source list, ticks and briefing trigger", []))
		else:
			_opening_venues = _consumer_list(venue_list, nodes, "opening_venues.consumers", errs)
			_opening_sources = []
			for source: Variant in sources:
				if not (source is String and nodes.has(source) and nodes[source]["kind"] == PowerGrid.KIND_SOURCE) or _opening_sources.has(source):
					errs.append(PowerGrid.diag("BAD_MISSION", "opening source must be a distinct source node", []))
				else:
					_opening_sources.append(source)
			if _opening_venues.size() != (venue_list as Array).size() or _opening_venues.size() < 2 \
					or _opening_sources.size() != (sources as Array).size() or not _opening_sources.has(_grid_source):
				errs.append(PowerGrid.diag("BAD_MISSION", "opening venues need valid consumers and distinct supply sources", []))
			var unique_venues: Dictionary = {}
			for c: String in _opening_venues:
				if unique_venues.has(c):
					errs.append(PowerGrid.diag("BAD_MISSION", "opening venues cannot repeat a consumer", [c]))
				unique_venues[c] = true
				if not _required.has(c):
					errs.append(PowerGrid.diag("BAD_MISSION", "opening venue must be required for main completion", [c]))
				_opening_ticks[c] = 0
			_opening_needed = int(needed)
			_opening_deadline = int(limit)
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
	var pickup_raw: Variant = definition.get("optional_pickup_deadline", null)
	if pickup_raw != null:
		var pickup: Dictionary = pickup_raw if pickup_raw is Dictionary else {}
		var consumer: Variant = pickup.get("consumer")
		var deadline: Variant = PowerGrid.to_int(pickup.get("deadline_ticks"))
		var required_latch: Variant = pickup.get("requires_latch", "")
		if not (consumer is String and _required.has(consumer) and
				deadline != null and int(deadline) >= 1 and
				required_latch is String and (required_latch == "" or _latches.has(required_latch)) and
				pickup.get("start_trigger") == "first_equipment_pickup" and
				_optional.is_empty() and _opening_venues.is_empty()):
			errs.append(PowerGrid.diag("BAD_MISSION",
				"pickup deadline needs a required consumer, valid access latch, positive ticks and host pickup trigger", []))
		else:
			_pickup_option = {"consumer": consumer, "deadline_ticks": int(deadline), "requires_latch": required_latch}
	var outage_raw: Variant = definition.get("optional_cumulative_outage", null)
	if outage_raw != null:
		var opt: Dictionary = outage_raw if outage_raw is Dictionary else {}
		var limit: Variant = PowerGrid.to_int(opt.get("deadline_ticks"))
		var consumer: Variant = opt.get("consumer")
		var sources_raw: Variant = opt.get("permitted_sources")
		var allowed: Array[String] = []
		if sources_raw is Array:
			for src_id: Variant in sources_raw:
				if not (src_id is String and nodes.has(src_id) and nodes[src_id]["kind"] == PowerGrid.KIND_SOURCE) or allowed.has(src_id):
					errs.append(PowerGrid.diag("BAD_MISSION", "outage sources must be distinct source nodes", []))
				else:
					allowed.append(src_id)
		if not (opt.size() == 4 and PowerGrid.is_valid_id(opt.get("id")) and
				consumer is String and _required.has(consumer) and limit != null and int(limit) >= 1 and
				sources_raw is Array and allowed.size() == (sources_raw as Array).size() and allowed.size() == 2 and
				allowed.has(_grid_source) and _optional.is_empty() and _pickup_option.is_empty() and
				_opening_venues.is_empty() and _continuous_optional.is_empty()):
			errs.append(PowerGrid.diag("BAD_MISSION", "cumulative outage needs a required consumer, two sources and positive tick limit", []))
		else:
			_outage_option = {"id": opt["id"], "consumer": consumer, "deadline_ticks": int(limit), "permitted_sources": allowed}
			_outage_unsupplied = false
			_outage_last_valid = _valid_outage_supply(grid.canonical_state())

	# Optional maximum uninterrupted telecom dark period, authored exclusively
	# by C11. Distinct permitted sources are authoritative graph source IDs.
	var interruption_raw: Variant = definition.get("optional_max_consecutive_outage", null)
	if interruption_raw != null:
		var interruption: Dictionary = interruption_raw if interruption_raw is Dictionary else {}
		var max_ticks: Variant = PowerGrid.to_int(interruption.get("max_outage_ticks"))
		var target: Variant = interruption.get("consumer")
		var sources_raw: Variant = interruption.get("permitted_sources")
		var accepted: Array[String] = []
		if sources_raw is Array:
			for candidate: Variant in sources_raw:
				if not (candidate is String and nodes.has(candidate) and
						nodes[candidate]["kind"] == PowerGrid.KIND_SOURCE) or accepted.has(candidate):
					errs.append(PowerGrid.diag("BAD_MISSION", "continuity sources must be distinct valid sources", []))
				else:
					accepted.append(candidate)
		if not (interruption.size() == 4 and PowerGrid.is_valid_id(interruption.get("id"))
				and target is String and _required.has(target) and max_ticks != null
				and int(max_ticks) >= 1 and sources_raw is Array and accepted.size() == 2
				and accepted.size() == (sources_raw as Array).size()
				and accepted.has(_grid_source) and _outage_option.is_empty()
				and _continuous_optional.is_empty() and _optional.is_empty()):
			errs.append(PowerGrid.diag("BAD_MISSION",
				"max consecutive outage needs a required consumer, two sources and positive tick limit", []))
		else:
			_interruption_option = {"id": interruption["id"], "consumer": target,
				"max_outage_ticks": int(max_ticks), "permitted_sources": accepted}
			_interruption_last_valid = _valid_interruption_supply(grid.canonical_state())
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
	_wind_roof_players.erase(player)


## Host movement says whether the player stands in a zone. Leaving the extraction zone cancels a countdown (MIS04).
func set_in_zone(player: String, zone: String, inside: bool) -> Array[Dictionary]:
	if zone != _zone or not _players.has(player):
		return []
	if inside:
		_in_zone[player] = true
		return []
	_in_zone.erase(player)
	return _cancel("player_left_zone")


## Called only from the host after the briefing is dismissed AND all admitted
## peers have acknowledged their loading snapshot. Never restarted on a duplicate.
func begin_after_briefing() -> Dictionary:
	if _opening_venues.is_empty():
		return {"ok": true, "not_required": true}
	if _completed_tick >= 0:
		return _refuse("ALREADY_COMPLETE", "the mission is complete", [])
	if _opening_started:
		return {"ok": true, "duplicate": true}
	_opening_started = true
	return {"ok": true, "opening_deadline_ticks": _opening_deadline}


## Host-only callback after an accepted, non-duplicate equipment pickup.
func note_equipment_pickup() -> Array[Dictionary]:
	if _pickup_option.is_empty() or _pickup_started or _completed_tick >= 0:
		return []
	_pickup_started = true
	return [{"type": "pickup_deadline_started", "deadline_ticks": _pickup_option["deadline_ticks"], "tick": _now}]


## A qualifying venue can be on GRID or GEN, but not on an overloaded
## source. The host power model owns all supply and dual-route decisions.
func _opening_supplied(consumer: String, st: Dictionary) -> bool:
	if not st["nodes"][consumer]["supplied"]:
		return false
	var source: String = _root_of(consumer, st)
	return _opening_sources.has(source) and not st["nodes"][source]["overloaded"]


# ---------- host tick ----------

## Call once per grid tick, after the grid has stepped. Returns this tick's mission events.
func tick(now: int) -> Array[Dictionary]:
	_now = now
	var events: Array[Dictionary] = []
	if _completed_tick >= 0:
		return events
	observe_supply_state()
	var st: Dictionary = _grid.canonical_state()
	if not _wind_routes.is_empty():
		_wind_elapsed += 1
		if _wind_elapsed == int(_wind_routes["warning_ticks"]):
			events.append({"type": "wind_warning", "tick": now,
				"roof_closes_at": _wind_routes["close_start_ticks"]})
		if _wind_elapsed == int(_wind_routes["close_start_ticks"]):
			events.append({"type": "wind_roof_closed", "tick": now,
				"through_tick": _wind_routes["close_end_ticks"]})
			for occupant: String in _sorted(_wind_roof_players.keys()):
				events.append({"type": "wind_safe_return_offered", "player": occupant,
					"route": _wind_routes["safe_return"], "tick": now})
		if _wind_elapsed == int(_wind_routes["close_end_ticks"]) + 1:
			events.append({"type": "wind_roof_reopened", "tick": now})
	for lid: String in _sorted(_latches.keys()):
		if _latched.has(lid):
			continue
		var l: Dictionary = _latches[lid]
		var valid_supply: bool = _latch_supplied(l, st)
		_latch_ticks[lid] = int(_latch_ticks[lid]) + 1 if valid_supply else 0
		if int(_latch_ticks[lid]) >= int(l["supplied_ticks"]):
			_latched[lid] = now
			_interaction.set_access(l["grants"], true)
			events.append({"type": "latch", "id": lid, "grants": l["grants"], "tick": now})
	# Count the latch-completion tick against the event-start boundary.
	# The core mission is never cancelled when an optional event deadline expires.
	if not _timed_latch_option.is_empty() and not _timed_latch_on_time and not _timed_latch_missed:
		_timed_latch_elapsed += 1
		var timed_id: String = _timed_latch_option["latch"]
		var timed_limit: int = int(_timed_latch_option["deadline_ticks"])
		if _latched.has(timed_id) and _timed_latch_elapsed <= timed_limit:
			_timed_latch_on_time = true
			events.append({"type": "timed_latch_bonus_achieved", "latch": timed_id,
				"elapsed_ticks": _timed_latch_elapsed, "tick": now})
		elif _timed_latch_elapsed > timed_limit:
			_timed_latch_missed = true
			events.append({"type": "timed_latch_bonus_missed", "latch": timed_id,
				"elapsed_ticks": _timed_latch_elapsed, "tick": now})
	# The opening clock is independent of absolute host ticks and cannot advance
	# during briefing/loading; it is therefore safe across offline save/reload.
	if _opening_started:
		_opening_elapsed += 1
		if _opening_elapsed <= _opening_deadline:
			for venue: String in _opening_venues:
				if _opening_latched.has(venue):
					continue
				_opening_ticks[venue] = int(_opening_ticks[venue]) + 1 if _opening_supplied(venue, st) else 0
				if int(_opening_ticks[venue]) >= _opening_needed:
					_opening_latched[venue] = _opening_elapsed
					events.append({"type": "venue_opening_latched", "id": venue, "tick": now, "elapsed": _opening_elapsed})
		elif not _opening_failed and _opening_latched.size() < _opening_venues.size():
			_opening_failed = true
			events.append({"type": "opening_deadline_missed", "tick": now, "deadline_ticks": _opening_deadline})
	# An optional opening deadline affects a bonus only, never repair/access,
	# extraction, required supply, or a host's grid state.
	if _optional_deadline_ticks >= 0 and now <= _optional_deadline_ticks:
		for optional_id: String in _optional:
			if not _optional_first_supplied.has(optional_id) and _on_grid(optional_id, st):
				_optional_first_supplied[optional_id] = now
				events.append({"type": "optional_service_on_time", "id": optional_id, "tick": now})
	if _pickup_started and not _pickup_on_time and not _pickup_missed:
		_pickup_elapsed += 1
		if _pickup_elapsed <= int(_pickup_option["deadline_ticks"]) and _on_grid(_pickup_option["consumer"], st):
			_pickup_on_time = true
			events.append({"type": "pickup_optional_on_time", "id": _pickup_option["consumer"],
				"elapsed_ticks": _pickup_elapsed, "tick": now})
		elif _pickup_elapsed > int(_pickup_option["deadline_ticks"]):
			_pickup_missed = true
			events.append({"type": "pickup_deadline_missed", "id": _pickup_option["consumer"], "tick": now})
	if not _outage_option.is_empty():
		if not _outage_failed and (_outage_unsupplied or not _valid_outage_supply(st)):
			_outage_ticks = mini(_outage_ticks + 1, int(_outage_option["deadline_ticks"]))
			if _outage_ticks >= int(_outage_option["deadline_ticks"]):
				_outage_failed = true
				events.append({"type": "cumulative_outage_bonus_missed", "id": _outage_option["id"], "tick": now})
		_outage_unsupplied = false
		_outage_last_valid = _valid_outage_supply(st)

	# Increment at most once per authoritative 10 Hz tick. Brief off/on
	# transitions are recorded by observe_supply_state() between host intents.
	# Missing the optional bonus must never block repairs or extraction.
	if not _interruption_option.is_empty():
		var supplied: bool = _valid_interruption_supply(st)
		if not _interruption_failed:
			if _interruption_pending or not supplied:
				_interruption_ticks = mini(_interruption_ticks + 1,
					int(_interruption_option["max_outage_ticks"]) + 1)
				if _interruption_ticks > int(_interruption_option["max_outage_ticks"]):
					_interruption_failed = true
					events.append({"type": "max_consecutive_outage_missed",
						"id": _interruption_option["id"], "tick": now})
			else:
				_interruption_ticks = 0
		_interruption_pending = false
		_interruption_last_valid = supplied
	# The zero/ten/twenty restoration cues are host-timed and emitted once,
	# even if verification subsequently drops or a saved host is resumed.
	if _finale_started and _finale_elapsed < int(_finale["stagger_ticks"]):
		_finale_elapsed += 1
		if _finale_elapsed == 10 or _finale_elapsed == 20:
			events.append({"type": "finale_lights_wave", "stage": 1 if _finale_elapsed == 10 else 2,
				"elapsed_ticks": _finale_elapsed, "tick": now})
		if _finale_elapsed == 20:
			events.append({"type": "finale_lights_completed", "tick": now})
	var was_verified: bool = verified()
	_verify_ticks = mini(_verify_ticks + 1, _verify_needed) if _all_required_on_grid(st) else 0
	if verified() and not was_verified:
		events.append({"type": "verified", "tick": now})
		if not _finale.is_empty() and not _finale_started:
			_finale_started = true
			_finale_elapsed = 0
			events.append({"type": "finale_lights_wave", "stage": 0,
				"elapsed_ticks": 0, "tick": now})
			events.append({"type": "finale_radio_subtitle",
				"text_key": _finale["radio_subtitle_key"], "tick": now})
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
	if _completed_tick >= 0:
		return
	var st: Dictionary = _grid.canonical_state()
	# A C08 depot interruption cannot be hidden by two valid switch commands
	# that both arrive between 10 Hz ticks. Legacy latch behavior is unchanged.
	for lid: String in _sorted(_latches.keys()):
		if not _latched.has(lid) and not _latch_supplied(_latches[lid], st):
			_latch_ticks[lid] = 0
	# A loss and restoration within one 10 Hz tick must reset an unfinished
	# venue's consecutive-tick count; the bonus is not a first-power latch.
	if _opening_started:
		for venue: String in _opening_venues:
			if not _opening_latched.has(venue) and not _opening_supplied(venue, st):
				_opening_ticks[venue] = 0
	if not _continuous_optional.is_empty() and _continuous_ok:
		if not _on_grid(_continuous_optional["consumer"], st):
			_continuous_ok = false
	if not _outage_option.is_empty():
		var outage_supplied: bool = _valid_outage_supply(st)
		# Only a real powered-to-unpowered transition flags an interruption.
		# Starting from darkness and powering up before the next tick is not
		# an extra outage tick; an off/on interruption while lit still counts.
		if not _outage_failed and _outage_last_valid and not outage_supplied:
			_outage_unsupplied = true
		_outage_last_valid = outage_supplied

	if not _interruption_option.is_empty():
		var telecom_supplied: bool = _valid_interruption_supply(st)
		if _interruption_last_valid and not telecom_supplied:
			_interruption_pending = true
		_interruption_last_valid = telecom_supplied


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
	for venue: String in _opening_venues:
		if _opening_latched.has(venue):
			optional_restored.append(venue)
	if not _pickup_option.is_empty() and _pickup_on_time:
		optional_restored.append(_pickup_option["consumer"])
	if not _outage_option.is_empty() and not _outage_failed and _valid_outage_supply(st):
		optional_restored.append(_outage_option["id"])
	if not _interruption_option.is_empty() and not _interruption_failed and _valid_interruption_supply(st):
		optional_restored.append(_interruption_option["id"])
	for reward_id: String in _optional_latch_rewards:
		if _latched.has(reward_id) and (_timed_latch_option.is_empty()
				or reward_id != _timed_latch_option["latch"] or _timed_latch_on_time):
			optional_restored.append(_latches[reward_id]["consumer"])
	var optional_total: int = _optional.size() + (1 if not _meter_evidence.is_empty() else 0) + (1 if not _continuous_optional.is_empty() else 0) + _opening_venues.size() + _optional_latch_rewards.size() + (1 if not _pickup_option.is_empty() else 0) + (1 if not _outage_option.is_empty() else 0) + (1 if not _interruption_option.is_empty() else 0)
	var preventable: int = maxi(0, _trips - _trip_allowance)
	var stars: int = 1 + (1 if optional_restored.size() == optional_total else 0) + (1 if preventable == 0 else 0)
	var report: Dictionary = {"required_restored": restored, "required_total": _required.size(), "optional_services": optional_restored,
		"optional_total": optional_total, "trips": _trips, "preventable_trips": preventable, "crew_recoveries": _recoveries,
		"ticks": _completed_tick, "equipment_collected": _equipment.all_stowed(), "stars": stars}
	if not _finale.is_empty():
		report["next_actions"] = (_finale["results_actions"] as Array).duplicate()
	return report


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
	if _ladder_requires.has(ladder_id) and not _latched.has(_ladder_requires[ladder_id]):
		return _refuse("ACCESS_NOT_READY", "power the ladder access light before climbing", [ladder_id])
	if _ladder_access.has(ladder_id):
		return {"ok": true, "duplicate": true}
	_ladder_access[ladder_id] = _now
	var grant: String = _fixed_ladders[ladder_id]
	_interaction.set_access(grant, true)
	return {"ok": true, "events": [{"type": "ladder_access", "id": ladder_id, "grants": grant, "tick": _now}]}


## Returns host-authorized route receipt; no client coordinates/timing are trusted.
## A gust never causes a forced fall or breaks repaired equipment.
func use_wind_route(player: String, route_id: String, in_range: bool) -> Dictionary:
	if _wind_routes.is_empty() or not [str(_wind_routes.get("roof_route", "")),
			str(_wind_routes.get("ground_route", "")), str(_wind_routes.get("safe_return", ""))].has(route_id):
		return _refuse("UNKNOWN_ROUTE", "unknown timed route", [route_id])
	if not _players.has(player):
		return _refuse("UNKNOWN_PLAYER", "player is not in this mission", [])
	if _completed_tick >= 0:
		return _refuse("ALREADY_COMPLETE", "mission is finished", [])
	if not in_range:
		return _refuse("NOT_IN_RANGE", "move closer to the route", [route_id])
	if route_id == _wind_routes["safe_return"]:
		if not _wind_roof_players.has(player):
			return _refuse("NOT_ON_ROOF", "only rooftop occupants can return", [route_id])
		_wind_roof_players.erase(player)
		return {"ok": true, "events": [{"type": "wind_safe_return", "player": player,
			"route": route_id, "tick": _now}]}
	if route_id == _wind_routes["roof_route"] and _wind_roof_closed():
		return _refuse("WIND_ROOF_CLOSED", "roof entry closed during gusts; ground access remains open", [route_id])
	if route_id == _wind_routes["roof_route"]:
		if _wind_roof_players.has(player):
			return {"ok": true, "duplicate": true}
		_wind_roof_players[player] = true
	else:
		_wind_roof_players.erase(player)
	if _wind_access_route.is_empty():
		_wind_access_route = route_id
		_interaction.set_access(_wind_routes["grants"], true)
	return {"ok": true, "events": [{"type": "wind_route_used", "player": player,
		"route": route_id, "tick": _now}]}


func _wind_roof_closed() -> bool:
	return not _wind_routes.is_empty() and _wind_elapsed >= int(_wind_routes["close_start_ticks"]) \
		and _wind_elapsed <= int(_wind_routes["close_end_ticks"])


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
	if cond.has("timed_latch"):
		return not _timed_latch_option.is_empty() and cond["timed_latch"] == _timed_latch_option["latch"] and _timed_latch_on_time
	if cond.has("ladder"):
		return _ladder_access.has(cond["ladder"])
	if cond.has("wind_access"):
		return not _wind_routes.is_empty() and cond["wind_access"] == _wind_routes["grants"] and not _wind_access_route.is_empty()
	if cond.has("opening_venue"):
		return _opening_venues.has(cond["opening_venue"]) and _opening_latched.has(cond["opening_venue"])
	if cond.has("cumulative_outage"):
		return not _outage_option.is_empty() and cond["cumulative_outage"] == _outage_option["id"] and \
			_completed_tick >= 0 and not _outage_failed
	if cond.has("max_consecutive_outage"):
		return not _interruption_option.is_empty() and cond["max_consecutive_outage"] == _interruption_option["id"] and \
			_completed_tick >= 0 and not _interruption_failed
	if cond.has("pickup_deadline"):
		return not _pickup_option.is_empty() and cond["pickup_deadline"] == _pickup_option["consumer"] and _pickup_on_time
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
	if not _opening_venues.is_empty():
		out["opening_venues"] = {"started": _opening_started, "elapsed": _opening_elapsed,
			"progress": _opening_ticks.duplicate(), "latched": _opening_latched.duplicate(), "failed": _opening_failed}
	if not _timed_latch_option.is_empty():
		out["timed_latch_bonus"] = {"elapsed_ticks": _timed_latch_elapsed,
			"on_time": _timed_latch_on_time, "missed": _timed_latch_missed,
			"remaining_ticks": maxi(0, int(_timed_latch_option["deadline_ticks"]) - _timed_latch_elapsed)}
	if not _pickup_option.is_empty():
		out["pickup_deadline"] = {"started": _pickup_started, "elapsed": _pickup_elapsed,
			"on_time": _pickup_on_time, "missed": _pickup_missed,
			"remaining_ticks": maxi(0, int(_pickup_option["deadline_ticks"]) - _pickup_elapsed)}
	if not _meter_evidence.is_empty():
		out["optional_meter_evidence"] = {"observed": _evidence_observed, "reset_attempted": _evidence_reset_attempted}
	if not _outage_option.is_empty():
		out["cumulative_outage"] = {"elapsed_ticks": _outage_ticks, "missed": _outage_failed,
			"pending_unpowered": _outage_unsupplied,
			"remaining_ticks": maxi(0, int(_outage_option["deadline_ticks"]) - _outage_ticks),
			"powered": _valid_outage_supply(_grid.canonical_state())}

	if not _interruption_option.is_empty():
		out["max_consecutive_outage"] = {"elapsed_ticks": _interruption_ticks, "missed": _interruption_failed,
			"pending_unpowered": _interruption_pending, "powered": _valid_interruption_supply(_grid.canonical_state()),
			"remaining_ticks": maxi(0, int(_interruption_option["max_outage_ticks"]) + 1 - _interruption_ticks)}
	if not _finale.is_empty():
		out["finale"] = {"started": _finale_started, "elapsed_ticks": _finale_elapsed,
			"complete": _finale_started and _finale_elapsed == int(_finale["stagger_ticks"]),
			"radio_subtitle_key": _finale["radio_subtitle_key"], "input_locked": false}
	if not _finale.is_empty():
		out["finale"] = {"started": _finale_started, "elapsed_ticks": _finale_elapsed}
	if not _continuous_optional.is_empty():
		out["optional_continuous_supply"] = {"ok": _continuous_ok}
	if not _fixed_ladders.is_empty():
		out["ladder_access"] = _ladder_access.duplicate()
	if not _wind_routes.is_empty():
		out["wind_routes"] = {"elapsed_ticks": _wind_elapsed,
			"warned": _wind_elapsed >= int(_wind_routes["warning_ticks"]),
			"roof_closed": _wind_roof_closed(), "access_route": _wind_access_route,
			"roof_players": _sorted(_wind_roof_players.keys())}
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
	if not _opening_venues.is_empty():
		out["opening_venues"] = {"started": _opening_started, "elapsed": _opening_elapsed,
			"progress": _opening_ticks.duplicate(), "latched": _opening_latched.duplicate(), "failed": _opening_failed}
	if not _timed_latch_option.is_empty():
		out["timed_latch_bonus"] = {"elapsed_ticks": _timed_latch_elapsed,
			"on_time": _timed_latch_on_time, "missed": _timed_latch_missed}
	if not _pickup_option.is_empty():
		out["pickup_deadline"] = {"started": _pickup_started, "elapsed": _pickup_elapsed,
			"on_time": _pickup_on_time, "missed": _pickup_missed}
	if not _meter_evidence.is_empty():
		out["optional_meter_evidence"] = {"observed": _evidence_observed, "reset_attempted": _evidence_reset_attempted}
	if not _outage_option.is_empty():
		out["cumulative_outage"] = {"elapsed_ticks": _outage_ticks, "missed": _outage_failed,
			"pending_unpowered": _outage_unsupplied}

	if not _interruption_option.is_empty():
		out["max_consecutive_outage"] = {"elapsed_ticks": _interruption_ticks, "missed": _interruption_failed,
			"pending_unpowered": _interruption_pending}
	if not _continuous_optional.is_empty():
		out["optional_continuous_supply"] = {"ok": _continuous_ok}
	if not _fixed_ladders.is_empty():
		out["ladder_access"] = _ladder_access.duplicate()
	if not _wind_routes.is_empty():
		out["wind_routes"] = {"elapsed_ticks": _wind_elapsed, "access_route": _wind_access_route}
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
		if not _latches.has(lid) or v == null or int(v) < 0 or int(v) > int(_latches[lid]["supplied_ticks"]):
			return bad
		latch_ticks[lid] = int(v)
	# All current contract latch counters are required; an omitted record cannot
	# silently erase an access requirement after loading an incompatible checkpoint.
	if latch_ticks.size() != _latches.size():
		return bad
	var latched: Dictionary = {}
	for lid: Variant in d["latched"]:
		var v: Variant = PowerGrid.to_int(d["latched"][lid])
		if not _latches.has(lid) or v == null or int(v) < 0 or \
				int(latch_ticks.get(lid, -1)) != int(_latches[lid]["supplied_ticks"]):
			return bad
		latched[lid] = int(v)
	for lid: String in latch_ticks:
		if int(latch_ticks[lid]) == int(_latches[lid]["supplied_ticks"]) and not latched.has(lid):
			return bad
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
	# This conditional shape is present only for contracts authoring opening venues.
	# Validate every field and any venue progress BEFORE mutating older state.
	var opening_started: bool = false
	var opening_elapsed: int = 0
	var opening_progress: Dictionary = {}
	var opening_latched: Dictionary = {}
	var opening_failed: bool = false
	if not _opening_venues.is_empty():
		var record: Variant = d.get("opening_venues")
		if not (record is Dictionary and (record as Dictionary).size() == 5
				and record.get("started") is bool and record.get("progress") is Dictionary
				and record.get("latched") is Dictionary and record.get("failed") is bool):
			return bad
		var elapsed: Variant = PowerGrid.to_int(record.get("elapsed"))
		if elapsed == null or int(elapsed) < 0:
			return bad
		opening_started = record["started"]
		opening_elapsed = int(elapsed)
		opening_failed = record["failed"]
		if not opening_started and opening_elapsed != 0:
			return bad
		var progress: Dictionary = record["progress"]
		if progress.size() != _opening_venues.size():
			return bad
		for c: Variant in progress:
			var ticks: Variant = PowerGrid.to_int(progress[c])
			if not (c is String and _opening_venues.has(c)) or ticks == null \
					or int(ticks) < 0 or int(ticks) > _opening_needed:
				return bad
			opening_progress[c] = int(ticks)
		for c: Variant in record["latched"]:
			var at: Variant = PowerGrid.to_int(record["latched"][c])
			if not (c is String and _opening_venues.has(c)) or at == null \
					or int(at) < _opening_needed or int(at) > _opening_deadline or int(at) > opening_elapsed \
					or int(opening_progress.get(c, 0)) != _opening_needed:
				return bad
			opening_latched[c] = int(at)
		for c: String in _opening_venues:
			if not opening_latched.has(c) and int(opening_progress.get(c, 0)) == _opening_needed:
				return bad
		if opening_failed and (opening_elapsed <= _opening_deadline or opening_latched.size() == _opening_venues.size()):
			return bad
	# Fail closed before committing any mission fields from the checkpoint.
	var pickup_started: bool = false
	var pickup_elapsed: int = 0
	var pickup_on_time: bool = false
	var pickup_missed: bool = false
	if not _pickup_option.is_empty():
		var pickup_record: Variant = d.get("pickup_deadline")
		if not (pickup_record is Dictionary and (pickup_record as Dictionary).size() == 4
				and pickup_record.get("started") is bool and pickup_record.get("on_time") is bool
				and pickup_record.get("missed") is bool):
			return bad
		var pickup_ticks: Variant = PowerGrid.to_int(pickup_record.get("elapsed"))
		if pickup_ticks == null or int(pickup_ticks) < 0 or int(pickup_ticks) > int(_pickup_option["deadline_ticks"]) + 1:
			return bad
		pickup_started = pickup_record["started"]
		pickup_elapsed = int(pickup_ticks)
		pickup_on_time = pickup_record["on_time"]
		pickup_missed = pickup_record["missed"]
		if (not pickup_started and (pickup_elapsed != 0 or pickup_on_time or pickup_missed)) or (pickup_on_time and pickup_missed):
			return bad
		if pickup_on_time and (pickup_elapsed < 1 or pickup_elapsed > int(_pickup_option["deadline_ticks"])
				or (_pickup_option["requires_latch"] != "" and not latched.has(_pickup_option["requires_latch"]))):
			return bad
		if pickup_missed != (pickup_elapsed == int(_pickup_option["deadline_ticks"]) + 1):
			return bad
	var outage_ticks: int = 0
	var outage_failed: bool = false
	var outage_pending: bool = false
	if not _outage_option.is_empty():
		var outage_record: Variant = d.get("cumulative_outage")
		if not (outage_record is Dictionary and (outage_record as Dictionary).size() == 3 and
				outage_record.get("missed") is bool and outage_record.get("pending_unpowered") is bool):
			return bad
		var elapsed: Variant = PowerGrid.to_int(outage_record.get("elapsed_ticks"))
		if elapsed == null or int(elapsed) < 0 or int(elapsed) > int(_outage_option["deadline_ticks"]):
			return bad
		outage_ticks = int(elapsed)
		outage_failed = outage_record["missed"]
		outage_pending = outage_record["pending_unpowered"]
		if outage_failed != (outage_ticks == int(_outage_option["deadline_ticks"])):
			return bad

	# Conditional C11 receipt: verify all types and exact shape before changing
	# any live state. Earlier contract saves do not acquire this key.
	var restored_interruption_ticks: int = 0
	var restored_interruption_failed: bool = false
	var restored_interruption_pending: bool = false
	if not _interruption_option.is_empty():
		var interruption_saved: Variant = d.get("max_consecutive_outage")
		if not (interruption_saved is Dictionary and (interruption_saved as Dictionary).size() == 3
				and interruption_saved.get("missed") is bool
				and interruption_saved.get("pending_unpowered") is bool):
			return bad
		var ticks_raw: Variant = PowerGrid.to_int(interruption_saved.get("elapsed_ticks"))
		var max_allowed: int = int(_interruption_option["max_outage_ticks"])
		if ticks_raw == null or int(ticks_raw) < 0 or int(ticks_raw) > max_allowed + 1:
			return bad
		restored_interruption_ticks = int(ticks_raw)
		restored_interruption_failed = interruption_saved["missed"]
		restored_interruption_pending = interruption_saved["pending_unpowered"]
		if restored_interruption_failed != (restored_interruption_ticks == max_allowed + 1):
			return bad
	# C12 finale progress is conditional; do not mutate live state until
	# the full receipt has been validated with all other checkpoint sections.
	var restored_finale_started: bool = false
	var restored_finale_elapsed: int = 0
	if not _finale.is_empty():
		var finale_saved: Variant = d.get("finale")
		if not (finale_saved is Dictionary and (finale_saved as Dictionary).size() == 2
				and finale_saved.get("started") is bool):
			return bad
		var elapsed_raw: Variant = PowerGrid.to_int(finale_saved.get("elapsed_ticks"))
		if elapsed_raw == null or int(elapsed_raw) < 0 or int(elapsed_raw) > int(_finale["stagger_ticks"]):
			return bad
		restored_finale_started = finale_saved["started"]
		restored_finale_elapsed = int(elapsed_raw)
		if not restored_finale_started and restored_finale_elapsed != 0:
			return bad
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
	# Check conditional C09 receipt before mutating state. After a reload,
	# rooftop occupancy is not restored without a verified physical position.
	var wind_elapsed: int = 0
	var wind_access: String = ""
	if not _wind_routes.is_empty():
		var wind_record: Variant = d.get("wind_routes")
		if not (wind_record is Dictionary and (wind_record as Dictionary).size() == 2
				and wind_record.get("access_route") is String):
			return bad
		var elapsed_raw: Variant = PowerGrid.to_int(wind_record.get("elapsed_ticks"))
		if elapsed_raw == null or int(elapsed_raw) < 0:
			return bad
		wind_elapsed = int(elapsed_raw)
		wind_access = wind_record["access_route"]
		if wind_access != "" and not [str(_wind_routes["ground_route"]), str(_wind_routes["roof_route"])].has(wind_access):
			return bad
	# C10 checkpoint fields are conditional: never alter older contract shapes.
	# Validate the complete record before committing a single restored field.
	var timed_elapsed: int = 0
	var timed_on_time: bool = false
	var timed_missed: bool = false
	if not _timed_latch_option.is_empty():
		var timed_saved: Variant = d.get("timed_latch_bonus")
		if not (timed_saved is Dictionary and (timed_saved as Dictionary).size() == 3
				and timed_saved.get("on_time") is bool and timed_saved.get("missed") is bool):
			return bad
		var elapsed: Variant = PowerGrid.to_int(timed_saved.get("elapsed_ticks"))
		var limit: int = int(_timed_latch_option["deadline_ticks"])
		if elapsed == null or int(elapsed) < 0 or int(elapsed) > limit + 1:
			return bad
		timed_elapsed = int(elapsed)
		timed_on_time = timed_saved["on_time"]
		timed_missed = timed_saved["missed"]
		if (timed_on_time and (timed_missed or timed_elapsed < 1 or timed_elapsed > limit
				or not latched.has(_timed_latch_option["latch"]))) or (timed_missed != (timed_elapsed == limit + 1)):
			return bad
		if not timed_on_time and not timed_missed and latched.has(_timed_latch_option["latch"]):
			return bad
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
	_opening_started = opening_started
	_opening_elapsed = opening_elapsed
	_opening_ticks = opening_progress
	_opening_latched = opening_latched
	_opening_failed = opening_failed
	_pickup_started = pickup_started
	_pickup_elapsed = pickup_elapsed
	_pickup_on_time = pickup_on_time
	_pickup_missed = pickup_missed
	_outage_ticks = outage_ticks
	_outage_failed = outage_failed
	_outage_unsupplied = outage_pending
	_outage_last_valid = _valid_outage_supply(_grid.canonical_state())
	_interruption_ticks = restored_interruption_ticks
	_interruption_failed = restored_interruption_failed
	_interruption_pending = restored_interruption_pending
	_interruption_last_valid = _valid_interruption_supply(_grid.canonical_state())
	_finale_started = restored_finale_started
	_finale_elapsed = restored_finale_elapsed
	_evidence_observed = observed
	_evidence_reset_attempted = reset_attempted
	_continuous_ok = continuous_ok
	_ladder_access = ladder_access
	_timed_latch_elapsed = timed_elapsed
	_timed_latch_on_time = timed_on_time
	_timed_latch_missed = timed_missed
	_wind_elapsed = wind_elapsed
	_wind_access_route = wind_access
	_wind_roof_players = {}
	if not _wind_routes.is_empty() and not _wind_access_route.is_empty():
		_interaction.set_access(_wind_routes["grants"], true)
	for ladder_id: String in _ladder_access:
		_interaction.set_access(_fixed_ladders[ladder_id], true)
	_countdown_left = -1
	_in_zone = {}
	return []


# ---------- supply attribution ----------

## A source-bound latch only advances while the authored source is supplying a
## healthy, non-overloaded route. This is a host rule, not a client light state.
func _latch_supplied(l: Dictionary, st: Dictionary) -> bool:
	var consumer: String = l["consumer"]
	if not st["nodes"][consumer]["supplied"]:
		return false
	if l.has("source"):
		var source: String = l["source"]
		return _root_of(consumer, st) == source and not st["nodes"][source]["overloaded"]
	return _on_grid(consumer, st) if _grid_sources.size() > 1 else true


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

## Authoritative continuity is valid on either of the two declared sources,
## only while the consumer is actually powered and its source is not overloaded.
func _valid_interruption_supply(st: Dictionary) -> bool:
	if _interruption_option.is_empty():
		return false
	var consumer: String = _interruption_option["consumer"]
	if not st["nodes"][consumer]["supplied"]:
		return false
	var root: String = _root_of(consumer, st)
	return (_interruption_option["permitted_sources"] as Array).has(root) and not st["nodes"][root]["overloaded"]


## The source must be host-authorized, exclusive and non-overloaded. Client visuals are not evidence.
func _valid_outage_supply(st: Dictionary) -> bool:
	if _outage_option.is_empty():
		return false
	var consumer: String = _outage_option["consumer"]
	if not st["nodes"][consumer]["supplied"]:
		return false
	var root: String = _root_of(consumer, st)
	return (_outage_option["permitted_sources"] as Array).has(root) and not st["nodes"][root]["overloaded"]


static func _refuse(code: String, message: String, ids: Array) -> Dictionary:
	var d: Dictionary = PowerGrid.diag(code, message, ids)
	return {"ok": false, "code": code, "key": "mission.refused." + code.to_lower(), "message": message, "ids": d["ids"]}


static func _sorted(keys: Array) -> Array[String]:
	var out: Array[String] = []
	out.assign(keys)
	out.sort()
	return out
