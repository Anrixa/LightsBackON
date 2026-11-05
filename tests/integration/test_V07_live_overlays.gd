extends "res://tests/test_case.gd"
## V07 runtime overlay integration: focus, device prompts and live modal input
## dispatch. These are automated engine tests, not a human UX01 controller run.

const Tracker := preload("res://scripts/ui/input_device_tracker.gd")
const UiText := preload("res://scripts/ui/ui_text.gd")
const Persistence := preload("res://scripts/persistence/offline_persistence.gd")

var _scene: Node3D
var _tree: SceneTree
var _qa63_root: String = ""


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
	if _qa63_root != "":
		_qa63_remove_tree(_qa63_root)
		_qa63_root = ""


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


func test_V07_restored_minimum_ui_scale_enters_accessibility_on_enabled_button() -> void:
	var model: RefCounted = _scene.get("settings")
	var panel: PanelContainer = _scene.get("accessibility")
	assert_true(model.call("set_value", "ui_scale_percent", 80))
	_scene.call("_settings_changed", model.call("snapshot"), false)
	assert_true((panel.get("scale_down") as Button).disabled, "scale-down disabled at its 80% lower bound")
	assert_false((panel.get("scale_up") as Button).disabled)
	assert_eq((panel.get("scale_label") as Label).text, UiText.tf("accessibility.scale", [80]),
		"the panel reflects actual loaded preferences, not startup defaults")
	_scene.call("_toggle_pause")
	_scene.call("_toggle_accessibility")
	assert_eq(_tree.root.gui_get_focus_owner(), panel.get("scale_up"),
		"controller focus enters on the first enabled action at the lower bound")
	_scene.call("_toggle_pause")
	_scene.call("_toggle_pause")


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
		var safe: float = float((_scene.get("_ui_tokens") as Dictionary)["safe_area_px"]) * minf(size.x / 1920.0, size.y / 1080.0)
		var allowed: Vector2 = size - Vector2(safe, safe) * 2.0
		assert_true(rect.size.x <= allowed.x + 2.0 and rect.size.y <= allowed.y + 2.0,
			"pause fits %s: %s inside %s" % [size, rect, allowed])
		assert_true(restored.size.x <= allowed.x + 2.0 and restored.size.y <= allowed.y + 2.0,
			"results fit %s" % str(size))
	_scene.call("_layout_modal_panels", _scene.get_viewport().get_visible_rect().size)


func test_V07_headless_scene_tests_cannot_replace_windowed_player_progress() -> void:
	if DisplayServer.get_name() != "headless":
		return
	assert_eq(Persistence.runtime_root(), Persistence.HEADLESS_SANDBOX_ROOT)
	var store: RefCounted = _scene.get("_store")
	assert_true(str(store.call("profile_path")).begins_with(Persistence.HEADLESS_SANDBOX_ROOT))
	assert_false(str(store.call("profile_path")).begins_with("user://profiles/"))


## QA60: live action feedback must convey gameplay, not internal command noise.
func test_QA60_heartbeat_and_tool_ack_cannot_replace_real_repair_feedback() -> void:
	var banner: Label = _scene.get("_status")
	_scene.call("_on_action_replied", {"type": "inspect", "payload": {}}, {"ok": true})
	var meaningful: String = banner.text
	assert_eq(meaningful, UiText.tf("offline.status.accepted", [UiText.t("offline.verb.measure")]))
	_scene.call("_on_action_replied", {"type": "heartbeat", "payload": {}}, {"ok": true})
	assert_eq(banner.text, meaningful, "an accepted 2-second lock heartbeat is not a new player action")
	_scene.call("_on_action_replied", {"type": "heartbeat", "payload": {}},
		{"ok": false, "message": "Synthetic heartbeat rejected"})
	assert_eq(banner.text, meaningful, "internal heartbeat errors must not mask the repair instruction")
	_scene.call("_select_slot", 2)
	assert_eq(banner.text, meaningful, "equipping a tool already changes the loadout and must not mask feedback")
	assert_eq(int(_scene.get("_slot")), 2)


