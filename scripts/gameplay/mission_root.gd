extends Node3D
## Offline-first C01 play scene. Instantiates the existing authored Alder graybox,
## a collision-backed first-person worker and the production host-only command path.
## No ENet/Steam gateway is enabled here, and all grid mutations use SessionHost.receive.

const WorldScene := preload("res://scenes/world/alder_street.tscn")
const PlayerController := preload("res://scripts/actors/first_person_controller.gd")
const OfflineSession := preload("res://scripts/gameplay/offline_c01_session.gd")
const TargetSelector := preload("res://scripts/interaction/target_selector.gd")
const InteractionVisibility := preload("res://scripts/interaction/interaction_visibility.gd")
const FieldHud := preload("res://scripts/ui/field_hud.gd")
const NetworkTablet := preload("res://scripts/ui/network_tablet.gd")
const OnboardingCard := preload("res://scripts/ui/onboarding_card.gd")
const AccessibilityPanel := preload("res://scripts/ui/accessibility_panel.gd")
const AccessibilitySettings := preload("res://scripts/ui/accessibility_settings.gd")
const ThemeTokens := preload("res://scripts/ui/theme_tokens.gd")
const UiText := preload("res://scripts/ui/ui_text.gd")
const InputDeviceTracker := preload("res://scripts/ui/input_device_tracker.gd")
const RestorationPresentation := preload("res://scripts/world/restoration_presentation.gd")
const OfflinePersistence := preload("res://scripts/persistence/offline_persistence.gd")

const MENU_PATH: String = "res://scenes/menu/main_menu.tscn"
const HOST_TICK_SECONDS: float = 0.1
const TOOL_LIST: Array[String] = OfflineSession.TOOL_LIST

var session: OfflineSession
var player: PlayerController
var hud: FieldHud
var tablet: NetworkTablet
var onboarding: OnboardingCard
var accessibility: AccessibilityPanel
var settings: AccessibilitySettings
var _world: Node3D
var _world_fx: RestorationPresentation
var _store: OfflinePersistence
var _save_enabled: bool = false
var _save_issue: String = ""
var _restored_view: Dictionary = {}
var _overlay: Control
var _pause_panel: PanelContainer
var _complete_panel: PanelContainer
var _status: Label
var _resume_button: Button
var _accessibility_button: Button
var _active_device: String = UiText.DEVICE_KBM
var _time_accumulator: float = 0.0
var _heartbeat_accumulator: float = 0.0
var _slot: int = 1
var _target: String = ""
var _paused: bool = false
var _finished: bool = false
var _last_position_zone: bool = false
var _ui_tokens: Dictionary = {}
var _interaction: Dictionary = {}
var _solo_tuning: Dictionary = {}


func _ready() -> void:
	_ui_tokens = _json("res://content/ui/tokens.json")
	_interaction = _json("res://content/interaction.json")
	_solo_tuning = _json("res://content/offline_solo.json")
	_make_lighting()
	_world = WorldScene.instantiate()
	_world.name = "District"
	add_child(_world)
	_make_player()

	session = OfflineSession.new()
	var errors: Array[Dictionary] = session.setup(_in_range, _position_cm)
	if not errors.is_empty():
		push_error("OFFLINE_C01_SETUP_FAILED: %s" % str(errors))
		return
	_store = OfflinePersistence.new()
	var identity: Dictionary = _store.initialize()
	_save_enabled = bool(identity.get("ok", false))
	if not _save_enabled:
		_save_issue = str(identity.get("code", "IDENTITY_ERROR"))
	var resume: bool = bool(get_tree().get_meta("offline_resume", false))
	get_tree().remove_meta("offline_resume")
	if _save_enabled and resume:
		var restored: Dictionary = _store.restore_into(session)
		if restored.get("ok", false) and restored.get("available", false):
			_restored_view = restored["view"]
			if not (restored.get("issues", []) as Array).is_empty():
				_save_issue = "Recovered from %s: %s" % [restored.get("source", ""),
					str(restored.get("issues", []))]
		else:
			_save_enabled = false
			_save_issue = str(restored.get("code", "MISSING_CHECKPOINT"))
	if not _restored_view.is_empty():
		_apply_restored_view(_restored_view)
	session.set_tool(TOOL_LIST[_slot - 1])
	_world_fx = RestorationPresentation.new()
	_world_fx.setup(_world)
	_make_ui()
	if bool(identity.get("ok", false)):
		var preference_result: Dictionary = _store.read_preferences(settings)
		if not preference_result.get("ok", false):
			_save_issue = str(preference_result.get("code", "BAD_PROFILE"))
		else:
			_settings_changed(settings.snapshot(), false)
	if _save_issue != "":
		_status.text = UiText.tf("offline.status.save_unavailable", [_save_issue])
	if _save_enabled and not resume:
		_save_checkpoint()
	session.changed.connect(_refresh_hud)
	session.action_replied.connect(_on_action_replied)
	session.mission_event.connect(_on_mission_event)
	player.moved.connect(_on_player_moved)
	_last_position_zone = session.inside_van(player.global_position)
	session.set_in_van_zone(_last_position_zone)
	_refresh_hud()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if session.completed():
		_finish()


