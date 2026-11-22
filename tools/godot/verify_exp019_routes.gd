extends SceneTree
## EXP019 A01: independently inspect each live Godot physics world, not just
## the deterministic source plan. This SceneTree (unlike the synchronous unit
## test runner) owns its awaited physics frames and frees all geometry before
## proceeding to the next source site.
const Atlas := preload("res://scripts/world/dispatch_atlas.gd")
const Plan := preload("res://scripts/world/expedition_layout_plan.gd")
const Graybox := preload("res://scripts/world/expedition_graybox.gd")
const Physical := preload("res://scripts/world/exp019_physical_worksite.gd")
const EXPECTED_SAMPLES: int = 200 * 4 * 3 * 3

var _failures: Array[String] = []
var _checked: int = 0


func _initialize() -> void:
	await process_frame
	var atlas: Dictionary = Atlas.load_catalog()
	if (atlas.get("levels", []) as Array).size() != 200:
		print("EXP019_PHYSICS_FATAL_INVALID_ATLAS")
		quit(2)
		return
	for i: int in range(200):
		var level: Dictionary = atlas["levels"][i]
		var location: Dictionary = atlas["locations"][i]
		var plan: Dictionary = Plan.make_plan(level, location)
		var audit: Dictionary = Physical.inspect(plan)
		if not audit.get("ok", false):
			_failures.append("%s source rejected: %s" % [str(level["id"]), str(audit)])
			continue
		var world: Node3D = Graybox.build(plan)
		if world == null:
			_failures.append("%s graybox failed" % str(level["id"]))
			continue
		var candidate: Node3D = Physical.build(plan, world)
		if candidate == null:
			world.free()
			_failures.append("%s physical collision build failed" % str(level["id"]))
			continue
		root.add_child(world)
		world.add_child(candidate)
		# Engine advances colliders before we interrogate its direct space state.
		await physics_frame
		var body: StaticBody3D = candidate.get_node("PhysicalSurfaces") as StaticBody3D
		if PhysicsServer3D.body_get_shape_count(body.get_rid()) != 52:
			_failures.append("%s wrong shape count" % str(level["id"]))
		for route: Dictionary in audit["routes"]:
			var points: Array[Vector3] = [
				route["start"], route["rise"], route["crest"], route["finish"]]
			for edge: int in range(3):
				for j: int in range(3):
					var fraction: float = (float(j) + 1.0) / 4.0
					var sample: Vector3 = points[edge].lerp(points[edge + 1], fraction)
					var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
						Vector3(sample.x, 5.0, sample.z),
						Vector3(sample.x, -0.60, sample.z), 1)
					var hit: Dictionary = root.get_world_3d().direct_space_state.intersect_ray(query)
					if hit.is_empty() or hit.get("collider") != body:
						_failures.append("%s route %d/%d/%d missing physical contact" % [
							str(level["id"]), int(route["index"]), edge, j])
					else:
						var actual: Vector3 = hit["position"]
						var expected: float = sample.y + Physical.THICKNESS_M * 0.5
						if absf(actual.y - expected) > 0.28:
							_failures.append("%s route %d/%d/%d height %.3f != %.3f" % [
								str(level["id"]), int(route["index"]), edge, j, actual.y, expected])
					_checked += 1
		root.remove_child(world)
		world.free()
		# Ensures no stale collider RID pollutes the next site's scene.
		await physics_frame
		if (i + 1) % 25 == 0:
			print("EXP019_A01_PHYSICS_PROGRESS=%d/200 samples=%d failures=%d" % [
				i + 1, _checked, _failures.size()])
			if _failures.size() > 80:
				break
	var expected_samples: int = EXPECTED_SAMPLES
	if _checked != expected_samples:
		_failures.append("actual samples %d != %d" % [_checked, expected_samples])
	var report: Dictionary = {
		"phase": "EXP019_A01", "qualification": Physical.QUALIFICATION,
		"source_sites": 200, "physics_ray_samples": _checked,
		"expected_ray_samples": expected_samples, "failure_count": _failures.size(),
		"failures": _failures, "human_controller_certified": false,
		"steam_or_release_certified": false}
	DirAccess.make_dir_recursive_absolute("res://build/exp019-a01")
	var file: FileAccess = FileAccess.open("res://build/exp019-a01/physics-reachability.json",
		FileAccess.WRITE)
	if file == null:
		print("EXP019_A01_EVIDENCE_WRITE_FAILURE")
		quit(2)
		return
	file.store_string(JSON.stringify(report, "\t", false) + "\n")
	file.close()
	for reason: String in _failures.slice(0, 30):
		print("EXP019_A01_PHYSICS_FAIL=" + reason)
	print("EXP019_A01_PHYSICS_SUMMARY=" + JSON.stringify({
		"samples": _checked, "failures": _failures.size(),
		"evidence": "build/exp019-a01/physics-reachability.json"}))
	quit(0 if _failures.is_empty() else 1)
