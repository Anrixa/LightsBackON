extends Node3D
## EXP03: opt-in, unsaved first-person expedition stage for source engineering.
## Every interaction uses the existing SessionHost and REAL Grid/Repair/Mission
## services through ExpeditionHostSession. This is NOT a release/playability
## certification: world geometry/route, UX, controller and GPU tests remain held.

const Atlas := preload("res://scripts/world/dispatch_atlas.gd")
const Plan := preload("res://scripts/world/expedition_layout_plan.gd")
const Graybox := preload("res://scripts/world/expedition_graybox.gd")
const Runtime := preload("res://scripts/gameplay/expedition_host_session.gd")
const PlayerController := preload("res://scripts/actors/first_person_controller.gd")
const TargetSelector := preload("res://scripts/interaction/target_selector.gd")
const Visibility := preload("res://scripts/interaction/interaction_visibility.gd")
const Interaction := preload("res://scripts/interaction/interaction_service.gd")
const Ledger := preload("res://scripts/progression/expedition_ledger.gd")
const SaveService := preload("res://scripts/persistence/save_service.gd")
const OfflinePersistence := preload("res://scripts/persistence/offline_persistence.gd")
const ContentHash := preload("res://scripts/network/content_hash.gd")

const MENU_PATH: String = "res://scenes/menu/main_menu.tscn"
const HOST_STEP_SECONDS: float = 0.1
const TOOL_IDS: Array[String] = ["meter", "screwdriver", "puller", "cutter", "crimper"]
const REACH_M: float = 2.30

@export var level_id: String = "LV_001"

var runtime: Runtime
var player: PlayerController
var world: Node3D
var _definitions: Dictionary = {}
var _sequence: int = 0
var _tick_accumulator: float = 0.0
var _selected_tool: int = 0
var _target: String = ""
var _task_label: Label
var _feedback: Label
var _target_label: Label
var _back: Button
var _loaded: bool = false
var _expedition_account: String = ""
var _expedition_saves: SaveService
var _expedition_profile: Dictionary = {}
var _reward_error: String = ""


func _ready() -> void:
	var requested: String = str(get_tree().get_meta("expedition_requested_level", level_id))
	get_tree().remove_meta("expedition_requested_level")
	_expedition_account = str(get_tree().get_meta("expedition_account_key", ""))
	get_tree().remove_meta("expedition_account_key")
	if _expedition_account != "":
		_expedition_saves = SaveService.new()
		_expedition_saves.configure(1, OfflinePersistence.SAVE_BUILD_ID,
			ContentHash.content_revision(), ContentHash.rules_revision())
		var loaded: Dictionary = Ledger.load_profile(_expedition_saves,
			_expedition_account, OfflinePersistence.runtime_root())
		if not loaded.get("ok", false):
			push_error("EXP04_PROFILE_HOLD_NO_OVERWRITE: " + str(loaded))
			return
		_expedition_profile = loaded["profile"]
		# A prior crash after inbox write but before profile commit is healed
		# before starting the next source-authoritative run.
		var recovered: Dictionary = Ledger.receive(_expedition_saves,
			_expedition_account, OfflinePersistence.runtime_root(), [], _utc_now())
		if not recovered.get("ok", false):
			push_error("EXP04_INBOX_HOLD_NO_OVERWRITE: " + str(recovered))
			return
		_expedition_profile = recovered["profile"]
	var catalog: Dictionary = Atlas.load_catalog()
	if not bool(Atlas.inspect(catalog).get("ok", false)):
		push_error("EXP03_ATLAS_INVALID")
		return
	var level: Dictionary = Atlas.find_level(catalog, requested)
	if level.is_empty():
		push_error("EXP03_UNKNOWN_LEVEL: " + requested)
		return
	var location: Dictionary = Atlas.find_location(catalog, str(level["location_id"]))
	var plan: Dictionary = Plan.make_plan(level, location)
	if not bool(plan.get("ok", false)):
		push_error("EXP03_LAYOUT_INVALID")
		return
	level_id = requested
	world = Graybox.build(plan)
	if world == null:
		push_error("EXP03_WORLD_FAILED")
		return
	world.name = "ExpeditionWorld"
	add_child(world)
	# The stage is not derived from any C01/C03/C04 scene and has no save
	# service. It cannot overwrite or migrate a completed campaign checkpoint.
	player = PlayerController.new()
	player.name = "Player"
	add_child(player)
	var start: Vector3 = (plan["stations"] as Array)[0]["position"]
	player.global_position = Vector3(start.x, 0.91, start.z + 1.70)
	runtime = Runtime.new()
	var result: Dictionary = runtime.start(
		level_id, Callable(self, "_host_position"), Callable(self, "_world_sight"),
		_expedition_account)
	if not bool(result.get("ok", false)):
		push_error("EXP03_HOST_START_FAILED: " + str(result))
		return
	_definitions = runtime.definition_snapshot()
	_add_host_targets()
	_build_overlay(level)
	# An original Compatibility scene with no extra lights or game-state
	# emissions. Authored graybox worksite visuals remain source-only.
	var light: DirectionalLight3D = DirectionalLight3D.new()
	light.name = "SourceHeadlessLight"
	light.rotation_degrees = Vector3(-42.0, -32.0, 0.0)
	light.light_energy = 0.85
	add_child(light)
	_loaded = true
	_refresh()
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _host_position(player_id: String) -> Vector3:
	return player.global_position if player != null and player_id == Runtime.PLAYER_ID else Vector3.INF


