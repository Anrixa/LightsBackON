extends RefCounted
## Host command authority (F03; blueprint p.9-10 "Host authority and command protocol", CLAUDE.md section 4).
##
## Every action, including the host player's own, arrives here as bytes plus the sender's transport peer ID.
## The host never trusts identity, session or authority claims inside the payload. Order of checks:
## size -> parse -> envelope shape -> membership (peer admitted) -> session -> sequence (dedupe) -> rate -> entity ->
## dispatch to the owning service (grid switch, meter, interaction, equipment). Duplicates (same peer, already seen
## seq) get the original reply back with "duplicate": true and are never applied twice. Every reply carries the host
## revision, which increments once per accepted command that changed authoritative state.
##
## Transport-agnostic and pure: no scene tree, no autoloads. The transport adapter delivers (peer_id, bytes).

const PowerGrid := preload("res://scripts/simulation/power_grid.gd")
const MeterModel := preload("res://scripts/simulation/meter_model.gd")
const Interaction := preload("res://scripts/interaction/interaction_service.gd")
const Equipment := preload("res://scripts/interaction/equipment_service.gd")
const MissionDirector := preload("res://scripts/simulation/mission_director.gd")
const Comms := preload("res://scripts/network/comms_service.gd")

const HOST_PEER: int = 1
const CHUNK_ENVELOPE_BYTES: int = 96  # {"type":"snapshot_chunk","index":N,"data":"..."} around the escaped slice
const ENVELOPE_KEYS: Array[String] = ["session", "seq", "type", "entity", "payload"]
const INTENTS: Array[String] = ["inspect", "request_lock", "release", "heartbeat", "repair_step", "equip", "toggle_switch", "place_item",
	"request_extract", "use_ladder", "use_route", "recover_self", "ping", "chat", "collect_lore", "operate_device", "operate_fault", "operate_consequence", "operate_logistics", "operate_balance", "operate_worksite"]
const DEFERRED_INTENTS: Array[String] = ["ready"]  # lobby; refused until implemented
const PLACE_ACTIONS: Array[String] = ["pickup", "place", "connect", "disconnect", "start", "stop", "reset_breaker", "recover", "drop"]

var session_id: String = ""
var revision: int = 0
var _protocol_version: int = 0
var _content_revision: String = ""
var _limits: Dictionary = {}
var _grid: PowerGrid
var _meter: MeterModel
var _interaction: Interaction
var _equipment: Equipment
var _mission: MissionDirector = null  # optional: sessions without a contract (tests, lobby) run without one
var _comms: Comms = null  # optional; comms are ephemeral and never part of the authoritative state
var _collectible_handler: Callable = Callable()  # optional EXP04 host-only pickup callback
var _collectible_state: Callable = Callable()  # optional EXP04 canonical discovered state
var _device_handler: Callable = Callable()  # opt-in EXP07; invoked only after host range and replay checks
var _device_state: Callable = Callable()  # host-owned EXP07 device state, part of canonical hash
var _fault_handler: Callable = Callable()  # opt-in EXP08; never a client-defined state transition
var _fault_state: Callable = Callable()  # canonical host-owned EXP08 state
var _fault_tick: Callable = Callable()  # fixed host tick, not a wire timestamp
var _consequence_handler: Callable = Callable()  # EXP009 host-only consequence actions
var _consequence_state: Callable = Callable()  # part of canonical state and hash
var _consequence_tick: Callable = Callable()  # after EXP08 state advances
var _logistics_handler: Callable = Callable()  # EXP010 stock, deliveries, recall
var _logistics_state: Callable = Callable()  # canonical host hash
var _logistics_tick: Callable = Callable()  # after EXP009 consequence tick
var _balance_handler: Callable = Callable()  # EXP011 finite critical-load operations
var _balance_state: Callable = Callable()  # authoritative EXP011 hash state
var _balance_tick: Callable = Callable()  # after EXP010 logistics host tick
var _worksite_handler: Callable = Callable()  # EXP012 source-pinned field orders
var _worksite_state: Callable = Callable()  # canonical state and host hash
var _worksite_tick: Callable = Callable()  # after EXP011 critical loads tick
var _expedition_intent_guard: Callable = Callable()  # optional EXP06 policy; checked after host dedupe
var _expedition_tick_authority: Callable = Callable()  # A12.11 host-only lifecycle owner, never wire-supplied
var _expedition_intent_guard_bound: bool = false  # A12.15: valid policy cannot be cleared or rebound
var _regional_dispatch_epoch_bound: bool = false  # A12.15: a lost callback fails closed
var _switches: Dictionary = {}  # switch id -> {"target", "field"}
var _members: Dictionary = {}  # transport peer id (int) -> player id
var _last_seq: Dictionary = {}  # peer id -> highest accepted seq
var _replies: Dictionary = {}  # peer id -> {seq: reply} (bounded by dedupe_window)
var _recent: Dictionary = {}  # peer id -> Array[int] ticks of accepted commands (rate window)
var _synced: Dictionary = {}  # peer id -> true once the peer confirmed it applied a snapshot (revision barrier)
var _join_revision: Dictionary = {}  # peer id -> host revision at admission
var _range_check: Callable  # (player_id: String, entity_id: String) -> bool, from host movement
var _position_of: Callable = func(_p: String) -> Vector3i: return Vector3i.ZERO  # host movement: player position in cm
var _now: int = 0
var _last_checkpoint_tick: int = 0
var _published_state: Dictionary = {}  # authoritative state as of _published_revision (what clients have been sent)
var _published_revision: int = 0


