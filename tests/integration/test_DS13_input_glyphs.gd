extends "res://tests/test_case.gd"
## DS13: the glyphs are original vector UI, but the InputMap remains the sole
## source of truth for input. Automated coverage verifies live remaps, semantic
## shapes, last-device transitions, focus, pseudo-locale and responsive layout.
## Physical keyboard/controller/contrast review is an independent local gate.

const InputGlyph := preload("res://scripts/ui/input_glyph.gd")
const InputPrompt := preload("res://scripts/ui/input_prompt.gd")
const FieldHud := preload("res://scripts/ui/field_hud.gd")
const OnboardingCard := preload("res://scripts/ui/onboarding_card.gd")
const ThemeTokens := preload("res://scripts/ui/theme_tokens.gd")
const UiText := preload("res://scripts/ui/ui_text.gd")
const InputDeviceTracker := preload("res://scripts/ui/input_device_tracker.gd")
const MenuScene := preload("res://scenes/menu/main_menu.tscn")
const MissionScene := preload("res://scenes/mission/mission_root.tscn")

var _tree: SceneTree
var _owned: Array[Node] = []
var _tokens: Dictionary = {}
var _old_locale: String = ""


func before_each() -> void:
	_tree = Engine.get_main_loop() as SceneTree
	_tokens = JSON.parse_string(FileAccess.get_file_as_string("res://content/ui/tokens.json"))
	_old_locale = UiText.locale()
	UiText.set_locale(UiText.LOCALE_EN)


func after_each() -> void:
	for node: Node in _owned:
		if is_instance_valid(node):
			_tree.root.remove_child(node)
			node.free()
	_owned.clear()
	UiText.set_locale(_old_locale)
	_tree.root.get_viewport().gui_release_focus()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _own(node: Node) -> Node:
	_tree.root.add_child(node)
	_owned.append(node)
	return node


func _glyph(action: String, device: String = UiText.DEVICE_KBM, scale: float = 100.0) -> InputGlyph:
	var glyph: InputGlyph = InputGlyph.new()
	glyph.configure(action, device, scale, _tokens)
	return _own(glyph) as InputGlyph


func _device_button(button: JoyButton = JOY_BUTTON_A) -> InputEventJoypadButton:
	var event: InputEventJoypadButton = InputEventJoypadButton.new()
	event.button_index = button
	event.pressed = true
	return event


