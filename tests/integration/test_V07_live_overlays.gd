extends "res://tests/test_case.gd"
## V07 runtime overlay integration: focus, device prompts and live modal input
## dispatch. These are automated engine tests, not a human UX01 controller run.

const Tracker := preload("res://scripts/ui/input_device_tracker.gd")
const UiText := preload("res://scripts/ui/ui_text.gd")
const Persistence := preload("res://scripts/persistence/offline_persistence.gd")

var _scene: Node3D
var _tree: SceneTree


func before_each() -> void:
	_tree = Engine.get_main_loop() as SceneTree
	_scene = (load("res://scenes/mission/mission_root.tscn") as PackedScene).instantiate()
	_tree.root.add_child(_scene)


func after_each() -> void:
	if _scene != null and is_instance_valid(_scene):
		_tree.root.remove_child(_scene)
		_scene.free()
	_scene = null
	_tree.root.get_viewport().gui_release_focus()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func test_V07_intentional_device_detection_ignores_release_and_stick_noise() -> void:
	var pad: InputEventJoypadButton = InputEventJoypadButton.new()
	pad.button_index = JOY_BUTTON_A
	pad.pressed = false
	assert_eq(Tracker.infer(pad), "")
	pad.pressed = true
	assert_eq(Tracker.infer(pad), UiText.DEVICE_PAD)
	var stick: InputEventJoypadMotion = InputEventJoypadMotion.new()
	stick.axis = JOY_AXIS_RIGHT_X
	stick.axis_value = 0.04
	assert_eq(Tracker.infer(stick), "", "stick drift never flickers input hints")
	stick.axis_value = 0.8
	assert_eq(Tracker.infer(stick), UiText.DEVICE_PAD)
	var mouse: InputEventMouseMotion = InputEventMouseMotion.new()
	mouse.relative = Vector2(1, 1)
	assert_eq(Tracker.infer(mouse), "", "pixel jitter is ignored")
	mouse.relative = Vector2(12, -2)
	assert_eq(Tracker.infer(mouse), UiText.DEVICE_KBM)
	var keyboard: InputEventKey = InputEventKey.new()
	keyboard.pressed = true
	keyboard.physical_keycode = KEY_W
	keyboard.echo = false
	assert_eq(Tracker.infer(keyboard), UiText.DEVICE_KBM)
	keyboard.echo = true
	assert_eq(Tracker.infer(keyboard), "")


func test_V07_live_hud_and_tablet_labels_follow_last_device() -> void:
	var hud: Node = _scene.get("hud")
	var tablet: PanelContainer = _scene.get("tablet")
	assert_eq(hud.get("device"), UiText.DEVICE_KBM)
	var pad: InputEventJoypadButton = InputEventJoypadButton.new()
	pad.pressed = true
	pad.button_index = JOY_BUTTON_A
	_scene.call("_input", pad)
	assert_eq(hud.get("device"), UiText.DEVICE_PAD)
	assert_eq(tablet.get("device"), UiText.DEVICE_PAD)
	_scene.call("_input", pad)
	assert_eq(hud.get("device"), UiText.DEVICE_PAD, "same device does not rebuild on every gamepad event")
	var key: InputEventKey = InputEventKey.new()
	key.pressed = true
	key.physical_keycode = KEY_E
	_scene.call("_input", key)
	assert_eq(hud.get("device"), UiText.DEVICE_KBM)
	assert_eq(tablet.get("device"), UiText.DEVICE_KBM)


func test_V07_pause_settings_controller_focus_is_explicit_and_back_is_hierarchical() -> void:
	var player: Node = _scene.get("player")
	var panel: PanelContainer = _scene.get("_pause_panel")
	var accessibility: PanelContainer = _scene.get("accessibility")
	_scene.call("_toggle_pause")
	assert_true(panel.visible)
	assert_false(bool(player.get("enabled")), "no movement while the pause modal is shown")
	assert_eq(_tree.root.gui_get_focus_owner(), _scene.get("_resume_button"))
	_scene.call("_toggle_accessibility")
	assert_true(accessibility.visible)
	assert_eq(_tree.root.gui_get_focus_owner(), accessibility.get("scale_down"),
		"controller enters settings on a concrete button")
	assert_true((accessibility.get("scale_down") as Button).focus_mode == Control.FOCUS_ALL)
	assert_true((accessibility.get("hints_toggle") as CheckBox).focus_mode == Control.FOCUS_ALL)
	_scene.call("_toggle_pause")
	assert_true(panel.visible, "first Back closes settings, not the whole pause overlay")
	assert_false(accessibility.visible)
	assert_eq(_tree.root.gui_get_focus_owner(), _scene.get("_accessibility_button"),
		"focus returns to the settings action on closing the nested panel")
	_scene.call("_toggle_pause")
	assert_false(panel.visible)
	assert_true(bool(player.get("enabled")))
	var focused: Control = _tree.root.gui_get_focus_owner()
	assert_true(focused == null or not panel.is_ancestor_of(focused),
		"hidden pause controls cannot keep controller focus")


