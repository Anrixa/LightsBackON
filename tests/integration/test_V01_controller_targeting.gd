extends "res://tests/test_case.gd"
## Physical solo interaction and controller UX regressions. Human controller feel,
## real GPU performance and Steam remain separate acceptance gates.

const Visibility := preload("res://scripts/interaction/interaction_visibility.gd")
const FieldHud := preload("res://scripts/ui/field_hud.gd")
const UiText := preload("res://scripts/ui/ui_text.gd")
const Fixture := preload("res://tests/support/ui_fixture.gd")
const Offline := preload("res://scripts/gameplay/offline_c01_session.gd")


func test_V01_Dpad_cycles_all_five_tools_and_fifth_key_is_present() -> void:
	var right: bool = false
	for event: InputEvent in InputMap.action_get_events("tool_next"):
		if event is InputEventJoypadButton and (event as InputEventJoypadButton).button_index == JOY_BUTTON_DPAD_RIGHT:
			right = true
	var left: bool = false
	for event: InputEvent in InputMap.action_get_events("tool_prev"):
		if event is InputEventJoypadButton and (event as InputEventJoypadButton).button_index == JOY_BUTTON_DPAD_LEFT:
			left = true
	var five: bool = false
	for event: InputEvent in InputMap.action_get_events("tool_slot_5"):
		if event is InputEventKey and (event as InputEventKey).physical_keycode == KEY_5:
			five = true
	assert_true(right, "D-pad right cycles tools")
	assert_true(left, "D-pad left cycles tools")
	assert_true(five, "fifth tool can be selected without scrolling")
	assert_eq(UiText.binding("tool_next", UiText.DEVICE_PAD), "D-pad right")
	assert_eq(UiText.binding("tool_prev", UiText.DEVICE_PAD), "D-pad left")
	assert_eq(Offline.TOOL_LIST.size(), 5, "all five authored tools available")


func test_V01_fifth_tool_is_named_even_when_HUD_only_shows_four_slots() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var hud: FieldHud = FieldHud.new()
	# This test measures a fixed canvas; unpin FULL_RECT anchors before sizing
	# it so Godot does not emit the invalid opposite-anchor size warning.
	hud.set_anchors_preset(Control.PRESET_TOP_LEFT)
	hud.size = Vector2(1920, 1080)
	tree.root.add_child(hud)
	var view: Dictionary = Fixture.worst_hud_view()
	view["selected_slot"] = 5
	hud.apply(view)
	var labels: Array[Node] = hud.find_children("*", "Label", true, false)
	var found: bool = false
	for label: Node in labels:
		if (label as Label).text == UiText.tf("offline.hud.fifth_tool", [UiText.t("tool.crimper")]):
			found = true
	assert_true(found, "selected fifth tool name remains visible without expanding the four-slot bar")
	assert_true(hud.tool_card != null)
	tree.root.remove_child(hud)
	hud.free()


func test_V01_physics_sight_blocks_intervening_wall_not_nearby_panel_face() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var world: Node3D = (load("res://scenes/world/alder_street.tscn") as PackedScene).instantiate()
	tree.root.add_child(world)
	var space: PhysicsDirectSpaceState3D = world.get_world_3d().direct_space_state
	var from: Vector3 = Vector3(5, 1.4, 22)
	var target: Vector3 = Vector3(5, 1.4, 24)
	assert_true(Visibility.can_reach(space, from, target, 2.3, 0.25), "unobstructed interactable in reach")
	var wall: StaticBody3D = StaticBody3D.new()
	wall.name = "TestBlockingWall"
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(2, 2.0, 0.25)
	shape.shape = box
	wall.position = Vector3(5, 1.4, 23)
	wall.add_child(shape)
	world.add_child(wall)
	assert_false(Visibility.can_reach(space, from, target, 2.3, 0.25),
		"an actual physics body between eye and target blocks interaction")
	assert_true(Visibility.can_reach(space, from, Vector3(5, 1.4, 22.98), 2.3, 0.25),
		"the authored panel face can be a few centimeters behind its own collider")
	assert_false(Visibility.can_reach(space, from, target, 1.0, 0.25),
		"proximity is checked independently of occlusion")
	world.remove_child(wall)
	wall.free()
	tree.root.remove_child(world)
	world.free()


func test_V01_host_range_uses_sight_not_only_center_distance() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var root: Node3D = (load("res://scenes/mission/mission_root.tscn") as PackedScene).instantiate()
	tree.root.add_child(root)
	var player: CharacterBody3D = root.get("player")
	var session: RefCounted = root.get("session")
	var marker: Marker3D = root.get_node("District/Markers/PANEL_JW")
	player.global_position = marker.global_position + Vector3(0, -0.85, 1.7)
	var near: bool = root.call("_in_range", "P1", "PANEL_JW")
	assert_true(near, "JW panel can be operated from its unobstructed front")
	var wall: StaticBody3D = StaticBody3D.new()
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(2, 2, 0.2)
	shape.shape = box
	wall.add_child(shape)
	wall.position = marker.global_position + Vector3(0, 0, 0.8)
	root.add_child(wall)
	assert_false(bool(root.call("_in_range", "P1", "PANEL_JW")),
		"host range refuses the same panel behind a physical obstacle")
	var reply: Dictionary = session.call("command", "inspect", "PANEL_JW", {})
	assert_eq(reply["code"], "NOT_IN_RANGE", "real host command cannot tunnel through wall")
	root.remove_child(wall)
	wall.free()
	tree.root.remove_child(root)
	root.free()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func test_V01_drop_command_returns_carried_generator_to_authored_anchor() -> void:
	var session: Offline = Offline.new()
	var errors: Array[Dictionary] = session.setup(
		func(_p: String, _id: String) -> bool: return true,
		func(_p: String) -> Vector3i: return Vector3i(800, 90, 1300))
	assert_true(errors.is_empty(), str(errors))
	assert_true(session.command("place_item", "GEN_PORTABLE", {"action": "pickup"})["ok"])
	assert_eq(session.equipment.carrier_of("GEN_PORTABLE"), "P1")
	assert_true(session.command("place_item", "GEN_PORTABLE", {"action": "drop"})["ok"])
	assert_eq(session.equipment.carrier_of("GEN_PORTABLE"), "")
	assert_eq(session.equipment.anchor_of("GEN_PORTABLE"), "VAN_BAY")
	assert_true(session.host_state()["equipment"]["items"]["GEN_PORTABLE"]["carrier"] == "")
