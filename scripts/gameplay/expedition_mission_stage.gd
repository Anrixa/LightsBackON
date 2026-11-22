extends Node3D
## EXP03: opt-in, unsaved first-person expedition stage for source engineering.
## Every interaction uses the existing SessionHost and REAL Grid/Repair/Mission
## services through ExpeditionHostSession. This is NOT a release/playability
## certification: world geometry/route, UX, controller and GPU tests remain held.

const Atlas := preload("res://scripts/world/dispatch_atlas.gd")
const Plan := preload("res://scripts/world/expedition_layout_plan.gd")
const Graybox := preload("res://scripts/world/expedition_graybox.gd")
const SiteComposition := preload("res://scripts/world/expedition_site_composition.gd")
const EnvironmentFeedback := preload("res://scripts/world/expedition_environment_feedback.gd")
const ApproachView := preload("res://scripts/world/expedition_approach_view.gd")
const Runtime := preload("res://scripts/gameplay/expedition_host_session.gd")
const PlayerController := preload("res://scripts/actors/first_person_controller.gd")
const TargetSelector := preload("res://scripts/interaction/target_selector.gd")
const Visibility := preload("res://scripts/interaction/interaction_visibility.gd")
const Interaction := preload("res://scripts/interaction/interaction_service.gd")
const Ledger := preload("res://scripts/progression/expedition_ledger.gd")
const Campaign := preload("res://scripts/progression/expedition_campaign.gd")
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
var _hazard_marker: MeshInstance3D
var _site_composition: Node3D
var _environmental_feedback: Node3D
var _approach_view: Node3D
var _approach_choice: String = "guarded"
var _outcome_choice: String = "buffer"
var _hazard_choice: String = "engineered"
var _puzzle_path: String = "forensic"
var _puzzle_option: int = 0
var _fault_route: String = "isolate"
var _consequence_choice: String = "isolate"
var _logistics_route: String = "direct"
var _logistics_job: String = "a"
var _worksite_route: String = "priority"
var _worksite_method: String = "precision"


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
	# This is a presentation-side early check, followed by the independent
	# host-side EXP05 gate in Runtime.start(). No C01 checkpoint is touched.
	if _expedition_account != "":
		var access: Dictionary = Campaign.can_launch(_expedition_profile, catalog,
			Campaign.load_routes(), requested)
		if not bool(access.get("ok", false)):
			push_error("EXP05_LEVEL_GATE_HOLD: " + str(access))
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
		_expedition_account, _expedition_account != "", "", true, true, true, true, true, true, true, true, true, true, true, true, true, true)
	if not bool(result.get("ok", false)):
		push_error("EXP03_HOST_START_FAILED: " + str(result))
		return
	_definitions = runtime.definition_snapshot()
	_add_host_targets()
	_add_site_composition(plan)
	_add_hazard_marker()
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
	if runtime.devices != null:
		for device: Dictionary in (_definitions["devices"] as Dictionary)["nodes"]:
			names[str(device["id"])] = str(device["action"]).replace("_", " ").to_upper()
	if runtime.faults != null:
		var fault: Dictionary = runtime.faults.definition_snapshot()
		names[str(fault["probe_a"])] = "DIAGNOSTIC PROBE A"
		names[str(fault["probe_b"])] = "DIAGNOSTIC PROBE B"
		names[str(fault["console"])] = "FAULT CONTROL CONSOLE"
	if runtime.consequences != null:
		var chain: Dictionary = runtime.consequences.definition_snapshot()
		for node: Dictionary in chain["nodes"]:
			names[str(node["id"])] = str(node["service"]).to_upper()
		names[str(chain["console"])] = "CASCADE CERTIFICATION CONSOLE"
	if runtime.logistics != null:
		var manifest: Dictionary = runtime.logistics.definition_snapshot()
		names[str(manifest["depot"])] = "EMERGENCY SUPPLY DEPOT"
		names[str(manifest["console"])] = "LOGISTICS CERTIFICATION"
		for job: Dictionary in manifest["jobs"]:
			names[str(job["id"])] = str(job["cargo"]).to_upper()
	if runtime.balancing != null:
		var load_board: Dictionary = runtime.balancing.definition_snapshot()
		names[str(load_board["board"])] = "CRITICAL LOAD CONTROL BOARD"
		names[str(load_board["console"])] = "SERVICE BALANCE CERTIFICATION"
		for service: Dictionary in load_board["services"]:
			names[str(service["id"])] = str(service["name"]).to_upper()
	if runtime.worksite != null:
		var order: Dictionary = runtime.worksite.definition_snapshot()
		names[str(order["board"])] = "WORKSITE REVIEW BOARD"
		names[str(order["decision"])] = "WORKSITE OPERATING STRATEGY"
		names[str(order["console"])] = "FINAL WORK ORDER CERTIFICATION"
		names[str(order["optional_target"])] = "OPTIONAL FIELD DISCOVERY"
		for checkpoint: Dictionary in order["checkpoints"]:
			names[str(checkpoint["id"])] = "REVIEW: " + str(checkpoint["title"]).to_upper()
	if runtime.site_a02 != null or runtime.site_exp013 != null:
		var active_site: Variant = runtime.site_exp013 if runtime.site_exp013 != null else runtime.site_a02
		var authored: Dictionary = active_site.definition_snapshot()
		names[str(authored["targets"]["A"])] = "SITE EVIDENCE / " + str(authored["title"]).to_upper()
		names[str(authored["targets"]["B"])] = "SITE ISOLATION / " + str(authored["title"]).to_upper()
		names[str(authored["targets"]["C"])] = "SITE HANDOFF / RECOVERY"
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


