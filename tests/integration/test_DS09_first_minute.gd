extends "res://tests/test_case.gd"
## DS09 first-minute clarity (docs/design/DS07-design-plan.md section DS09, docs/evidence/DS09.md):
## 0. 3D resolution setting (Auto/100/85/75/50 %, bilinear root-viewport scaling, saved with the preferences);
## 1. shader warm-up behind the loading card, holding host time and input until it is done;
## 2. onboarding names the west junction cabinet, objective card Now/Later, crew "You" once and hidden in solo, all five
##    tools on the bar, the tablet fits the C01 network at zoom 1.0, `unknown` >= 5:1 on the panel, and the scripted
##    first-reading driver stays internal-only.
## Frame times, compile stalls and what a person sees are measured on the GPU (evidence file), not here.

const Settings := preload("res://scripts/ui/accessibility_settings.gd")
const SettingsPanel := preload("res://scripts/ui/accessibility_panel.gd")
const ShaderWarmup := preload("res://scripts/world/shader_warmup.gd")
const LoadingCard := preload("res://scripts/ui/loading_card.gd")
const GuideCard := preload("res://scripts/ui/onboarding_card.gd")
const HudPresenter := preload("res://scripts/ui/hud_presenter.gd")
const FieldHud := preload("res://scripts/ui/field_hud.gd")
const NetworkTablet := preload("res://scripts/ui/network_tablet.gd")
const IntentOutbox := preload("res://scripts/ui/intent_outbox.gd")
const ThemeTokens := preload("res://scripts/ui/theme_tokens.gd")
const UiText := preload("res://scripts/ui/ui_text.gd")
const Fixture := preload("res://tests/support/ui_fixture.gd")
const Runner := preload("res://tests/support/solution_runner.gd")
const FirstReading := preload("res://scripts/diagnostics/ds09_first_reading_driver.gd")
const MissionDirector := preload("res://scripts/simulation/mission_director.gd")

var _tree: SceneTree
var _owned: Array[Node] = []
var _scale_before: float = 1.0
var _mode_before: Viewport.Scaling3DMode = Viewport.SCALING_3D_MODE_BILINEAR


func before_each() -> void:
	_tree = Engine.get_main_loop() as SceneTree
	_scale_before = _tree.root.scaling_3d_scale
	_mode_before = _tree.root.scaling_3d_mode
	UiText.set_locale(UiText.LOCALE_EN)


func after_each() -> void:
	for n: Node in _owned:
		if is_instance_valid(n):
			n.get_parent().remove_child(n)
			n.free()
	_owned.clear()
	_tree.root.scaling_3d_scale = _scale_before
	_tree.root.scaling_3d_mode = _mode_before
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _own(n: Node) -> Node:
	_tree.root.add_child(n)
	_owned.append(n)
	return n


# ---------- 0. 3D resolution ----------

func test_DS09_render_scale_options_default_to_auto_and_auto_follows_the_pixel_budget() -> void:
	var model: Settings = Settings.new()
	assert_eq(model.render_scale_options(), [0, 100, 85, 75, 50] as Array[int])
	assert_true(model.render_scale_is_auto(), "Auto is the default")
	# DS08 Intel UHD bench: 100 % at 2560x1600 = 14.0 ms (target <= 14 ms missed in the harness), 75 % = 10.8 ms.
	assert_eq(model.resolved_render_scale_percent(Vector2(2560, 1600)), 75)
	assert_eq(model.resolved_render_scale_percent(Vector2(1920, 1080)), 100)
	assert_eq(model.resolved_render_scale_percent(Vector2(1920, 1200)), 100)
	assert_eq(model.resolved_render_scale_percent(Vector2(2560, 1440)), 75)
	assert_eq(model.resolved_render_scale_percent(Vector2(3840, 2160)), 50)
	assert_true(model.set_value("render_scale_percent", 85))
	assert_eq(model.resolved_render_scale_percent(Vector2(2560, 1600)), 85, "a fixed choice is used as is")


func test_DS09_render_scale_refuses_values_outside_the_list() -> void:
	var model: Settings = Settings.new()
	for bad: Variant in [60, 101, -1, 75.0, "75", true]:
		assert_false(model.set_value("render_scale_percent", bad), "refused: %s" % str(bad))
	assert_true(model.render_scale_is_auto(), "a refused value changes nothing")


