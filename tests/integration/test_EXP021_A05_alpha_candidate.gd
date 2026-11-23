extends "res://tests/test_case.gd"
## EXP021 A05: 200 real Godot scene builds, 200 original host startups,
## 1000 immutable task bindings, 25 actual scene effect/audio fixtures.
## This does NOT prove 200 MissionDirector completions or human playability.

const Atlas := preload("res://scripts/world/dispatch_atlas.gd")
const Plan := preload("res://scripts/world/expedition_layout_plan.gd")
const Graybox := preload("res://scripts/world/expedition_graybox.gd")
const Art := preload("res://scripts/world/exp021_environment_art.gd")
const Batch := preload("res://scripts/world/exp021_render_batch.gd")
const Presentation := preload("res://scripts/world/exp017_restoration_feedback.gd")
const Exp018 := preload("res://scripts/world/exp018_host_presentation.gd")
const Audio := preload("res://scripts/world/exp021_spatial_audio.gd")
const Effects := preload("res://scripts/world/exp021_restoration_effects.gd")
const Runtime := preload("res://scripts/gameplay/expedition_host_session.gd")

const REPORT_PATH: String = "res://build/exp021-a05/scene-host-evidence.json"
var _host_player_position: Vector3 = Vector3.ZERO


func _position_for(_player_id: String) -> Vector3:
	return _host_player_position


func _write_evidence(evidence: Dictionary) -> void:
	var root_path: String = ProjectSettings.globalize_path(REPORT_PATH.get_base_dir())
	var result: Error = DirAccess.make_dir_recursive_absolute(root_path)
	assert_eq(result, OK, "A05 evidence directory must be available")
	if result != OK:
		return
	var report: FileAccess = FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	assert_true(report != null, "A05 evidence cannot be silently omitted")
	if report != null:
		report.store_string(JSON.stringify(evidence, "\t") + "\n")
		report.flush()
		report.close()


func _valid_original_stations(plan: Dictionary, board: Dictionary, serial: int) -> bool:
	if not plan.get("stations") is Array or not board.get("tasks") is Array:
		return false
	var markers: Array = plan["stations"]
	var tasks: Array = board["tasks"]
	if markers.size() != 5 or tasks.size() != 5:
		return false
	for slot: int in range(5):
		var expected: String = "JOB_%03d_%d" % [serial, slot + 1]
		if not markers[slot] is Dictionary or not tasks[slot] is Dictionary:
			return false
		if str(markers[slot].get("id", "")) != expected or \
				str(tasks[slot].get("id", "")) != expected:
			return false
	return true


