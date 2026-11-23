extends SceneTree
## RB01 evidence: 1920x1080 screenshots of the screens a player reads first, as a release build shows them.
## Needs a GPU window and an isolated user dir (the menu creates a local profile, the mission writes a checkpoint):
##   APPDATA=<temp dir> godot --path . --resolution 1920x1080 -s "$PWD/tools/godot/capture_player_screens.gd" -- \
##     --out-dir=docs/evidence/RB01/after
## Runs against older checkouts too ("before" shots): it uses BuildFlavor only when that file exists.
## Writes main_menu.png, c01_first_frame.png, c01_pause.png, c01_results.png, c03_notice.png, c04_notice.png.

const BUILD_FLAVOR_PATH: String = "res://scripts/ui/build_flavor.gd"
const MENU_PATH: String = "res://scenes/menu/main_menu.tscn"
const SCREENS: Array[Array] = [
	["c01", "res://scenes/mission/mission_root.tscn"],
	["c03", "res://scenes/mission/c03_roof_preview.tscn"],
	["c04", "res://scenes/mission/c04_sign_spur_preview.tscn"],
]
const SIZE: Vector2i = Vector2i(1920, 1080)
const SETTLE_FRAMES: int = 30
const WARMUP_TIMEOUT_MS: int = 120000


func _initialize() -> void:
	var out_dir: String = "build/rb01"
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--out-dir="):
			out_dir = a.trim_prefix("--out-dir=")
	DirAccess.make_dir_recursive_absolute(out_dir)
	if ResourceLoader.exists(BUILD_FLAVOR_PATH):
		load(BUILD_FLAVOR_PATH).call("simulate_release", true)
	root.size = SIZE
	DisplayServer.window_set_size(SIZE)
	await process_frame
	change_scene_to_file(MENU_PATH)
	await _settle()
	await _shoot(out_dir.path_join("main_menu.png"))
	for screen: Array in SCREENS:
		set_meta("offline_resume", false)
		change_scene_to_file(str(screen[1]))
		await _settle()
		var deadline: int = Time.get_ticks_msec() + WARMUP_TIMEOUT_MS
		while current_scene != null and current_scene.has_method("is_warming") and bool(current_scene.call("is_warming")) \
				and Time.get_ticks_msec() < deadline:
			await process_frame
		await _settle()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		var tag: String = str(screen[0])
		await _shoot(out_dir.path_join(("%s_first_frame.png" if tag == "c01" else "%s_notice.png") % tag))
		if tag == "c01":
			current_scene.call("_toggle_pause")
			await _settle()
			await _shoot(out_dir.path_join("c01_pause.png"))
			current_scene.call("_toggle_pause")
			current_scene.call("_finish")
			await _settle()
			await _shoot(out_dir.path_join("c01_results.png"))
	quit(0)


func _settle() -> void:
	for _i: int in SETTLE_FRAMES:
		await process_frame
	await RenderingServer.frame_post_draw


func _shoot(path: String) -> void:
	var image: Image = root.get_texture().get_image()
	# Saved at the size actually rendered; the log says so if the window could not open at 1920x1080.
	image.save_png(path)
	print("RB01 capture %s rendered=%s%s" % [path, image.get_size(), "" if image.get_size() == SIZE else " (NOT 1920x1080)"])