## EXP014: build only a non-colliding, source-bound field presentation.
## Validation uses the same host positions and inspected route definitions;
## this layer cannot register network entities or change host authority.
func _add_site_composition(plan: Dictionary) -> void:
	var active: Variant = runtime.site_exp013 if runtime.site_exp013 != null else runtime.site_a02
	if active == null:
		return
	var case_source: Dictionary = active.definition_snapshot()
	var positions: Dictionary = _definitions["positions"]
	var checked: Dictionary = SiteComposition.inspect(case_source, positions)
	if not bool(checked.get("ok", false)):
		push_error("EXP014_SOURCE_COMPOSITION_HOLD: " + str(checked))
		return
	_site_composition = SiteComposition.build(case_source, positions)
	if _site_composition != null:
		world.add_child(_site_composition)
	# EXP014 A04 is visual evidence only, tied to the same already-authored
	# plan, site source, immutable task IDs and A03 region package.
	var regional: Node3D = world.get_node_or_null("EXP014_A03_RegionalFacilities") as Node3D
	if regional != null:
		_environmental_feedback = EnvironmentFeedback.attach(plan, case_source, regional)
		if _environmental_feedback == null:
			push_error("EXP014_A04_ENVIRONMENT_SOURCE_HOLD")
	# Source-anchored approach ribbons represent the available entry options
	# but never register physical navigation or new interaction targets.
	if runtime.site_approach != null:
		_approach_view = ApproachView.build(plan, case_source, positions)
		if _approach_view == null:
			push_error("EXP014_A05_APPROACH_SOURCE_HOLD")
		else:
			world.add_child(_approach_view)


## A visible diagnostic marker, not a damage collider or tested path blocker.
## Host timing and permission checks remain authoritative independently.
func _add_hazard_marker() -> void:
	if runtime.bespoke == null:
		return
	var marker: MeshInstance3D = MeshInstance3D.new()
	marker.name = "EXP06HazardNotice"
	var surface: CylinderMesh = CylinderMesh.new()
	surface.top_radius = 1.8
	surface.bottom_radius = 1.8
	surface.height = 0.045
	marker.mesh = surface
	var paint: StandardMaterial3D = StandardMaterial3D.new()
	paint.albedo_color = Color("#D89032")
	paint.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	paint.albedo_color.a = 0.54
	paint.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	marker.material_override = paint
	var worksite: Vector3 = _definitions["positions"]["R_WEST"]
	marker.position = Vector3(worksite.x, 0.045, worksite.z)
	world.add_child(marker)
	_hazard_marker = marker
	marker.visible = false


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
	controls.text = "WASD move • mouse aim • E interact / EXP011 energize or shed • R EXP08 route • T EXP009 response • U EXP010 direct/relay • Y EXP010 shipment A/B • K recall depot shipment • 1–5 tools • V EXP012 route • B EXP012 method • Esc atlas\nEXP06–EXP009: Complete equipment, stability and service recovery. EXP010: Open depot manifest, allocate one direct and one relay shipment from finite stocks, wait for host transit, receive each cargo, certify the logistics board. Unsafe supply pauses transit and reopens completed deliveries for recheck. EXP011: Open load board, allocate no more than 6 PU, stabilize each service through host ticks, shed and latch, then certify. EXP012: Open review board after live EXP011 certification; select priority/resilience route at strategy marker; complete source-linked checkpoint reviews using precise or finite-cell rapid sampling, then certify. Supply loss requires rechecks. Source/headless only; physical playability remains held."
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
		if runtime.bespoke != null:
			if _hazard_marker != null:
				_hazard_marker.visible = runtime.bespoke.hazard_active()
			_refresh()
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


## Select only source-defined actions for the opt-in host contingency.
## The player never sends a progress counter, host tick or success verdict.
func _activate_contingency_target() -> void:
	var state: Dictionary = runtime.site_contingency.snapshot()
	if str(state["fault"]) != "":
		if _target == str(state["recovery_target"]):
			_send("operate_worksite", _target, {"action": "recover"})
		return
	if bool(state["solved"]):
		return
	var next: Dictionary = state["next"]
	if next.is_empty():
		return
	var mode: String = str(next["mode"])
	var phase: String = str(state["phase"])
	var progress: int = int(state["progress"])
	var action: String = ""
	if phase == "ready" and _target == str(next["target"]):
		action = str(next["action"])
	elif phase == "stable":
		var guard: String = str(next["guard"])
		var guard_progress: int = int(state["guard_progress"])
		var proof_station: String = str(next["support"]) if guard == "supplies_ready" else \
			str(next["witness"]) if guard == "cascade_stable" else str(next["target"])
		var proof_action: String = "stock_check" if guard == "supplies_ready" else \
			"relay_ping" if guard == "cascade_stable" else "clearance_probe"
		if progress == 0 and guard != "load_balanced" and guard_progress == 0:
			if _target == proof_station:
				action = proof_action
		elif progress == 0 and _target == str(next["support"]):
			var ready_tick: int = int(state["start_tick"]) + int(next["dwell_ticks"]) + 3
			var proof_ready: bool = guard == "load_balanced" and int(state["tick"]) >= ready_tick
			proof_ready = proof_ready or (guard != "load_balanced" and \
				int(state["tick"]) - int(state["guard_tick"]) >= 3)
			if proof_ready:
				action = "read" if mode == "quorum" else \
					"arm" if mode == "reserve_lease" else "isolate"
		elif progress == 1 and _target == str(next["witness"]):
			action = "attest" if mode == "quorum" else \
				"transfer" if mode == "reserve_lease" else "verify"
		elif progress == 2 and _target == str(next["target"]):
			action = "seal" if mode == "quorum" else \
				"release" if mode == "reserve_lease" else "close"
	if action != "":
		_send("operate_worksite", _target, {"action": action})
	elif _feedback != null:
		_feedback.text = "EXP014: %s / stage %d / go to %s then %s then %s." % [
			mode.to_upper(), progress, str(next["support"]),
			str(next["witness"]), str(next["target"])]


