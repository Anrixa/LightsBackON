extends RefCounted
## Production offline C01 adapter: one host-local participant sends the same command bytes
## as a remote client would. No test fixtures, Steam dependency or client-side grid edits.
##
## Authoritative grid/repair/equipment/mission logic stays in the existing services.
## The scene owns movement, target picking, camera presentation and local preferences.

signal changed
signal action_replied(envelope: Dictionary, reply: Dictionary)
signal mission_event(event: Dictionary)

const PowerGrid := preload("res://scripts/simulation/power_grid.gd")
const MeterModel := preload("res://scripts/simulation/meter_model.gd")
const Interaction := preload("res://scripts/interaction/interaction_service.gd")
const Equipment := preload("res://scripts/interaction/equipment_service.gd")
const MissionDirector := preload("res://scripts/simulation/mission_director.gd")
const SessionHost := preload("res://scripts/network/session_host.gd")
const Comms := preload("res://scripts/network/comms_service.gd")
const IntentOutbox := preload("res://scripts/ui/intent_outbox.gd")
const HudPresenter := preload("res://scripts/ui/hud_presenter.gd")
const TabletPresenter := preload("res://scripts/ui/tablet_presenter.gd")
const UiText := preload("res://scripts/ui/ui_text.gd")

const CONTRACT: String = "res://content/contracts/c01_alder_street"
const SESSION_ID: String = "S_C01_LOCAL"
const CONTENT_REVISION: String = "C01_LOCAL_DEVELOPMENT"
const PLAYER_ID: String = "P1"
const PEER_ID: int = SessionHost.HOST_PEER
const PROTOCOL_VERSION: int = 1
const PUMP_ROUTE: String = "E_TEMP_PUMP"
const GENERATOR: String = "GEN_PORTABLE"
const PUMP_LATCH: String = "LATCH_PUMP_DRAIN"
const TOOL_LIST: Array[String] = ["meter", "screwdriver", "puller", "cutter", "crimper"]

var grid: PowerGrid
var meter: MeterModel
var interaction: Interaction
var equipment: Equipment
var mission: MissionDirector
var host: SessionHost
var outbox: IntentOutbox
var _content: Dictionary = {}
var _markers: Dictionary = {}
var _repairs_by_panel: Dictionary = {}
var _tuning: Dictionary = {}
var _solo_tuning: Dictionary = {}
var _tick: int = 0
var _last_zone_state: bool = false
var _position_of: Callable


static func _json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


## The caller supplies live host-side range and position checks from its physical character.
## Nothing in this module silently bypasses proximity merely because play is offline.
func setup(range_check: Callable, position_of: Callable) -> Array[Dictionary]:
	_position_of = position_of
	_content = {
		"grid": _json(CONTRACT.path_join("grid.json")),
		"meter": _json(CONTRACT.path_join("meter.json")),
		"repairs": _json(CONTRACT.path_join("repairs.json")),
		"equipment": _json(CONTRACT.path_join("equipment.json")),
		"switches": _json(CONTRACT.path_join("switches.json")),
		"mission": _json(CONTRACT.path_join("mission.json")),
		"tablet": _json(CONTRACT.path_join("tablet.json")),
		"world": _json("res://content/world/alder_street.json"),
		"comms": _json("res://content/comms.json")
	}
	_tuning = _json("res://content/interaction.json")
	_solo_tuning = _json("res://content/offline_solo.json")
	_markers.clear()
	_repairs_by_panel.clear()
	for record: Dictionary in _content["world"]["markers"]:
		_markers[str(record["id"])] = record
	for repair: Dictionary in _content["repairs"]["repairs"]:
		_repairs_by_panel[str(repair["panel"])] = repair

	var errors: Array[Dictionary] = []
	grid = PowerGrid.new()
	errors.append_array(grid.load_definition(_content["grid"]))
	if not errors.is_empty():
		return errors
	meter = MeterModel.new()
	errors.append_array(meter.load_definition(_content["meter"], grid))
	interaction = Interaction.new()
	errors.append_array(interaction.load_definition(_tuning, _content["repairs"], grid, meter))
	equipment = Equipment.new()
	errors.append_array(equipment.load_definition(_content["equipment"], grid, meter))
	mission = MissionDirector.new()
	errors.append_array(mission.load_definition(_content["mission"], grid, interaction, equipment))
	if not errors.is_empty():
		return errors

	host = SessionHost.new()
	errors.append_array(host.configure(_json("res://content/network.json"), PROTOCOL_VERSION, CONTENT_REVISION,
		SESSION_ID, grid, meter, interaction, equipment, _content["switches"], range_check))
	if not errors.is_empty():
		return errors
	host.set_position_provider(position_of)
	host.set_mission(mission)
	var comms: Comms = Comms.new()
	errors.append_array(comms.load_definition(_content["comms"]))
	if not errors.is_empty():
		return errors
	host.set_comms(comms)
	var admitted: Dictionary = host.admit(PEER_ID, PLAYER_ID, PROTOCOL_VERSION, CONTENT_REVISION, TOOL_LIST)
	if not admitted.get("ok", false):
		errors.append({"code": "OFFLINE_ADMISSION_FAILED", "message": str(admitted)})
		return errors
	outbox = IntentOutbox.new(SESSION_ID, func(bytes: PackedByteArray) -> Dictionary: return host.receive(PEER_ID, bytes))
	outbox.replied.connect(_on_reply)
	return errors


