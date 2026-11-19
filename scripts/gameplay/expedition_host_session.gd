extends RefCounted
## EXP03: host-only expedition session for the 200 authored dispatches.
##
## Every client action goes through the production SessionHost.receive() byte
## envelope and the original Grid/Meter/Interaction/Equipment/Mission services.
## Task advancement observes accepted host evidence; never trusts client claims
## of progress, location, rewards, inspection results, or clock time.
##
## The caller must supply a SERVER-OWNED character position provider, not a
## client-reported transform. This source/headless service has no collision
## world; the later physical scene integration must add sight/capsule checks.

const Atlas := preload("res://scripts/world/dispatch_atlas.gd")
const Plan := preload("res://scripts/world/expedition_layout_plan.gd")
const Factory := preload("res://scripts/gameplay/expedition_contract_factory.gd")
const Grid := preload("res://scripts/simulation/power_grid.gd")
const Meter := preload("res://scripts/simulation/meter_model.gd")
const Interaction := preload("res://scripts/interaction/interaction_service.gd")
const Equipment := preload("res://scripts/interaction/equipment_service.gd")
const Mission := preload("res://scripts/simulation/mission_director.gd")
const Host := preload("res://scripts/network/session_host.gd")
const Rewards := preload("res://scripts/progression/reward_service.gd")
const Ledger := preload("res://scripts/progression/expedition_ledger.gd")
const SaveService := preload("res://scripts/persistence/save_service.gd")

const RUNTIME_SCHEMA: int = 1
const PROTOCOL: int = 1
const PLAYER_ID: String = "P1"
const TOOLS: Array[String] = ["meter", "screwdriver", "puller", "cutter", "crimper"]
const INTERACTION_REACH_M: float = 2.30
const PANEL_RADIUS_M: float = 0.48
const SWITCH_RADIUS_M: float = 0.34
const EXTRACTION_RADIUS_M: float = 1.50

var grid: Grid
var meter: Meter
var interaction: Interaction
var equipment: Equipment
var mission: Mission
var host: Host

var _definitions: Dictionary = {}
var _position_source: Callable
var _physics_visibility: Callable
var _tasks: Array[Dictionary] = []
var _completed: Dictionary = {}
var _observed_inspections: Dictionary = {}
var _tick: int = 0
var _ready: bool = false
var _collectible: Dictionary = {}
var _lore_claimed: bool = false
var _account_key: String = ""
var _issued: Dictionary = {}
var _reward_queue: Rewards.HostQueue = Rewards.HostQueue.new()


static func _json(path: String) -> Dictionary:
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return value if value is Dictionary else {}


static func _fail(code: String, details: Variant = null) -> Dictionary:
	return {"ok": false, "code": code, "details": details}


