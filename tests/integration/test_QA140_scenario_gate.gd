extends "res://tests/test_case.gd"
## QA140: the unattended scenario driver is opt-in, internal-only and rides on an active QA56 capture.

const Scenario := preload("res://scripts/diagnostics/qa140_scenario_driver.gd")
const FrameProbe := preload("res://scripts/diagnostics/qa56_frame_probe.gd")


func test_QA140_scenario_requires_explicit_argument() -> void:
	assert_true(Scenario.requested(PackedStringArray(["--qa56-capture", "--qa140-scenario"])))
	assert_false(Scenario.requested(PackedStringArray(["--qa56-capture"])))
	assert_false(Scenario.requested(PackedStringArray([])))


func test_QA140_scenario_is_gated_to_internal_or_editor_builds() -> void:
	assert_eq(Scenario.allowed(), OS.has_feature("internal") or OS.has_feature("editor"))
	var source: String = FileAccess.get_file_as_string("res://scripts/diagnostics/qa140_scenario_driver.gd")
	assert_true(source.contains("OS.has_feature(\"internal\") or OS.has_feature(\"editor\")"),
		"release exports must not run the scripted scenario")
	var boot_source: String = FileAccess.get_file_as_string("res://scenes/boot/boot.gd")
	assert_true(boot_source.contains("if not QA140Scenario.allowed():"), "boot must check the build gate")
	# The scenario starts only after a QA56 probe was configured (it returns earlier otherwise).
	assert_true(boot_source.find("_start_qa140_scenario_if_requested(args, probe, session_id)") >
		boot_source.find("if not probe.configure(session_id):"))


func test_QA140_driver_is_idle_until_added_to_tree() -> void:
	var driver: Node = Scenario.new()
	assert_false(driver.is_processing(), "no monitor sampling or input before the scenario starts")
	assert_eq(driver.process_mode, Node.PROCESS_MODE_ALWAYS)
	driver.free()


func test_QA140_probe_segment_marker_ignores_repeats_and_negatives() -> void:
	var probe: Node = FrameProbe.new()
	probe.call("mark_segment", 2)
	assert_eq(int(probe.get("_segment")), 2)
	probe.call("mark_segment", -1)
	assert_eq(int(probe.get("_segment")), 2)
	probe.call("mark_segment", 2)
	assert_eq(int(probe.get("_segment")), 2)
	probe.free()
