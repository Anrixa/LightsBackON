extends "res://tests/test_case.gd"
## QA56 is an opt-in local diagnostics path, not a new default export behavior.

const FrameProbe := preload("res://scripts/diagnostics/qa56_frame_probe.gd")


func test_QA56_session_id_accepts_only_32_hex_characters() -> void:
	assert_true(FrameProbe.valid_session_id("0123456789abcdef0123456789abcdef"))
	assert_true(FrameProbe.valid_session_id("ABCDEF0123456789ABCDEF0123456789"))
	assert_false(FrameProbe.valid_session_id(""))
	assert_false(FrameProbe.valid_session_id("0123456789abcdef"))
	assert_false(FrameProbe.valid_session_id("0123456789abcdef0123456789abcde/"))
	assert_false(FrameProbe.valid_session_id("0123456789abcdef0123456789abcdeg"))


func test_QA56_probe_has_no_default_capture_side_effects() -> void:
	var probe: Node = FrameProbe.new()
	assert_false(probe.is_processing(), "capture must be disabled until configured")
	assert_false(probe.is_processing_input(), "F9 marker must be inactive by default")
	probe.free()
	var boot_source: String = FileAccess.get_file_as_string("res://scenes/boot/boot.gd")
	assert_true(boot_source.contains("args.has(\"--qa56-capture\")"),
		"release launch must require explicit telemetry opt-in")