func test_DS09_older_profiles_without_the_key_read_as_auto_and_new_ones_roundtrip() -> void:
	var model: Settings = Settings.new()
	assert_true(model.set_value("ui_scale_percent", 120))
	var older: Dictionary = model.snapshot()
	older.erase("render_scale_percent")
	var restored: Settings = Settings.new()
	assert_true(restored.restore_snapshot(older), "a pre-DS09 profile still loads (no save migration)")
	assert_eq(int(restored.value("ui_scale_percent")), 120)
	assert_true(restored.render_scale_is_auto())
	assert_true(model.set_value("render_scale_percent", 50))
	var again: Settings = Settings.new()
	assert_true(again.restore_snapshot(model.snapshot()))
	assert_eq(int(again.value("render_scale_percent")), 50)
	var broken: Dictionary = model.snapshot()
	broken["render_scale_percent"] = 60
	assert_false(again.restore_snapshot(broken), "an unknown 3D resolution makes the record invalid, as before")
	assert_eq(int(again.value("render_scale_percent")), 50, "nothing changed")


func test_DS09_settings_panel_has_a_focusable_render_scale_control() -> void:
	var panel: PanelContainer = _own(SettingsPanel.new()) as PanelContainer
	var model: Settings = Settings.new()
	panel.call("set_settings", model)
	var buttons: Array[Button] = panel.get("render_buttons")
	assert_eq(buttons.size(), 5)
	var emitted: Array[Dictionary] = []
	panel.connect("settings_changed", func(v: Dictionary) -> void: emitted.append(v))
	for b: Button in buttons:
		assert_eq(b.focus_mode, Control.FOCUS_ALL, "controller can reach %s" % b.text)
		assert_true(b.custom_minimum_size.x >= 48.0 and b.custom_minimum_size.y >= 48.0, "48 px target")
	assert_eq(buttons[0].text, UiText.t("settings.render_scale.auto"))
	assert_true(buttons[0].button_pressed, "Auto shows as chosen")
	buttons[3].pressed.emit()  # 75 %
	assert_eq(int(model.value("render_scale_percent")), 75)
	assert_eq(emitted.size(), 1)
	assert_true(buttons[3].button_pressed and not buttons[0].button_pressed)
	var detail: Label = panel.get("render_detail")
	assert_true(detail.text.contains("75%"), "the detail line names the percentage in use: %s" % detail.text)


func test_DS09_mission_applies_the_render_scale_to_the_root_viewport() -> void:
	var scene: Node = _own((load("res://scenes/mission/mission_root.tscn") as PackedScene).instantiate())
	var model: Settings = scene.get("settings")
	assert_eq(_tree.root.scaling_3d_mode, Viewport.SCALING_3D_MODE_BILINEAR, "Compatibility's only 3D scaling mode")
	assert_true(model.set_value("render_scale_percent", 50))
	scene.call("_settings_changed", model.snapshot(), false)
	assert_true(is_equal_approx(_tree.root.scaling_3d_scale, 0.5))
	assert_true(model.set_value("render_scale_percent", 100))
	scene.call("_settings_changed", model.snapshot(), false)
	assert_true(is_equal_approx(_tree.root.scaling_3d_scale, 1.0))


# ---------- 1. shader warm-up ----------

func test_DS09_warmup_tour_is_deterministic_and_spaced() -> void:
	var config: Dictionary = ShaderWarmup.load_config()
	var lights: Array[Node3D] = []
	var holder: Node3D = _own(Node3D.new()) as Node3D
	for p: Vector3 in [Vector3(30, 6, 24), Vector3(5, 6, 16), Vector3(31, 6, 25), Vector3(60, 6, 20)]:
		var l: OmniLight3D = OmniLight3D.new()
		holder.add_child(l)
		l.global_position = p
		lights.append(l)
	var spawn: Vector3 = Vector3(4.5, 1.6, 15.0)
	var points: Array[Vector3] = ShaderWarmup.vantages(spawn, lights, config)
	assert_eq(points[0], spawn, "the spawn comes first")
	assert_eq(points.size(), 3, "the light 1.4 m from the spawn and the one 1.4 m from another light are skipped")
	for p: Vector3 in points:
		assert_true(is_equal_approx(p.y, spawn.y), "eye height")
	lights.reverse()
	assert_eq(ShaderWarmup.vantages(spawn, lights, config), points, "node order does not change the tour")
	assert_eq(ShaderWarmup.views(points, config).size(), points.size() * int(config["yaw_steps"]))


