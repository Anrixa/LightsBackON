extends RefCounted
## EXP021 A04: coalesce only verified, non-colliding A01 detail boxes into
## material-grouped MultiMesh. This lowers submission count without replacing
## physics bodies, task nodes, host entity identities or legacy materials.
const Art := preload("res://scripts/world/exp021_environment_art.gd")
const ROOT_PATH: String = "EXP014_A03_RegionalFacilities/EXP021_A01_EnvironmentArt"
const QUALIFICATION: String = "HEADLESS_DRAW_SUBMISSION_PROXY_NOT_MEASURED_GPU"

static func _collect(node: Node, output: Array) -> bool:
	for child: Node in node.get_children():
		if child is CollisionObject3D or child is CollisionShape3D or child is Area3D:
			return false
		if child is MeshInstance3D:
			output.append(child)
		if not _collect(child, output):
			return false
	return true


## No partial mutation: every piece, material and source identity is
## validated and all MultiMesh buffers are built before old art is freed.
static func optimize(world: Node3D, plan: Dictionary) -> Dictionary:
	var audit: Dictionary = Art.inspect(plan)
	if not bool(audit.get("ok", false)) or world == null or \
			str(world.get_meta("source_level_id", "")) != str(audit.get("level_id", "")):
		return {"ok": false, "code": "EXP021_A04_SOURCE_PLAN_REJECTED"}
	var art: Node3D = world.get_node_or_null(ROOT_PATH) as Node3D
	if art == null or str(art.get_meta("source_signature", "")) != \
			str(audit["source_signature"]) or \
			art.has_meta("exp021_batch_count"):
		return {"ok": false, "code": "EXP021_A04_SOURCE_ART_MISSING_OR_ALREADY_BATCHED"}
	var sources: Array = []
	if not _collect(art, sources) or sources.size() < 12:
		return {"ok": false, "code": "EXP021_A04_WRONG_GEOMETRY_SCOPE"}
	var groups: Dictionary = {}
	for item: Variant in sources:
		var mesh: MeshInstance3D = item as MeshInstance3D
		if mesh == null or not mesh.mesh is BoxMesh or mesh.material_override == null:
			return {"ok": false, "code": "EXP021_A04_UNSUPPORTED_SOURCE_MESH"}
		var box: BoxMesh = mesh.mesh as BoxMesh
		if not box.size.is_finite() or box.size.x <= 0.0 or \
				box.size.y <= 0.0 or box.size.z <= 0.0:
			return {"ok": false, "code": "EXP021_A04_INVALID_SOURCE_DIMENSIONS"}
		var key: int = mesh.material_override.get_instance_id()
		if not groups.has(key):
			groups[key] = {"material": mesh.material_override, "nodes": []}
		(groups[key]["nodes"] as Array).append(mesh)
	if groups.size() < 2 or groups.size() > 4 or groups.size() >= sources.size():
		return {"ok": false, "code": "EXP021_A04_NO_BATCH_GAIN"}
	var start_us: int = Time.get_ticks_usec()
	var batch_root: Node3D = Node3D.new()
	batch_root.name = "EXP021_A04_OptimizedArt"
	batch_root.set_meta("source_signature", str(audit["source_signature"]))
	batch_root.set_meta("presentation_only", true)
	var unit: BoxMesh = BoxMesh.new()
	unit.size = Vector3.ONE
	# Material ordering is stable by resource-ID within a run; never claimed
	# as persistent identity across runs or used for source acceptance.
	var keys: Array = groups.keys()
	keys.sort()
	for index: int in range(keys.size()):
		var group: Dictionary = groups[keys[index]]
		var members: Array = group["nodes"]
		var multi: MultiMesh = MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.mesh = unit
		multi.instance_count = members.size()
		for slot: int in range(members.size()):
			var visual: MeshInstance3D = members[slot] as MeshInstance3D
			var box: BoxMesh = visual.mesh as BoxMesh
			var local: Transform3D = art.global_transform.affine_inverse() * \
				visual.global_transform
			var scaled: Transform3D = Transform3D(local.basis.scaled(box.size),
				local.origin)
			multi.set_instance_transform(slot, scaled)
		var draw: MultiMeshInstance3D = MultiMeshInstance3D.new()
		draw.name = "Batch%02d" % index
		draw.multimesh = multi
		draw.material_override = group["material"]
		batch_root.add_child(draw)
	art.add_child(batch_root)
	for item: Variant in sources:
		var old: MeshInstance3D = item as MeshInstance3D
		old.get_parent().remove_child(old)
		old.free()
	art.set_meta("exp021_batch_count", keys.size())
	art.set_meta("exp021_original_mesh_count", sources.size())
	var elapsed_us: int = Time.get_ticks_usec() - start_us
	return {"ok": true, "level_id": audit["level_id"],
		"source_meshes": sources.size(), "draw_batches": keys.size(),
		"submission_proxy_saved": sources.size() - keys.size(),
		"cpu_transform_build_us": elapsed_us,
		"scope": QUALIFICATION, "new_collision_objects": 0,
		"source_signature": audit["source_signature"]}


static func inspect_optimized(world: Node3D, plan: Dictionary) -> Dictionary:
	var audit: Dictionary = Art.inspect(plan)
	var art: Node3D = world.get_node_or_null(ROOT_PATH) as Node3D if world != null else null
	if not audit.get("ok", false) or art == null or \
			str(art.get_meta("source_signature", "")) != str(audit.get("source_signature", "")):
		return {"ok": false, "code": "EXP021_A04_BAD_SCENE_ID"}
	var batches: Node3D = art.get_node_or_null("EXP021_A04_OptimizedArt") as Node3D
	if batches == null or batches.get_child_count() < 2:
		return {"ok": false, "code": "EXP021_A04_BATCH_MISSING"}
	var instances: int = 0
	for child: Node in batches.get_children():
		if not child is MultiMeshInstance3D:
			return {"ok": false, "code": "EXP021_A04_UNEXPECTED_DRAW"}
		instances += (child as MultiMeshInstance3D).multimesh.instance_count
	if instances != int(art.get_meta("exp021_original_mesh_count", -1)):
		return {"ok": false, "code": "EXP021_A04_LOST_INSTANCES"}
	return {"ok": true, "instances": instances, "batches": batches.get_child_count(),
		"host_authority_unchanged": true, "scope": QUALIFICATION}
