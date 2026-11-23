extends "res://tests/test_case.gd"
## Headless scene submission count is a proxy, not a measured GPU draw-call number.
## Stress replays use real SessionHost inspect command envelopes and duplicate gates.
const Atlas := preload("res://scripts/world/dispatch_atlas.gd")
const Plan := preload("res://scripts/world/expedition_layout_plan.gd")
const Graybox := preload("res://scripts/world/expedition_graybox.gd")
const Batch := preload("res://scripts/world/exp021_render_batch.gd")
const Art := preload("res://scripts/world/exp021_environment_art.gd")
const Runtime := preload("res://scripts/gameplay/expedition_host_session.gd")
const EVIDENCE: String = "res://build/exp021-a04/headless-performance.json"

var _position: Vector3 = Vector3.ZERO


func _host_position(_player: String) -> Vector3:
	return _position


func _message(session: String, seq: int) -> PackedByteArray:
	return JSON.stringify({"session": session, "seq": seq, "type": "inspect",
		"entity": "PANEL_WEST", "payload": {}}).to_utf8_buffer()


func _write(payload: Dictionary) -> void:
	var parent: String = ProjectSettings.globalize_path(EVIDENCE.get_base_dir())
	var err: Error = DirAccess.make_dir_recursive_absolute(parent)
	assert_eq(err, OK)
	if err != OK:
		return
	var file: FileAccess = FileAccess.open(EVIDENCE, FileAccess.WRITE)
	assert_true(file != null)
	if file != null:
		file.store_string(JSON.stringify(payload, "\t") + "\n")
		file.flush()
		file.close()


func test_EXP021_A04_25_region_mesh_batches_and_25_host_stress_cases() -> void:
	var catalog: Dictionary = Atlas.load_catalog()
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var reports: Array[Dictionary] = []
	var saved: int = 0
	var accepted: int = 0
	var duplicates: int = 0
	var denials: int = 0
	var host_elapsed_us: int = 0
	for region: int in range(25):
		var serial: int = region * 8 + 1
		var plan: Dictionary = Plan.make_plan(
			catalog["levels"][serial - 1], catalog["locations"][serial - 1])
		var world: Node3D = Graybox.build(plan)
		assert_true(world != null)
		if world == null:
			continue
		tree.root.add_child(world)
		var out: Dictionary = Batch.optimize(world, plan)
		assert_true(out.get("ok", false), "batch source LV_%03d %s" % [serial, str(out)])
		if out.get("ok", false):
			assert_true(int(out["source_meshes"]) >= 12)
			assert_true(int(out["draw_batches"]) <= 4)
			assert_eq(out.get("new_collision_objects"), 0)
			assert_true(Batch.inspect_optimized(world, plan).get("ok", false))
			saved += int(out["submission_proxy_saved"])
		tree.root.remove_child(world)
		world.free()
		# Separate simulation: one real host, correct peer/session, 16 exact
		# duplicates and 8 rejected external peer attempts per region.
		var host: Runtime = Runtime.new()
		_position = Vector3.ZERO
		var started: Dictionary = host.start_exp016_source_qualification(
			"LV_%03d" % serial, Callable(self, "_host_position"))
		assert_true(started.get("ok", false), str(started))
		if not started.get("ok", false):
			continue
		_position = host.definition_snapshot()["positions"]["PANEL_WEST"]
		host.host.tick(1)
		var packet: PackedByteArray = _message(host.session_id(), 1)
		var start_us: int = Time.get_ticks_usec()
		var reply: Dictionary = host.receive(1, packet)
		assert_true(reply.get("ok", false), str(reply))
		if reply.get("ok", false):
			accepted += 1
		var after: Dictionary = host.authoritative_state().duplicate(true)
		for j: int in range(16):
			var again: Dictionary = host.receive(1, packet)
			assert_true(again.get("duplicate", false), str(again))
			assert_eq(host.authoritative_state(), after)
			if again.get("duplicate", false):
				duplicates += 1
		for j: int in range(8):
			var denied: Dictionary = host.receive(999, _message(host.session_id(), j + 2))
			assert_eq(str(denied.get("code", "")), "UNKNOWN_PEER")
			if str(denied.get("code", "")) == "UNKNOWN_PEER":
				denials += 1
		host_elapsed_us += Time.get_ticks_usec() - start_us
		reports.append({"level_id": "LV_%03d" % serial,
			"region_id": "REG_%02d" % (region + 1),
			"source_meshes": int(out.get("source_meshes", 0)),
			"batched_submissions": int(out.get("draw_batches", 0)),
			"source_task_count": (catalog["levels"][serial - 1]["tasks"] as Array).size(),
			"accepted_host_inspect": bool(reply.get("ok", false)),
			"duplicate_copies": 16, "unknown_peer_denials": 8})
	assert_eq(reports.size(), 25)
	assert_eq(accepted, 25)
	assert_eq(duplicates, 400)
	assert_eq(denials, 200)
	assert_true(saved >= 25 * 8)
	assert_true(Art.cached_box_mesh_count() < 100)
	_write({"phase": "EXP021_A04", "status": "PASS" if failures.is_empty() else "FAIL",
		"scope": "HEADLESS_SCENE_SUBMISSION_PROXY_AND_SIMULATED_HOST_STRESS",
		"actual_gpu_p95": "NOT_MEASURED",
		"real_steam_network": "NOT_TESTED",
		"sampled_regions": reports.size(), "mesh_submissions_saved_proxy": saved,
		"authenticated_host_inspects": accepted,
		"idempotent_duplicate_replays": duplicates,
		"wrong_peer_denials": denials,
		"host_stress_elapsed_us_observation_only": host_elapsed_us,
		"reports": reports,
		"all_200_source_identity": "INHERITED_EXP018_A05_QUALIFIED",
		"full_200_3d_physical_playability": "NOT_ESTABLISHED"})

func test_EXP021_A04_forged_source_rejected_without_scene_mutation() -> void:
	var catalog: Dictionary = Atlas.load_catalog()
	var plan: Dictionary = Plan.make_plan(catalog["levels"][0], catalog["locations"][0])
	var world: Node3D = Graybox.build(plan)
	var before: int = world.get_child_count()
	var invalid: Dictionary = plan.duplicate(true)
	invalid["region_id"] = "REG_23"
	assert_false(Batch.optimize(world, invalid).get("ok", false))
	assert_eq(world.get_child_count(), before)
	assert_true(Batch.optimize(world, plan).get("ok", false))
	assert_false(Batch.optimize(world, plan).get("ok", false))
	world.free()