func test_DS09_warmup_holds_host_time_and_input_behind_the_loading_card() -> void:
	var scene: Node = _own((load("res://scenes/mission/mission_root.tscn") as PackedScene).instantiate())
	assert_false(bool(scene.call("is_warming")), "headless runs skip the warm-up on their own")
	scene.call("begin_shader_warmup")
	assert_true(bool(scene.call("is_warming")))
	var card: Control = scene.find_child("LoadingCard", true, false) as Control
	assert_true(card != null and card.is_visible_in_tree(), "the loading card covers the street")
	assert_eq(card.mouse_filter, Control.MOUSE_FILTER_STOP)
	assert_true((card.find_child("LoadingBriefing", true, false) as Label).text == UiText.t("offline.loading.briefing"))
	var player: Node = scene.get("player")
	assert_false(bool(player.get("enabled")), "no movement under the card")
	var session: RefCounted = scene.get("session")
	var tick_before: int = int(session.get("grid").get("tick"))
	scene.call("_physics_process", 1.0)
	assert_eq(int(session.get("grid").get("tick")), tick_before, "host time waits for the warm-up")
	var warmup: Node = scene.find_child("ShaderWarmup", true, false)
	var frames: int = int(warmup.call("view_count")) + 3
	for _i: int in frames:
		warmup.call("_process", 0.016)
	assert_false(bool(scene.call("is_warming")))
	var stats: Dictionary = scene.get("warmup_stats")
	assert_eq(int(stats["views"]), int(warmup.call("view_count")))
	assert_true(bool(player.get("enabled")), "controls come back")
	assert_true((scene.get("player") as Node).get("camera") == scene.get_viewport().get_camera_3d(),
		"the player's camera is current again")


func test_DS09_menu_and_mission_show_the_same_loading_card() -> void:
	var menu: Control = _own((load("res://scenes/menu/main_menu.tscn") as PackedScene).instantiate()) as Control
	var from_menu: Control = menu.call("show_loading_card") as Control
	var from_mission: ColorRect = LoadingCard.build(Runner.json("res://content/ui/tokens.json"), 100.0, 46, true, true)
	_own(from_mission)
	for part: String in ["LoadingTitle", "LoadingBriefing", "LoadingDetail"]:
		assert_eq((from_menu.find_child(part, true, false) as Label).text, (from_mission.find_child(part, true, false) as Label).text,
			part)
	assert_true(from_menu.find_child("LoadingProgress", true, false) != null)


# ---------- 2. first-minute clarity ----------

func test_DS09_onboarding_names_the_west_cabinet_and_the_real_keys() -> void:
	var card: PanelContainer = _own(GuideCard.new()) as PanelContainer
	var instruction: Label = card.get("instruction")
	assert_true(instruction.text.contains("WEST JUNCTION JW"), "first step names the cabinet plate: %s" % instruction.text)
	card.call("observe", "player_moved")
	var kbm: String = UiText.tf("guide.step.measure", [UiText.binding("tool_slot_1", UiText.DEVICE_KBM),
		UiText.binding("interact", UiText.DEVICE_KBM)])
	assert_eq(instruction.text, kbm)
	assert_false(instruction.text.contains("%"), "every slot filled")
	card.call("set_device", UiText.DEVICE_PAD)
	assert_eq(instruction.text, UiText.tf("guide.step.measure", [UiText.binding("tool_next", UiText.DEVICE_PAD),
		UiText.binding("interact", UiText.DEVICE_PAD)]), "controller labels on a controller")
	assert_true(UiText.t("offline.loading.briefing").contains("west junction cabinet"), "the loading card names the first job")


func test_DS09_objective_card_names_one_current_job() -> void:
	var objectives: Array[Dictionary] = [
		{"id": "A", "text_key": "objective.c01.restore_west", "status": MissionDirector.STATUS_ACTIVE},
		{"id": "B", "text_key": "objective.c01.drain_basement", "status": MissionDirector.STATUS_ACTIVE},
		{"id": "C", "text_key": "objective.c01.restore_east", "status": MissionDirector.STATUS_ACTIVE}]
	var rows: Array[Dictionary] = HudPresenter.objective_rows(objectives, 3)
	assert_eq(rows.map(func(r: Dictionary) -> String: return str(r["lane"])), ["now", "later", "later"])
	assert_eq(rows.map(func(r: Dictionary) -> String: return str(r["status"])), ["active", "pending", "pending"])
	assert_eq(objectives[1]["status"], MissionDirector.STATUS_ACTIVE, "the host's objective list is not changed")
	var hud: Container = _hud(Vector2(1920, 1080), {"objectives": rows, "crew": [], "tools": Fixture.TOOLS})
	assert_true(hud.objective_card.find_child("Lane_now", true, false) != null)
	assert_true(hud.objective_card.find_child("Lane_later", true, false) != null)
	assert_eq(hud.objective_card.find_children("Lane_*", "Label", true, false).size(), 2, "one heading per lane")