## Optional source-engineered policy hook. Normal C01-C12 sessions leave it unset.
## Invoked only for a validated, nonduplicate SessionHost command.
func set_expedition_intent_guard(guard: Callable) -> void:
	# Set once during session construction. A stale caller cannot replace
	# the original-source intent guard with a permissive or empty callable.
	if _expedition_intent_guard_bound or not guard.is_valid():
		return
	_expedition_intent_guard = guard
	_expedition_intent_guard_bound = true


## Host-only ownership fence, opt-in for A09 regional networks. Obsolete
## sessions may advance transport rate time but not world/mission ticks.
func set_expedition_tick_authority(authority: Callable) -> void:
	# Never allow rebinding or clearing the original-region ownership epoch.
	# Failed or freed callbacks remain revoked rather than becoming legacy.
	if _regional_dispatch_epoch_bound or not authority.is_valid():
		return
	_expedition_tick_authority = authority
	_regional_dispatch_epoch_bound = true


## All A09-only host lifecycle hooks share the owner-issued dispatch epoch.
## Unbound original campaign SessionHost objects remain unchanged.
func _regional_lifecycle_revoked() -> bool:
	return _regional_dispatch_epoch_bound and \
		(not _expedition_tick_authority.is_valid() or \
		not bool(_expedition_tick_authority.call()))


func configure(limits: Dictionary, protocol_version: int, content_revision: String, new_session_id: String,
		grid: PowerGrid, meter: MeterModel, interaction: Interaction, equipment: Equipment,
		switches_def: Dictionary, range_check: Callable) -> Array[Dictionary]:
	_limits = {}
	var errs: Array[Dictionary] = []
	for key: String in ["max_message_bytes", "max_payload_keys", "max_string_length", "dedupe_window", "rate_limit_commands",
			"rate_limit_window_ticks", "checkpoint_interval_ticks", "snapshot_chunk_bytes", "max_players"]:
		var v: Variant = PowerGrid.to_int(limits.get(key))
		if v == null or int(v) < 1:
			errs.append(PowerGrid.diag("BAD_VALUE", "network limit %s must be an int >= 1" % key, []))
		else:
			_limits[key] = int(v)
	for rec: Variant in switches_def.get("switches", []):
		var s: Dictionary = rec if rec is Dictionary else {}
		var target: Variant = s.get("target")
		var field: Variant = s.get("field")
		var grid_state: Dictionary = grid.canonical_state()
		var nodes: Dictionary = grid_state["nodes"]
		var edges: Dictionary = grid_state["edges"]
		# Switches may control an authored node or edge. Only its predefined
		# boolean SETTABLE fields are exposed to a host-validated intent.
		var kind: String = ""
		if target is String and nodes.has(target):
			kind = nodes[target]["kind"]
		elif target is String and edges.has(target):
			kind = PowerGrid.KIND_EDGE
		var allowed: bool = field is String and kind != "" and (PowerGrid.SETTABLE[kind] as Array).has(field)
		if not PowerGrid.is_valid_id(s.get("id")) or not allowed:
			errs.append(PowerGrid.diag("BAD_SWITCH", "switch %s needs an ID and a settable grid field" % str(s.get("id")), []))
		else:
			_switches[s["id"]] = {"target": target, "field": field}
	session_id = new_session_id
	_protocol_version = protocol_version
	_content_revision = content_revision
	_grid = grid
	_meter = meter
	_interaction = interaction
	_equipment = equipment
	_range_check = range_check
	return errs


## Join handshake (NET08 logic): rejects before spawning on any version mismatch, with a reason.
func admit(peer_id: int, player_id: String, protocol_version: int, content_revision: String, tools: Array[String]) -> Dictionary:
	# A12.14: no new peer/mission authority after dispatch replacement.
	if _regional_lifecycle_revoked():
		return _refuse("EXP015_A12_14_STALE_HOST_LIFECYCLE",
			"regional dispatch ownership has changed", [])
	if protocol_version != _protocol_version:
		return _refuse("PROTOCOL_MISMATCH", "this game version uses protocol %d, the host uses %d" % [protocol_version, _protocol_version], [])
	if content_revision != _content_revision:
		return _refuse("CONTENT_MISMATCH", "content differs from the host's; update the game", [])
	if _members.has(peer_id) or not PowerGrid.is_valid_id(player_id):
		return _refuse("ALREADY_JOINED", "peer is already in the session", [])
	var replaced: Array[Dictionary] = []
	for old_peer: int in _members.keys():
		if _members[old_peer] == player_id:
			# same participant on a new connection (identity comes from the transport): the stale connection is dropped
			# first, so the session never holds two actors for one player
			replaced = remove(old_peer)
	if _members.size() >= int(_limits["max_players"]):
		return _refuse("SESSION_FULL", "this crew already has %d players" % _limits["max_players"], [])
	_members[peer_id] = player_id
	_last_seq[peer_id] = 0
	_replies[peer_id] = {}
	_recent[peer_id] = [] as Array[int]
	_interaction.join(player_id, tools)
	if _mission != null:
		_mission.player_joined(player_id)
	revision += 1
	_join_revision[peer_id] = revision
	if peer_id == HOST_PEER:
		_synced[peer_id] = true  # the host player reads the authoritative state directly
	return {"ok": true, "session": session_id, "player": player_id, "revision": revision, "needs_snapshot": peer_id != HOST_PEER,
		"replaced": replaced}