func _world_sight(origin: Vector3, target: Vector3, radius: float) -> bool:
	if player == null or world == null:
		return false
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	return Visibility.can_reach(space, origin, target, REACH_M, radius,
		[player.get_rid()] as Array[RID])


## Neutral, noncolliding 3D plates at the exact existing host-bound targets.
## Labels identify equipment, never the undiagnosed fault or power state.
func _add_host_targets() -> void:
	var group: Node3D = Node3D.new()
	group.name = "HostTargets"
	world.add_child(group)
	var names: Dictionary = {
		str(runtime.lore_state()["id"]): "LORE RELIC",
		"PANEL_WEST": "WEST METER", "SW_EAST": "EAST FEED",
		"R_WEST": "WEST WORKSITE", "PANEL_SPUR": "SPUR METER",
		"SW_GRID_SPUR": "GRID SPUR", "SW_WEST_SPUR": "WEST BYPASS",
		"SW_SIGN": "SIGN FEED", "ZONE_EXTRACT": "RETURN ZONE"
	}
	for id: String in _definitions["positions"]:
		var marker: Marker3D = Marker3D.new()
		marker.name = id
		marker.position = _definitions["positions"][id]
		marker.set_meta("host_entity", id)
		marker.set_meta("presentation_only", true)
		group.add_child(marker)
		if id != "ZONE_EXTRACT":
			var mesh: BoxMesh = BoxMesh.new()
			mesh.size = Vector3(0.32, 0.32, 0.32) if id.begins_with("FIND_") 				else Vector3(0.75, 0.43, 0.11)
			var plate: MeshInstance3D = MeshInstance3D.new()
			plate.name = "WorksitePlate"
			plate.mesh = mesh
			if id.begins_with("FIND_"):
				var material: StandardMaterial3D = StandardMaterial3D.new()
				material.albedo_color = Color("#EFC56B")
				material.metallic = 0.55
				material.roughness = 0.30
				plate.material_override = material
			marker.add_child(plate)
		var label: Label3D = Label3D.new()
		label.name = "WorksiteLabel"
		label.text = str(names.get(id, id))
		label.font_size = 44
		label.pixel_size = 0.006
		label.position = Vector3(0.0, 0.6, 0.0)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.modulate = Color("#E4EDF1")
		marker.add_child(label)