func _apply_restored_view(view: Dictionary) -> void:
	var p: Array = view["position_cm"]
	player.global_position = Vector3(float(p[0]), float(p[1]), float(p[2])) / 100.0
	player.rotation.y = float(view["yaw_millirad"]) / 1000.0
	player.camera.rotation.x = float(view["pitch_millirad"]) / 1000.0
	_slot = int(view["tool_slot"])
	player.carrying = session.equipment.carrier_of(OfflineSession.GENERATOR) == OfflineSession.PLAYER_ID


func _save_checkpoint() -> void:
	if not _save_enabled or session == null or player == null:
		return
	var yaw: int = roundi(wrapf(player.rotation.y, -PI, PI) * 1000.0)
	var pitch: int = roundi(player.camera.rotation.x * 1000.0)
	var result: Dictionary = _store.write_checkpoint(session, player.position_cm(), yaw, pitch, _slot)
	if not result.get("ok", false):
		_save_enabled = false
		_save_issue = str(result.get("code", "SAVE_ERROR"))
		if _status != null:
			_status.text = UiText.tf("offline.status.save_unavailable", [_save_issue])


static func _json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


func _make_lighting() -> void:
	var visual: Dictionary = _solo_tuning["presentation"]
	var env: Environment = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(str(visual["environment_color"]))
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(str(visual["ambient_color"]))
	env.ambient_light_energy = 1.0
	var sky_light: WorldEnvironment = WorldEnvironment.new()
	sky_light.name = "WorldLight"
	sky_light.environment = env
	add_child(sky_light)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_color = Color(str(visual["sun_color"]))
	sun.light_energy = float(visual["sun_energy_percent"]) / 100.0
	var sun_angles: Array = visual["sun_rotation_deg"]
	sun.rotation_degrees = Vector3(float(sun_angles[0]), float(sun_angles[1]), float(sun_angles[2]))
	add_child(sun)


func _make_player() -> void:
	player = PlayerController.new()
	player.name = "Player"
	add_child(player)
	var spawn: Marker3D = _world.get_node("Markers/SPAWN_1") as Marker3D
	var dimensions: Dictionary = _json("res://content/world/kit_dimensions.json")
	player.global_position = spawn.global_position + Vector3.UP * float(dimensions["player_height_cm"]) / 200.0
	player.rotation_degrees.y = -90.0


func _make_ui() -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	layer.name = "Interface"
	add_child(layer)
	_overlay = Control.new()
	_overlay.name = "Screen"
	_fill(_overlay)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_overlay)

	hud = FieldHud.new()
	hud.name = "HUD"
	_overlay.add_child(hud)
	_fill(hud)

	onboarding = OnboardingCard.new()
	onboarding.name = "Onboarding"
	_overlay.add_child(onboarding)
	onboarding.anchor_left = 0.5
	onboarding.anchor_right = 0.5
	onboarding.offset_left = -280.0
	onboarding.offset_right = 280.0
	onboarding.offset_top = 36.0
	onboarding.offset_bottom = 190.0

	_status = Label.new()
	_status.name = "Message"
	_overlay.add_child(_status)
	_status.anchor_left = 0.5
	_status.anchor_right = 0.5
	_status.offset_left = -360.0
	_status.offset_right = 360.0
	_status.offset_top = 200.0
	_status.offset_bottom = 250.0
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_color_override("font_color", ThemeTokens.color(_ui_tokens, "action"))
	_status.theme = ThemeTokens.build(_ui_tokens)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE

	tablet = NetworkTablet.new()
	tablet.name = "NetworkTablet"
	_overlay.add_child(tablet)
	_fill(tablet)
	tablet.visible = false
	tablet.setup(session.outbox)
	tablet.closed.connect(_resume_after_tablet)

	settings = AccessibilitySettings.new()
	accessibility = AccessibilityPanel.new()
	accessibility.name = "Accessibility"
	accessibility.set_settings(settings)
	accessibility.settings_changed.connect(_settings_changed)

	_pause_panel = _make_pause_panel()
	_pause_panel.visible = false
	_overlay.add_child(_pause_panel)
	# Modal dimensions reflow with the viewport and the selected UI scale.
	var column: VBoxContainer = _pause_panel.find_child("PauseActions", true, false) as VBoxContainer
	column.add_child(accessibility)
	accessibility.visible = false

	_complete_panel = _make_completion_panel()
	_complete_panel.visible = false
	_overlay.add_child(_complete_panel)
	_layout_modal_panels(get_viewport().get_visible_rect().size)
	get_viewport().size_changed.connect(_on_viewport_size_changed)
	_settings_changed(settings.snapshot(), false)