func test_QA60_action_refusal_is_legible_and_transient_when_playing() -> void:
	var banner: Label = _scene.get("_status")
	var tuning: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/offline_solo.json"))
	var duration: float = float(tuning["feedback"]["important_seconds"])
	_scene.call("_on_action_replied", {"type": "repair_step", "payload": {"step": "test"}},
		{"ok": false, "message": "Move closer to the panel"})
	assert_eq(banner.text, "Move closer to the panel", "the actual host refusal is shown, not a generic OK")
	assert_true(is_equal_approx(float(_scene.get("_feedback_remaining_s")), duration))
	_scene.call("_process", duration * 0.5)
	assert_false(banner.text.is_empty(), "a host refusal must remain visible long enough to read")
	_scene.call("_process", duration * 0.6)
	assert_eq(banner.text, "", "a stale refusal must not permanently cover the first repair")


func test_QA60_feedback_clock_does_not_expire_behind_pause_or_tablet() -> void:
	var banner: Label = _scene.get("_status")
	var duration: float = float((JSON.parse_string(FileAccess.get_file_as_string(
		"res://content/offline_solo.json")) as Dictionary)["feedback"]["normal_seconds"])
	_scene.call("_show_feedback", "Read the panel", false, false)
	assert_eq(banner.text, "Read the panel")
	_scene.call("_toggle_pause")
	_scene.call("_process", duration + 1.0)
	assert_eq(banner.text, "Read the panel", "pause should not consume an unseen status timeout")
	_scene.call("_toggle_pause")
	_scene.call("_open_tablet")
	_scene.call("_process", duration + 1.0)
	assert_eq(banner.text, "Read the panel", "tablet should not consume an unseen status timeout")
	(_scene.get("tablet") as PanelContainer).call("close")
	_scene.call("_process", duration + 1.0)
	assert_eq(banner.text, "", "feedback expires only after the player returns to the world")


func test_QA60_save_failure_remains_visible_after_activity_and_timeout() -> void:
	var banner: Label = _scene.get("_status")
	_scene.call("_show_feedback", "Saving disabled: failure", true, true)
	_scene.call("_on_action_replied", {"type": "repair_step", "payload": {"step": "isolate"}}, {"ok": true})
	_scene.call("_on_mission_event", {"type": "trip"})
	_scene.call("_process", 120.0)
	assert_eq(banner.text, "Saving disabled: failure",
		"critical lost-save protection must survive ordinary actions, grid events and timeout")
	assert_true(bool(_scene.get("_feedback_persistent")))


func test_QA60_feedback_banner_obeys_720p_and_narrow_safe_area() -> void:
	var banner: Label = _scene.get("_status")
	var tokens: Dictionary = _scene.get("_ui_tokens")
	for dimensions: Vector2 in [Vector2(440, 350), Vector2(960, 540),
			Vector2(1280, 720), Vector2(1920, 1080)]:
		_scene.call("_layout_onboarding", dimensions)
		var safe: float = float((preload("res://scripts/ui/theme_tokens.gd")).safe_area(tokens, dimensions))
		assert_true(banner.offset_right - banner.offset_left <= dimensions.x - safe * 2.0 + 0.001,
			"feedback must not exceed viewport safe width at %s" % str(dimensions))
		assert_true(banner.offset_bottom < dimensions.y * 0.75,
			"feedback is displayed above the central interaction zone")
	_scene.call("_layout_onboarding", _scene.get_viewport().get_visible_rect().size)


func test_QA61_live_checkpoint_guidance_does_not_replay_durable_steps() -> void:
	var card: PanelContainer = _scene.get("onboarding")
	var guide: RefCounted = card.get("guide")
	var session: RefCounted = _scene.get("session")
	assert_eq(guide.call("step_id"), "MOVE", "new shift begins at real movement")
	_scene.call("_sync_onboarding_progress", true)
	assert_eq(guide.call("step_id"), "MEASURE", "a resumed shift never restarts at the van")
	# A controlled presentation fixture models durable isolation from a restored
	# checkpoint. The meter snapshot remains intentionally absent on disk.
	var service: RefCounted = session.get("interaction")
	var states: Dictionary = service.get("_state")
	states["R_JW_FUSE"] = 2
	service.set("_state", states)
	_scene.call("_sync_onboarding_progress", true)
	assert_eq(guide.call("step_id"), "MEASURE",
		"isolated-but-unmeasured progress must ask for a fresh reading")
	var meter: RefCounted = session.get("meter")
	assert_true(bool((meter.call("inspect", "PANEL_JW", session.get("grid")) as Dictionary)["ok"]))
	_scene.call("_sync_onboarding_progress", false)
	assert_eq(guide.call("step_id"), "REPAIR",
		"fresh authoritative meter evidence and durable isolation resume the repair")
	assert_eq((card.get("instruction") as Label).text, UiText.t("guide.step.repair"))