func _build_overlay(level: Dictionary) -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	layer.name = "ExpeditionUI"
	add_child(layer)
	var surface: MarginContainer = MarginContainer.new()
	surface.name = "ExpeditionTaskOverlay"
	surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side: String in ["left", "top", "right", "bottom"]:
		surface.add_theme_constant_override("margin_" + side, 18)
	layer.add_child(surface)
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	surface.add_child(box)
	var title: Label = Label.new()
	title.text = "%s  /  %s\nEXPERIMENTAL FIELD DISPATCH • NO PLAYABILITY CERTIFICATION" % [
		level_id, str(level["title"])]
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.add_theme_color_override("font_color", Color("#F3D396"))
	box.add_child(title)
	_task_label = Label.new()
	_task_label.name = "TaskStatuses"
	_task_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_task_label.add_theme_color_override("font_color", Color("#DAE9E9"))
	box.add_child(_task_label)
	_target_label = Label.new()
	_target_label.name = "TaskTarget"
	_target_label.add_theme_color_override("font_color", Color("#88E2E6"))
	box.add_child(_target_label)
	_feedback = Label.new()
	_feedback.name = "TaskFeedback"
	_feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_feedback.add_theme_color_override("font_color", Color("#F1D6B2"))
	box.add_child(_feedback)
	var controls: Label = Label.new()
	controls.text = "WASD move • mouse aim • E interact • 1–5 tools • Esc return to atlas\nStage 4: inspect optional archive, then pick up its lore relic. Unsafe WEST bypass is hazardous."
	controls.add_theme_color_override("font_color", Color("#D9E3EC"))
	controls.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(controls)
	_back = Button.new()
	_back.name = "ReturnToDispatchButton"
	_back.text = "Return to dispatch atlas (original C01 save unchanged)"
	_back.custom_minimum_size = Vector2(310.0, 45.0)
	_back.pressed.connect(_return_to_menu)
	box.add_child(_back)
	_back.mouse_filter = Control.MOUSE_FILTER_STOP
	_back.focus_mode = Control.FOCUS_NONE


func _return_to_menu() -> void:
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().set_meta("expedition_reopen_atlas", true)
	get_tree().change_scene_to_file(MENU_PATH)


func _physics_process(delta: float) -> void:
	if not _loaded:
		return
	_tick_accumulator += delta
	while _tick_accumulator >= HOST_STEP_SECONDS:
		_tick_accumulator -= HOST_STEP_SECONDS
		runtime.tick_host()
		_persist_rewards()
	var selected: String = _aim_target()
	if selected != _target:
		_target = selected
		_refresh()
	elif runtime.host.revision != int(get_meta("display_revision", -1)):
		_refresh()


func _aim_target() -> String:
	if player == null or player.camera == null:
		return ""
	var eye: Vector3 = player.camera.global_position
	var positions: Dictionary = _definitions["positions"]
	var candidates: Array[Dictionary] = []
	for id: String in positions:
		if id == "ZONE_EXTRACT":
			continue
		var target: Vector3 = positions[id]
		var radius: float = Runtime.SWITCH_RADIUS_M if id.begins_with("SW_") else Runtime.PANEL_RADIUS_M
		if _world_sight(eye, target, radius):
			candidates.append({"id": id, "position": target, "radius": radius})
	var aim: Vector3 = -player.camera.global_transform.basis.z
	var selected: String = TargetSelector.select(eye, aim, candidates, REACH_M, 6.0)
	if selected != "":
		return selected
	var zone: Vector3 = positions["ZONE_EXTRACT"]
	if Vector2(player.global_position.x - zone.x, player.global_position.z - zone.z).length() <= Runtime.EXTRACTION_RADIUS_M:
		return "ZONE_EXTRACT"
	return ""


func _send(kind: String, entity: String, payload: Dictionary = {}) -> Dictionary:
	_sequence += 1
	var envelope: Dictionary = {"session": runtime.session_id(), "seq": _sequence,
		"type": kind, "entity": entity, "payload": payload}
	var reply: Dictionary = runtime.receive(1, JSON.stringify(envelope).to_utf8_buffer())
	_persist_rewards()
	if _feedback != null:
		_feedback.text = ("%s: %s" % [kind, "ACCEPTED" if reply.get("ok", false) else
			str(reply.get("code", "DENIED"))])
	_refresh()
	return reply


func _next_repair() -> void:
	var state: String = runtime.interaction.repair_state("R_WEST")
	if state == "restored":
		_feedback.text = "West feeder repair already restored."
		return
	if runtime.interaction.lock_owner("R_WEST") != Runtime.PLAYER_ID:
		_send("request_lock", "R_WEST")
		return
	var index: int = Interaction.STATES.find(state)
	if index < 0 or index >= Interaction.STEPS.size():
		return
	var step: String = Interaction.STEPS[index]
	var definition: Dictionary = (_definitions["repairs"]["repairs"] as Array)[0]
	var required: String = str((definition["tools"] as Dictionary).get(step, ""))
	if required != "" and TOOL_IDS[_selected_tool] != required:
		_feedback.text = "Equip %s before the %s repair step." % [required, step]
		return
	_send("repair_step", "R_WEST", {"step": step})


