extends SceneTree
## Writes a location's graybox scene from its layout (RB02 location format; V01 graybox, kit pieces from F05). The
## scene path and district ID come from content/locations/<location>/location.json. Rerun after editing the layout or
## the kit; the V01 test fails while the committed scene and the data disagree.
##   godot --headless --path . -s "$PWD/tools/godot/build_district.gd" [-- --location=alder_street]
## Exit 0 = written, 1 = the location is invalid or the save failed.

const KitBuilder := preload("res://scripts/world/kit_builder.gd")
const DistrictBuilder := preload("res://scripts/world/district_builder.gd")
const LocationData := preload("res://scripts/world/location_data.gd")
const SceneWriter := preload("res://scripts/world/scene_writer.gd")


func _initialize() -> void:
	var location_dir: String = LocationData.ALDER_STREET
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--location="):
			location_dir = a.trim_prefix("--location=")
	var bundle: Dictionary = LocationData.load_location(location_dir)
	var errors: Array[Dictionary] = LocationData.validate(bundle)
	if not errors.is_empty():
		for e: Dictionary in errors:
			print("INVALID %s: %s %s" % [location_dir, e["code"], e["message"]])
		quit(1)
		return
	var d: Dictionary = LocationData.layout(bundle)
	var path: String = d["scene"]
	var root: Node3D = DistrictBuilder.build(d, KitBuilder.load_kit())
	var err: Error = SceneWriter.save(root, path, str(d["district_id"]))
	root.free()
	print(("WROTE %s" % path) if err == OK else "FAILED %s: %s" % [path, error_string(err)])
	quit(0 if err == OK else 1)