## Revision barrier: a joining peer may send commands only after confirming it applied a snapshot at or after its
## admission revision (it sat in the joining screen until then).
func confirm_synced(peer_id: int, applied_revision: int) -> Dictionary:
	# No stale snapshot barrier acknowledgement from an obsolete host.
	if _regional_lifecycle_revoked():
		return _refuse("EXP015_A12_14_STALE_HOST_LIFECYCLE",
			"regional dispatch ownership has changed", [])
	if not _members.has(peer_id):
		return _refuse("UNKNOWN_PEER", "sender is not a member of this session", [])
	if applied_revision < int(_join_revision[peer_id]) or applied_revision > revision:
		return _refuse("STALE_SNAPSHOT", "the applied snapshot is older than this connection", [])
	_synced[peer_id] = true
	return {"ok": true, "revision": revision}


## Transport reports a disconnect: locks release and carried items return to a pad.
func remove(peer_id: int) -> Array[Dictionary]:
	# Old transport teardown must not mutate obsolete mission/equipment state.
	if _regional_lifecycle_revoked():
		return []
	if not _members.has(peer_id):
		return []
	var player: String = _members[peer_id]
	var events: Array[Dictionary] = _interaction.disconnect_player(player)
	events.append_array(_equipment.disconnect_player(player))
	if _mission != null:
		_mission.player_left(player)
	if _comms != null:
		events.append_array(_comms.player_left(player))
	for d: Dictionary in [_members, _last_seq, _replies, _recent, _synced, _join_revision]:
		d.erase(peer_id)
	revision += 1
	return events


## One host grid tick (call at 10 Hz): grid step (trips), meter trip reasons, lock timeouts, checkpoint timer.
## Returns this tick's events; trips and lock releases are durable and advance the revision with the tick itself.
func tick(now: int) -> Array[Dictionary]:
	_now = now
	# A12.11: a superseded regional host cannot advance grid trips, mission
	# deadlines, repair locks, regional overlays or checkpoint revisions.
	# Keep only transport rate-window time moving for authenticated denials.
	if _regional_lifecycle_revoked():
		return []
	var before: String = state_hash()
	var events: Array[Dictionary] = _grid.step()
	_meter.record_events(events, _grid)
	events.append_array(_interaction.tick(now))
	if _mission != null:
		_mission.note_events(events)
		events.append_array(_mission.tick(now))  # after the grid step, so latches and verification see this tick's supply
	if _comms != null:
		events.append_array(_comms.tick(now))
	# EXP08 stability advances inside the original host hash/revision barrier.
	if _fault_tick.is_valid():
		_fault_tick.call()
	# EXP009 propagation observes this same authoritative tick, after EXP08.
	if _consequence_tick.is_valid():
		_consequence_tick.call()
	if _logistics_tick.is_valid():
		_logistics_tick.call()
	if _balance_tick.is_valid():
		_balance_tick.call()
	if _worksite_tick.is_valid():
		_worksite_tick.call()
	if now - _last_checkpoint_tick >= int(_limits["checkpoint_interval_ticks"]):
		_last_checkpoint_tick = now
		events.append({"type": "checkpoint_due", "reason": "interval", "tick": now})
	if state_hash() != before:
		revision += 1
	return events


## Delta for clients since the last publish: {"type": "delta", "from", "to", "ops", "hash"}; {} when nothing changed.
## ops are set/del on key paths of the canonical authoritative state; "hash" is the state hash after applying them.
func publish() -> Dictionary:
	# An obsolete A09 SessionHost must not publish the replacement dispatch's
	# shared source through its old session ID. The current host is unaffected.
	if _regional_lifecycle_revoked():
		return {}
	if revision == _published_revision and not _published_state.is_empty():
		return {}
	var now_state: Dictionary = authoritative_state()
	var ops: Array[Dictionary] = []
	_diff(_published_state, now_state, [], ops)
	var msg: Dictionary = {"type": "delta", "from": _published_revision, "to": revision, "ops": ops, "hash": state_hash()}
	_published_state = now_state.duplicate(true)
	_published_revision = revision
	return msg


