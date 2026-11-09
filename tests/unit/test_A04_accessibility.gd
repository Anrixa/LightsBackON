extends "res://tests/test_case.gd"
## A04 automation: preference bounds, hint progression and reusable controls.
## Human first-repair and physical-controller runs remain unverified.

const Settings := preload("res://scripts/ui/accessibility_settings.gd")
const Guide := preload("res://scripts/ui/onboarding_guide.gd")
const SettingsPanel := preload("res://scripts/ui/accessibility_panel.gd")
const GuideCard := preload("res://scripts/ui/onboarding_card.gd")
const UiText := preload("res://scripts/ui/ui_text.gd")


func test_A04_preferences_clamp_scale_and_reject_invalid_input() -> void:
	var model: RefCounted = Settings.new()
	assert_eq(model.call("value", "ui_scale_percent"), 100)
	assert_eq(model.call("value", "reduce_flashes"), true)
	assert_true(bool(model.call("set_value", "ui_scale_percent", 170)))
	assert_eq(model.call("value", "ui_scale_percent"), 150)
	assert_true(bool(model.call("set_value", "ui_scale_percent", -10)))
	assert_eq(model.call("value", "ui_scale_percent"), 80)
	assert_false(bool(model.call("set_value", "ui_scale_percent", "huge")))
	assert_false(bool(model.call("set_value", "nonexistent", true)))
	assert_false(bool(model.call("set_value", "reduce_flashes", "yes")))
	var original: Dictionary = model.call("snapshot")
	original["ui_scale_percent"] = 9
	assert_eq(model.call("value", "ui_scale_percent"), 80)


func test_A04_motion_and_flash_preferences_have_safe_hooks() -> void:
	var model: RefCounted = Settings.new()
	assert_eq(float(model.call("camera_motion_multiplier")), 0.0)
	assert_eq(float(model.call("flash_multiplier")), 0.0)
	model.call("set_value", "reduce_camera_motion", false)
	model.call("set_value", "reduce_flashes", false)
	assert_eq(float(model.call("camera_motion_multiplier")), 1.0)
	assert_eq(float(model.call("flash_multiplier")), 1.0)


func test_A04_guide_only_advances_on_ordered_accepted_events() -> void:
	var guide: RefCounted = Guide.new()
	assert_eq(guide.call("step_id"), "MOVE")
	assert_false(bool(guide.call("observe", "repair_restored")))
	assert_true(bool(guide.call("observe", "player_moved")))
	assert_eq(guide.call("step_id"), "MEASURE")
	assert_false(bool(guide.call("observe", "player_moved")))
	assert_true(bool(guide.call("observe", "meter_measured")))
	assert_true(bool(guide.call("observe", "junction_isolated")))
	assert_eq(guide.call("step_id"), "REPAIR")
	assert_true(bool(guide.call("observe", "repair_restored")))
	assert_true(bool(guide.call("completed")))
	assert_eq(guide.call("request_hint_key"), "")


func test_A04_hints_are_progressive_bounded_and_can_be_disabled() -> void:
	var guide: RefCounted = Guide.new()
	assert_eq(guide.call("idle_hint_key", 19.9), "")
	assert_eq(guide.call("idle_hint_key", 20.0), "guide.hint.move.1")
	assert_eq(guide.call("idle_hint_key", 45.0), "guide.hint.move.2")
	assert_eq(guide.call("idle_hint_key", 90.0), "guide.hint.move.3")
	assert_eq(guide.call("request_hint_key"), "guide.hint.move.1")
	assert_eq(guide.call("request_hint_key"), "guide.hint.move.2")
	assert_eq(guide.call("request_hint_key"), "guide.hint.move.3")
	assert_eq(guide.call("request_hint_key"), "guide.hint.move.3")
	guide.call("set_hints_enabled", false)
	assert_eq(guide.call("request_hint_key"), "")
	assert_eq(guide.call("idle_hint_key", 999.0), "")


