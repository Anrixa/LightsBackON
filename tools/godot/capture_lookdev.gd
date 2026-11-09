extends SceneTree
## DS08 three-state screenshot set: renders scenes/lookdev/alder_lookdev.tscn in each FAKE supply state (dark,
## temporary, grid) from the capture views in content/world/alder_street_dressing.json, at the window size given on
## the command line (1920x1080 for evidence). Needs a real GPU window; it does not run headless or in CI.
##   godot --path . --resolution 1920x1080 -s "$PWD/tools/godot/capture_lookdev.gd" -- --out-dir=build/ds08 [--prefix=DS08]
## Writes <out-dir>/<prefix>_<view>_<state>.png. Exit 0 = all written.

const Lookdev := preload("res://scenes/lookdev/alder_lookdev.gd")
const StreetDressing := preload("res://scripts/world/street_dressing.gd")
const KitBuilder := preload("res://scripts/world/kit_builder.gd")
const SETTLE_FRAMES: int = 45
const FOV_DEG: float = 75.0


func _initialize() -> void:
	var out_dir: String = "build/ds08"
	var prefix: String = "DS08"
	var only_state: String = ""
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--out-dir="):
			out_dir = a.trim_prefix("--out-dir=")
		elif a.begins_with("--prefix="):
			prefix = a.trim_prefix("--prefix=")
		elif a.begins_with("--state="):
			only_state = a.trim_prefix("--state=")
	DirAccess.make_dir_recursive_absolute(out_dir)
	var scene: Lookdev = (load("res://scenes/lookdev/alder_lookdev.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await process_frame
	scene.camera.fov = FOV_DEG
	var views: Array = StreetDressing.load_dressing()["capture_views"]
	var failed: int = 0
	for state: String in Lookdev.FAKE_STATES:
		if only_state != "" and state != only_state:
			continue
		scene.set_fake_state(state)
		for v: Dictionary in views:
			scene.camera.look_at_from_position(KitBuilder.cm(v["eye_cm"]), KitBuilder.cm(v["look_cm"]))
			failed += await _shoot(out_dir.path_join("%s_%s_%s.png" % [prefix, str(v["id"]), state]))
	quit(1 if failed > 0 else 0)


func _shoot(path: String) -> int:
	for i: int in SETTLE_FRAMES:
		await process_frame
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	var err: Error = img.save_png(path)
	print(("WROTE %s (%dx%d, %s)" % [path, img.get_width(), img.get_height(), RenderingServer.get_video_adapter_name()])
		if err == OK else "FAILED %s: %s" % [path, error_string(err)])
	return 0 if err == OK else 1