## All A05 commands reuse host-registered SC targets. The UI only
## chooses an action; source validation and the decision belong to the host.
func _activate_approach_target() -> void:
	if runtime.site_approach == null:
		return
	var state: Dictionary = runtime.site_approach.snapshot()
	var action: String = ""
	if str(state["fault"]) != "":
		if _target == str(state["recovery_target"]):
			action = "recover"
	else:
		var next: Dictionary = state["next"]
		if _target == str(next.get("target", "")):
			if str(state["phase"]) == "arrival":
				action = "approach_" + _approach_choice
			elif str(state["phase"]) == "decision":
				action = "commit_" + _worksite_route
			else:
				action = str(next.get("action", ""))
	if action != "":
		_send("operate_worksite", _target, {"action": action})
	elif _feedback != null:
		_feedback.text = "EXP014 A05: host requests %s at %s; evidence %d/%d." % [
			str((state["next"] as Dictionary).get("action", "recover")),
			str((state["next"] as Dictionary).get("target", state["recovery_target"])),
			int(state["step"]), int(state["total_steps"])]


## A06 choices only describe an intent. The host decides whether the
## authenticated SC target and actual restoration evidence permit progress.
func _activate_outcome_target() -> void:
	if runtime.site_outcomes == null:
		return
	var state: Dictionary = runtime.site_outcomes.snapshot()
	var next: Dictionary = state["next"]
	if next.is_empty():
		return
	if _target != str(next.get("target", "")):
		if _feedback != null:
			_feedback.text = "A06 host requests " + str(next.get("target", ""))
		return
	var action: String = str(next.get("action", ""))
	if str(state["phase"]) == "plan" and _outcome_choice == "managed":
		action = str(next.get("alternative", ""))
	_send("operate_worksite", _target, {"action": action})


## A07 uses only existing SC targets; hazard progress and time originate
## from the host. J changes the requested control, not the authoritative result.
func _activate_hazard_target() -> void:
	if runtime.site_hazards == null:
		return
	var state: Dictionary = runtime.site_hazards.snapshot()
	var next: Dictionary = state["next"]
	if next.is_empty():
		return
	if _target != str(next.get("target", "")):
		if _feedback != null:
			_feedback.text = "A07 HOST REQUEST: " + str(next.get("target", ""))
		return
	var action: String = str(next.get("action", ""))
	if str(state["phase"]) == "choice" and _hazard_choice == "temporary":
		action = str(next.get("alternative", ""))
	_send("operate_worksite", _target, {"action": action})


## A08 offers real parallel evidence choices. The host derives the available
## DAG frontier; O cycles possible steps and P chooses the investigation path.
func _activate_puzzle_target() -> void:
	if runtime.site_puzzles == null:
		return
	var state: Dictionary = runtime.site_puzzles.snapshot()
	var action: String = ""
	if str(state["phase"]) == "fault":
		if _target == str(state["recovery_target"]):
			action = "recover"
	elif str(state["phase"]) == "choose":
		for item: Dictionary in state["choices"]:
			if str(item["mode"]) == _puzzle_path and _target == str(item["target"]):
				action = str(item["action"])
				break
	elif str(state["phase"]) == "running":
		var options: Array = state["available"]
		if not options.is_empty():
			_puzzle_option = posmod(_puzzle_option, options.size())
			var option: Dictionary = options[_puzzle_option]
			if _target == str(option["target"]):
				action = str(option["action"])
	if action != "":
		_send("operate_worksite", _target, {"action": action})
		_puzzle_option = 0
	elif _feedback != null:
		_feedback.text = "A08: follow host evidence frontier; P path / O next proof."