func _activate_target() -> void:
	if _target == "":
		return
	match _target:
		"PANEL_WEST", "PANEL_SPUR":
			_send("inspect", _target)
		"R_WEST":
			_next_repair()
		"ZONE_EXTRACT":
			_send("request_extract", _target, {"action": "start"})
		_:
			if _target.begins_with("FIND_"):
				_send("collect_lore", _target)
				return
			if _target.begins_with("SW_"):
				var mapping: Dictionary = {
					"SW_EAST": "E_GRID_EAST",
					"SW_GRID_SPUR": "E_GRID_SPUR",
					"SW_WEST_SPUR": "E_WEST_SPUR",
					"SW_SIGN": "SIGN"
				}
				if not mapping.has(_target):
					return
				var grid_state: Dictionary = runtime.grid.canonical_state()
				var source: Dictionary = grid_state["nodes"]["SIGN"] if _target == "SW_SIGN" else \
					grid_state["edges"][mapping[_target]]
				_send("toggle_switch", _target, {"value": not bool(source["enabled"])})


func _select_tool(index: int) -> void:
	if index < 0 or index >= TOOL_IDS.size():
		return
	_selected_tool = index
	player.set_equipped_tool(TOOL_IDS[index])
	_send("equip", "", {"tool": TOOL_IDS[index]})


func _unhandled_input(event: InputEvent) -> void:
	if not _loaded or not event.is_pressed() or event.is_echo():
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
		_return_to_menu()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("interact") or event.is_action_pressed("tool_primary"):
		_activate_target()
		get_viewport().set_input_as_handled()
		return
	for i: int in range(TOOL_IDS.size()):
		if event.is_action_pressed("tool_slot_" + str(i + 1)):
			_select_tool(i)
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("tool_next"):
		_select_tool(wrapi(_selected_tool + 1, 0, TOOL_IDS.size()))
	if event.is_action_pressed("tool_prev"):
		_select_tool(wrapi(_selected_tool - 1, 0, TOOL_IDS.size()))


## Save the pending server receipts before acknowledging. A failed profile
## write retains the host queue for another attempt; no old file is reset.
func _persist_rewards() -> void:
	if _expedition_account == "" or _expedition_saves == null or runtime == null:
		return
	var pending: Array[Dictionary] = runtime.pending_rewards(_expedition_account)
	if pending.is_empty():
		return
	var result: Dictionary = Ledger.receive(_expedition_saves,
		_expedition_account, OfflinePersistence.runtime_root(), pending, _utc_now())
	if not result.get("ok", false):
		_reward_error = str(result.get("code", "UNKNOWN_SAVE_ERROR"))
		return
	_reward_error = ""
	_expedition_profile = result["profile"]
	for key: String in result["acks"]:
		runtime.ack_reward(_expedition_account, key)


func _utc_now() -> String:
	return Time.get_datetime_string_from_system(true) + "Z"


func _refresh() -> void:
	if not _loaded or _task_label == null:
		return
	var board: Dictionary = runtime.task_board()
	var lines: Array[String] = []
	for task: Dictionary in board["tasks"]:
		var icon: String = "DONE" if task["completed"] else "OPTIONAL" if not task["required"] else "PENDING"
		lines.append("[%s] %s — %s" % [icon, str(task["id"]), str(task["title"])])
	lines.append("Mandatory %d/4 • Optional %s • Grid verified: %s • Mission complete: %s" % [
		int(board["required_completed"]), str(board["optional_completed"]),
		str(board["mission_verified"]), str(board["mission_completed"])])
	lines.append("LORE %s  •  %s" % [
		"COLLECTED" if board["lore_collected"] else "AVAILABLE AFTER DISCOVERY",
		str(board["lore_id"])])
	if _expedition_account != "":
		lines.append("FIELD POINTS: %d / %d  •  Archived lore: %d / %d" % [
			int(_expedition_profile.get("field_points", 0)), Ledger.MAX_FIELD_POINTS,
			(_expedition_profile.get("lore_finds", {}) as Dictionary).size(), Ledger.MAX_FINDS])
	else:
		lines.append("Field progression unavailable: existing local identity not ready")
	if _reward_error != "":
		lines.append("EXP04 SAVE HOLD: " + _reward_error)
	_task_label.text = "\n".join(lines)
	if _target_label != null:
		_target_label.text = "Target: %s  /  tool: %s  /  host revision: %d" % [
			_target if _target != "" else "(aim at numbered station)",
			TOOL_IDS[_selected_tool], int(board["host_revision"])]
	set_meta("display_revision", int(board["host_revision"]))