func command(kind: String, entity: String, payload: Dictionary = {}) -> Dictionary:
	if outbox == null:
		return {"ok": false, "code": "SESSION_NOT_READY"}
	return outbox.send(kind, entity, payload)


func set_tool(tool: String) -> Dictionary:
	if not TOOL_LIST.has(tool):
		return {"ok": false, "code": "UNKNOWN_TOOL"}
	return command("equip", "", {"tool": tool})


## Each call represents one of the 10 Hz authoritative ticks, independent of render FPS.
func tick_once() -> Array[Dictionary]:
	_tick += 1
	var events: Array[Dictionary] = host.tick(_tick)
	for event: Dictionary in events:
		mission_event.emit(event)
	if not events.is_empty():
		changed.emit()
	return events


func set_in_van_zone(inside: bool) -> void:
	if inside == _last_zone_state:
		return
	_last_zone_state = inside
	for event: Dictionary in host.set_in_zone(PLAYER_ID, "ZONE_VAN", inside):
		mission_event.emit(event)
	changed.emit()


func in_van_zone() -> bool:
	return _last_zone_state


func extraction_action() -> Dictionary:
	var state: Dictionary = mission.canonical_state()
	return {"kind": "request_extract", "entity": "ZONE_VAN",
		"payload": {"action": "cancel" if int(state["countdown_left"]) >= 0 else "start"}}


func completed() -> bool:
	return mission.is_complete()


func host_state() -> Dictionary:
	return host.authoritative_state()


func hud_view(selected_slot: int, target: String, tool: String) -> Dictionary:
	var context: Dictionary = {
		"local_player": PLAYER_ID, "names": {PLAYER_ID: "You"}, "tools": TOOL_LIST,
		"selected_slot": selected_slot,
		"district_key": "district.alder_street", "contract_key": "contract.c01",
		"repairs": _content["repairs"], "equipment": _content["equipment"],
		"prompt": prompt_for(target, tool)
	}
	return HudPresenter.build(host_state(), mission.objectives(), context)


func tablet_view() -> Dictionary:
	var readings: Dictionary = {}
	var findings: Dictionary = {}
	for panel: Dictionary in _content["meter"]["panels"]:
		var pid: String = str(panel["id"])
		readings[pid] = meter.readings(pid, grid)
		findings[pid] = meter.findings(pid, grid)
	return TabletPresenter.build({
		"grid": _content["grid"], "tablet": _content["tablet"], "meter": _content["meter"],
		"repairs": _content["repairs"], "grid_source": _content["mission"]["grid_source"]
	}, {"grid": grid.canonical_state(), "readings": readings, "findings": findings,
		"repairs": interaction.canonical_state(), "names": {PLAYER_ID: "You"}})


