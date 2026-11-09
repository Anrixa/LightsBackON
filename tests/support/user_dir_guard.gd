extends RefCounted
## SAVE22: the headless test runner must never read or write the PC's real Godot user dir.
##
## Godot derives user:// from APPDATA (Windows) or XDG_DATA_HOME (Linux) at startup and offers no runtime override,
## so the launcher (tools/run_tests.sh, tools/qa_resource_probe.py) points those at a fresh per-run directory and
## names it in LBO_TEST_USER_ROOT. The runner refuses to start unless user:// really resolves inside that directory:
## otherwise a checkpoint left by an older build or content revision (CONTENT_MISMATCH) fails unrelated tests, and a
## test could overwrite a player's progress.

const ENV_NAME: String = "LBO_TEST_USER_ROOT"


## "" when the current process is isolated, otherwise a reason a person can act on.
static func current_error() -> String:
	return isolation_error(OS.get_user_data_dir(), OS.get_environment(ENV_NAME), OS.get_name() == "Windows")


## Pure check so it can be unit-tested. Paths may use either slash; Windows paths compare case-insensitively.
static func isolation_error(user_data_dir: String, isolated_root: String, case_insensitive: bool) -> String:
	if isolated_root.strip_edges() == "":
		return "%s is not set; run the suite through tools/run_tests.sh so user:// is a fresh temp dir" % ENV_NAME
	var user: String = _normalized(user_data_dir, case_insensitive)
	var root: String = _normalized(isolated_root, case_insensitive)
	# The trailing slash stops "/tmp/run1" from accepting "/tmp/run10/...".
	if not user.begins_with(root + "/"):
		return "user:// resolves to %s, outside %s=%s; tests would touch the real user dir" % [
			user_data_dir, ENV_NAME, isolated_root]
	return ""


static func _normalized(path: String, case_insensitive: bool) -> String:
	var p: String = path.strip_edges().replace("\\", "/").simplify_path().trim_suffix("/")
	return p.to_lower() if case_insensitive else p
