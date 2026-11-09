extends "res://tests/test_case.gd"
## SAVE22: the headless suite runs in its own empty user:// and never sees the PC's real saves.

const Guard := preload("res://tests/support/user_dir_guard.gd")
const Persistence := preload("res://scripts/persistence/offline_persistence.gd")


func test_SAVE22_this_run_uses_the_isolated_user_dir() -> void:
	assert_eq(Guard.current_error(), "", "the runner only starts when user:// is isolated")
	var root: String = OS.get_environment(Guard.ENV_NAME)
	assert_true(root != "", "launcher names the isolated root")
	# Every save path the game and tests use resolves through user://, so all of them land in the temp root.
	for path: String in ["user://", Persistence.HEADLESS_SANDBOX_ROOT, "user://profiles"]:
		var abs_path: String = ProjectSettings.globalize_path(path)
		assert_eq(Guard.isolation_error(abs_path.path_join("x"), root, OS.get_name() == "Windows"), "",
			"%s globalizes to %s, inside the isolated root" % [path, abs_path])


func test_SAVE22_guard_refuses_a_missing_root() -> void:
	assert_true(Guard.isolation_error("/home/me/.local/share/godot/app_userdata/LBO", "", false) != "")
	assert_true(Guard.isolation_error("/home/me/.local/share/godot/app_userdata/LBO", "   ", false) != "")


func test_SAVE22_guard_refuses_the_real_user_dir() -> void:
	var real: String = "C:/Users/me/AppData/Roaming/Godot/app_userdata/Lights Back On (working title)"
	assert_true(Guard.isolation_error(real, "C:/Users/me/AppData/Local/Temp/lbo_test_user.abc123", true) != "")


func test_SAVE22_guard_refuses_a_sibling_with_the_same_prefix() -> void:
	assert_true(Guard.isolation_error("/tmp/lbo_test_user.ab10/godot/app_userdata/LBO", "/tmp/lbo_test_user.ab1", false) != "",
		"a directory name that only starts with the root is outside it")
	assert_true(Guard.isolation_error("/tmp/lbo_test_user.ab1", "/tmp/lbo_test_user.ab1", false) != "",
		"user:// is a subdirectory of the root, never the root itself")


func test_SAVE22_guard_accepts_godot_paths_under_the_root() -> void:
	assert_eq(Guard.isolation_error("/tmp/lbo_test_user.ab1/godot/app_userdata/LBO", "/tmp/lbo_test_user.ab1/", false), "")
	# Windows: Godot reports forward slashes; the launcher may pass backslashes or a different drive-letter case.
	assert_eq(Guard.isolation_error("C:/Users/me/AppData/Local/Temp/lbo_test_user.x/Godot/app_userdata/LBO",
		"c:\\users\\me\\appdata\\local\\temp\\lbo_test_user.x", true), "")
	assert_true(Guard.isolation_error("/tmp/LBO_TEST_USER.X/godot/app_userdata/LBO", "/tmp/lbo_test_user.x", false) != "",
		"Linux paths stay case-sensitive")


func test_SAVE22_guard_ignores_dot_segments_that_escape_the_root() -> void:
	assert_true(Guard.isolation_error("/tmp/lbo_test_user.ab1/../real/godot/app_userdata/LBO", "/tmp/lbo_test_user.ab1", false) != "")