func interact(target: String, tool: String) -> Dictionary:
	var plan: Dictionary = action_for(target, tool)
	if plan.is_empty():
		return {"ok": false, "code": "NO_ACTION"}
	if plan.has("blocked"):
		return {"ok": false, "code": "SELECT_TOOL", "message": str(plan["blocked"])}
	return command(str(plan["kind"]), str(plan["entity"]), plan["payload"])


## UI prompts and clicks share a single deterministic action plan; decisions involving
## fault diagnosis still belong to the actual measured meter state and host validation.
func action_for(target: String, tool: String) -> Dictionary:
	if target == "ZONE_VAN":
		return extraction_action()
	if _repairs_by_panel.has(target):
		var repair: Dictionary = _repairs_by_panel[target]
		var state: String = interaction.repair_state(str(repair["id"]))
		if state == "restored":
			return {"kind": "inspect", "entity": target, "payload": {}}
		if not meter.readings(target, grid)["_panel"].has("tick"):
			if tool != "meter":
				return {"blocked": UiText.t("offline.select_meter")}
			return {"kind": "inspect", "entity": target, "payload": {}}
		if interaction.lock_owner(str(repair["id"])) != PLAYER_ID:
			return {"kind": "request_lock", "entity": str(repair["id"]), "payload": {}}
		var state_index: int = Interaction.STATES.find(state)
		if state_index < 0 or state_index >= Interaction.STEPS.size():
			return {}
		var step: String = Interaction.STEPS[state_index]
		var required: String = str((repair["tools"] as Dictionary).get(step, ""))
		if required != "" and required != tool:
			return {"blocked": UiText.tf("offline.select_tool", [UiText.t("tool." + required)])}
		return {"kind": "repair_step", "entity": str(repair["id"]), "payload": {"step": step}}
	if target == GENERATOR:
		return _generator_action()
	if target == "VAN_BAY" or target == "PAD_PUMP" or target == "STORE_PUMP_HOUSE":
		if equipment.carrier_of(GENERATOR) == PLAYER_ID:
			return {"kind": "place_item", "entity": GENERATOR, "payload": {"action": "place", "anchor": target}}
		return {}
	if target.begins_with("SW_"):
		for sw: Dictionary in _content["switches"]["switches"]:
			if str(sw["id"]) == target:
				var node: Dictionary = grid.canonical_state()["nodes"][str(sw["target"])]
				return {"kind": "toggle_switch", "entity": target,
					"payload": {"value": not bool(node[str(sw["field"])])}}
	return {}


func prompt_for(target: String, tool: String) -> Dictionary:
	if target == "":
		return {}
	var plan: Dictionary = action_for(target, tool)
	if plan.is_empty():
		return {}
	var object_key: String = "offline.object.unknown"
	var verb_key: String = "offline.verb.interact"
	var detail: String = ""
	if target == "ZONE_VAN":
		object_key = "offline.object.van"
		verb_key = "offline.verb.depart"
	elif _repairs_by_panel.has(target):
		var record: Dictionary = _repairs_by_panel[target]
		object_key = str(record["name_key"])
		var state: String = interaction.repair_state(str(record["id"]))
		detail = UiText.t("status.repair." + state)
		verb_key = "offline.verb.repair"
		if str(plan.get("kind", "")) == "inspect":
			verb_key = "offline.verb.measure"
		elif str(plan.get("kind", "")) == "request_lock":
			verb_key = "offline.verb.lock"
	elif target == GENERATOR:
		object_key = "equipment.generator"
		verb_key = "offline.verb." + str((plan.get("payload", {}) as Dictionary).get("action", "interact"))
	elif target.begins_with("SW_"):
		object_key = "offline.object.switch"
		verb_key = "offline.verb.switch"
	else:
		object_key = "offline.object.pad"
		verb_key = "offline.verb.place"
	if plan.has("blocked"):
		detail = str(plan["blocked"])
	return {"object_key": object_key, "action": "interact", "verb_key": verb_key,
		"detail_text": detail}


