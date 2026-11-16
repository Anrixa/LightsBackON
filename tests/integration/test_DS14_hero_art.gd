extends "res://tests/test_case.gd"
## DS14 procedural hero art acceptance. Verify real first-person integration and
## original asset boundaries; actual screen look, GPU budget and controller feel
## are independent physical gates and cannot be inferred from this suite.

const HeroProps := preload("res://scripts/world/hero_prop_builder.gd")
const EquipmentView := preload("res://scripts/actors/first_person_equipment.gd")
const Controller := preload("res://scripts/actors/first_person_controller.gd")
const GeneratorView := preload("res://scripts/world/generator_tradeoff_presentation.gd")
const GalleryScene := preload("res://scenes/lookdev/ds14_hero_gallery.tscn")
const MissionScene := preload("res://scenes/mission/mission_root.tscn")
const Offline := preload("res://scripts/gameplay/offline_c01_session.gd")

var _tree: SceneTree
var _holder: Node3D


func before_each() -> void:
	_tree = Engine.get_main_loop() as SceneTree
	_holder = Node3D.new()
	_tree.root.add_child(_holder)


func after_each() -> void:
	_tree.root.remove_child(_holder)
	_holder.free()
	_holder = null
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func test_DS14_original_asset_is_a_visual_only_presentation_manifest() -> void:
	var art: HeroProps = HeroProps.new()
	var manifest: Dictionary = art.configuration()
	assert_eq(str(manifest.get("license", "")), "project-owned")
	assert_true(str(manifest.get("creator", "")).contains("Lights Back On"))
	assert_eq((manifest["worker"] as Dictionary)["variants"].size(), 3)
	assert_eq(HeroProps.TOOLS, Offline.TOOL_LIST)
	assert_true(FileAccess.file_exists(HeroProps.ART_PATH))
	assert_false(HeroProps.ART_PATH.begins_with("res://content/"),
		"cosmetic-only data must not invalidate previous C01 gameplay checkpoints")


func test_DS14_all_five_distinct_tools_are_original_noncancellable_visual_nodes() -> void:
	var art: HeroProps = HeroProps.new()
	var shapes: Array[int] = []
	for id: String in HeroProps.TOOLS:
		var model: Node3D = art.build_tool(id)
		_holder.add_child(model)
		assert_eq(str(model.name), "Tool_" + id)
		var meshes: Array[Node] = model.find_children("*", "MeshInstance3D", true, false)
		assert_true(meshes.size() >= 5, "each canonical tool needs a distinct close-up silhouette")
		assert_eq(model.find_children("*", "CollisionObject3D", true, false).size(), 0)
		assert_eq(model.find_children("*", "CollisionShape3D", true, false).size(), 0)
		assert_eq(model.find_children("*", "AudioStreamPlayer3D", true, false).size(), 0)
		shapes.append(meshes.size())
	assert_eq(shapes.size(), 5)
	assert_true(shapes[0] != shapes[1] or shapes[1] != shapes[2])
	var unknown: Node3D = art.build_tool("not_a_gameplay_tool")
	assert_true(bool(unknown.get_meta("ds14_unknown_tool", false)))
	assert_eq(unknown.get_child_count(), 0)
	unknown.free()


func test_DS14_gloves_and_live_view_use_canonical_tool_selection() -> void:
	var player: Controller = Controller.new()
	_holder.add_child(player)
	assert_true(player.camera is Camera3D)
	assert_eq(player.camera.get_child_count(), 1, "one cosmetic view child under the existing aiming camera")
	var view: EquipmentView = player.equipment_view
	assert_true(view != null)
	assert_true(view.find_child("GlovedHands", true, false) is Node3D)
	assert_eq(view.current_tool(), "meter")
	var first_model: Node3D = view.tool_model("meter")
	assert_true(first_model.visible)
	player.set_equipped_tool("cutter")
	assert_eq(view.current_tool(), "cutter")
	assert_false(first_model.visible)
	assert_true(view.tool_model("cutter").visible)
	player.set_equipped_tool("crimper")
	assert_true(view.tool_model("crimper").visible)
	player.set_equipped_tool("nonexistent")
	assert_eq(view.current_tool(), "")
	assert_false(view.tool_model("crimper").visible)
	assert_eq(player.get_child_count(), 2, "the player keeps one collider and one camera")
	assert_eq(player.find_children("*", "CollisionShape3D", true, false).size(), 1)
	assert_eq(view.find_children("*", "CollisionObject3D", true, false).size(), 0)