## QA62: mission completion must be an actionable modal, not a mouse-only dead end.
func test_QA62_results_grab_controller_focus_and_block_world_input() -> void:
	var results: PanelContainer = _scene.get("_complete_panel")
	var player: Node = _scene.get("player")
	var session: RefCounted = _scene.get("session")
	var grid: RefCounted = session.get("grid")
	_scene.set("_target", "PANEL_JW")
	var initial_hash: String = str(grid.call("canonical_hash"))
	_scene.call("_finish")
	var menu: Button = results.find_child("ReturnToMenu", true, false) as Button
	assert_true(results.visible)
	assert_true(menu != null, "results must expose a named, keyboard/controller-focusable exit")
	assert_eq(_tree.root.gui_get_focus_owner(), menu, "results are navigable without a pointer")
	assert_false(bool(player.get("enabled")), "completion must not reactivate player movement")
	assert_eq(Input.mouse_mode, Input.MOUSE_MODE_VISIBLE)
	var action: InputEventAction = InputEventAction.new()
	action.action = "interact"
	action.pressed = true
	_scene.call("_unhandled_input", action)
	assert_eq(str(grid.call("canonical_hash")), initial_hash,
		"world interactions cannot leak through the completed results overlay")
	_scene.call("_finish")
	assert_eq(_tree.root.gui_get_focus_owner(), menu, "duplicate completion leaves focus intact")


func test_QA62_completion_closes_visible_tablet_before_focusing_results() -> void:
	_scene.call("_open_tablet")
	var tablet: PanelContainer = _scene.get("tablet")
	assert_true(tablet.visible)
	assert_false(bool((_scene.get("player") as Node).get("enabled")))
	_scene.call("_on_mission_event", {"type": "mission_complete"})
	var results: PanelContainer = _scene.get("_complete_panel")
	var menu: Button = results.find_child("ReturnToMenu", true, false) as Button
	assert_false(tablet.visible, "a full-screen tablet cannot obstruct finished results")
	assert_true(results.visible)
	assert_eq(_tree.root.gui_get_focus_owner(), menu,
		"closing the tablet must not restore stale hidden focus over the results")
	assert_false(bool((_scene.get("player") as Node).get("enabled")),
		"tablet closed callback cannot re-enable movement after completion")


func test_QA62_completion_replaces_paused_modal_without_hidden_focus() -> void:
	_scene.call("_toggle_pause")
	_scene.call("_toggle_accessibility")
	assert_true((_scene.get("_pause_panel") as PanelContainer).visible)
	assert_true((_scene.get("accessibility") as PanelContainer).visible)
	_scene.call("_finish")
	var results: PanelContainer = _scene.get("_complete_panel")
	var menu: Button = results.find_child("ReturnToMenu", true, false) as Button
	assert_false((_scene.get("_pause_panel") as PanelContainer).visible)
	assert_false((_scene.get("accessibility") as PanelContainer).visible)
	assert_true(results.visible)
	assert_eq(_tree.root.gui_get_focus_owner(), menu)
	assert_false(bool((_scene.get("player") as Node).get("enabled")))