## Only source-pinned ID selection is accepted. Reject a forged catalog or
## invalid geometry before constructing a single authority-bearing service.
func start(level_id: String, host_position: Callable,
		physics_visibility: Callable = Callable(), account_key: String = "") -> Dictionary:
	if _ready:
		return _fail("SESSION_ALREADY_STARTED")
	if account_key != "" and not SaveService.is_valid_key(account_key):
		return _fail("INVALID_ACCOUNT_KEY")
	if not host_position.is_valid() or (physics_visibility.is_valid() and not host_position.is_valid()):
		return _fail("MISSING_HOST_POSITION")
	var atlas: Dictionary = Atlas.load_catalog()
	var audit: Dictionary = Atlas.inspect(atlas)
	if not bool(audit.get("ok", false)):
		return _fail("ATLAS_SOURCE_INVALID", audit.get("failures", []))
	var level: Dictionary = Atlas.find_level(atlas, level_id)
	if level.is_empty():
		return _fail("UNKNOWN_LEVEL")
	var location: Dictionary = Atlas.find_location(atlas, str(level["location_id"]))
	var plan: Dictionary = Plan.make_plan(level, location)
	_definitions = Factory.build(level, plan)
	if not bool(_definitions.get("ok", false)):
		return _fail("CONTRACT_FACTORY_FAILED", _definitions)
	_position_source = host_position
	_physics_visibility = physics_visibility
	_account_key = account_key
	# Lore ownership never participates in the grid, equipment, or repair state.
	_collectible = level["collectible"].duplicate(true)
	var item_id: String = str(_collectible["id"])
	(_definitions["positions"] as Dictionary)[item_id] = 		(_definitions["positions"] as Dictionary)["PANEL_SPUR"] + Vector3(0.0, -0.35, 0.55)
	grid = Grid.new()
	meter = Meter.new()
	interaction = Interaction.new()
	equipment = Equipment.new()
	mission = Mission.new()
	var errors: Array[Dictionary] = []
	errors.append_array(grid.load_definition(_definitions["grid"]))
	if not errors.is_empty():
		return _fail("GRID_INVALID", errors)
	errors.append_array(meter.load_definition(_definitions["meter"], grid))
	errors.append_array(interaction.load_definition(
		_json("res://content/interaction.json"), _definitions["repairs"], grid, meter))
	errors.append_array(equipment.load_definition(_definitions["equipment"], grid, meter))
	if not errors.is_empty():
		return _fail("SERVICE_INVALID", errors)
	errors.append_array(mission.load_definition(_definitions["mission"], grid, interaction, equipment))
	if not errors.is_empty():
		return _fail("MISSION_INVALID", errors)
	host = Host.new()
	var rev: String = _content_revision()
	var sid: String = _session_id()
	errors.append_array(host.configure(_json("res://content/network.json"), PROTOCOL,
		rev, sid, grid, meter, interaction, equipment,
		_definitions["switches"], Callable(self, "_in_range")))
	if not errors.is_empty():
		return _fail("HOST_INVALID", errors)
	host.set_position_provider(Callable(self, "_position_cm"))
	host.set_mission(mission)
	host.set_collectible_authority(Callable(self, "_claim_lore"), Callable(self, "_lore_state"))
	var accepted: Dictionary = host.admit(Host.HOST_PEER, PLAYER_ID, PROTOCOL, rev, TOOLS)
	if not bool(accepted.get("ok", false)):
		return _fail("ADMISSION_REFUSED", accepted)
	var begun: Dictionary = host.begin_after_briefing()
	if not bool(begun.get("ok", false)):
		return _fail("BRIEFING_REFUSED", begun)
	_tasks.clear()
	for task: Dictionary in level["tasks"]:
		_tasks.append({"id": str(task["id"]), "kind": str(task["kind"]),
			"title": str(task["title"]), "required": bool(task["required"])})
	_ready = true
	return {"ok": true, "level_id": level_id, "session": sid, "content_revision": rev,
		"task_count": _tasks.size(),
		"qualification": "AUTHORITY_SOURCE_HEADLESS_ONLY_NO_PLAYABILITY"}


func _session_id() -> String:
	return "S_EXP03_" + str(_definitions.get("level_id", "UNKNOWN"))


func _content_revision() -> String:
	return "EXP03_" + str(_definitions.get("source_fingerprint", ""))


func session_id() -> String:
	return _session_id() if _ready else ""


func definition_snapshot() -> Dictionary:
	return _definitions.duplicate(true)


## Real SessionHost receives the exact client message and checks peer identity,
## session ID, sequence, rate, permissions, tools and range. No direct grid.apply
## or direct repair mutation is exposed here.
func receive(peer_id: int, message: PackedByteArray) -> Dictionary:
	if not _ready:
		return _fail("SESSION_NOT_READY")
	var reply: Dictionary = host.receive(peer_id, message)
	if not bool(reply.get("ok", false)) or bool(reply.get("duplicate", false)):
		return reply
	# Decode only AFTER the host accepted the envelope. A decoded task ID or
	# player-supplied success flag is neither requested nor consumed.
	var command: Variant = JSON.parse_string(message.get_string_from_utf8())
	if command is Dictionary:
		var action: Dictionary = command
		if action.get("type") == "inspect" and \
				["PANEL_WEST", "PANEL_SPUR"].has(str(action.get("entity", ""))):
			var panel: String = str(action["entity"])
			var snapshots: Dictionary = meter.canonical_state()["snapshots"]
			if snapshots.has(panel):
				_observed_inspections[panel] = true
	_update_progress()
	return reply