func test_EXP021_A05_200_actual_scenes_host_startups_and_1000_original_task_bindings() -> void:
	var source: Dictionary = Atlas.load_catalog()
	var records: Array[Dictionary] = []
	var task_ids: Dictionary = {}
	var regions: Dictionary = {}
	var scene_count: int = 0
	var host_count: int = 0
	var batch_count: int = 0
	var source_projection_count: int = 0
	var full_audio_fixtures: int = 0
	var unique_scenes: Dictionary = {}
	for serial: int in range(1, 201):
		var level: Dictionary = source["levels"][serial - 1]
		var location: Dictionary = source["locations"][serial - 1]
		var plan: Dictionary = Plan.make_plan(level, location)
		assert_true(plan.get("ok", false), "plan LV_%03d" % serial)
		if not plan.get("ok", false):
			continue
		var audit: Dictionary = Art.inspect(plan)
		assert_true(audit.get("ok", false), "visual source LV_%03d" % serial)
		if not audit.get("ok", false):
			continue
		var visual_sig: String = str(audit["source_signature"])
		assert_false(unique_scenes.has(visual_sig), "unique scene identity")
		unique_scenes[visual_sig] = true
		regions[str(audit["region_id"])] = true
		var world: Node3D = Graybox.build(plan)
		assert_true(world != null, "actual Godot world LV_%03d" % serial)
		if world == null:
			continue
		scene_count += 1
		var collision: Node3D = world.get_node_or_null("CandidateGround") as Node3D
		assert_true(collision is StaticBody3D, "original physical floor is intact")
		var batches: Dictionary = Batch.optimize(world, plan)
		assert_true(batches.get("ok", false), "art batching LV_%03d %s" %
			[serial, str(batches)])
		if not batches.get("ok", false):
			world.free()
			continue
		batch_count += 1
		assert_true(Batch.inspect_optimized(world, plan).get("ok", false))
		var view: Node3D = Presentation.build(plan, world)
		assert_true(view != null, "real original source display")
		if view == null:
			world.free()
			continue
		world.add_child(view)
		var host: Runtime = Runtime.new()
		_host_player_position = Vector3.ZERO
		var started: Dictionary = host.start_exp016_source_qualification(
			"LV_%03d" % serial, Callable(self, "_position_for"))
		assert_true(started.get("ok", false), "real host startup: " + str(started))
		if not started.get("ok", false):
			world.free()
			continue
		host_count += 1
		var board: Dictionary = host.task_board()
		assert_true(board.get("ok", false), "original host task board")
		assert_true(_valid_original_stations(plan, board, serial),
			"one-to-one original 5 task IDs")
		if not _valid_original_stations(plan, board, serial):
			world.free()
			continue
		var per_level_tasks: Array[String] = []
		for task: Dictionary in board["tasks"]:
			var task_id: String = str(task["id"])
			assert_false(task_ids.has(task_id), "duplicate original job ID " + task_id)
			task_ids[task_id] = true
			per_level_tasks.append(task_id)
		var projected: Dictionary = Exp018.reflect(view, host, false)
		assert_true(projected.get("ok", false), "host-driven restoration LV_%03d: %s" %
			[serial, str(projected)])
		if projected.get("ok", false):
			source_projection_count += 1
		if serial % 8 == 1:
			var audio: Variant = Audio.new()
			var audio_ready: Dictionary = audio.setup(world, plan)
			assert_true(audio_ready.get("ok", false), "A02 scene audio")
			var effects: Variant = Effects.new()
			var fx_ready: Dictionary = effects.setup(world, plan)
			assert_true(fx_ready.get("ok", false), "A03 scene effects")
			if audio_ready.get("ok", false) and fx_ready.get("ok", false):
				var grid: Dictionary = host.grid.canonical_state()
				var audio_state: Dictionary = audio.reflect(board, grid)
				var visual_state: Dictionary = effects.reflect(board, grid)
				assert_true(audio_state.get("ok", false), "A02 original grid")
				assert_true(visual_state.get("ok", false), "A03 original grid")
				if audio_state.get("ok", false) and visual_state.get("ok", false):
					full_audio_fixtures += 1
		records.append({
			"level_id": "LV_%03d" % serial,
			"region_id": str(audit["region_id"]),
			"location_id": str(audit["location_id"]),
			"original_task_ids": per_level_tasks,
			"art_signature": visual_sig,
			"physical_world_constructed": true,
			"host_session_started": true,
			"host_canonical_restoration_projected": projected.get("ok", false),
			"decoration_batches": int(batches.get("draw_batches", 0)),
			"physical_playability_qualified": false,
			"mission_director_completed": false
		})
		world.free()
		if serial % 25 == 0:
			print("EXP021_A05 scenes=%d/200 hosts=%d task_ids=%d source_views=%d" %
				[scene_count, host_count, task_ids.size(), source_projection_count])
	assert_eq(scene_count, 200)
	assert_eq(host_count, 200)
	assert_eq(batch_count, 200)
	assert_eq(source_projection_count, 200)
	assert_eq(task_ids.size(), 1000)
	assert_eq(regions.size(), 25)
	assert_eq(unique_scenes.size(), 200)
	assert_eq(records.size(), 200)
	assert_eq(full_audio_fixtures, 25)
	_write_evidence({
		"phase": "EXP021_A05",
		"status": "PASS" if failures.is_empty() else "FAIL",
		"scope": "200_ACTUAL_GODOT_SCENE_ASSEMBLIES_PLUS_HOST_STARTUP_NO_FULL_MISSION",
		"scene_builds": scene_count,
		"host_startups": host_count,
		"source_projections": source_projection_count,
		"environment_batch_assemblies": batch_count,
		"regions": regions.size(),
		"distinct_scenes": unique_scenes.size(),
		"original_task_ids": task_ids.size(),
		"full_audio_fx_samples": full_audio_fixtures,
		"actual_mission_director_completions": "NOT_ESTABLISHED",
		"real_gpu_p95": "NOT_MEASURED",
		"two_client_steam": "NOT_TESTED",
		"human_controller_review": "NOT_TESTED",
		"release": "HOLD",
		"records": records,
		"assertion_failures": failures.duplicate()
	})
