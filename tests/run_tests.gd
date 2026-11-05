extends SceneTree
## Minimal headless test runner with no third-party addons.
##
##   godot --headless --path . -s res://tests/run_tests.gd -- [--filter=text] [--dir=res://tests]\n##   Optional QA53 diagnosis: --settle-frames=30 (2 normally); never hides engine warnings.
##
## Finds every res://tests/**/test_*.gd, instantiates it, and runs each method whose
## name starts with "test_". Exit code 0 = all passed, 1 = failures, 2 = runner error.
## Name test methods after the acceptance-matrix ID where one exists, e.g. test_SIM08_equality_is_not_overload.

const TEST_CASE_PATH := "res://tests/test_case.gd"


func _initialize() -> void:
	var filter := ""
	var root_dir := "res://tests"
	var settle_frames: int = 2
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--filter="):
			filter = a.trim_prefix("--filter=")
		elif a.begins_with("--dir="):
			root_dir = a.trim_prefix("--dir=")
		elif a.begins_with("--settle-frames="):
			var value: String = a.trim_prefix("--settle-frames=")
			if value.is_valid_int():
				settle_frames = clampi(int(value), 2, 60)
	# The root window joins the tree after _initialize starts; scene tests need its physics world.
	await process_frame
	var result: int = _run(root_dir, filter)
	# The HUD/tablet legitimately queue_free() their previous child trees when reflowing.
	# These queues need end-of-frame processing before quitting, otherwise the
	# headless runner reports orphaned CanvasItems even though gameplay cleans them.
	for _i: int in settle_frames:
		await process_frame
	quit(result)


func _collect(dir_path: String, out: Array[String]) -> void:
	var d := DirAccess.open(dir_path)
	if d == null:
		return
	var names: Array[String] = []
	d.list_dir_begin()
	var n := d.get_next()
	while n != "":
		if n != "." and n != "..":
			names.append(n)
		n = d.get_next()
	d.list_dir_end()
	names.sort()  # deterministic order
	for name in names:
		var p := dir_path.path_join(name)
		if DirAccess.dir_exists_absolute(p):
			# Diagnostic stress fixtures intentionally create/tear down multiple
			# menu scenes. Keep the canonical gameplay test count and shutdown
			# diagnostics comparable; run them explicitly with --dir below.
			if dir_path == "res://tests" and name == "diagnostics":
				continue
			_collect(p, out)
		elif name.begins_with("test_") and name.ends_with(".gd") and p != TEST_CASE_PATH:
			out.append(p)


func _run(root_dir: String, filter: String) -> int:
	var files: Array[String] = []
	_collect(root_dir, files)
	var n_pass := 0
	var n_fail := 0
	var n_assert := 0
	var report: Array[String] = []
	for path in files:
		var script := load(path) as GDScript
		if script == null:
			print("RUNNER ERROR: cannot load %s" % path)
			return 2
		var method_names: Array[String] = []
		for m in script.get_script_method_list():
			var mn: String = m["name"]
			if mn.begins_with("test_"):
				method_names.append(mn)
		method_names.sort()
		for mn in method_names:
			if filter != "" and not (path.contains(filter) or mn.contains(filter)):
				continue
			var t = script.new()
			t.before_each()
			t.call(mn)
			t.after_each()
			n_assert += t.assertions
			if t.failures.is_empty() and t.assertions > 0:
				n_pass += 1
				print("  PASS  %s::%s" % [path.get_file(), mn])
			else:
				n_fail += 1
				if t.assertions == 0:
					t.failures.append("test made no assertions")
				print("  FAIL  %s::%s" % [path.get_file(), mn])
				for f in t.failures:
					print("        - %s" % f)
	print("tests: %d passed, %d failed, %d assertions" % [n_pass, n_fail, n_assert])
	if n_pass + n_fail == 0:
		print("no tests ran (filter='%s')" % filter)
		return 2 if filter != "" else 0
	return 0 if n_fail == 0 else 1