## Called by SessionHost ONLY after its existing transport/session/sequence,
## rate, proximity and optional physics line-of-sight gates all passed.
func _claim_lore(player_id: String, item_id: String) -> Dictionary:
	if player_id != PLAYER_ID or item_id != str(_collectible.get("id", "")):
		return _fail("UNKNOWN_COLLECTIBLE")
	if _lore_claimed:
		return _fail("ALREADY_COLLECTED")
	if not _completed.has(str(_tasks[3]["id"])):
		return _fail("DISCOVERY_EVIDENCE_REQUIRED")
	_lore_claimed = true
	if _account_key != "":
		var receipt: Dictionary = Ledger.make_receipt(_account_key,
			str(_definitions["level_id"]), item_id, "lore")
		var single: Array[Dictionary] = [receipt]
		_reward_queue.issue(single)
	return {"ok": true, "collected_id": item_id}


func _lore_state() -> Dictionary:
	return {"id": str(_collectible.get("id", "")), "collected": _lore_claimed}


## Only accepted new task facts become personal field-point receipts.
func _issue_task_rewards() -> void:
	if _account_key == "":
		return
	var batch: Array[Dictionary] = []
	for task: Dictionary in _tasks:
		var id: String = str(task["id"])
		if _completed.has(id) and not _issued.has(id):
			_issued[id] = true
			batch.append(Ledger.make_receipt(_account_key,
				str(_definitions["level_id"]), id, str(task["kind"])))
	if not batch.is_empty():
		_reward_queue.issue(batch)


## Only the trusted local host calls the pending-receipt/ack interface.
func pending_rewards(account_key: String) -> Array[Dictionary]:
	if account_key == "" or account_key != _account_key:
		return [] as Array[Dictionary]
	return _reward_queue.pending_for(account_key)


func ack_reward(account_key: String, receipt_key: String) -> void:
	if _account_key != "" and account_key == _account_key:
		_reward_queue.ack(account_key, receipt_key)


func lore_state() -> Dictionary:
	return _lore_state().duplicate(true)


func _host_position(player_id: String) -> Vector3:
	if not _position_source.is_valid() or player_id != PLAYER_ID:
		return Vector3.INF
	var candidate: Variant = _position_source.call(player_id)
	if not candidate is Vector3:
		return Vector3.INF
	var position: Vector3 = candidate
	if not position.is_finite() or position.x < 0.0 or position.x > 52.0 or \
			position.z < 0.0 or position.z > 52.0 or position.y < -1.0 or position.y > 10.0:
		return Vector3.INF
	return position


func _position_cm(player_id: String) -> Vector3i:
	var position: Vector3 = _host_position(player_id)
	if position == Vector3.INF:
		return Vector3i.ZERO
	return Vector3i(roundi(position.x * 100.0), roundi(position.y * 100.0),
		roundi(position.z * 100.0))


func _in_range(player_id: String, entity_id: String) -> bool:
	var positions: Dictionary = _definitions.get("positions", {})
	if not positions.has(entity_id):
		return false
	var body: Vector3 = _host_position(player_id)
	if body == Vector3.INF:
		return false
	var origin: Vector3 = body + Vector3.UP * 0.85
	var target: Vector3 = positions[entity_id]
	var radius: float = SWITCH_RADIUS_M if entity_id.begins_with("SW_") else PANEL_RADIUS_M
	if origin.distance_to(target) > INTERACTION_REACH_M + radius:
		return false
	# A physical scene must provide its real physics LoS callback; do not
	# substitute a client boolean. Headless source tests measure range only.
	if _physics_visibility.is_valid():
		return _physics_visibility.call(origin, target, radius)
	return true