func _make_pause_panel() -> PanelContainer:
	var panel: PanelContainer = PanelContainer.new()
	panel.name = "Pause"
	panel.theme = ThemeTokens.build(_ui_tokens)
	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 32)
	margin.add_theme_constant_override("margin_right", 32)
	margin.add_theme_constant_override("margin_top", 32)
	margin.add_theme_constant_override("margin_bottom", 32)
	panel.add_child(margin)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.name = "PauseScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.follow_focus = true
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(scroll)
	var column: VBoxContainer = VBoxContainer.new()
	column.name = "PauseActions"
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 14)
	scroll.add_child(column)
	_pause_label(column, "offline.pause.title", 34)
	_resume_button = _button(column, "offline.pause.resume", _resume_play)
	_accessibility_button = _button(column, "offline.pause.accessibility", _toggle_accessibility)
	_button(column, "offline.pause.recover", _recover_player)
	_button(column, "offline.pause.exit", _exit_to_menu)
	return panel


func _make_completion_panel() -> PanelContainer:
	var panel: PanelContainer = PanelContainer.new()
	panel.name = "Results"
	panel.theme = ThemeTokens.build(_ui_tokens)
	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 32)
	margin.add_theme_constant_override("margin_right", 32)
	margin.add_theme_constant_override("margin_top", 32)
	margin.add_theme_constant_override("margin_bottom", 32)
	panel.add_child(margin)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 18)
	margin.add_child(column)
	_pause_label(column, "offline.complete.title", 32)
	var result: Label = Label.new()
	result.name = "Score"
	result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(result)
	_button(column, "offline.complete.menu", _exit_to_menu)
	return panel


func _pause_label(parent: Control, key: String, font_size: int) -> void:
	var title: Label = Label.new()
	title.text = UiText.t(key)
	title.add_theme_font_size_override("font_size", font_size)
	parent.add_child(title)


func _button(parent: Control, key: String, action: Callable) -> Button:
	var button: Button = Button.new()
	button.text = UiText.t(key)
	button.custom_minimum_size.y = 50.0
	button.pressed.connect(action)
	parent.add_child(button)
	return button


static func _fill(control: Control) -> void:
	control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


static func _center(control: Control, dimensions: Vector2) -> void:
	control.anchor_left = 0.5
	control.anchor_right = 0.5
	control.anchor_top = 0.5
	control.anchor_bottom = 0.5
	control.offset_left = -dimensions.x * 0.5
	control.offset_right = dimensions.x * 0.5
	control.offset_top = -dimensions.y * 0.5
	control.offset_bottom = dimensions.y * 0.5


func _on_viewport_size_changed() -> void:
	if settings != null:
		_settings_changed(settings.snapshot(), false)


