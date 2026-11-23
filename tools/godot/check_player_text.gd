extends SceneTree
## RB01 release text gate (ADR-019 point 4). Run it through the wrapper, which isolates user:// (the main menu creates a
## local profile when it opens):
##   bash tools/check_player_text.sh [--visible-only] [--report=build/rb01/player_text.json]
## As a release build would (BuildFlavor.simulate_release): instantiates every scene the "Windows Desktop" preset packs,
## lets each run a few frames, and reads every Label, Label3D, Button, RichTextLabel, LineEdit and dialog text, hidden
## panels included unless --visible-only. Also checks every string in content/ui/strings/en.json.
## Exit 0 = no internal ID, phase label, raw snake_case, developer wording or file path anywhere; 1 = findings; 2 = setup.

const Audit := preload("res://scripts/diagnostics/player_text_audit.gd")
const BuildFlavor := preload("res://scripts/ui/build_flavor.gd")
const UserDirGuard := preload("res://tests/support/user_dir_guard.gd")
const SETTLE_FRAMES: int = 4


func _initialize() -> void:
	var visible_only: bool = false
	var report_path: String = ""
	for a: String in OS.get_cmdline_user_args():
		if a == "--visible-only":
			visible_only = true
		elif a.begins_with("--report="):
			report_path = a.trim_prefix("--report=")
	var isolation: String = UserDirGuard.current_error()
	if isolation != "":
		print("PLAYER_TEXT ERROR: %s" % isolation)
		quit(2)
		return
	BuildFlavor.simulate_release(true)
	await process_frame
	var findings: Array[Dictionary] = []
	var scenes: Array[String] = Audit.shipped_scenes()
	if scenes.is_empty():
		print("PLAYER_TEXT ERROR: no shipped scenes found")
		quit(2)
		return
	var nodes_read: int = 0
	for path: String in scenes:
		if Audit.INTERNAL_ONLY_SCENES.has(path):
			print("  internal-only  %s (%s)" % [path, Audit.INTERNAL_ONLY_SCENES[path]])
			continue
		var packed: PackedScene = load(path) as PackedScene
		if packed == null:
			findings.append({"path": path, "text": "(cannot load scene)", "rules": ["load_error"]})
			continue
		var scene: Node = packed.instantiate()
		root.add_child(scene)
		for _i: int in SETTLE_FRAMES:
			await process_frame
		var found: Array[Dictionary] = Audit.scan_tree(scene, visible_only)
		var read: int = Audit.count_text_nodes(scene, visible_only)
		nodes_read += read
		for f: Dictionary in found:
			f["path"] = "%s::%s" % [path, f["path"]]
		findings.append_array(found)
		print("  %-4s %s (%d text nodes)" % ["ok" if found.is_empty() else "FAIL", path, read])
		root.remove_child(scene)
		scene.free()
		await process_frame
	for f: Dictionary in Audit.scan_table(Audit.load_table()):
		f["path"] = "en.json::" + str(f["key"])
		findings.append(f)
	print(Audit.format_findings(findings))
	if report_path != "":
		DirAccess.make_dir_recursive_absolute(report_path.get_base_dir())
		var file: FileAccess = FileAccess.open(report_path, FileAccess.WRITE)
		if file != null:
			file.store_string(JSON.stringify({"scenes": scenes, "text_nodes_read": nodes_read, "findings": findings}, "  "))
			file.close()
	print("PLAYER_TEXT_RESULT %s scenes=%d text_nodes=%d findings=%d" % [
		"ok" if findings.is_empty() else "FAIL", scenes.size(), nodes_read, findings.size()])
	quit(0 if findings.is_empty() else 1)