func _inside_extraction(player_id: String) -> bool:
	var body: Vector3 = _host_position(player_id)
	if body == Vector3.INF:
		return false
	var center: Vector3 = _definitions["positions"]["ZONE_EXTRACT"]
	return Vector2(body.x - center.x, body.z - center.z).length() <= EXTRACTION_RADIUS_M \
		and absf(body.y - 0.90) <= 1.1


## The host alone owns time. Its zone presence comes from the authoritative
## position provider; neither an RPC nor a client task report can set it.
func tick_host() -> Dictionary:
	if not _ready:
		return _fail("SESSION_NOT_READY")
	_tick += 1
	host.set_in_zone(PLAYER_ID, "ZONE_EXTRACT", _inside_extraction(PLAYER_ID))
	host.tick(_tick)
	_update_progress()
	return {"ok": true, "tick": _tick, "revision": host.revision,
		"completed": mission.results().size() > 0}


func _update_progress() -> void:
	if not _ready:
		return
	var bindings: Dictionary = _definitions["bindings"]
	var first: String = str(_tasks[0]["id"])
	var second: String = str(_tasks[1]["id"])
	var third: String = str(_tasks[2]["id"])
	var optional: String = str(_tasks[3]["id"])
	var last: String = str(_tasks[4]["id"])
	var meter_snapshots: Dictionary = meter.canonical_state()["snapshots"]
	var state: Dictionary = grid.canonical_state()
	var repairs: Dictionary = interaction.canonical_state()["repairs"]
	if _observed_inspections.has("PANEL_WEST") and meter_snapshots.has("PANEL_WEST"):
		_completed[first] = true
	if _completed.has(first) and bool(state["edges"]["E_GRID_EAST"]["enabled"]):
		_completed[second] = true
	if _completed.has(second) and str(repairs["R_WEST"]["state"]) == "restored" and \
			not bool(state["nodes"]["WEST"]["failed"]) and \
			not bool(state["nodes"]["WEST"]["tripped"]):
		_completed[third] = true
	if _observed_inspections.has("PANEL_SPUR") and meter_snapshots.has("PANEL_SPUR"):
		_completed[optional] = true
	if _completed.has(first) and _completed.has(second) and _completed.has(third) and \
			not mission.results().is_empty():
		_completed[last] = true
	_issue_task_rewards()


## Read-only per-run task projection; preview field_points are NEVER granted.
func task_board() -> Dictionary:
	if not _ready:
		return _fail("SESSION_NOT_READY")
	var out: Array[Dictionary] = []
	var required_done: int = 0
	for task: Dictionary in _tasks:
		var done: bool = _completed.has(str(task["id"]))
		if done and task["required"]:
			required_done += 1
		out.append({
			"id": task["id"], "kind": task["kind"], "title": task["title"],
			"required": task["required"], "completed": done,
			"state": "done" if done else "optional" if not task["required"] else "pending",
			"binding": (_definitions["bindings"] as Dictionary)[task["id"]]["entity"]
		})
	return {
		"ok": true, "schema": RUNTIME_SCHEMA, "level_id": _definitions["level_id"],
		"tasks": out, "required_completed": required_done,
		"required_total": 4, "optional_completed": _completed.has(str(_tasks[3]["id"])),
		"lore_collected": _lore_claimed, "lore_id": str(_collectible.get("id", "")),
		"mission_verified": mission.verified(),
		"mission_completed": not mission.results().is_empty(),
		"host_revision": host.revision,
		"not_certified": "NO_PHYSICAL_PLAYABILITY_OR_REWARD_PROMOTION"
	}


func authoritative_state() -> Dictionary:
	return host.authoritative_state().duplicate(true) if _ready else {}


func state_hash() -> String:
	if not _ready:
		return ""
	return host.state_hash()


func completed() -> bool:
	return _ready and not mission.results().is_empty()