## Keep panels inside the same authored safe area as the HUD. The pause
## controls scroll when necessary rather than expanding beyond a small screen.
## Keep the tutorial in the center gap between top-corner HUD cards.
## At small viewports, shrink it without moving the reticle or controls.
func _layout_onboarding(screen_size: Vector2) -> void:
	if onboarding == null:
		return
	var effective: float = ThemeTokens.effective_percent(int(settings.value("ui_scale_percent")), screen_size)
	var safe: float = float(ThemeTokens.safe_area(_ui_tokens, screen_size))
	var side: float = float(ThemeTokens.px(420.0, effective))
	var gap_width: float = maxf(screen_size.x * 0.23, screen_size.x - 2.0 * side - 2.0 * safe)
	var width: float = minf(560.0 * effective / 100.0, gap_width)
	var height: float = minf(260.0 * effective / 100.0, screen_size.y * 0.44)
	onboarding.offset_left = -width * 0.5
	onboarding.offset_right = width * 0.5
	onboarding.offset_top = safe
	onboarding.offset_bottom = safe + height
	if _status != null:
		_status.offset_top = safe + height + 8.0
		_status.offset_bottom = _status.offset_top + float(ThemeTokens.px(50.0, effective))


func _layout_modal_panels(screen_size: Vector2) -> void:
	if _pause_panel == null or _complete_panel == null:
		return
	var desired: int = int(settings.value("ui_scale_percent")) if settings != null else 100
	var effective: float = ThemeTokens.effective_percent(desired, screen_size)
	var margin: float = float(ThemeTokens.safe_area(_ui_tokens, screen_size))
	var available: Vector2 = Vector2(maxf(1.0, screen_size.x - margin * 2.0),
		maxf(1.0, screen_size.y - margin * 2.0))
	_center(_pause_panel, Vector2(minf(660.0 * effective / 100.0, available.x),
		minf(510.0 * effective / 100.0, available.y)))
	_center(_complete_panel, Vector2(minf(660.0 * effective / 100.0, available.x),
		minf(370.0 * effective / 100.0, available.y)))


## Input labels follow the last *intentional* gamepad or keyboard/mouse input.
## Re-render views only on device transitions, never on every stick frame.
func _input(event: InputEvent) -> void:
	var inferred: String = InputDeviceTracker.infer(event)
	if inferred == "" or inferred == _active_device:
		return
	_active_device = inferred
	if hud != null:
		hud.set_device(inferred)
	if tablet != null:
		tablet.set_device(inferred)
	if onboarding != null:
		onboarding.set_device(inferred)


## Effects and onboarding are presentation only; mission simulation retains its
## fixed authoritative tick in _physics_process.
func _process(delta: float) -> void:
	if _world_fx != null:
		_world_fx.advance(delta)
	if onboarding != null and not _paused and not _finished and tablet != null and not tablet.visible:
		onboarding.advance_idle(delta)


func _physics_process(delta: float) -> void:
	if session == null or _paused or _finished:
		return
	_time_accumulator += delta
	while _time_accumulator >= HOST_TICK_SECONDS:
		_time_accumulator -= HOST_TICK_SECONDS
		session.tick_once()
	if tablet.visible:
		return
	_update_target()
	var inside: bool = session.inside_van(player.global_position)
	if inside != _last_position_zone:
		_last_position_zone = inside
		session.set_in_van_zone(inside)
	_heartbeat_accumulator += delta
	if _heartbeat_accumulator >= float(_interaction["lock_heartbeat_timeout_ticks"]) / 20.0:
		_heartbeat_accumulator = 0.0
		_send_heartbeats()
	if player.global_position.y < float(_solo_tuning["player"]["fall_recovery_cm"]) / 100.0:
		_recover_player()


func _update_target() -> void:
	var aim: Camera3D = player.camera
	var candidates: Array[Dictionary] = []
	for candidate: Dictionary in session.targets():
		if _can_see(candidate["position"], float(candidate["radius"])):
			candidates.append(candidate)
	var selected: String = TargetSelector.select(aim.global_position, -aim.global_transform.basis.z, candidates,
		float(_interaction["ray_length_cm"]) / 100.0, float(_interaction["aim_assist_cone_deg"]))
	if selected == "" and session.in_van_zone() and (session.mission.verified() or
			int(session.mission.canonical_state()["countdown_left"]) >= 0):
		selected = "ZONE_VAN"
	if selected != _target:
		_target = selected
		_refresh_hud()


func _in_range(player_id: String, entity: String) -> bool:
	if player_id != OfflineSession.PLAYER_ID:
		return false
	if entity == OfflineSession.GENERATOR and session.equipment.carrier_of(entity) == player_id:
		return true
	var target_position: Vector3 = session.entity_position(entity)
	if target_position == Vector3.INF:
		return false
	return _can_see(target_position, session.radius_for(entity))