## Join/reconnect snapshot (blueprint p.10): a manifest plus bounded chunks of the canonical state at the published
## revision. Any delta published afterwards starts from that revision, so a joining client queues them and applies
## the ones newer than the snapshot. Returns {"deltas": [flushed delta or empty], "manifest", "chunks"}.
func snapshot() -> Dictionary:
	# Reconnection to an obsolete original-region session must not reveal
	# newer regional feeder/reserve/debt state or an untrusted old manifest.
	if _regional_lifecycle_revoked():
		return _refuse("EXP015_A12_13_STALE_HOST_SNAPSHOT",
			"regional dispatch ownership has changed", [])
	var flushed: Dictionary = publish()
	var text: String = PowerGrid.serialize(_published_state)
	var size: int = int(_limits["snapshot_chunk_bytes"])
	var chunks: Array[Dictionary] = []
	# bound the encoded message, not the raw slice: inside JSON every quote and backslash doubles (the text is ASCII)
	var budget: int = size - CHUNK_ENVELOPE_BYTES
	var start: int = 0
	var used: int = 0
	for i: int in text.length():
		var c: int = text.unicode_at(i)
		var cost: int = 2 if c == 0x22 or c == 0x5C else 1
		if used + cost > budget:
			chunks.append({"type": "snapshot_chunk", "index": chunks.size(), "data": text.substr(start, i - start)})
			start = i
			used = 0
		used += cost
	chunks.append({"type": "snapshot_chunk", "index": chunks.size(), "data": text.substr(start)})
	var manifest: Dictionary = {"type": "snapshot_manifest", "revision": _published_revision, "hash": text.sha256_text(),
		"bytes": text.length(), "chunks": chunks.size(), "protocol_version": _protocol_version, "content_revision": _content_revision}
	return {"deltas": [] if flushed.is_empty() else [flushed], "manifest": manifest, "chunks": chunks}


static func _diff(old: Dictionary, new: Dictionary, path: Array, ops: Array[Dictionary]) -> void:
	var keys: Array = old.keys()
	for k: Variant in new:
		if not old.has(k):
			keys.append(k)
	keys.sort()
	for k: Variant in keys:
		var p: Array = path.duplicate()
		p.append(k)
		if not new.has(k):
			ops.append({"op": "del", "path": p})
		elif old.has(k) and old[k] is Dictionary and new[k] is Dictionary:
			_diff(old[k], new[k], p, ops)
		elif not old.has(k) or PowerGrid.serialize(old[k]) != PowerGrid.serialize(new[k]):
			ops.append({"op": "set", "path": p, "value": new[k]})


## The single entry point for commands. peer_id comes from the transport, never from the bytes.
func receive(peer_id: int, bytes: PackedByteArray) -> Dictionary:
	if bytes.size() > int(_limits["max_message_bytes"]):
		return _refuse("TOO_LARGE", "command exceeds %d bytes" % _limits["max_message_bytes"], [])
	var json: JSON = JSON.new()
	if json.parse(bytes.get_string_from_utf8()) != OK or not json.data is Dictionary:
		return _refuse("MALFORMED", "command is not a JSON object", [])
	var msg: Dictionary = json.data
	var shape: Dictionary = _check_shape(msg)
	if not shape.is_empty():
		return shape
	if not _members.has(peer_id):
		return _refuse("UNKNOWN_PEER", "sender is not a member of this session", [])
	if not _synced.has(peer_id):
		return _refuse("NOT_SYNCED", "still joining: apply the snapshot first", [])
	if msg["session"] != session_id:
		return _refuse("WRONG_SESSION", "command is for another session", [])
	var seq: int = int(PowerGrid.to_int(msg["seq"]))
	var cache: Dictionary = _replies[peer_id]
	if seq <= int(_last_seq[peer_id]):
		if cache.has(seq):
			# Deduplication must preserve the original *denial* (and its
			# domain-specific reason). A refused command has no accepted
			# world side effect. Only a previously successful response is
			# revoked when the regional host loses source ownership.
			# This retains A12.10 anchor expiry diagnostics while preventing
			# old authenticated successes from being falsely replayed.
			var cached_reply: Dictionary = cache[seq]
			if _regional_lifecycle_revoked() and bool(cached_reply.get("ok", false)):
				return _refuse("EXP015_A12_15_STALE_REPLAY",
					"regional dispatch ownership has changed", [])
			var again: Dictionary = (cache[seq] as Dictionary).duplicate(true)
			again["duplicate"] = true
			return again
		return _refuse("STALE_SEQUENCE", "sequence %d is older than the dedupe window" % seq, [])
	var window: Array[int] = _recent[peer_id]
	while not window.is_empty() and _now - window[0] >= int(_limits["rate_limit_window_ticks"]):
		window.pop_front()
	if window.size() >= int(_limits["rate_limit_commands"]):
		return _refuse("RATE_LIMITED", "too many commands; slow down", [])
	# from here the sequence is consumed: a resend of this seq returns this exact reply
	window.append(_now)
	_last_seq[peer_id] = seq
	var before: String = state_hash()
	var reply: Dictionary = _dispatch(_members[peer_id], msg)
	# A refused stale regional intent must not cause even indirect mission
	# observation or evidence changes. Older owners may retain their mission
	# object after takeover; only a current owner may observe live supply.
	if _mission != null and not _regional_lifecycle_revoked():
		_mission.observe_supply_state()
	# A refused reset can still consume a C07 evidence-before-reset bonus;
	# the host revision must reflect any authorized mission fact change.
	if state_hash() != before:
		revision += 1
	reply["seq"] = seq
	reply["revision"] = revision
	cache[seq] = reply.duplicate(true)
	var cutoff: int = seq - int(_limits["dedupe_window"])
	for old: int in cache.keys():
		if old <= cutoff:
			cache.erase(old)  # skipped sequence numbers must not grow the cache
	return reply


