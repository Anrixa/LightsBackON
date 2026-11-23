extends "res://tests/test_case.gd"
## Source/host-only audio proofs; headless never opens a live audio endpoint.
const Atlas := preload("res://scripts/world/dispatch_atlas.gd")
const Plan := preload("res://scripts/world/expedition_layout_plan.gd")
const Graybox := preload("res://scripts/world/expedition_graybox.gd")
const Audio := preload("res://scripts/world/exp021_spatial_audio.gd")

func test_EXP021_A02_200_independent_source_bindings_and_original_waves() -> void:
	var catalog: Dictionary = Atlas.load_catalog()
	var signatures: Dictionary = {}
	for i: int in range(200):
		var plan: Dictionary = Plan.make_plan(catalog["levels"][i], catalog["locations"][i])
		var checked: Dictionary = Audio.inspect(plan)
		assert_true(checked.get("ok", false))
		if checked.get("ok", false):
			assert_false(signatures.has(str(checked["signature"])))
			signatures[str(checked["signature"])] = true
	assert_eq(signatures.size(), 200)
	var plan: Dictionary = Plan.make_plan(catalog["levels"][0], catalog["locations"][0])
	var world: Node3D = Graybox.build(plan)
	var audio: Variant = Audio.new()
	var ready: Dictionary = audio.setup(world, plan)
	assert_true(ready.get("ok", false))
	assert_eq(int(ready.get("source_audio_streams", 0)), 8)
	assert_true(audio.audio_root().get_node("AcceptedToolCue3D") is AudioStreamPlayer3D)
	assert_true(audio.audio_root().get_node("StormBed").stream is AudioStreamWAV)
	assert_eq((audio.audio_root().get_node("StormBed").stream as AudioStreamWAV).data.size(), 44100)
	world.free()

func test_EXP021_A02_acknowledgements_must_be_host_accepted() -> void:
	var catalog: Dictionary = Atlas.load_catalog()
	var plan: Dictionary = Plan.make_plan(catalog["levels"][0], catalog["locations"][0])
	var world: Node3D = Graybox.build(plan)
	var sound: Variant = Audio.new()
	assert_true(sound.setup(world, plan).get("ok", false))
	assert_false(sound.play_confirmed_command({"ok": false}, "repair_step", "meter", Vector3.ZERO))
	assert_false(sound.play_confirmed_command({"ok": true}, "fabricate", "meter", Vector3.ZERO))
	assert_false(sound.play_confirmed_command({"ok": true}, "repair_step", "unknown", Vector3.ZERO))
	assert_eq(sound.event_count(), 0)
	assert_true(sound.play_confirmed_command({"ok": true}, "repair_step", "crimper", Vector3(5, 1, 5)))
	assert_eq(sound.last_cue(), "crimper")
	assert_eq(sound.event_count(), 1)
	world.free()

func test_EXP021_A02_reject_stale_and_false_grid_supply_before_audio_change() -> void:
	var catalog: Dictionary = Atlas.load_catalog()
	var plan: Dictionary = Plan.make_plan(catalog["levels"][0], catalog["locations"][0])
	var world: Node3D = Graybox.build(plan)
	var sound: Variant = Audio.new()
	assert_true(sound.setup(world, plan).get("ok", false))
	var board: Dictionary = {"level_id": "LV_001", "host_revision": 7, "mission_verified": true}
	var grid: Dictionary = {"tick": 9, "nodes": {
		"GRID": {"online": true}, "LOAD_A": {"supplied": true},
		"LOAD_B": {"supplied": true}, "LOAD_C": {"supplied": true}
	}}
	assert_true(sound.reflect(board, grid).get("ok", false))
	assert_true(sound.is_verified())
	sound.advance(1.0)
	var recovery_db: float = sound.audio_root().get_node("RecoveryBed").volume_db
	var wrong: Dictionary = grid.duplicate(true)
	wrong["tick"] = 10
	wrong["nodes"]["GRID"]["online"] = false
	assert_false(sound.reflect(board, wrong).get("ok", false))
	assert_true(sound.is_verified())
	assert_eq(sound.audio_root().get_node("RecoveryBed").volume_db, recovery_db)
	board["host_revision"] = 8
	grid["tick"] = 11
	grid["nodes"]["LOAD_C"]["supplied"] = false
	assert_true(sound.reflect(board, grid).get("ok", false))
	assert_false(sound.is_verified())
	world.free()