## QA64: the tablet is a read-only modal, not a pause of authoritative time.
## Its host tick must retain the normal lock-liveness schedule while open.
func test_QA64_tablet_keeps_repair_heartbeat_clock_advancing() -> void:
	var session: RefCounted = _scene.get("session")
	var player: Node = _scene.get("player")
	_scene.set("_heartbeat_accumulator", 0.0)
	_scene.call("_open_tablet")
	var before_tick: int = int(session.get("_tick"))
	for _i: int in 6:
		_scene.call("_physics_process", 0.25)
	assert_true((_scene.get("tablet") as PanelContainer).visible)
	assert_false(bool(player.get("enabled")), "tablet still blocks world controls")
	assert_true(int(session.get("_tick")) >= before_tick + 14,
		"authoritative host time continues underneath the tablet")
	var remaining: float = float(_scene.get("_heartbeat_accumulator"))
	assert_true(remaining > 0.2 and remaining < 0.9,
		"heartbeat period must elapse and restart while tablet is visible, got %s" % str(remaining))
	(_scene.get("tablet") as PanelContainer).call("close")


## QA63: recover_self acknowledges before the physical player is teleported.
## A pre-teleport checkpoint write on a fallen/out-of-bounds transform fails
## BAD_VIEW and permanently disables otherwise healthy persistence.
func test_QA63_fall_recovery_saves_only_the_relocated_player_position() -> void:
	var store: Persistence = _qa63_isolated_store()
	var player: CharacterBody3D = _scene.get("player") as CharacterBody3D
	var session: RefCounted = _scene.get("session")
	var grid: RefCounted = session.get("grid")
	var original_hash: String = str(grid.call("canonical_hash"))
	player.global_position = Vector3(-8.0, -5.0, -8.0)
	assert_false(bool(store.checkpoint_status().get("available", false)))
	_scene.call("_recover_player")
	var position: Vector3i = player.call("position_cm")
	var saved: Dictionary = store.checkpoint_status()
	assert_true(bool(_scene.get("_save_enabled")),
		"the invalid old position cannot disable future checkpoints")
	assert_true(saved.get("ok", false), str(saved))
	assert_true(saved.get("available", false), "successful recovery must create a durable checkpoint")
	assert_eq((saved.get("view", {}) as Dictionary).get("position_cm", []),
		[position.x, position.y, position.z], "reopening the shift must start at the recovered van spawn")
	assert_eq(str(grid.call("canonical_hash")), original_hash, "recovering a player does not reset the grid")
	assert_eq(player.velocity, Vector3.ZERO, "no falling velocity carries over after recovery")


func test_QA63_pause_recover_replaces_old_position_before_resume() -> void:
	var store: Persistence = _qa63_isolated_store()
	var player: CharacterBody3D = _scene.get("player") as CharacterBody3D
	player.global_position = Vector3(44.0, 1.0, 23.0)
	_scene.call("_toggle_pause")
	var before: Dictionary = store.checkpoint_status()
	assert_true(before.get("available", false), "pause saves the pre-recovery checkpoint")
	var old_position: Array = (before.get("view", {}) as Dictionary).get("position_cm", [])
	_scene.call("_recover_player")
	var after: Dictionary = store.checkpoint_status()
	var position: Vector3i = player.call("position_cm")
	assert_true(bool(_scene.get("_save_enabled")))
	assert_ne((after.get("view", {}) as Dictionary).get("position_cm", []), old_position,
		"pause-menu recovery cannot keep the last location in the save")
	assert_eq((after.get("view", {}) as Dictionary).get("position_cm", []),
		[position.x, position.y, position.z], "save the new location before dismissing the pause menu")
	assert_false(bool(_scene.get("_paused")), "successful pause-menu recovery resumes play")


func _qa63_isolated_store() -> Persistence:
	# Test saves must never mutate the user's normal profile or other suites'
	# headless checkpoint sandbox.
	_qa63_root = "user://test_runtime/qa63_%d_%d" % [Time.get_ticks_usec(), randi()]
	var store: Persistence = Persistence.new()
	var result: Dictionary = store.initialize(_qa63_root)
	assert_true(result.get("ok", false), str(result))
	_scene.set("_store", store)
	_scene.set("_save_enabled", true)
	return store


static func _qa63_remove_tree(path: String) -> void:
	var dir: DirAccess = DirAccess.open(path)
	if dir == null:
		return
	for filename: String in dir.get_files():
		DirAccess.remove_absolute(path.path_join(filename))
	for directory: String in dir.get_directories():
		_qa63_remove_tree(path.path_join(directory))
	DirAccess.remove_absolute(path)