func _check_shape(msg: Dictionary) -> Dictionary:
	if msg.size() != ENVELOPE_KEYS.size():
		return _refuse("MALFORMED", "command needs exactly %s" % str(ENVELOPE_KEYS), [])
	for key: String in ENVELOPE_KEYS:
		if not msg.has(key):
			return _refuse("MALFORMED", "command is missing %s" % key, [])
	var seq: Variant = PowerGrid.to_int(msg["seq"])
	if seq == null or int(seq) < 1:
		return _refuse("MALFORMED", "seq must be an int >= 1", [])
	if not (msg["session"] is String and msg["type"] is String and msg["entity"] is String and msg["payload"] is Dictionary):
		return _refuse("MALFORMED", "session, type and entity are strings; payload is an object", [])
	var payload: Dictionary = msg["payload"]
	if payload.size() > int(_limits["max_payload_keys"]):
		return _refuse("TOO_LARGE", "payload has too many fields", [])
	for k: Variant in payload:
		var v: Variant = payload[k]
		if not (v is bool or v is float or (v is String and (v as String).length() <= int(_limits["max_string_length"]))):
			return _refuse("MALFORMED", "payload values are bools, numbers or short strings", [])
	return {}


func _dispatch(player: String, msg: Dictionary) -> Dictionary:
	var kind: String = msg["type"]
	var entity: String = msg["entity"]
	var payload: Dictionary = msg["payload"]
	if DEFERRED_INTENTS.has(kind):
		return _refuse("UNSUPPORTED_INTENT", "%s is not available in this build" % kind, [])
	if not INTENTS.has(kind):
		return _refuse("UNKNOWN_INTENT", "unknown intent %s" % kind, [])
	# Sequence and dedupe have already been processed. No denied command may
	# reach a grid or repair side effect. The guard uses only host-owned state.
	if _expedition_intent_guard_bound:
		# A guard that was valid at bind time must never silently become
		# a bypass if its callable target later disappears.
		if not _expedition_intent_guard.is_valid():
			return _refuse("EXP015_A12_15_INTENT_GUARD_UNAVAILABLE",
				"host intent authority is unavailable", [entity])
		var policy_reply: Variant = _expedition_intent_guard.call(player, kind, entity, payload)
		if not policy_reply is Dictionary:
			return _refuse("EXP06_POLICY_DENIED", "expedition intent policy denied", [entity])
		if not bool(policy_reply.get("ok", false)):
			return policy_reply

	if kind == "ping" or kind == "chat":
		if _comms == null:
			return _refuse("UNSUPPORTED_INTENT", "communication is not available in this session", [])
		if kind == "ping":
			if entity != "" and not PowerGrid.is_valid_id(entity):
				return _refuse("UNKNOWN_ENTITY", "pings target a content ID or nothing", [])
			return _comms.ping(player, payload.get("ping"), entity, _position_of.call(player))
		if payload.has("phrase"):
			return _comms.phrase(player, payload["phrase"])
		return _comms.chat(player, payload.get("text"))
	if kind == "recover_self":
		return _recover_player(player)
	if kind == "request_extract":
		if _mission == null:
			return _refuse("NO_MISSION", "no contract is running", [])
		var action: Variant = payload.get("action")
		return _mission.request_extract(player, action if action is String else "")
	# Ladder access follows membership/rate/dedupe checks and trusts only the
	# host range callback, never a client position or permission flag.
	if kind == "use_ladder":
		if _mission == null:
			return _refuse("NO_MISSION", "no contract is running", [])
		if not payload.is_empty():
			return _refuse("MALFORMED", "use_ladder takes no payload", [entity])
		return _mission.use_ladder(entity, _range_check.call(player, entity))
	# A peer may request an authored route; it cannot choose its own clock or position.
	if kind == "use_route":
		if _mission == null:
			return _refuse("NO_MISSION", "no contract is running", [])
		if not payload.is_empty():
			return _refuse("MALFORMED", "use_route takes no client payload", [entity])
		return _mission.use_wind_route(player, entity, _range_check.call(player, entity))
	var in_range: bool = _range_check.call(player, entity)
	# EXP07 devices share the same host sequence, replay, rate, range and sight gates.
	# No legacy C01-C12 session attaches a device authority.
	if kind == "operate_device":
		if not _device_handler.is_valid():
			return _refuse("UNSUPPORTED_INTENT", "this session has no EXP07 devices", [])
		if payload.size() != 1 or not payload.get("action") is String:
			return _refuse("MALFORMED", "operate_device needs exactly one action", [entity])
		if not in_range:
			return _refuse("NOT_IN_RANGE", "move closer to %s" % entity, [entity])
		var result: Variant = _device_handler.call(player, entity, str(payload["action"]))
		if not result is Dictionary:
			return _refuse("EXP07_INVALID_HOST_RESULT", "device authority produced invalid result", [entity])
		return result
	# EXP08 uses the same authorized envelope, source-bound entity range and LoS.
	if kind == "operate_fault":
		if not _fault_handler.is_valid():
			return _refuse("UNSUPPORTED_INTENT", "EXP08 not active in this session", [])
		if payload.size() != 1 or not payload.get("action") is String:
			return _refuse("MALFORMED", "operate_fault takes exactly one action", [entity])
		if not in_range:
			return _refuse("NOT_IN_RANGE", "move closer to %s" % entity, [entity])
		var fault_reply: Variant = _fault_handler.call(player, entity, str(payload["action"]))
		if not fault_reply is Dictionary:
			return _refuse("EXP08_INVALID_HOST_RESULT", "fault authority returned invalid result", [entity])
		return fault_reply
	# EXP009 never accepts a peer's clock, service health, exposure or outcome.
	if kind == "operate_consequence":
		if not _consequence_handler.is_valid():
			return _refuse("UNSUPPORTED_INTENT", "EXP009 not active in this session", [])
		if payload.size() != 1 or not payload.get("action") is String:
			return _refuse("MALFORMED", "operate_consequence takes exactly one action", [entity])
		if not in_range:
			return _refuse("NOT_IN_RANGE", "move closer to %s" % entity, [entity])
		var consequence_reply: Variant = _consequence_handler.call(player, entity, str(payload["action"]))
		if not consequence_reply is Dictionary:
			return _refuse("EXP009_INVALID_HOST_RESULT", "consequence authority returned invalid result", [entity])
		return consequence_reply
	# EXP010: validated source-bound inventory and dispatch command.
	if kind == "operate_logistics":
		if not _logistics_handler.is_valid():
			return _refuse("UNSUPPORTED_INTENT", "EXP010 not active in this session", [])
		if payload.size() != 1 or not payload.get("action") is String:
			return _refuse("MALFORMED", "operate_logistics takes exactly one action", [entity])
		if not in_range:
			return _refuse("NOT_IN_RANGE", "move closer to %s" % entity, [entity])
		var logistics_reply: Variant = _logistics_handler.call(player, entity, str(payload["action"]))
		if not logistics_reply is Dictionary:
			return _refuse("EXP010_INVALID_HOST_RESULT", "logistics authority returned invalid result", [entity])
		return logistics_reply
	# EXP011: host-owned temporary grid capacity and service stabilization.
	if kind == "operate_balance":
		if not _balance_handler.is_valid():
			return _refuse("UNSUPPORTED_INTENT", "EXP011 not active in this session", [])
		if payload.size() != 1 or not payload.get("action") is String:
			return _refuse("MALFORMED", "operate_balance takes exactly one action", [entity])
		if not in_range:
			return _refuse("NOT_IN_RANGE", "move closer to %s" % entity, [entity])
		var balance_reply: Variant = _balance_handler.call(player, entity, str(payload["action"]))
		if not balance_reply is Dictionary:
			return _refuse("EXP011_INVALID_HOST_RESULT", "load authority returned invalid result", [entity])
		return balance_reply
	# EXP012: source-pinned worksite decision and checkpoint commands.
	if kind == "operate_worksite":
		if not _worksite_handler.is_valid():
			return _refuse("UNSUPPORTED_INTENT", "EXP012 not active in this session", [])
		if payload.size() != 1 or not payload.get("action") is String:
			return _refuse("MALFORMED", "operate_worksite takes exactly one action", [entity])
		if not in_range:
			return _refuse("NOT_IN_RANGE", "move closer to %s" % entity, [entity])
		var work_reply: Variant = _worksite_handler.call(player, entity, str(payload["action"]))
		if not work_reply is Dictionary:
			return _refuse("EXP012_INVALID_HOST_RESULT", "worksite authority returned invalid result", [entity])
		return work_reply
	# EXP04's optional pickup is subject to the SAME transport membership,
	# session, sequence, rate, entity proximity and sight checks as repairs.
	# Without an explicit server-side handler existing contracts refuse it.
	if kind == "collect_lore":
		if not _collectible_handler.is_valid():
			return _refuse("UNSUPPORTED_INTENT", "this contract has no lore pickup authority", [])
		if not payload.is_empty():
			return _refuse("MALFORMED", "collect_lore has no client payload", [entity])
		if not in_range:
			return _refuse("NOT_IN_RANGE", "move closer to %s" % entity, [entity])
		var collectible_reply: Variant = _collectible_handler.call(player, entity)
		if not collectible_reply is Dictionary:
			return _refuse("UNSUPPORTED_INTENT", "invalid collectible host reply", [entity])
		return collectible_reply
	match kind:
		"toggle_switch":
			if not _switches.has(entity):
				return _refuse("UNKNOWN_ENTITY", "no switch %s" % entity, [])
			if not in_range:
				return _refuse("NOT_IN_RANGE", "move closer to %s" % entity, [entity])
			if not payload.get("value") is bool:
				return _refuse("MALFORMED", "toggle_switch needs a bool value", [entity])
			var sw: Dictionary = _switches[entity]
			if _mission != null:
				_mission.note_breaker_reset_attempt(sw["target"], sw["field"], payload["value"])
			var res: Dictionary = _grid.apply({"op": "set", "id": sw["target"], "field": sw["field"], "value": payload["value"]})
			if not res["ok"]:
				var ids: Array = (res["ids"] as Array).duplicate()
				ids.append(entity)
				var refusal: Dictionary = _refuse("GRID_REFUSED", res["message"], ids)
				refusal["grid_code"] = res["code"]
				return refusal
			_meter.observe(_grid)
			return {"ok": true}
		"inspect":
			if not _meter.has_panel(entity):
				return _refuse("UNKNOWN_ENTITY", "no meter panel %s" % entity, [])
			if not in_range:
				return _refuse("NOT_IN_RANGE", "move closer to %s" % entity, [entity])
			var sample: Dictionary = _meter.inspect(entity, _grid)
			if sample.get("ok", false) and _mission != null:
				_mission.note_meter_inspection(entity, _meter.readings(entity, _grid))
			return sample
		"equip":
			return _interaction.handle(player, {"type": "equip", "tool": payload.get("tool", "")})
		"place_item":
			var action: Variant = payload.get("action")
			if not (action is String and PLACE_ACTIONS.has(action)):
				return _refuse("MALFORMED", "place_item needs an action", [entity])
			var intent: Dictionary = {"type": action, "item": entity, "in_range": in_range}
			if action == "drop":
				intent["position_cm"] = _position_of.call(player)  # host's own position for the player, never the client's claim
			for key: String in ["anchor", "route"]:
				if payload.has(key):
					intent[key] = payload[key]
			if action == "place" and payload.get("anchor") is String and not _range_check.call(player, payload["anchor"]):
				# the carrier must stand at the destination too; carrying never teleports an item across the map
				return _refuse("NOT_IN_RANGE", "move closer to %s" % payload["anchor"], [entity, payload["anchor"]])
			var res: Dictionary = _equipment.handle(player, intent)
			if action == "pickup" and res.get("ok", false) and _mission != null:
				var pickup_events: Array[Dictionary] = _mission.note_equipment_pickup()
				if not pickup_events.is_empty():
					var all_events: Array = res.get("events", [])
					all_events.append_array(pickup_events)
					res["events"] = all_events
			return _strip(res)
	# request_lock, release, heartbeat, repair_step go to the repair interaction service
	var intent: Dictionary = {"type": kind, "repair": entity, "in_range": in_range}
	if payload.has("step"):
		intent["step"] = payload["step"]
	var res: Dictionary = _interaction.handle(player, intent)
	if res.get("code") == "UNKNOWN_REPAIR":
		return _refuse("UNKNOWN_ENTITY", "no repair %s" % entity, [])
	if res.get("state") == "restored":
		res["checkpoint_due"] = true  # host checkpoints after durable repair completion (blueprint p.10)
	return _strip(res)


