extends "res://tests/test_case.gd"
## RB02 stage audit on the Alder Street location (scripts/diagnostics/stage_audit.gd audit_location, ADR-019 quality
## gates): the scene built from content/locations/alder_street, skinned and dressed as the mission does, has nothing
## floating, nothing outside the envelope but the skyline backdrop, every C01 target reached and seen, four clear crew
## spawns, and an opening shot that frames the Corner Market (hero landmark) and the JW cabinet (first job). The
## negative tests prove each check can fail.

const Audit := preload("res://scripts/diagnostics/stage_audit.gd")
const LocationData := preload("res://scripts/world/location_data.gd")
const DistrictBuilder := preload("res://scripts/world/district_builder.gd")
const StreetLook := preload("res://scripts/world/street_look.gd")
const StreetDressing := preload("res://scripts/world/street_dressing.gd")

var _world: Node3D
var _bundle: Dictionary


func before_each() -> void:
	_bundle = LocationData.load_location()
	var d: Dictionary = LocationData.layout(_bundle)
	var look: Dictionary = LocationData.look(_bundle)
	_world = (load(str(d["scene"])) as PackedScene).instantiate()
	_world.name = "District"
	(Engine.get_main_loop() as SceneTree).root.add_child(_world)
	StreetLook.skin_world(_world, look, d)
	StreetDressing.new().build(_world, d, look, LocationData.dressing(_bundle))


func after_each() -> void:
	if _world != null:
		_world.get_parent().remove_child(_world)
		_world.free()
		_world = null


func test_RB02_alder_street_passes_the_stage_audit() -> void:
	var report: Dictionary = Audit.audit_location(_world, _bundle)
	assert_true(bool(report["ok"]), str(report))
	assert_eq(report["floating"], [] as Array[String], "nothing floats")
	assert_eq(report["out_of_bounds"], [] as Array[String], "only the skyline backdrop leaves the envelope")
	assert_eq(report["unreachable"], [] as Array[String], "every target is reached and seen")
	assert_eq(int(report["targets"]), 11, "3 panels, 3 switches, 2 consumers and 3 anchors")
	assert_true(int(report["meshes"]) > 100, "the dressed street was audited (%d meshes)" % int(report["meshes"]))
	for id: String in (report["spawns"] as Dictionary):
		assert_true(bool(report["spawns"][id]), "%s is clear" % id)
	var shot: Dictionary = report["opening_shot"]
	assert_true(float(shot["hero_framed_share"]) >= Audit.FRAMED_SHARE, "hero landmark framed: %s" % str(shot))
	assert_true(float(shot["first_job_framed_share"]) >= Audit.FRAMED_SHARE, "first job framed: %s" % str(shot))
	print("RB02_AUDIT targets=%d meshes=%d hero=%.2f first_job=%.2f near_wall=%d%% fov=%d" % [int(report["targets"]),
		int(report["meshes"]), float(shot["hero_framed_share"]), float(shot["first_job_framed_share"]),
		int(shot["near_wall_percent"]), int(shot["fov_deg"])])


func test_RB02_audit_finds_a_floating_cabinet() -> void:
	# The dressed cabinet is what the player sees (the graybox box under Props is hidden by the dressing).
	(_world.get_node("Dressing/Cabinet_CABINET_JE") as Node3D).position.y += 3.0
	var report: Dictionary = Audit.audit_location(_world, _bundle)
	assert_false(bool(report["ok"]))
	var hit: bool = false
	for p: String in report["floating"]:
		hit = hit or p.begins_with("Dressing/Cabinet_CABINET_JE")
	assert_true(hit, "lifted cabinet reported: %s" % str(report["floating"]))


func test_RB02_audit_finds_a_walled_off_panel() -> void:
	# A solid block boxes the JW cabinet in: the panel can no longer be seen from anywhere reachable.
	var wall: StaticBody3D = StaticBody3D.new()
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(5.0, 3.0, 2.0)
	shape.shape = box
	wall.add_child(shape)
	# Placed before it joins the tree: a body moved afterwards reaches the physics server only on the next physics frame.
	wall.position = Vector3(30.0, 1.5, 24.3)
	_world.add_child(wall)
	var report: Dictionary = Audit.audit_location(_world, _bundle)
	assert_true((report["unreachable"] as Array).has("PANEL_JW"), str(report["unreachable"]))
	assert_false(bool(report["ok"]))


func test_RB02_audit_refuses_an_opening_shot_into_a_wall() -> void:
	var facing_van: Dictionary = LocationData.apply_patch(_bundle, [
		{"path": ["manifest", "spawn", "opening_shot", "yaw_deg"], "set": 180}])
	var shot: Dictionary = Audit.opening_shot(_world, facing_van, 78, 1.75)
	assert_false(bool(shot["ok"]), "facing south misses the market and the cabinet: %s" % str(shot))
	var hero_elsewhere: Dictionary = LocationData.apply_patch(_bundle, [
		{"path": ["manifest", "landmarks", 0, "role"], "set": "secondary"},
		{"path": ["manifest", "landmarks", 3, "role"], "set": "hero"}])
	shot = Audit.opening_shot(_world, hero_elsewhere, 78, 1.75)
	assert_true(float(shot["hero_framed_share"]) < Audit.FRAMED_SHARE,
		"the pump house is behind the south block from the spawn: %s" % str(shot))
