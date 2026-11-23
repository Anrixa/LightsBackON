extends "res://tests/test_case.gd"
## RB02 location format (scripts/world/location_data.gd). The parity cases in tests/data/locations/cases.json also run
## in tests/python/test_rb02_location.py against tools/lbo_location.py, so both validators return the same codes.

const LocationData := preload("res://scripts/world/location_data.gd")
const DistrictBuilder := preload("res://scripts/world/district_builder.gd")
const KitBuilder := preload("res://scripts/world/kit_builder.gd")
const StreetLook := preload("res://scripts/world/street_look.gd")
const StreetDressing := preload("res://scripts/world/street_dressing.gd")
const CASES: String = "res://tests/data/locations/cases.json"
const CHALLENGE: String = "res://tests/data/locations/alder_c01_challenge.json"
const C01: String = "res://content/contracts/c01_alder_street"
const PROFILE: String = "res://content/world/look_stormglass.json"

var _alder: Dictionary
var _cases: Dictionary


func before_each() -> void:
	_alder = LocationData.load_location()
	_cases = JSON.parse_string(FileAccess.get_file_as_string(CASES))


static func _codes(diags: Array[Dictionary]) -> Array:
	var seen: Dictionary = {}
	for d: Dictionary in diags:
		seen[str(d["code"])] = true
	var out: Array = seen.keys()
	out.sort()
	return out


func test_RB02_alder_street_validates_and_is_listed() -> void:
	assert_eq(LocationData.validate(_alder), [] as Array[Dictionary])
	assert_true(LocationData.all_locations().has("ALDER_STREET"))
	assert_eq(LocationData.check_contract(_alder, C01), [] as Array[Dictionary], "C01 fits Alder Street")


func test_RB02_location_parity_cases() -> void:
	var kit: Array[String] = LocationData.kit_ids()
	var dims: Dictionary = LocationData.dimensions()
	var cases: Array = _cases["location_cases"]
	assert_true(cases.size() >= 20, "%d cases" % cases.size())
	for c: Dictionary in cases:
		var got: Array[Dictionary] = LocationData.validate(LocationData.apply_patch(_alder, c["ops"]), kit, dims)
		assert_eq(_codes(got), c["codes"], "%s: %s" % [c["name"], str(got)])


func test_RB02_challenge_parity_cases() -> void:
	var challenge: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CHALLENGE))
	for c: Dictionary in _cases["challenge_cases"]:
		var ops: Array = []
		for op: Dictionary in c["ops"]:
			var wrapped: Dictionary = op.duplicate(true)
			wrapped["path"] = ["c"] + (op["path"] as Array)
			ops.append(wrapped)
		var patched: Dictionary = LocationData.apply_patch({"c": challenge}, ops)["c"]
		var got: Array[Dictionary] = LocationData.check_challenge(_alder, patched)
		assert_eq(_codes(got), c["codes"], "%s: %s" % [c["name"], str(got)])


func test_RB02_a_contract_on_another_street_does_not_fit() -> void:
	var got: Array[Dictionary] = LocationData.check_contract(_alder, "res://content/contracts/c05_canal_pump_access")
	assert_true(_codes(got).has("CONTRACT_MISMATCH"), str(got))


func test_RB02_layout_carries_the_manifest_scene_and_id() -> void:
	var d: Dictionary = DistrictBuilder.load_district()
	assert_eq(str(d["scene"]), "res://scenes/world/alder_street.tscn")
	assert_eq(str(d["district_id"]), "ALDER_STREET")
	var rules_only: Dictionary = LocationData.load_location(LocationData.ALDER_STREET, false)
	assert_true((rules_only["dressing"] as Dictionary).is_empty() and (rules_only["look"] as Dictionary).is_empty(),
		"rules code never loads the presentation files (ADR-018)")


## The scene is rebuilt from the location and matches the committed one node for node (V01 compares every node too).
func test_RB02_scene_rebuilds_from_the_location() -> void:
	var built: Node3D = DistrictBuilder.build(DistrictBuilder.load_district(), KitBuilder.load_kit())
	var loaded: Node3D = (load(str(_alder["manifest"]["scene"])) as PackedScene).instantiate()
	assert_eq(DistrictBuilder.describe(built), DistrictBuilder.describe(loaded), "rerun tools/godot/build_district.gd")
	for id: String in ["Markers/SPAWN_1", "Markers/PANEL_JW", "Markers/TRUNK_JE", "Zones/ZONE_VAN", "Props/CABINET_JW",
			"Buildings/MARKET"]:
		assert_true(loaded.get_node_or_null(NodePath(id)) != null, "gameplay node path %s" % id)
	built.free()
	loaded.free()


func test_RB02_look_merges_the_location_palette_over_the_shared_profile() -> void:
	var look: Dictionary = StreetLook.load_look()
	var profile: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PROFILE))
	assert_false(profile.has("buildings"), "the palette lives with the location")
	assert_eq(look["buildings"], _alder["look"]["palette"])
	assert_eq(look["environment"], profile["environment"], "Alder Street overrides nothing")
	for b: Dictionary in _alder["layout"]["buildings"]:
		assert_true((look["buildings"] as Dictionary).has(b["id"]), "%s has a palette" % b["id"])
	var overridden: Dictionary = _alder.duplicate(true)
	overridden["look"]["environment"] = {"fog_density_x10000": 1}
	assert_eq(int(LocationData.look(overridden)["environment"]["fog_density_x10000"]), 1, "a location can override the environment")


func test_RB02_dressing_carries_the_lamps_from_the_look() -> void:
	var dress: Dictionary = StreetDressing.load_dressing()
	assert_eq(dress["lamps"], _alder["look"]["lamps"])
	assert_true((dress["lamps"] as Array).size() >= 8, "street lamps")
	assert_true(dress.has("capture_views") and dress.has("signs") and dress.has("substation"))


func test_RB02_opening_shot_sets_the_spawn_yaw() -> void:
	assert_eq(LocationData.spawn_marker_id(_alder), "SPAWN_1")
	assert_true(is_equal_approx(LocationData.spawn_yaw_rad(_alder), deg_to_rad(-90.0)), "faces east along the street")