## Host-only lifecycle gate, not an untrusted client intent. Called once the
## briefing overlay is dismissed and every joined peer confirmed its snapshot.
func begin_after_briefing() -> Dictionary:
	# Old host cannot re-arm mission state after successor activation.
	if _regional_lifecycle_revoked():
		return _refuse("EXP015_A12_14_STALE_HOST_LIFECYCLE",
			"regional dispatch ownership has changed", [])
	if _mission == null:
		return _refuse("NO_MISSION", "no mission to start", [])
	if _members.is_empty():
		return _refuse("NO_PLAYERS", "briefing waits for an admitted crew", [])
	for peer: int in _members:
		if not _synced.has(peer):
			return _refuse("NOT_SYNCED", "briefing waits for every player to load", [])
	var before: String = state_hash()
	var reply: Dictionary = _mission.begin_after_briefing()
	if state_hash() != before:
		revision += 1
	return reply


## Hash of every authoritative state this host owns (ADR-003 canonical bytes); clients compare it (G07).
func state_hash() -> String:
	return PowerGrid.serialize(authoritative_state()).sha256_text()


func authoritative_state() -> Dictionary:
	# Direct read access is host-internal, but must be safe even if an
	# obsolete session remains referenced after a newer A09 dispatch.
	if _regional_lifecycle_revoked():
		return {"authority": "EXP015_A12_13_STALE_HOST_SNAPSHOT"}
	var repairs: Dictionary = _interaction.canonical_state()
	repairs.erase("revision")
	var items: Dictionary = _equipment.canonical_state()
	items.erase("revision")
	var crew: Array[String] = []
	crew.assign(_members.values())
	crew.sort()
	# the crew list is authoritative too, so a duplicate actor after a reconnect would show up as a hash mismatch
	var state: Dictionary = {"grid": _grid.canonical_state(), "repairs": repairs, "equipment": items, "meter": _meter.canonical_state(),
		"crew": crew}
	if _mission != null:
		state["mission"] = _mission.canonical_state()
	if _collectible_state.is_valid():
		state["field_lore"] = _collectible_state.call()
	if _device_state.is_valid():
		state["exp07_devices"] = _device_state.call()
	if _fault_state.is_valid():
		state["exp08_faults"] = _fault_state.call()
	if _consequence_state.is_valid():
		state["exp009_consequences"] = _consequence_state.call()
	if _logistics_state.is_valid():
		state["exp010_logistics"] = _logistics_state.call()
	if _balance_state.is_valid():
		state["exp011_critical_loads"] = _balance_state.call()
	if _worksite_state.is_valid():
		state["exp012_worksite_orders"] = _worksite_state.call()
	return state