func test_DS09_crew_says_you_once_and_solo_hides_the_card() -> void:
	var you: String = UiText.t("hud.you")
	var solo: Container = _hud(Vector2(1920, 1080), {"crew": [{"player": "P1", "name": you, "local": true}],
		"tools": Fixture.TOOLS})
	assert_false(solo.crew_card.visible, "a crew of one has nothing to coordinate")
	for l: Node in solo.crew_card.find_children("*", "Label", true, false):
		assert_false((l as Label).text.contains("%s (%s)" % [you, you]), "never 'You (You)'")
	var duo: Container = _hud(Vector2(1920, 1080), {"crew": [{"player": "P1", "name": "Rowan", "local": true},
		{"player": "P2", "name": "Mira", "local": false}], "tools": Fixture.TOOLS})
	assert_true(duo.crew_card.visible)
	var texts: Array[String] = []
	for l: Node in duo.crew_card.find_children("*", "Label", true, false):
		texts.append((l as Label).text)
	assert_true(texts.has("Rowan (%s)" % you))


func test_DS09_tool_bar_shows_all_five_tools_at_1080p() -> void:
	for with_prompt: bool in [false, true]:
		var view: Dictionary = Fixture.worst_hud_view()
		if not with_prompt:
			view.erase("prompt")
		var hud: Container = _hud(Vector2(1920, 1080), view)
		for i: int in range(1, 6):
			var slot: Control = hud.tool_card.find_child("Slot_%d" % i, true, false) as Control
			assert_true(slot != null and slot.is_visible_in_tree(), "slot %d visible (prompt %s)" % [i, with_prompt])
		for l: Node in hud.tool_card.find_children("*", "Label", true, false):
			for n: int in range(1, 6):
				assert_ne((l as Label).text, UiText.tf("hud.tools_more", [n]), "no '+N more' hiding a tool")
		assert_false(hud.tool_card.get_rect().intersects(hud.event_card.get_rect()), "the bar does not run under the event card")


func test_DS09_tablet_fits_the_c01_network_at_zoom_one_on_1080p() -> void:
	var ctx: Dictionary = Fixture.mid_shift()
	var frame: Control = _own(Control.new()) as Control
	frame.size = Vector2(1920, 1080)
	var tablet: PanelContainer = NetworkTablet.new()
	frame.add_child(tablet)
	tablet.set_anchors_preset(Control.PRESET_TOP_LEFT)
	tablet.size = frame.size
	tablet.ui_scale_percent = 100
	tablet.setup(IntentOutbox.new(Runner.SESSION, func(_b: PackedByteArray) -> Dictionary: return {}))
	tablet.show_data(Fixture.tablet_view(ctx), ctx["mission"].objectives())
	Fixture.settle(tablet)
	var map: Control = tablet.get("map")
	assert_true(is_equal_approx(float(map.call("zoom")), 1.0), "default zoom keeps map text at body size")
	var view: Rect2 = Rect2(Vector2.ZERO, map.size)
	for nid: String in (map.get("nodes") as Dictionary).keys():
		var r: Rect2 = map.call("node_rect", nid)
		assert_true(Fixture.rect_inside(r, view), "%s on screen without panning: %s in %s" % [nid, r, view])


func test_DS09_unknown_token_has_contrast_headroom_on_the_panel() -> void:
	var tokens: Dictionary = Runner.json("res://content/ui/tokens.json")
	var ratio: float = _contrast(ThemeTokens.color(tokens, "unknown"), ThemeTokens.color(tokens, "panel"))
	assert_true(ratio >= 5.0, "unknown on panel %.2f:1 (ADR-004 DS09 addendum: at least 5:1)" % ratio)


func test_DS09_first_reading_driver_is_opt_in_and_internal_only() -> void:
	assert_false(FirstReading.requested(PackedStringArray([])))
	assert_true(FirstReading.requested(PackedStringArray(["--ds09-first-reading"])))
	assert_eq(FirstReading.allowed(), OS.has_feature("internal") or OS.has_feature("editor"))
	var boot: String = FileAccess.get_file_as_string("res://scenes/boot/boot.gd")
	assert_true(boot.contains("FirstReading.allowed()"), "boot checks the build before starting it")


# ---------- helpers ----------

func _hud(size: Vector2, view: Dictionary) -> Container:
	var hud: Container = _own(FieldHud.new()) as Container
	hud.set_anchors_preset(Control.PRESET_TOP_LEFT)
	hud.size = size
	hud.apply(view)
	Fixture.settle(hud)
	return hud


static func _contrast(a: Color, b: Color) -> float:
	var la: float = _luminance(a)
	var lb: float = _luminance(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


static func _luminance(c: Color) -> float:
	var lin: Callable = func(v: float) -> float: return v / 12.92 if v <= 0.04045 else pow((v + 0.055) / 1.055, 2.4)
	return 0.2126 * float(lin.call(c.r)) + 0.7152 * float(lin.call(c.g)) + 0.0722 * float(lin.call(c.b))