func _activate_target() -> void:
	if _target == "":
		return
	if _target.begins_with("SC_") and (runtime.site_a02 != null or runtime.site_exp013 != null):
		if runtime.site_approach != null and not runtime.site_approach.solved():
			_activate_approach_target()
			return
		if runtime.site_outcomes != null and not runtime.site_outcomes.prepared():
			_activate_outcome_target()
			return
		if runtime.site_hazards != null and runtime.site_hazards.needs_action():
			_activate_hazard_target()
			return
		if runtime.site_puzzles != null and runtime.site_puzzles.needs_action():
			_activate_puzzle_target()
			return
		if runtime.site_outcomes != null and runtime.site_outcomes.needs_action():
			_activate_outcome_target()
			return
		var active_site: Variant = runtime.site_exp013 if runtime.site_exp013 != null else runtime.site_a02
		# EXP014 is a post-intervention layer. Reuse the same physical host
		# station IDs and authenticated worksite ingress, never a new RPC.
		if runtime.site_contingency != null and active_site.solved():
			_activate_contingency_target()
			return
		var case_state: Dictionary = active_site.snapshot()
		var next: Dictionary = case_state["next"]
		if str(case_state["fault"]) != "":
			if _target == str(case_state["recovery_target"]):
				_send("operate_worksite", _target, {"action": "recover"})
		elif not bool(case_state["solved"]) and not next.is_empty():
			var start_target: String = str(next["target"])
			var helper: String = str(next["support_target"])
			var phase: String = str(case_state["phase"])
			var mode: String = str(next["mode"])
			var count: int = int(case_state["support_count"])
			var action: String = ""
			if phase == "ready" and _target == start_target:
				action = str(next["action"])
			elif phase == "stable":
				if mode == "hold" and _target == start_target:
					action = "confirm"
				elif mode == "pulse" and _target == start_target:
					action = "pulse"
				elif mode == "sample":
					if _target == helper and count < 2:
						action = "read"
					elif _target == start_target and count == 2:
						action = "confirm"
				elif mode == "handoff":
					if _target == helper and count == 0:
						action = "transfer"
					elif _target == start_target and count == 1:
						action = "commit"
				elif mode == "balance":
					if _target == helper and count == 0:
						action = "trim"
					elif _target == start_target and count == 1:
						action = "confirm"
			if action != "":
				_send("operate_worksite", _target, {"action": action})
			elif _feedback != null:
				_feedback.text = "Authored site: Follow host procedure %s at %s, then %s (%s)." % [
					str(next["action"]), start_target, helper, phase]
		return
	if _target.begins_with("WO_") and runtime.worksite != null:
		var order: Dictionary = runtime.worksite.definition_snapshot()
		var state: Dictionary = runtime.worksite.snapshot()
		if _target == str(order["board"]):
			_send("operate_worksite", _target, {"action": "open"})
		elif _target == str(order["decision"]):
			_send("operate_worksite", _target, {"action": _worksite_route})
		elif _target == str(order["console"]):
			_send("operate_worksite", _target, {"action": "certify"})
		elif _target == str(order["optional_target"]):
			_send("operate_worksite", _target, {"action": "log"})
		elif (state["states"] as Dictionary).has(_target):
			var state_name: String = str(state["states"][_target]["status"])
			match state_name:
				"pending":
					_send("operate_worksite", _target, {"action": _worksite_method})
				"stable":
					_send("operate_worksite", _target, {"action": "confirm"})
				"recheck":
					_send("operate_worksite", _target, {"action": "recheck"})
				"warming":
					if _feedback != null:
						_feedback.text = "EXP012: Await host stability, then confirm this review."
				"latched":
					if _feedback != null:
						_feedback.text = "EXP012: This checkpoint is already signed off."
		return
	if _target.begins_with("LB_") and runtime.balancing != null:
		var board: Dictionary = runtime.balancing.definition_snapshot()
		var status: Dictionary = runtime.balancing.snapshot()
		if _target == str(board["board"]):
			_send("operate_balance", _target, {"action": "open"})
		elif _target == str(board["console"]):
			_send("operate_balance", _target, {"action": "certify"})
		elif (status["circuits"] as Dictionary).has(_target):
			var circuit: String = str(status["circuits"][_target]["status"])
			var action: String = ""
			match circuit:
				"pending": action = "energize"
				"warming", "stable": action = "shed"
				"recheck": action = "recheck"
			if action != "":
				_send("operate_balance", _target, {"action": action})
			elif _feedback != null:
				_feedback.text = "EXP011 circuit is already latched."
		return
	if _target.begins_with("LG_") and runtime.logistics != null:
		var manifest: Dictionary = runtime.logistics.definition_snapshot()
		var logistics_state: Dictionary = runtime.logistics.snapshot()
		if _target == str(manifest["depot"]):
			var action: String = "dispatch_" + _logistics_job + "_" + _logistics_route
			if not logistics_state["manifest"]:
				action = "manifest"
			_send("operate_logistics", _target, {"action": action})
		elif _target == str(manifest["console"]):
			_send("operate_logistics", _target, {"action": "certify"})
		elif (logistics_state["jobs"] as Dictionary).has(_target):
			var status: String = str(logistics_state["jobs"][_target]["status"])
			if ["arrived", "recheck"].has(status):
				_send("operate_logistics", _target, {"action": "receive" if status == "arrived" else "recheck"})
			else:
				_feedback.text = "EXP010 shipment " + _target + " is " + status.to_upper()
		return
	if _target.begins_with("FC_") and runtime.consequences != null:
		var chain: Dictionary = runtime.consequences.definition_snapshot()
		var snapshot: Dictionary = runtime.consequences.snapshot()
		if _target == str(chain["console"]):
			_send("operate_consequence", _target, {"action": "certify"})
		elif (snapshot["states"] as Dictionary).has(_target):
			var node_state: Dictionary = snapshot["states"][_target]
			var action: String = "survey"
			if bool(node_state["surveyed"]):
				action = "repair" if node_state["status"] == "failed" else _consequence_choice
			_send("operate_consequence", _target, {"action": action})
		return
	if _target.begins_with("FD_") and runtime.faults != null:
		var fault: Dictionary = runtime.faults.definition_snapshot()
		var phase: String = str(runtime.faults.snapshot()["phase"])
		if _target == str(fault["probe_a"]) or _target == str(fault["probe_b"]):
			_send("operate_fault", _target, {"action": "scan"})
		elif _target == str(fault["console"]):
			var action: String = ""
			match phase:
				"route": action = _fault_route
				"prepared": action = "stabilize"
				"verified": action = "certify"
				"faulted": action = "reset"
			if action != "":
				_send("operate_fault", _target, {"action": action})
			elif _feedback != null:
				_feedback.text = "EXP08: Complete both scans or await the host stability countdown."
		return
	if _target.begins_with("DV_") and runtime.devices != null:
		var device: Dictionary = runtime.devices.device_definition(_target)
		if not device.is_empty():
			var action: String = "reset" if runtime.devices.status_for(_target) == "jammed" else str(device["action"])
			_send("operate_device", _target, {"action": action})
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
	if event is InputEventKey and event.physical_keycode == KEY_V and not event.ctrl_pressed and not event.alt_pressed:
		_worksite_route = "resilience" if _worksite_route == "priority" else "priority"
		if _feedback != null:
			_feedback.text = "EXP012 strategy: " + _worksite_route.to_upper()
		_refresh()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.physical_keycode == KEY_G and not event.ctrl_pressed and not event.alt_pressed:
		_approach_choice = "urgent" if _approach_choice == "guarded" else "guarded"
		if _feedback != null:
			_feedback.text = "EXP014 A05 approach selected: " + _approach_choice.to_upper()
		_refresh()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.physical_keycode == KEY_H and not event.ctrl_pressed and not event.alt_pressed:
		_outcome_choice = "managed" if _outcome_choice == "buffer" else "buffer"
		if _feedback != null:
			_feedback.text = "EXP014 A06 service plan: " + _outcome_choice.to_upper()
		_refresh()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.physical_keycode == KEY_J and not event.ctrl_pressed and not event.alt_pressed:
		_hazard_choice = "temporary" if _hazard_choice == "engineered" else "engineered"
		if _feedback != null:
			_feedback.text = "EXP014 A07 containment choice: " + _hazard_choice.to_upper()
		_refresh()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.physical_keycode == KEY_P and not event.ctrl_pressed and not event.alt_pressed:
		_puzzle_path = "field" if _puzzle_path == "forensic" else "forensic"
		_puzzle_option = 0
		if _feedback != null:
			_feedback.text = "EXP014 A08 investigation choice: " + _puzzle_path.to_upper()
		_refresh()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.physical_keycode == KEY_O and not event.ctrl_pressed and not event.alt_pressed:
		if runtime.site_puzzles != null:
			var options: Array = runtime.site_puzzles.snapshot()["available"]
			if not options.is_empty():
				_puzzle_option = (_puzzle_option + 1) % options.size()
		_refresh()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.physical_keycode == KEY_B and not event.ctrl_pressed and not event.alt_pressed:
		_worksite_method = "rapid" if _worksite_method == "precision" else "precision"
		if _feedback != null:
			_feedback.text = "EXP012 sampling method: " + _worksite_method.to_upper()
		_refresh()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.physical_keycode == KEY_K and not event.ctrl_pressed and not event.alt_pressed:
		if _target.begins_with("LG_") and runtime.logistics != null and \
				_target == str(runtime.logistics.definition_snapshot()["depot"]):
			_send("operate_logistics", _target, {"action": "recall"})
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.physical_keycode == KEY_U and not event.ctrl_pressed and not event.alt_pressed:
		_logistics_route = "relay" if _logistics_route == "direct" else "direct"
		_refresh()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.physical_keycode == KEY_Y and not event.ctrl_pressed and not event.alt_pressed:
		_logistics_job = "b" if _logistics_job == "a" else "a"
		_refresh()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.physical_keycode == KEY_T and not event.ctrl_pressed and not event.alt_pressed:
		_consequence_choice = "divert" if _consequence_choice == "isolate" else "isolate"
		if _feedback != null:
			_feedback.text = "EXP009 response selected: " + _consequence_choice.to_upper()
		_refresh()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.physical_keycode == KEY_R and not event.ctrl_pressed and not event.alt_pressed:
		_fault_route = "reroute" if _fault_route == "isolate" else "isolate"
		if _feedback != null:
			_feedback.text = "EXP08 route selected: " + _fault_route.to_upper()
		_refresh()
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
	if board.has("bespoke"):
		var status: Dictionary = board["bespoke"]
		lines.append("EXP06 %s • PUZZLE %s" % [str(status["family"]),
			"PASS" if status["puzzle_solved"] else "ACTIVE"])
		lines.append("TASK: " + str(status["instruction"]))
		lines.append("HAZARD: %s [%s] • %s • safe in %d ticks • exposure %d ticks" % [
			str(status["hazard_kind"]), str(status["hazard_blocks"]),
			"UNSAFE" if status["hazard_active"] else "SAFE",
			int(status["safe_in_ticks"]), int(status["exposure_ticks"])])
	if board.has("devices"):
		var graph: Dictionary = board["devices"]
		var done: int = 0
		for status: Variant in (graph["status"] as Dictionary).values():
			if status == "done":
				done += 1
		lines.append("EXP07 DEVICES %d/%d • faults %d • resets %d • extraction %s" % [
			done, (graph["status"] as Dictionary).size(), int(graph["faults"]),
			int(graph["resets"]), "READY" if graph["solved"] else "BLOCKED"])
		if _target.begins_with("DV_") and runtime.devices != null:
			var current: Dictionary = runtime.devices.device_definition(_target)
			if not current.is_empty():
				lines.append("DEVICE %s: %s • %s • requires %s" % [
					_target, str(current["action"]), runtime.devices.status_for(_target),
					str(current["requires"])])
	if board.has("faults"):
		var fault_status: Dictionary = board["faults"]
		lines.append("EXP08 %s • route %s (selected %s) • hold %d/%d ticks • spare %d • faults %d / resets %d" % [
			str(fault_status["phase"]).to_upper(), str(fault_status["route"]),
			_fault_route, int(fault_status["stable_ticks"]), int(fault_status["hold_ticks"]),
			int(fault_status["spares"]), int(fault_status["faults"]), int(fault_status["resets"])])
		if _target.begins_with("FD_"):
			lines.append("EXP08 target: %s • probes scanned %d/2 • extraction %s" % [
				_target, (fault_status["scans"] as Dictionary).size(),
				"READY" if fault_status["solved"] else "BLOCKED"])
	if board.has("consequences"):
		var consequence: Dictionary = board["consequences"]
		lines.append("EXP009 CASCADE %s • failures %d • recovered %d • reserve %d • diversions %d • reopens %d" % [
			"CERTIFIED" if consequence["certified"] else "ACTIVE" if consequence["started"] else "DORMANT",
			int(consequence["failures"]), int(consequence["recoveries"]),
			int(consequence["reserve"]), int(consequence["diversions"]), int(consequence["reopens"])])
		for node: Dictionary in (_definitions["consequences"] as Dictionary)["nodes"]:
			var state: Dictionary = consequence["states"][str(node["id"])]
			lines.append("%s • %s • exposure %d/%d • %s" % [
				str(node["service"]), str(state["status"]).to_upper(),
				int(state["exposure"]), int(node["threshold_ticks"]),
				str(node["impact"]) if state["status"] == "failed" else "service response required"])
		if _target.begins_with("FC_"):
			lines.append("EXP009 target %s • selected %s • E survey / response / repair / certify" % [
				_target, _consequence_choice])
	if board.has("logistics"):
		var logistics: Dictionary = board["logistics"]
		lines.append("EXP010 LOGISTICS %s • stock %d spares / %d fuel • tick %d • late %d • recall %d • reopens %d" % [
			"CERTIFIED" if logistics["certified"] else "MANIFESTED" if logistics["manifest"] else "DORMANT",
			int(logistics["stock"]["spares"]), int(logistics["stock"]["fuel"]), int(logistics["tick"]),
			int(logistics["late"]), int(logistics["recalls"]), int(logistics["reopens"])])
		for job: Dictionary in (_definitions["logistics"] as Dictionary)["jobs"]:
			var state: Dictionary = logistics["jobs"][str(job["id"])]
			lines.append("%s • %s • %s • deadline %d ticks • %s" % [
				str(job["id"]), str(job["cargo"]), str(state["status"]).to_upper(),
				int(job["deadline_ticks"]), str(job["priority"])])
		lines.append("EXP010 choice: job %s / %s route • U route, Y job, E act, K recall at depot" % [
			_logistics_job.to_upper(), _logistics_route])
		if not (logistics["active"] as Dictionary).is_empty():
			var active: Dictionary = logistics["active"]
			lines.append("SUPPLY IN TRANSIT: %s / %s • %d/%d host ticks" % [
				str(active["job"]), str(active["route"]), int(active["elapsed"]), int(active["duration"])])
	if board.has("balancing"):
		var loads: Dictionary = board["balancing"]
		lines.append("EXP011 CRITICAL LOADS %s • %d/%d PU • tick %d • late %d • abort %d • reopens %d • mode %s" % [
			"CERTIFIED" if loads["certified"] else "OPEN" if loads["opened"] else "DORMANT",
			int(loads["used_pu"]), int(loads["capacity_pu"]), int(loads["tick"]),
			int(loads["late"]), int(loads["aborts"]), int(loads["reopens"]), str(loads["mode"])])
		for service: Dictionary in (_definitions["balancing"] as Dictionary)["services"]:
			var state: Dictionary = loads["circuits"][str(service["id"])]
			lines.append("%s • %s • %d PU • %s • %d/%d host ticks • deadline %d" % [
				str(service["id"]), str(service["name"]), int(service["demand_pu"]),
				str(state["status"]).to_upper(), int(state["ticks"]),
				int(service["dwell_ticks"]), int(service["deadline_ticks"])])
		lines.append("EXP011: E on board to inspect/open; E at a circuit to energize / shed after STABLE; E at console to certify.")
	if board.has("worksite"):
		var worksite: Dictionary = board["worksite"]
		lines.append("EXP012 WORKSITE %s • route %s • cells %d • active crews %d/%d • abort %d • reopens %d" % [
			"CERTIFIED" if worksite["certified"] else "OPEN" if worksite["opened"] else "DORMANT",
			str(worksite["route"]), int(worksite["cells_left"]),
			int(worksite["active_crews"]), int(worksite["crew_capacity"]),
			int(worksite["aborts"]), int(worksite["reopens"])])
		for checkpoint: Dictionary in (_definitions["worksite"] as Dictionary)["checkpoints"]:
			var cp: Dictionary = worksite["states"][str(checkpoint["id"])]
			lines.append("%s • %s • method %s • %d/%d host ticks" % [
				str(checkpoint["title"]), str(cp["status"]).to_upper(),
				str(cp["method"]), int(cp["elapsed"]), int(cp["needed"])])
		lines.append("EXP012 route selection V: %s • method B: %s • discovery %s (optional)" % [
			_worksite_route.to_upper(), _worksite_method.to_upper(),
			"LOGGED" if worksite["optional_logged"] else "UNLOGGED"])
		if worksite.has("site_a02") or worksite.has("site_exp013"):
			var new_site: bool = worksite.has("site_exp013")
			var authored: Dictionary = worksite["site_exp013"] if new_site else worksite["site_a02"]
			var badge: String = ("EXP013 " + str(_definitions.get("site_exp013_phase", "A01"))) if new_site else "EXP012 A02"
			lines.append("%s / %s / %s" % [badge,
				str(authored["title"]), str(authored["stakes"])])
			lines.append("%s route %s / procedure %d/%d / %s / failure %s / recovery %d" % [
				badge, str(authored["route"]),
				int(authored["step"]) + 1 if not authored["solved"] else 4,
				int(authored["step_count"]), str(authored["phase"]),
				str(authored["fault"]) if authored["fault"] != "" else "none",
				int(authored["recoveries"])])
			if not authored["solved"]:
				var next_step: Dictionary = authored["next"]
				if next_step.is_empty():
					lines.append("%s: open A01 worksite board, then select the operating strategy." % badge)
				else:
					lines.append("%s: E on %s to %s / %s; support %s; %d/%d host ticks." % [
						badge, str(next_step["target"]), str(next_step["action"]),
						str(next_step["mode"]), str(next_step["support_target"]),
						int(authored["tick"]), int(authored["deadline"])])
				if authored["fault"] != "":
					lines.append("%s FAULT: E at %s to recover safely." % [
						badge, str(authored["recovery_target"])])
	if board.has("worksite") and board["worksite"].has("site_contingency"):
		var state: Dictionary = board["worksite"]["site_contingency"]
		lines.append("EXP014 CONTINGENCY %s • route %s • stage %d/3 • %s • failures %d / recoveries %d" % [
			"HOST VERIFIED" if state["solved"] else "ACTIVE", str(state["route"]),
			int(state["step"]) if state["solved"] else int(state["step"]) + 1,
			str(state["phase"]), int(state["failures"]), int(state["recoveries"])])
		if str(state["fault"]) != "":
			lines.append("EXP014 FAULT %s • recovery station %s" % [
				str(state["fault"]), str(state["recovery_target"])])
		elif not bool(state["solved"]):
			var current: Dictionary = state["next"]
			if not current.is_empty():
				lines.append("EXP014 %s • guard %s • target %s → support %s → witness %s • host progress %d/2" % [
					str(current["mode"]), str(current["guard"]), str(current["target"]),
					str(current["support"]), str(current["witness"]), int(state["progress"])])
	if board.has("worksite") and board["worksite"].has("site_approach"):
		var intel: Dictionary = board["worksite"]["site_approach"]
		lines.append("EXP014 A05 APPROACH %s • mode %s (G: %s) • investigation %d/%d • failures %d / recovery %d" % [
			str(intel["phase"]).to_upper(), str(intel["approach"]),
			_approach_choice, int(intel["step"]), int(intel["total_steps"]),
			int(intel["failures"]), int(intel["recoveries"])])
		if str(intel["observed_risk"]) != "":
			lines.append("EVIDENCE 1 CONFIRMED: source risk %s • required live support %s" % [
				str(intel["observed_risk"]), str(intel["observed_guard"])])
		if str(intel["observed_protocol"]) != "":
			lines.append("EVIDENCE 2 CONFIRMED: independent %s proof required" % [
				str(intel["observed_protocol"])])
		if bool(intel["intel_revealed"]):
			lines.append("HOST-VERIFIED DECISION BRIEF: recommended %s • chosen %s" % [
				str(intel["recommended_route"]), str(intel["route"])])
		if str(intel["fault"]) != "":
			lines.append("A05 FAULT %s • recover at %s; no intervention unlocked." % [
				str(intel["fault"]), str(intel["recovery_target"])])
		elif not bool(intel["solved"]):
			var requested: Dictionary = intel["next"]
			lines.append("A05 HOST REQUEST: %s at %s • choose V for decision route • E to act" % [
				str(requested.get("action", "")), str(requested.get("target", ""))])
		else:
			lines.append("A05 OPERATING ROUTE LOCKED: %s • select same route at worksite board" % str(intel["route"]))
	if board.has("worksite") and board["worksite"].has("site_outcomes"):
		var outcome: Dictionary = board["worksite"]["site_outcomes"]
		lines.append("EXP014 A06 SERVICE %s • %s / %s • reserve %d • debt %d • exposure %d • quality %d" % [
			str(outcome["phase"]).to_upper(), str(outcome["route"]), str(outcome["mode"]),
			int(outcome["reserve"]), int(outcome["service_debt"]),
			int(outcome["exposure_ticks"]), int(outcome["quality_index"])])
		lines.append("A06 %s risk • incidents %d • recoveries %d • host witness %d/%d • H selects %s" % [
			str(outcome["risk_class"]), int(outcome["incidents"]), int(outcome["recoveries"]),
			int(outcome["audit_count"]), int(outcome["total_audits"]), _outcome_choice.to_upper()])
		var following: Dictionary = outcome["next"]
		if not following.is_empty():
			lines.append("A06 HOST REQUEST: %s at %s • fault %s" % [
				str(following.get("action", "")), str(following.get("target", "")),
				str(outcome["fault"]) if outcome["fault"] != "" else "none"])
		if bool(outcome["solved"]):
			lines.append("A06 HOST CERTIFIED: operational consequences verified; not production points.")
	if board.has("worksite") and board["worksite"].has("site_hazards"):
		var hazard: Dictionary = board["worksite"]["site_hazards"]
		lines.append("EXP014 A07 %s HAZARD • %s • %s mode • pressure %d • exposure %d" % [
			str(hazard["risk_class"]).to_upper(), str(hazard["phase"]).to_upper(),
			str(hazard["mode"]), int(hazard["pressure"]), int(hazard["exposure"])])
		lines.append("A07 mitigation %d/%d • materials %d • residual %d • failures %d • recovery %d • J: %s" % [
			int(hazard["step"]), int(hazard["mitigation_total"]),
			int(hazard["materials"]), int(hazard["liability"]),
			int(hazard["failures"]), int(hazard["recoveries"]),
			_hazard_choice.to_upper()])
		var hazard_next: Dictionary = hazard["next"]
		if not hazard_next.is_empty():
			lines.append("A07 HOST REQUEST: %s at %s • fault %s" % [
				str(hazard_next.get("action", "")), str(hazard_next.get("target", "")),
				str(hazard["fault"]) if hazard["fault"] != "" else "none"])
		if bool(hazard["solved"]):
			lines.append("A07 ENVIRONMENT VERIFIED BY HOST (source/headless only)")
	if board.has("worksite") and board["worksite"].has("site_puzzles"):
		var puzzle: Dictionary = board["worksite"]["site_puzzles"]
		lines.append("EXP014 A08 EVIDENCE %s • %s • %d/%d verified • kits %d • liabilities %d • failures %d / recoveries %d" % [
			str(puzzle["phase"]).to_upper(), str(puzzle["mode"]),
			int(puzzle["completed"]), int(puzzle["total"]),
			int(puzzle["kits"]), int(puzzle["liabilities"]),
			int(puzzle["failures"]), int(puzzle["recoveries"])])
		if str(puzzle["phase"]) == "choose":
			lines.append("A08 path P: %s • FORENSIC uses finite instrument kits / FIELD uses seven source witnesses" % _puzzle_path.to_upper())
			for option: Dictionary in puzzle["choices"]:
				lines.append("  %s • begin at %s (%d evidence nodes)" % [
					str(option["mode"]), str(option["target"]), int(option["steps"])])
		elif str(puzzle["phase"]) == "running":
			var ready: Array = puzzle["available"]
			if not ready.is_empty():
				_puzzle_option = posmod(_puzzle_option, ready.size())
				for i: int in range(ready.size()):
					var proof: Dictionary = ready[i]
					lines.append("%s %s at %s • source %s • guard %s • kit %d" % [
						"SELECTED" if i == _puzzle_option else "READY",
						str(proof["kind"]), str(proof["target"]),
						str(proof["source_action"]), str(proof["guard"]), int(proof["cost"])])
			lines.append("O: cycle independent evidence • E: submit host proof at selected station")
		elif str(puzzle["phase"]) == "fault":
			lines.append("A08 FAULT %s • recover at %s, retained kit costs" % [
				str(puzzle["fault"]), str(puzzle["recovery_target"])])
		elif bool(puzzle["solved"]):
			lines.append("A08 HOST-VERIFIED INVESTIGATION COMPLETE; existing worksite route remains locked.")
	_task_label.text = "\n".join(lines)
	if _target_label != null:
		_target_label.text = "Target: %s  /  tool: %s  /  host revision: %d" % [
			_target if _target != "" else "(aim at numbered station)",
			TOOL_IDS[_selected_tool], int(board["host_revision"])]
	if _site_composition != null:
		var active: Variant = runtime.site_exp013 if runtime.site_exp013 != null else runtime.site_a02
		if active != null:
			SiteComposition.reflect(_site_composition, active.snapshot())
			if runtime.site_contingency != null and active.solved():
				SiteComposition.reflect_contingency(
					_site_composition, runtime.site_contingency.snapshot())
	if _approach_view != null and runtime.site_approach != null:
		ApproachView.reflect(_approach_view, runtime.site_approach.snapshot())
	if _environmental_feedback != null:
		var active_source: Variant = runtime.site_exp013 if runtime.site_exp013 != null else runtime.site_a02
		if active_source != null:
			var contingency_state: Dictionary = runtime.site_contingency.snapshot() if runtime.site_contingency != null else {}
			EnvironmentFeedback.reflect(_environmental_feedback, active_source.snapshot(), contingency_state)
	set_meta("display_revision", int(board["host_revision"]))