## Only an explicit expedition instance attaches this extension. Legacy campaigns
## continue to reject collect_lore and preserve their canonical snapshots.
func set_collectible_authority(handler: Callable, state_provider: Callable) -> void:
	_collectible_handler = handler
	_collectible_state = state_provider


## EXP07 is opt-in per experimental expedition session. Every other host is unchanged.
func set_expedition_device_authority(handler: Callable, state_provider: Callable) -> void:
	_device_handler = handler
	_device_state = state_provider


## Isolated EXP08 extension. Legacy hosts do not install these callbacks.
func set_expedition_fault_authority(handler: Callable, state_provider: Callable,
		tick_provider: Callable) -> void:
	_fault_handler = handler
	_fault_state = state_provider
	_fault_tick = tick_provider


## EXP009 only attaches to explicit experimental expedition sessions.
func set_expedition_consequence_authority(handler: Callable, state_provider: Callable,
		tick_provider: Callable) -> void:
	_consequence_handler = handler
	_consequence_state = state_provider
	_consequence_tick = tick_provider


## EXP010 is disabled in all legacy and non-EXP010 sessions.
func set_expedition_logistics_authority(handler: Callable, state_provider: Callable,
		tick_provider: Callable) -> void:
	_logistics_handler = handler
	_logistics_state = state_provider
	_logistics_tick = tick_provider