func test_DS13_keyboard_cap_uses_real_first_binding_and_has_no_input_authority() -> void:
	var glyph: InputGlyph = _glyph("interact")
	assert_eq(glyph.glyph_info()["kind"], "keyboard")
	assert_eq(glyph.glyph_info()["label"], UiText.binding("interact", UiText.DEVICE_KBM))
	assert_eq(glyph.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	assert_eq(glyph.focus_mode, Control.FOCUS_NONE)
	assert_true(glyph.custom_minimum_size.x >= 42.0)
	assert_true(glyph.custom_minimum_size.y > 30.0)
	assert_eq(glyph.get_meta("binding_label"), UiText.binding("interact", UiText.DEVICE_KBM))


func test_DS13_mouse_button_has_mouse_shape_not_a_keycap() -> void:
	var glyph: InputGlyph = _glyph("ping")
	assert_eq(glyph.glyph_info()["kind"], "mouse")
	assert_eq(glyph.glyph_info()["code"], MOUSE_BUTTON_MIDDLE)
	assert_eq(glyph.glyph_info()["label"], UiText.binding("ping", UiText.DEVICE_KBM))
	assert_eq(glyph.glyph_info()["label"], "MMB")


func test_DS13_gamepad_face_button_and_shoulder_do_not_use_platform_trademarks() -> void:
	var primary: InputGlyph = _glyph("interact", UiText.DEVICE_PAD)
	var shoulder: InputGlyph = _glyph("map_meter", UiText.DEVICE_PAD)
	assert_eq(primary.glyph_info()["kind"], "button")
	assert_eq(primary.glyph_info()["label"], "A")
	assert_eq(shoulder.glyph_info()["kind"], "shoulder")
	assert_eq(shoulder.glyph_info()["label"], UiText.binding("map_meter", UiText.DEVICE_PAD))
	assert_true(primary.glyph_info()["label"] != "Cross" and primary.glyph_info()["label"] != "Circle")


func test_DS13_dpad_and_analog_trigger_use_distinct_project_drawn_families() -> void:
	var next: Dictionary = InputGlyph.describe("tool_next", UiText.DEVICE_PAD)
	assert_eq(next["kind"], "dpad")
	var trigger: Dictionary = InputGlyph.describe("tool_primary", UiText.DEVICE_PAD)
	assert_eq(trigger["kind"], "shoulder")
	var stick: Dictionary = InputGlyph.describe("move_forward", UiText.DEVICE_PAD)
	assert_true(stick["kind"] == "stick" or stick["kind"] == "unbound")
	# Each kind derives from the actual mapped event, not a fixed action-name
	# table; changing its input device always rebuilds the semantic shape.


func test_DS13_missing_action_is_explicitly_unbound_not_a_fake_E_or_A() -> void:
	var glyph: InputGlyph = _glyph("DS13_ACTION_THAT_DOES_NOT_EXIST")
	assert_eq(glyph.glyph_info()["kind"], "unbound")
	assert_eq(glyph.glyph_info()["label"], UiText.t("input.unbound"))
	glyph.configure("DS13_ACTION_THAT_DOES_NOT_EXIST", UiText.DEVICE_PAD, 100.0, _tokens)
	assert_eq(glyph.glyph_info()["kind"], "unbound")


func test_DS13_keyboard_remapping_refreshes_existing_visible_glyph_without_rebuild() -> void:
	var glyph: InputGlyph = _glyph("interact")
	var original: Array[InputEvent] = InputMap.action_get_events("interact")
	InputMap.action_erase_events("interact")
	var change: InputEventKey = InputEventKey.new()
	change.physical_keycode = KEY_F
	InputMap.action_add_event("interact", change)
	glyph._process(0.3)
	assert_eq(glyph.glyph_info()["label"], "F")
	assert_eq(glyph.get_meta("binding_label"), "F")
	assert_eq(UiText.binding("interact", UiText.DEVICE_KBM), "F")
	InputMap.action_erase_events("interact")
	for event: InputEvent in original:
		InputMap.action_add_event("interact", event)
	glyph.refresh_binding()
	assert_eq(glyph.glyph_info()["label"], "E")
	assert_eq(glyph.action, "interact", "a visual remap never modifies the action ID")


func test_DS13_controller_remapping_changes_glyph_type_when_button_becomes_dpad() -> void:
	var glyph: InputGlyph = _glyph("interact", UiText.DEVICE_PAD)
	var original: Array[InputEvent] = InputMap.action_get_events("interact")
	InputMap.action_erase_events("interact")
	var dpad: InputEventJoypadButton = _device_button(JOY_BUTTON_DPAD_RIGHT)
	InputMap.action_add_event("interact", dpad)
	glyph.refresh_binding()
	assert_eq(glyph.glyph_info()["kind"], "dpad")
	assert_eq(glyph.glyph_info()["label"], UiText.binding("interact", UiText.DEVICE_PAD))
	InputMap.action_erase_events("interact")
	for event: InputEvent in original:
		InputMap.action_add_event("interact", event)
	glyph.refresh_binding()
	assert_eq(glyph.glyph_info()["kind"], "button")
	assert_eq(glyph.glyph_info()["label"], "A")


func test_DS13_existing_device_tracker_discards_releases_noise_and_mouse_jitter() -> void:
	var glyph: InputGlyph = _glyph("ping")
	var release: InputEventJoypadButton = _device_button()
	release.pressed = false
	assert_eq(InputDeviceTracker.infer(release), "")
	var drift: InputEventJoypadMotion = InputEventJoypadMotion.new()
	drift.axis = JOY_AXIS_LEFT_X
	drift.axis_value = 0.05
	assert_eq(InputDeviceTracker.infer(drift), "")
	var mouse: InputEventMouseMotion = InputEventMouseMotion.new()
	mouse.relative = Vector2(1, 1)
	assert_eq(InputDeviceTracker.infer(mouse), "")
	assert_eq(glyph.glyph_info()["kind"], "mouse", "idle input cannot switch a visible glyph")
	assert_eq(InputDeviceTracker.infer(_device_button()), UiText.DEVICE_PAD)


func test_DS13_hud_prompt_and_hints_use_original_glyph_components() -> void:
	var hud: FieldHud = FieldHud.new()
	hud.size = Vector2(1920, 1080)
	_own(hud)
	hud.apply({
		"district_key": "district.alder_street",
		"contract_key": "contract.c01",
		"objectives": [],
		"crew": [],
		"tools": ["meter", "screwdriver"],
		"selected_slot": 1,
		"event": {},
		"prompt": {"action": "interact", "object_key": "prompt.object.panel_jw",
			"verb_key": "prompt.verb.inspect"}
	})
	var action: InputPrompt = hud.find_child("PromptAction", true, false) as InputPrompt
	assert_true(action != null)
	assert_eq(action.glyph.glyph_info()["label"], "E")
	assert_eq(action.caption.text, UiText.t("prompt.verb.inspect"))
	assert_true(hud.find_child("Hint_map_meter", true, false) is InputPrompt)
	assert_true(hud.find_child("Hint_ping", true, false) is InputPrompt)
	hud.set_device(UiText.DEVICE_PAD)
	action = hud.find_child("PromptAction", true, false) as InputPrompt
	assert_eq(action.glyph.glyph_info()["label"], "A")
	assert_eq((hud.find_child("Hint_ping", true, false) as InputPrompt).glyph.glyph_info()["label"], "LB")


func test_DS13_onboarding_glyphs_follow_the_step_device_and_live_binding() -> void:
	var card: OnboardingCard = OnboardingCard.new()
	_own(card)
	assert_true(card.find_child("HintGlyph", true, false) is InputGlyph)
	assert_eq((card.find_child("HintGlyph", true, false) as InputGlyph).glyph_info()["label"], "H")
	card.observe("player_moved")
	assert_true(card.instruction.text.contains("1"))
	var strip: HFlowContainer = card.find_child("InstructionGlyphs", true, false) as HFlowContainer
	assert_eq(strip.get_child_count(), 2)
	assert_eq((strip.get_child(0) as InputGlyph).glyph_info()["label"], "1")
	assert_eq((strip.get_child(1) as InputGlyph).glyph_info()["label"], "E")
	card.set_device(UiText.DEVICE_PAD)
	assert_eq(strip.get_child_count(), 2)
	assert_eq((strip.get_child(1) as InputGlyph).glyph_info()["label"], "A")
	assert_eq(card.hint_button.text, UiText.t("guide.more_help"), "no bracketed fake hint label")
	assert_false((card.find_child("HintGlyph", true, false) as InputGlyph).focus_mode == Control.FOCUS_ALL)


func test_DS13_main_menu_legend_is_device_aware_scrollable_and_remapping_based() -> void:
	var menu: Control = MenuScene.instantiate() as Control
	_own(menu)
	var legend: HFlowContainer = menu.find_child("ControlsGlyphLegend", true, false) as HFlowContainer
	assert_true(legend != null)
	assert_eq(legend.get_child_count(), 6)
	assert_true((menu.get("_scroll") as ScrollContainer).follow_focus)
	var interact: InputPrompt = legend.find_child("Control_interact", true, false) as InputPrompt
	assert_eq(interact.glyph.glyph_info()["label"], "E")
	menu._input(_device_button())
	interact = legend.find_child("Control_interact", true, false) as InputPrompt
	assert_eq(interact.glyph.glyph_info()["label"], "A")
	assert_eq(menu.get("_last_device"), UiText.DEVICE_PAD)
	var jitter: InputEventMouseMotion = InputEventMouseMotion.new()
	jitter.relative = Vector2(0.3, 0.4)
	menu._input(jitter)
	assert_eq(menu.get("_last_device"), UiText.DEVICE_PAD)
	menu.call("_layout_for_size", Vector2(1280, 720))
	assert_true(legend.get_child_count() == 6)


func test_DS13_tablet_inspect_ping_close_glyphs_preserve_controller_focus() -> void:
	var mission: Node3D = MissionScene.instantiate() as Node3D
	_own(mission)
	mission.call("_open_tablet")
	var tablet: PanelContainer = mission.get("tablet") as PanelContainer
	assert_true(tablet != null and tablet.visible)
	tablet.select("JW")  # select an inspectable junction, not a source without a meter panel
	var close: InputGlyph = tablet.find_child("CloseGlyph", true, false) as InputGlyph
	var ping: InputGlyph = tablet.find_child("PingGlyph", true, false) as InputGlyph
	var inspect: InputPrompt = tablet.find_child("InspectGlyphRow", true, false) as InputPrompt
	assert_true(close != null and ping != null and inspect != null)
	assert_eq(close.glyph_info()["label"], UiText.binding("map_meter", UiText.DEVICE_KBM))
	assert_eq(ping.glyph_info()["label"], UiText.binding("ping", UiText.DEVICE_KBM))
	assert_eq(inspect.glyph.glyph_info()["label"], UiText.binding("ui_accept", UiText.DEVICE_KBM))
	tablet.close_button.grab_focus()
	tablet.set_device(UiText.DEVICE_PAD)
	assert_eq(_tree.root.gui_get_focus_owner(), tablet.close_button)
	assert_eq((tablet.find_child("CloseGlyph", true, false) as InputGlyph).glyph_info()["label"],
		UiText.binding("map_meter", UiText.DEVICE_PAD))
	assert_eq((tablet.find_child("PingGlyph", true, false) as InputGlyph).glyph_info()["label"], "LB")
	assert_eq((tablet.find_child("InspectGlyphRow", true, false) as InputPrompt).glyph.glyph_info()["label"], "A")
	assert_eq(tablet.close_button.text, UiText.t("tablet.close"))
	assert_eq((tablet.find_child("CloseGlyph", true, false) as InputGlyph).focus_mode, Control.FOCUS_NONE)
	# The overlay glyph must not cover the caption: the button reserves the glyph's footprint before its text.
	for b: Button in [tablet.close_button, tablet.ping_button]:
		var g: InputGlyph = b.find_child("*Glyph", false, false) as InputGlyph
		assert_true(b.icon != null and float(b.icon.get_width()) >= g.offset_right,
			"%s reserves %s px for its glyph" % [b.name, g.offset_right])
	tablet.close()


func test_DS13_pseudo_locale_and_higher_scale_keep_glyph_captions_localized() -> void:
	UiText.set_locale(UiText.LOCALE_PSEUDO)
	var prompt: InputPrompt = InputPrompt.new()
	_own(prompt)
	prompt.configure("interact", UiText.t("hud.hint.tablet"), UiText.DEVICE_PAD, 150.0, _tokens)
	assert_eq(prompt.glyph.glyph_info()["label"], UiText.binding("interact", UiText.DEVICE_PAD),
		"the pseudo-locale transforms the same live binding used elsewhere")
	assert_true(prompt.caption.text.contains("~"))
	assert_true(prompt.glyph.custom_minimum_size.y > 42.0)
	assert_true(prompt.caption.mouse_filter == Control.MOUSE_FILTER_IGNORE)
	assert_true(prompt.glyph.focus_mode == Control.FOCUS_NONE)