## The same physics sight check gates both prompt candidates and host commands.
func _can_see(target_position: Vector3, radius_m: float) -> bool:
	if player == null or player.camera == null:
		return false
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	return InteractionVisibility.can_reach(space, player.camera.global_position, target_position,
		float(_interaction["ray_length_cm"]) / 100.0, radius_m, [player.get_rid()] as Array[RID])


func _position_cm(player_id: String) -> Vector3i:
	if player_id != OfflineSession.PLAYER_ID or player == null:
		return Vector3i.ZERO
	return player.position_cm()


func _unhandled_input(event: InputEvent) -> void:
	if session == null or _finished:
		return
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		_toggle_pause()
		get_viewport().set_input_as_handled()
		return
	if _paused or tablet.visible:
		return
	if event.is_action_pressed("onboarding_hint"):
		onboarding.show_hint()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("map_meter"):
		_open_tablet()
	elif event.is_action_pressed("interact") or event.is_action_pressed("tool_primary"):
		_interact()
	elif event.is_action_pressed("tool_next"):
		_select_slot(_slot + 1)
	elif event.is_action_pressed("tool_prev"):
		_select_slot(_slot - 1)
	elif event.is_action_pressed("drop_item"):
		if session.equipment.carrier_of(OfflineSession.GENERATOR) == OfflineSession.PLAYER_ID:
			session.command("place_item", OfflineSession.GENERATOR, {"action": "drop"})
	else:
		for i: int in range(TOOL_LIST.size()):
			if event.is_action_pressed("tool_slot_" + str(i + 1)):
				_select_slot(i + 1)
				break


func _interact() -> void:
	if _target == "":
		return
	var reply: Dictionary = session.interact(_target, TOOL_LIST[_slot - 1])
	if not reply.get("ok", false):
		_status.text = str(reply.get("message", UiText.t("offline.status.refused")))


func _select_slot(number: int) -> void:
	_slot = wrapi(number - 1, 0, TOOL_LIST.size()) + 1
	session.set_tool(TOOL_LIST[_slot - 1])
	_refresh_hud()
	_save_checkpoint()


func _send_heartbeats() -> void:
	for repair: Dictionary in session.repair_definitions():
		var id: String = str(repair["id"])
		if session.interaction.lock_owner(id) == OfflineSession.PLAYER_ID and _in_range(OfflineSession.PLAYER_ID, id):
			session.command("heartbeat", id, {})


func _on_player_moved() -> void:
	if onboarding != null:
		onboarding.observe("player_moved")


func _on_action_replied(envelope: Dictionary, reply: Dictionary) -> void:
	if not reply.get("ok", false):
		_status.text = str(reply.get("message", UiText.t("offline.status.refused")))
		return
	var kind: String = str(envelope["type"])
	_status.text = UiText.tf("offline.status.accepted", [UiText.t("offline.verb." + _action_verb(kind))])
	if kind == "inspect":
		onboarding.observe("meter_measured")
		_refresh_tablet()
	elif kind == "repair_step":
		var step: String = str((envelope["payload"] as Dictionary).get("step", ""))
		if step == "isolate":
			onboarding.observe("junction_isolated")
		elif step == "restore":
			onboarding.observe("repair_restored")
	if kind == "place_item":
		player.carrying = session.equipment.carrier_of(OfflineSession.GENERATOR) == OfflineSession.PLAYER_ID
	if ["repair_step", "place_item", "toggle_switch", "recover_self", "request_extract"].has(kind):
		_save_checkpoint()


static func _action_verb(kind: String) -> String:
	match kind:
		"inspect": return "measure"
		"repair_step": return "repair"
		"request_lock": return "lock"
		"toggle_switch": return "switch"
		"place_item": return "interact"
		"request_extract": return "depart"
	return "interact"


func _on_mission_event(event: Dictionary) -> void:
	var kind: String = str(event.get("type", ""))
	match kind:
		"latch":
			_status.text = UiText.t("offline.status.drain")
		"verified":
			_status.text = UiText.t("offline.status.verified")
			_save_checkpoint()
		"trip":
			_status.text = UiText.t("offline.status.trip")
		"mission_complete":
			_save_checkpoint()
			_finish()
		"checkpoint_due":
			_save_checkpoint()


