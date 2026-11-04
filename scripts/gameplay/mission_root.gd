extends Node3D
## Offline-first C01 play scene. Instantiates the existing authored Alder graybox,
## a collision-backed first-person worker and the production host-only command path.
## No ENet/Steam gateway is enabled here, and all grid mutations use SessionHost.receive.

const WorldScene := preload("res://scenes/world/alder_street.tscn")
const PlayerController := preload("res://scripts/actors/first_person_controller.gd")
const OfflineSession := preload("res://scripts/gameplay/offline_c01_session.gd")
const TargetSelector := preload("res://scripts/interaction/target_selector.gd")
const FieldHud := preload("res://scripts/ui/field_hud.gd")
const NetworkTablet := preload("res://scripts/ui/network_tablet.gd")
const OnboardingCard := preload("res://scripts/ui/onboarding_card.gd")
const AccessibilityPanel := preload("res://scripts/ui/accessibility_panel.gd")
const AccessibilitySettings := preload("res://scripts/ui/accessibility_settings.gd")
const ThemeTokens := preload("res://scripts/ui/theme_tokens.gd")
const UiText := preload("res://scripts/ui/ui_text.gd")

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
var _overlay: Control
var _pause_panel: PanelContainer
var _complete_panel: PanelContainer
var _status: Label
var _resume_button: Button
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
	session.set_tool(TOOL_LIST[_slot - 1])
	_make_ui()
	session.changed.connect(_refresh_hud)
	session.action_replied.connect(_on_action_replied)
	session.mission_event.connect(_on_mission_event)
	player.moved.connect(_on_player_moved)
	_last_position_zone = session.inside_van(player.global_position)
	session.set_in_van_zone(_last_position_zone)
	_refresh_hud()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


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
	sun.light_energy = float(visual["sun_energy"])
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
	_center(_pause_panel, Vector2(660.0, 510.0))
	var column: VBoxContainer = _pause_panel.find_child("PauseActions", true, false) as VBoxContainer
	column.add_child(accessibility)
	accessibility.visible = false

	_complete_panel = _make_completion_panel()
	_complete_panel.visible = false
	_overlay.add_child(_complete_panel)
	_center(_complete_panel, Vector2(660.0, 370.0))
	settings.apply_to_views(hud, tablet)
	onboarding.set_hints_enabled(bool(settings.value("hints_enabled")))


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
	var column: VBoxContainer = VBoxContainer.new()
	column.name = "PauseActions"
	column.add_theme_constant_override("separation", 14)
	margin.add_child(column)
	_pause_label(column, "offline.pause.title", 34)
	_resume_button = _button(column, "offline.pause.resume", _resume_play)
	_button(column, "offline.pause.accessibility", _toggle_accessibility)
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
	if player.global_position.y < float(_solo_tuning["player"]["fall_recovery_y_m"]):
		_recover_player()


func _update_target() -> void:
	var aim: Camera3D = player.camera
	var selected: String = TargetSelector.select(aim.global_position, -aim.global_transform.basis.z, session.targets(),
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
	return player.camera.global_position.distance_to(target_position) <= float(_interaction["ray_length_cm"]) / 100.0


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
	if event.is_action_pressed("map_meter"):
		_open_tablet()
	elif event.is_action_pressed("interact") or event.is_action_pressed("tool_primary"):
		_interact()
	elif event.is_action_pressed("tool_next"):
		_select_slot(_slot + 1)
	elif event.is_action_pressed("tool_prev"):
		_select_slot(_slot - 1)
	else:
		for i: int in range(4):
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
		"trip":
			_status.text = UiText.t("offline.status.trip")
		"mission_complete":
			_finish()


func _refresh_hud() -> void:
	if hud == null or session == null:
		return
	hud.apply(session.hud_view(_slot, _target, TOOL_LIST[_slot - 1]))


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
	_paused = not _paused
	player.set_controls_active(not _paused)
	_pause_panel.visible = _paused
	if _paused:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_resume_button.grab_focus()
	else:
		accessibility.visible = false
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _resume_play() -> void:
	if _paused:
		_toggle_pause()


func _toggle_accessibility() -> void:
	accessibility.visible = not accessibility.visible


func _settings_changed(_values: Dictionary) -> void:
	settings.apply_to_views(hud, tablet)
	onboarding.set_hints_enabled(bool(settings.value("hints_enabled")))
	_refresh_hud()


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
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file(MENU_PATH)
