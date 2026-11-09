extends "res://tests/test_case.gd"
## DS08 Stormglass look: the look and dressing are visual only (no collision, no moved gameplay node), signs and icons
## follow the host snapshot through RestorationPresentation, the mission uses the look, and the lookdev scene that fakes
## state is labelled and never referenced by shipping code. Rendering quality itself is judged from GPU screenshots
## (docs/evidence/DS08.md), not here.

const StreetLook := preload("res://scripts/world/street_look.gd")
const StreetDressing := preload("res://scripts/world/street_dressing.gd")
const RestorationPresentation := preload("res://scripts/world/restoration_presentation.gd")
const DistrictBuilder := preload("res://scripts/world/district_builder.gd")
const UiText := preload("res://scripts/ui/ui_text.gd")
const Lookdev := preload("res://scenes/lookdev/alder_lookdev.gd")

var _tree: SceneTree
var _holder: Node3D


func before_each() -> void:
	_tree = Engine.get_main_loop() as SceneTree
	_holder = Node3D.new()
	_tree.root.add_child(_holder)


func after_each() -> void:
	if _holder != null and is_instance_valid(_holder):
		_tree.root.remove_child(_holder)
		_holder.free()
	_holder = null
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _district() -> Dictionary:
	return DistrictBuilder.load_district()


func _world(d: Dictionary) -> Node3D:
	var world: Node3D = (load(str(d["scene"])) as PackedScene).instantiate()
	world.name = "District"
	_holder.add_child(world)
	return world


func _dressed() -> Node3D:
	var d: Dictionary = _district()
	var world: Node3D = _world(d)
	var look: Dictionary = StreetLook.load_look()
	StreetLook.skin_world(world, look, d)
	StreetDressing.new().build(world, d, look, StreetDressing.load_dressing())
	return world


static func _collision_lines(root: Node) -> Array[String]:
	var out: Array[String] = []
	for n: Node in root.find_children("*", "", true, false):
		if n is CollisionObject3D or n is CollisionShape3D or n is Marker3D or n is Area3D:
			var n3: Node3D = n as Node3D
			out.append("%s|%s|%s" % [root.get_path_to(n), n.get_class(), str(n3.global_transform)])
	out.sort()
	return out


func test_DS08_look_data_is_complete_and_keys_exist() -> void:
	var look: Dictionary = StreetLook.load_look()
	var dress: Dictionary = StreetDressing.load_dressing()
	var d: Dictionary = _district()
	var ids: Array[String] = []
	for b: Dictionary in d["buildings"]:
		ids.append(str(b["id"]))
	for id: String in (look["buildings"] as Dictionary).keys():
		if id.begins_with("_"):
			continue
		assert_true(ids.has(id), "palette for unknown building %s" % id)
	for id: String in (dress["signs"] as Dictionary).keys():
		assert_true(ids.has(id), "sign for unknown building %s" % id)
		var def: Dictionary = dress["signs"][id]
		assert_true(UiText.has(str(def["fascia_key"])), "missing string %s" % def["fascia_key"])
		if str(def["plaque_key"]) != "":
			assert_true(UiText.has(str(def["plaque_key"])), "missing string %s" % def["plaque_key"])
	for key: String in ["world.supply.dark", "world.supply.temporary", "world.supply.grid", "world.van.label",
			"world.substation.label", "world.cabinet.jw", "world.cabinet.je"]:
		assert_true(UiText.has(key), "missing string " + key)
	for c: Dictionary in dress["cabinets"]:
		assert_true(UiText.has(str(c["plate_key"])))
	for service: String in RestorationPresentation.SERVICES:
		assert_true((dress["signs"] as Dictionary).has(service), "every C01 service gets a sign: " + service)
	assert_true((dress["capture_views"] as Array).size() >= 3, "three-state capture needs views")


func test_DS08_dressing_adds_no_collision_and_moves_no_gameplay_node() -> void:
	var d: Dictionary = _district()
	var plain: Node3D = _world(d)
	var before: Array[String] = _collision_lines(plain)
	_holder.remove_child(plain)
	plain.free()
	var world: Node3D = _dressed()
	var after: Array[String] = _collision_lines(world)
	assert_eq(after, before, "look and dressing must not add, remove or move collision, markers or zones")
	var dressing: Node = world.get_node("Dressing")
	assert_eq(dressing.find_children("*", "CollisionObject3D", true, false).size(), 0)
	assert_eq(dressing.find_children("*", "CollisionShape3D", true, false).size(), 0)
	assert_eq(world.get_node("LookTiles").find_children("*", "CollisionObject3D", true, false).size(), 0)