func _refresh_hud() -> void:
	if hud == null or session == null:
		return
	hud.apply(session.hud_view(_slot, _target, TOOL_LIST[_slot - 1]))
	if _world_fx != null:
		_world_fx.apply(session.host_state(), session.mission.is_latched(OfflineSession.PUMP_LATCH))


func _refresh_tablet() -> void:
	if tablet != null and tablet.visible:
		tablet.show_data(session.tablet_view(), session.mission.objectives(),
			["district.alder_street", "contract.c01"])


func _open_tablet() -> void:
	tablet.show_data(session.tablet_view(), session.mission.objectives(),
		["district.alder_street", "contract.c01"])
	player.set_controls_active(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	tablet.open()
	get_viewport().set_input_as_handled()


func _resume_after_tablet() -> void:
	if not _paused and not _finished:
		player.set_controls_active(true)
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_refresh_hud()


func _toggle_pause() -> void:
	if tablet.visible:
		tablet.close()
		return
	if _paused and accessibility.visible:
		_toggle_accessibility()
		return
	_paused = not _paused
	player.set_controls_active(not _paused)
	_pause_panel.visible = _paused
	if _paused:
		_save_checkpoint()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_resume_button.grab_focus()
	else:
		accessibility.visible = false
		var focus_owner: Control = get_viewport().gui_get_focus_owner()
		if focus_owner != null and _pause_panel.is_ancestor_of(focus_owner):
			get_viewport().gui_release_focus()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _resume_play() -> void:
	if _paused:
		_toggle_pause()


func _toggle_accessibility() -> void:
	if not _paused:
		return
	accessibility.visible = not accessibility.visible
	if accessibility.visible:
		accessibility.focus_first()
	elif is_instance_valid(_accessibility_button):
		_accessibility_button.grab_focus()


func _settings_changed(_values: Dictionary, persist: bool = true) -> void:
	settings.apply_to_views(hud, tablet)
	accessibility.refresh()
	if player != null:
		player.set_reduce_camera_motion(bool(settings.value("reduce_camera_motion")))
	if _world_fx != null:
		_world_fx.set_reduce_flashes(bool(settings.value("reduce_flashes")))
	if onboarding != null:
		onboarding.set_ui_scale(int(settings.value("ui_scale_percent")))
		_layout_onboarding(get_viewport().get_visible_rect().size)
	if _pause_panel != null and _complete_panel != null:
		var effective: float = ThemeTokens.effective_percent(int(settings.value("ui_scale_percent")),
			get_viewport().get_visible_rect().size)
		_pause_panel.theme = ThemeTokens.build(_ui_tokens, effective)
		_complete_panel.theme = ThemeTokens.build(_ui_tokens, effective)
		accessibility.set_ui_scale(int(settings.value("ui_scale_percent")))
		_layout_modal_panels(get_viewport().get_visible_rect().size)
	onboarding.set_hints_enabled(bool(settings.value("hints_enabled")))
	_refresh_hud()
	if persist and _store != null and _store.account_key != "":
		var result: Dictionary = _store.write_preferences(settings)
		if not result.get("ok", false):
			_save_issue = str(result.get("code", "PROFILE_WRITE_ERROR"))
			_status.text = UiText.tf("offline.status.save_unavailable", [_save_issue])


func _recover_player() -> void:
	var result: Dictionary = session.command("recover_self", "", {})
	if not result.get("ok", false):
		_status.text = str(result.get("message", ""))
		return
	var spawn: Marker3D = _world.get_node("Markers/SPAWN_1") as Marker3D
	var dimensions: Dictionary = _json("res://content/world/kit_dimensions.json")
	player.global_position = spawn.global_position + Vector3.UP * float(dimensions["player_height_cm"]) / 200.0
	player.velocity = Vector3.ZERO
	_last_position_zone = session.inside_van(player.global_position)
	session.set_in_van_zone(_last_position_zone)
	_status.text = UiText.t("offline.status.recovered")
	if _paused:
		_toggle_pause()


func _finish() -> void:
	if _finished:
		return
	_finished = true
	player.set_controls_active(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_complete_panel.visible = true
	var results: Dictionary = session.mission.results()
	var score: Label = _complete_panel.find_child("Score", true, false) as Label
	if score != null:
		score.text = UiText.tf("offline.complete.score", [int(results.get("stars", 0)),
			int(results.get("required_restored", 0)), int(results.get("required_total", 0))])


func _exit_to_menu() -> void:
	_save_checkpoint()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file(MENU_PATH)