func test_A04_controls_and_guide_card_instantiate_with_text() -> void:
	var panel: PanelContainer = SettingsPanel.new()
	var card: PanelContainer = GuideCard.new()
	var label: Label = panel.get("scale_label")
	assert_true(not label.text.is_empty())
	var down: Button = panel.get("scale_down")
	down.pressed.emit()
	var model: RefCounted = panel.get("settings")
	assert_eq(model.call("value", "ui_scale_percent"), 90)
	var toggle: CheckBox = panel.get("flash_toggle")
	toggle.toggled.emit(false)
	assert_eq(model.call("value", "reduce_flashes"), false)
	var instruction: Label = card.get("instruction")
	assert_eq(instruction.text, UiText.t("guide.step.move"))
	card.call("observe", "player_moved")
	# DS09: the measure step names the real keys (meter slot, interact) from the live InputMap.
	assert_eq(instruction.text, UiText.tf("guide.step.measure", [UiText.binding("tool_slot_1", UiText.DEVICE_KBM),
		UiText.binding("interact", UiText.DEVICE_KBM)]))
	card.call("show_hint")
	var hint: Label = card.get("hint")
	assert_true(not hint.text.is_empty())
	assert_true(ResourceLoader.exists("res://scenes/ui/accessibility_panel.tscn"))
	assert_true(ResourceLoader.exists("res://scenes/ui/onboarding_card.tscn"))
	panel.free()
	card.free()


func test_A04_every_guide_and_accessibility_key_is_localized() -> void:
	var doc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/accessibility.json"))
	for step: Dictionary in doc["steps"]:
		assert_true(UiText.has(str(step["text_key"])), str(step["id"]))
		for key: String in step["hint_keys"]:
			assert_true(UiText.has(key), key)
	for key: String in ["accessibility.title", "accessibility.scale", "accessibility.scale_down",
			"accessibility.scale_up", "accessibility.reduce_motion", "accessibility.reduce_flashes",
			"accessibility.hints", "guide.more_help", "guide.complete"]:
		assert_true(UiText.has(key), key)


## QA61: tutorial state is a projection of accepted/loaded gameplay, not a
## separately persisted progress flag. Only the first legitimate repair unlocks completion.
func test_QA61_resumed_guide_rechecks_unsaved_meter_evidence() -> void:
	var guide: RefCounted = Guide.new()
	assert_true(bool(guide.call("sync_from_world", false, true, false, true)))
	assert_eq(guide.call("step_id"), "MEASURE",
		"restored isolation cannot skip inspecting again because meter snapshots are not saved")
	assert_false(bool(guide.call("observe", "junction_isolated")),
		"an already-durable isolation event cannot be replayed to bypass measurement")
	assert_true(bool(guide.call("sync_from_world", true, true, false, false)))
	assert_eq(guide.call("step_id"), "REPAIR",
		"new meter evidence plus durable isolation skips the impossible repeated isolate step")
	assert_false(bool(guide.call("sync_from_world", false, false, false, true)),
		"an obsolete checkpoint flag must not move the guide backwards")
	assert_true(bool(guide.call("sync_from_world", false, false, true, true)))
	assert_true(bool(guide.call("completed")), "an already-restored first repair is not retaught")
	assert_eq(guide.call("request_hint_key"), "")


func test_QA61_resumed_card_restarts_hints_only_on_genuine_progress() -> void:
	var card: PanelContainer = GuideCard.new()
	var guide: RefCounted = card.get("guide")
	card.call("show_hint")
	assert_false((card.get("hint") as Label).text.is_empty())
	card.call("sync_from_world", false, false, false, true)
	assert_eq(guide.call("step_id"), "MEASURE")
	assert_eq((card.get("hint") as Label).text, "", "stale movement hints are erased")
	card.call("show_hint")
	assert_false((card.get("hint") as Label).text.is_empty())
	card.call("sync_from_world", false, false, false, true)
	assert_false((card.get("hint") as Label).text.is_empty(),
		"reconciling the same step never erases help the player requested")
	card.call("sync_from_world", true, false, false, false)
	assert_eq(guide.call("step_id"), "ISOLATE")
	card.call("sync_from_world", false, false, true, true)
	assert_eq((card.get("instruction") as Label).text, UiText.t("guide.complete"))
	assert_false((card.get("hint_button") as Button).visible)
	card.free()