func test_DS14_carried_generator_hides_handheld_tool_without_inventory_mutation() -> void:
	var view: EquipmentView = EquipmentView.new()
	_holder.add_child(view)
	view.select_tool("puller")
	assert_true(view.tool_model("puller").visible)
	view.set_carrying(true)
	assert_true(view.carrying())
	assert_false(view.tool_model("puller").visible)
	assert_true((view.find_child("GlovedHands", true, false) as Node3D).visible)
	view.set_carrying(false)
	assert_true(view.tool_model("puller").visible)
	view.set_carrying(false)
	assert_true(view.tool_model("puller").visible)


func test_DS14_generator_has_visual_reel_and_unchanged_host_readout() -> void:
	var world: Node3D = Node3D.new()
	_holder.add_child(world)
	var generator: GeneratorView = GeneratorView.new()
	generator.setup(world)
	var model: Node3D = world.get_node_or_null("DS11TemporarySupply/PortableGenerator") as Node3D
	assert_true(model != null)
	assert_true(model.get_node_or_null("LoadReadout") is Label3D)
	assert_true(model.get_node_or_null("DS14HeroDetails/CableReel") is Node3D)
	assert_true(model.get_node_or_null("DS14HeroDetails/TransportWheel_-1") is MeshInstance3D)
	assert_true(model.get_node_or_null("DS14HeroDetails/Louvre_0") is MeshInstance3D)
	assert_eq(model.get_node("DS14HeroDetails").find_children("*", "CollisionObject3D", true, false).size(), 0)
	assert_eq(model.get_node("DS14HeroDetails").find_children("*", "CollisionShape3D", true, false).size(), 0)
	assert_false(model.visible, "new generator art cannot imply generator has been placed")
	assert_eq(generator.ring_count(), int(generator.load_config()["ring_segments"]))
	assert_false(generator.cable_visible("E_TEMP_PUMP"))


func test_DS14_three_worker_variants_do_not_spawn_fake_players() -> void:
	var art: HeroProps = HeroProps.new()
	var variants: Array[String] = ["field", "line", "supervisor"]
	for name: String in variants:
		var model: Node3D = art.build_worker(name)
		_holder.add_child(model)
		assert_eq(str(model.name), "Worker_" + name)
		assert_true(model.get_node_or_null("HardHat") is MeshInstance3D)
		assert_true(model.get_node_or_null("ToolPouch") is MeshInstance3D)
		assert_eq(model.find_children("*", "CollisionObject3D", true, false).size(), 0)
		assert_eq(model.find_children("*", "CharacterBody3D", true, false).size(), 0)
	var gallery: Node3D = GalleryScene.instantiate() as Node3D
	_holder.add_child(gallery)
	assert_true(gallery.get_node_or_null("Worker_field") is Node3D)
	assert_true(gallery.get_node_or_null("Worker_line") is Node3D)
	assert_true(gallery.get_node_or_null("Worker_supervisor") is Node3D)
	assert_true(gallery.get_node_or_null("Gallery_CableReel") is Node3D)
	assert_true(gallery.get_node_or_null("Gallery_crimper") is Node3D)


func test_DS14_real_mission_tool_slot_matches_first_person_model() -> void:
	var mission: Node3D = MissionScene.instantiate() as Node3D
	_holder.add_child(mission)
	var player: Controller = mission.get("player") as Controller
	assert_true(player != null and player.equipment_view != null)
	assert_eq(player.equipment_view.current_tool(), "meter")
	mission.call("_select_slot", 3)
	assert_eq(player.equipment_view.current_tool(), "puller")
	assert_true(player.equipment_view.tool_model("puller").visible)
	mission.call("_select_slot", 5)
	assert_eq(player.equipment_view.current_tool(), "crimper")
	assert_true(player.equipment_view.tool_model("crimper").visible)
	assert_eq(int(mission.get("_slot")), 5)