func _generator_action() -> Dictionary:
	var equipment_state: Dictionary = equipment.canonical_state()["items"][GENERATOR]
	var anchor: String = str(equipment_state["anchor"])
	if equipment.carrier_of(GENERATOR) != "":
		return {}
	var action: String = ""
	var payload: Dictionary = {}
	if anchor == "VAN_BAY" or anchor == "STORE_PUMP_HOUSE":
		action = "pickup"
	elif anchor == "PAD_PUMP":
		var grid_state: Dictionary = grid.canonical_state()
		var online: bool = bool(grid_state["nodes"]["GEN"]["online"])
		var connected: bool = bool(grid_state["edges"][PUMP_ROUTE]["enabled"])
		if online:
			action = "stop"
		elif connected and mission.is_latched(PUMP_LATCH):
			action = "disconnect"
			payload["route"] = PUMP_ROUTE
		elif connected:
			action = "start"
		elif mission.is_latched(PUMP_LATCH):
			action = "pickup"
		else:
			action = "connect"
			payload["route"] = PUMP_ROUTE
	if action == "":
		return {}
	payload["action"] = action
	return {"kind": "place_item", "entity": GENERATOR, "payload": payload}


## Returns only potentially interactable scene IDs. Equipment uses its authoritative
## anchor, never a hard-coded visual duplicate at the starting van.
func repair_definitions() -> Array:
	return (_content["repairs"]["repairs"] as Array).duplicate(true)


func targets() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id: String in _markers:
		var marker: Dictionary = _markers[id]
		var kind: String = str(marker["kind"])
		if kind == "panel" and not _repairs_by_panel.has(id):
			continue
		if kind == "anchor" and equipment.carrier_of(GENERATOR) != PLAYER_ID:
			continue
		if not ["panel", "switch", "anchor"].has(kind):
			continue
		out.append({"id": id, "position": entity_position(id), "radius": _radius(kind)})
	if equipment.carrier_of(GENERATOR) == "":
		out.append({"id": GENERATOR, "position": entity_position(GENERATOR),
			"radius": _radius("equipment")})
	return out


func entity_position(entity: String) -> Vector3:
	var marker_id: String = entity
	if _repairs_by_panel.has(entity):
		marker_id = entity
	elif entity.begins_with("R_"):
		for repair: Dictionary in _content["repairs"]["repairs"]:
			if str(repair["id"]) == entity:
				marker_id = str(repair["panel"])
				break
	elif entity == GENERATOR:
		var anchor: String = equipment.anchor_of(GENERATOR)
		if anchor == "":
			var cm: Vector3i = _position_of.call(PLAYER_ID)
			return Vector3(cm) / 100.0
		marker_id = anchor
	if not _markers.has(marker_id):
		return Vector3.INF
	var coords: Array = (_markers[marker_id] as Dictionary)["pos_cm"]
	return Vector3(float(coords[0]), float(coords[1]), float(coords[2])) / 100.0


func _radius(kind: String) -> float:
	return float((_solo_tuning["selection_radius_cm"] as Dictionary).get(kind, 45)) / 100.0


func inside_van(position: Vector3) -> bool:
	var zones: Array = _content["world"]["zones"]
	for zone: Dictionary in zones:
		if str(zone["id"]) != "ZONE_VAN":
			continue
		var min_cm: Array = zone["min_cm"]
		var size_cm: Array = zone["size_cm"]
		return position.x >= float(min_cm[0]) / 100.0 and position.x <= float(min_cm[0] + size_cm[0]) / 100.0 \
			and position.z >= float(min_cm[2]) / 100.0 and position.z <= float(min_cm[2] + size_cm[2]) / 100.0
	return false


func _on_reply(envelope: Dictionary, reply: Dictionary) -> void:
	action_replied.emit(envelope, reply)
	if reply.get("ok", false):
		for event: Dictionary in reply.get("events", []):
			mission_event.emit(event)
		changed.emit()
