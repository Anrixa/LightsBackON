extends "res://tests/test_case.gd"
## DS stage audit on built dispatch stages: no floating geometry, nothing outside the site, no host target inside a
## collider, no station inside a building, and a clear spawn facing station 01. 50 levels cover every region twice
## (levels 1, 5, 9, ... 197); LBO_FULL_STAGE_AUDIT=1 runs all 200 (docs/evidence/DS-stage-audit.md).
const Stage := preload("res://scenes/expeditions/mission_stage.tscn")
const Audit := preload("res://scripts/diagnostics/stage_audit.gd")


func test_DS_STAGE_AUDIT_sampled_dispatch_levels_are_physically_coherent() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	# LBO_FULL_STAGE_AUDIT=1 audits all 200 levels (about 4 minutes); the default samples every fourth.
	var step: int = 1 if OS.get_environment("LBO_FULL_STAGE_AUDIT") == "1" else 4
	for i: int in range(1, 201, step):
		var level_id: String = "LV_%03d" % i
		var stage: Node3D = Stage.instantiate()
		stage.set("level_id", level_id)
		tree.root.add_child(stage)
		var report: Dictionary = Audit.audit(stage)
		assert_true(bool(report.get("ok", false)), "%s: %s" % [level_id, str({
			"floating": report.get("floating"), "out_of_bounds": report.get("out_of_bounds"),
			"buried_targets": report.get("buried_targets"), "spawn": report.get("spawn")})])
		tree.root.remove_child(stage)
		stage.free()


func test_DS_STAGE_AUDIT_detects_a_floating_part() -> void:
	# The audit must not pass vacuously: lift a worksite cabinet back off the ground and expect a finding.
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var stage: Node3D = Stage.instantiate()
	stage.set("level_id", "LV_001")
	tree.root.add_child(stage)
	var lifted: Node3D = null
	for group: Node in stage.find_children("Assemblies", "", true, false):
		lifted = group.get_child(0) as Node3D
		break
	assert_true(lifted != null)
	if lifted != null:
		# Well clear of the 2.6 m access gantry, so nothing it touches can hold it up.
		lifted.position.y = 5.0
		var report: Dictionary = Audit.audit(stage)
		assert_false(bool(report.get("ok", true)))
		assert_true((report.get("floating", []) as Array).size() > 0)
	tree.root.remove_child(stage)
	stage.free()