## EXP011 is explicitly opt-in; no original campaign or earlier EXP session binds it.
func set_expedition_balance_authority(handler: Callable, state_provider: Callable,
		tick_provider: Callable) -> void:
	_balance_handler = handler
	_balance_state = state_provider
	_balance_tick = tick_provider


## EXP012 only attaches to explicitly opted-in expedition instances.
func set_expedition_worksite_authority(handler: Callable, state_provider: Callable,
		tick_provider: Callable) -> void:
	_worksite_handler = handler
	_worksite_state = state_provider
	_worksite_tick = tick_provider


## Attach crew communication (V06).
func set_comms(comms: Comms) -> void:
	_comms = comms


## Host movement supplies player positions (integer cm) used for item drops; until V01 every player is at the origin.
func set_position_provider(position_of: Callable) -> void:
	_position_of = position_of


## Van-menu recovery for a stranded player (blueprint p.6): the player returns to the van; their locks release and a
## carried item goes back to the last anchor it stood on. The network and every repair stay exactly as they are.
func _recover_player(player: String) -> Dictionary:
	var events: Array[Dictionary] = _interaction.recover_player(player)
	events.append_array(_equipment.disconnect_player(player))  # same return path as a carrier who dropped out
	# zone presence is not touched here: the player lands at the van and host movement reports where they stand
	events.append({"type": "player_recovered", "player": player})
	if _mission != null:
		_mission.note_events(events)
	return {"ok": true, "events": events}


## Attach the contract's mission director (V02). Players already admitted are reported to it.
func set_mission(mission: MissionDirector) -> void:
	_mission = mission
	for peer: int in _members:
		_mission.player_joined(_members[peer])


## Host movement reports zone presence; leaving the extraction zone cancels a running countdown (MIS04).
func set_in_zone(player: String, zone: String, inside: bool) -> Array[Dictionary]:
	# Reject old host-owned zone presence without touching the mission.
	if _regional_lifecycle_revoked():
		return []
	if _mission == null:
		return []
	var before: String = state_hash()
	var events: Array[Dictionary] = _mission.set_in_zone(player, zone, inside)
	if state_hash() != before:
		revision += 1
	return events


func member(peer_id: int) -> String:
	return _members.get(peer_id, "")


## Service replies carry their own revision counters; the host revision is the only one clients see.
static func _strip(res: Dictionary) -> Dictionary:
	var out: Dictionary = res.duplicate(true)
	out.erase("revision")
	return out


func _refuse(code: String, message: String, ids: Array) -> Dictionary:
	var d: Dictionary = PowerGrid.diag(code, message, ids)
	return {"ok": false, "code": code, "key": "network.refused." + code.to_lower(), "message": message, "ids": d["ids"],
		"revision": revision}