func test_V07_paused_or_open_tablet_never_sends_a_world_interaction() -> void:
	var session: RefCounted = _scene.get("session")
	var grid: RefCounted = session.get("grid")
	var before: String = str(grid.call("canonical_hash"))
	var meter: RefCounted = session.get("meter")
	_scene.set("_target", "PANEL_JW")
	var action: InputEventAction = InputEventAction.new()
	action.action = "interact"
	action.pressed = true
	_scene.call("_toggle_pause")
	_scene.call("_unhandled_input", action)
	assert_eq(str(grid.call("canonical_hash")), before)
	assert_false((meter.call("readings", "PANEL_JW", grid) as Dictionary)["_panel"].has("tick"),
		"pause blocks a meter read behind the overlay")
	_scene.call("_toggle_pause")
	_scene.call("_open_tablet")
	var tablet: PanelContainer = _scene.get("tablet")
	assert_true(tablet.visible)
	assert_false(bool((_scene.get("player") as Node).get("enabled")))
	_scene.call("_unhandled_input", action)
	assert_false((meter.call("readings", "PANEL_JW", grid) as Dictionary)["_panel"].has("tick"),
		"tablet blocks a world action behind its full-screen panel")
	tablet.call("close")
	assert_false(tablet.visible)
	assert_true(bool((_scene.get("player") as Node).get("enabled")))


func test_V07_live_tablet_preserves_close_and_ping_focus_on_device_scale_changes() -> void:
	_scene.call("_open_tablet")
	var tablet: PanelContainer = _scene.get("tablet")
	var close: Button = tablet.get("close_button")
	close.grab_focus()
	assert_eq(_tree.root.gui_get_focus_owner(), close)
	var pad: InputEventJoypadButton = InputEventJoypadButton.new()
	pad.pressed = true
	pad.button_index = JOY_BUTTON_A
	_scene.call("_input", pad)
	assert_eq(tablet.get("device"), UiText.DEVICE_PAD)
	assert_eq(_tree.root.gui_get_focus_owner(), tablet.get("close_button"),
		"switching to controller hints does not jump to the map entry")
	var ping: Button = tablet.get("ping_button")
	ping.grab_focus()
	tablet.call("set_ui_scale", 150)
	assert_eq(_tree.root.gui_get_focus_owner(), tablet.get("ping_button"),
		"changing UI scale preserves the focused action")
	tablet.call("close")
	assert_false(tablet.visible)


func test_V07_pause_overlay_reflows_and_scrolls_at_small_viewports() -> void:
	var pause: PanelContainer = _scene.get("_pause_panel")
	var scroll: ScrollContainer = pause.find_child("PauseScroll", true, false) as ScrollContainer
	assert_true(scroll != null, "the pause modal has a bounded scroll container")
	assert_true(scroll.follow_focus, "focus follows keyboard/controller selection past the fold")
	var accessibility: Node = _scene.get("accessibility")
	var settings: RefCounted = _scene.get("settings")
	assert_true(settings.call("set_value", "ui_scale_percent", 150))
	_scene.call("_settings_changed", settings.call("snapshot"), false)
	assert_eq((_scene.get("hud") as Node).get("ui_scale_percent"), 150)
	assert_eq((_scene.get("tablet") as Node).get("ui_scale_percent"), 150)
	assert_true(accessibility.get("theme") != null, "pause settings apply the same effective UI scale")
	for size: Vector2 in [Vector2(960, 540), Vector2(1280, 720), Vector2(1920, 1080)]:
		_scene.call("_layout_modal_panels", size)
		var rect: Rect2 = pause.get_rect()
		var restored: Rect2 = (_scene.get("_complete_panel") as PanelContainer).get_rect()
		var safe: float = float(_scene._ui_tokens["safe_area_px"]) * minf(size.x / 1920.0, size.y / 1080.0)
		var allowed: Vector2 = size - Vector2(safe, safe) * 2.0
		assert_true(rect.size.x <= allowed.x + 2.0 and rect.size.y <= allowed.y + 2.0,
			"pause fits %s: %s inside %s" % [size, rect, allowed])
		assert_true(restored.size.x <= allowed.x + 2.0 and restored.size.y <= allowed.y + 2.0,
			"results fit %s" % str(size))
	_scene.call("_layout_modal_panels", _scene.get_viewport_rect().size)


func test_V07_headless_scene_tests_cannot_replace_windowed_player_progress() -> void:
	if DisplayServer.get_name() != "headless":
		return
	assert_eq(Persistence.runtime_root(), Persistence.HEADLESS_SANDBOX_ROOT)
	var store: RefCounted = _scene.get("_store")
	assert_true(str(store.call("profile_path")).begins_with(Persistence.HEADLESS_SANDBOX_ROOT))
	assert_false(str(store.call("profile_path")).begins_with("user://profiles/"))