func test_DS08_debug_id_billboards_are_replaced_by_plaques() -> void:
	var world: Node3D = _dressed()
	assert_false((world.get_node("Labels") as Node3D).visible, "debug-ID billboards (JW, JE, VAN) hidden")
	for service: String in RestorationPresentation.SERVICES:
		var label: Label3D = world.get_node("Buildings/%s/Label" % service) as Label3D
		assert_eq(label.billboard, BaseMaterial3D.BILLBOARD_DISABLED, service + " plaque is flat on the facade")
		assert_false(label.text.contains(service), service + " plaque shows a player-facing name, not the ID")
		assert_true(label.get_node_or_null("StatusIcon") is Sprite3D, service + " plaque has a supply icon")
	assert_true(world.get_node_or_null("Dressing/Fascia_PUB/Name") is Label3D)
	assert_true(world.get_node_or_null("Dressing/Van") != null)
	assert_true(world.get_node_or_null("Dressing/Cabinet_CABINET_JW/Plate") is Label3D)


func test_DS08_plaque_text_and_icon_follow_the_snapshot() -> void:
	var world: Node3D = _dressed()
	var fx: RestorationPresentation = RestorationPresentation.new()
	fx.setup(world, StreetLook.load_look()["windows"])
	fx.apply(Lookdev.fake_snapshot("dark"), false)
	fx.advance(30.0)
	assert_eq(fx.icon_state_of("APT_W"), "dark")
	assert_true(fx.state_label_of("APT_W").contains(UiText.t("world.supply.dark")))
	assert_true(fx.state_label_of("APT_W").begins_with(UiText.t("node.c01.apt_w")), "plaque uses the tablet's name")
	fx.apply(Lookdev.fake_snapshot("temporary"), true)
	fx.advance(30.0)
	assert_eq(fx.icon_state_of("PUB"), "temporary")
	assert_true(fx.state_label_of("PUB").contains(UiText.t("world.supply.temporary")))
	fx.apply(Lookdev.fake_snapshot("grid"), true)
	fx.advance(30.0)
	assert_eq(fx.icon_state_of("WORKSHOP"), "grid")
	assert_true(fx.state_label_of("WORKSHOP").contains("GRID POWER"))


func test_DS08_mission_uses_the_look_with_host_state() -> void:
	var scene: Node = (load("res://scenes/mission/mission_root.tscn") as PackedScene).instantiate()
	_holder.add_child(scene)
	var env: WorldEnvironment = scene.get_node("WorldLight") as WorldEnvironment
	assert_eq(env.environment.background_mode, Environment.BG_SKY)
	assert_true(env.environment.fog_enabled)
	assert_true(scene.get_node_or_null("Moon") is DirectionalLight3D)
	assert_true(scene.get_node_or_null("Rain") is GPUParticles3D)
	assert_true(scene.get_node_or_null("District/Dressing") != null)
	var fx: RefCounted = scene.get("_world_fx")
	assert_eq(fx.call("icon_state_of", "APT_W"), "dark", "plaque icon comes from the real host snapshot")


func test_DS08_lookdev_fakes_are_labelled_and_not_shipped() -> void:
	var scene: Lookdev = (load("res://scenes/lookdev/alder_lookdev.tscn") as PackedScene).instantiate()
	_holder.add_child(scene)
	scene.set_fake_state("grid")
	assert_true(scene._caption.text.contains("FAKE STATE"))
	for dir: String in ["res://scripts/gameplay", "res://scripts/world", "res://scripts/ui", "res://scenes/mission"]:
		for f: String in DirAccess.get_files_at(dir):
			if f.ends_with(".gd") or f.ends_with(".tscn"):
				var text: String = FileAccess.get_file_as_string(dir.path_join(f))
				assert_false(text.contains("scenes/lookdev"), "%s must not reference the lookdev scene" % f)


func test_DS08_menu_shows_a_loading_card_before_the_mission_loads() -> void:
	# A cold shader cache makes the first mission frame take seconds on integrated GPUs (docs/evidence/DS08.md);
	# the menu must present a loading card first so the wait never looks like a hang.
	var menu: Control = (load("res://scenes/menu/main_menu.tscn") as PackedScene).instantiate() as Control
	_holder.add_child(menu)
	var card: Control = menu.call("show_loading_card") as Control
	assert_true(card != null and card.visible)
	assert_eq(card.mouse_filter, Control.MOUSE_FILTER_STOP, "the card blocks a second launch press")
	assert_eq((card.find_child("LoadingTitle", true, false) as Label).text, UiText.t("offline.loading.title"))
	assert_true(UiText.has("offline.loading.detail"))
	assert_eq(menu.call("show_loading_card"), card, "only one card")
