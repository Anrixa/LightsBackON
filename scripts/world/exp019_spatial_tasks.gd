extends RefCounted
## EXP019 A02 — all 1,000 source tasks have world anchors tied to immutable
## ExpeditionHostSession bindings. This is a read-only visual bridge: operations
## remain on the existing authenticated SessionHost IDs and evidence graph.
const Physical := preload("res://scripts/world/exp019_physical_worksite.gd")
const QUALIFICATION: String = "SOURCE_BOUND_TASK_INTERACTION_HOST_AUTHORITY_ONLY"
const KINDS: Array[String] = ["investigation", "power_routing", "field_repair",
	"optional_discovery", "restoration"]
const ROLES: Array[String] = ["PANEL_WEST", "SW_EAST", "R_WEST",
	"PANEL_SPUR", "ZONE_EXTRACT"]


static func _fail(code: String) -> Dictionary:
	return {"ok": false, "code": code, "qualification": QUALIFICATION}


static func inspect(plan: Dictionary, definitions: Dictionary) -> Dictionary:
	var physical: Dictionary = Physical.inspect(plan)
	if not bool(physical.get("ok", false)):
		return _fail("EXP019_A02_PHYSICAL_ROUTE_REQUIRED")
	if not bool(definitions.get("ok", false)) or \
			str(definitions.get("level_id", "")) != str(plan["id"]):
		return _fail("EXP019_A02_FOREIGN_HOST_DEFINITION")
	var bindings: Variant = definitions.get("bindings")
	var positions: Variant = definitions.get("positions")
	if not bindings is Dictionary or not positions is Dictionary or \
			bindings.size() != 5:
		return _fail("EXP019_A02_BAD_HOST_BINDINGS")
	var anchors: Array[Dictionary] = []
	var task_ids: Dictionary = {}
	for index: int in range(5):
		var station: Dictionary = plan["stations"][index]
		var task_id: String = str(station["id"])
		var kind: String = str(station["kind"])
		if task_ids.has(task_id) or kind != KINDS[index] or \
				not bindings.has(task_id) or not bindings[task_id] is Dictionary:
			return _fail("EXP019_A02_TASK_SOURCE_DRIFT")
		var record: Dictionary = bindings[task_id]
		var entity: String = str(record.get("entity", ""))
		if entity != ROLES[index] or \
				str(record.get("task_id", "")) != task_id or \
				str(record.get("kind", "")) != kind or \
				not positions.has(entity) or \
				not positions[entity] is Vector3 or \
				not record.get("position") is Vector3:
			return _fail("EXP019_A02_UNAUTHENTICATED_TARGET")
		var station_pos: Vector3 = station["position"]
		var target_pos: Vector3 = positions[entity]
		var binding_pos: Vector3 = record["position"]
		if station_pos.distance_to(binding_pos) > 0.01 or \
				Vector2(target_pos.x - station_pos.x,
					target_pos.z - station_pos.z).length() > 0.01 or \
				not target_pos.is_finite() or target_pos.y < 0.0 or target_pos.y > 3.0:
			return _fail("EXP019_A02_WORLD_TARGET_MISMATCH")
		var stand: Vector3 = Vector3(station_pos.x, 0.90, station_pos.z + 1.1)
		if stand.x < 2.0 or stand.x > 50.0 or stand.z < 2.0 or stand.z > 50.0:
			return _fail("EXP019_A02_INACCESSIBLE_STAND")
		if stand.distance_to(target_pos) > 2.30:
			return _fail("EXP019_A02_HOST_INTERACTION_OUT_OF_REACH")
		task_ids[task_id] = true
		anchors.append({"task_id": task_id, "kind": kind, "host_entity": entity,
			"station": station_pos, "target": target_pos, "stand": stand,
			"required": bool(record.get("required", index != 3))})
	return {"ok": true, "level_id": plan["id"], "location_id": plan["location_id"],
		"anchors": anchors, "task_count": 5,
		"signature": physical["signature"],
		"qualification": QUALIFICATION, "source_task_ids": task_ids.keys()}


static func _material(color: Color) -> StandardMaterial3D:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.4
	return mat


static func build(plan: Dictionary, definitions: Dictionary, world: Node3D) -> Node3D:
	var audit: Dictionary = inspect(plan, definitions)
	if not bool(audit.get("ok", false)) or world == null or \
			str(world.get_meta("source_level_id", "")) != str(audit["level_id"]) or \
			world.get_node_or_null("EXP019_A01_PhysicalWorksite") == null:
		return null
	var root: Node3D = Node3D.new()
	root.name = "EXP019_A02_SpatialTaskAnchors"
	root.set_meta("source_level_id", audit["level_id"])
	root.set_meta("source_task_ids", audit["source_task_ids"])
	root.set_meta("source_route_signature", audit["signature"])
	root.set_meta("last_host_revision", -1)
	root.set_meta("qualification", QUALIFICATION)
	root.set_meta("host_authority_only", true)
	for index: int in range(5):
		var item: Dictionary = audit["anchors"][index]
		var marker: Node3D = Node3D.new()
		marker.name = "Task%02d" % (index + 1)
		marker.position = item["station"]
		marker.set_meta("task_id", item["task_id"])
		marker.set_meta("host_entity", item["host_entity"])
		marker.set_meta("task_kind", item["kind"])
		marker.set_meta("standoff", item["stand"])
		marker.set_meta("host_completed", false)
		root.add_child(marker)
		var ring: CylinderMesh = CylinderMesh.new()
		ring.top_radius = 0.60
		ring.bottom_radius = 0.60
		ring.height = 0.07
		var mesh: MeshInstance3D = MeshInstance3D.new()
		mesh.name = "WorkArea"
		mesh.mesh = ring
		mesh.position = Vector3(0, -0.07, 0)
		mesh.material_override = _material(Color("#66818F"))
		marker.add_child(mesh)
		var label: Label3D = Label3D.new()
		label.name = "HostTaskStatus"
		label.text = "%s / %s / PENDING" % [item["task_id"], item["host_entity"]]
		label.position = Vector3(0, 2.0, 0)
		label.font_size = 40
		label.pixel_size = 0.005
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		marker.add_child(label)
	return root


## Only a host task_board may change visible completion. No client progress,
## local collision trigger, tool animation or presentation timer calls this.
static func reflect(root: Node3D, board: Dictionary) -> Dictionary:
	if root == null or root.get_meta("qualification", "") != QUALIFICATION or \
			not bool(root.get_meta("host_authority_only", false)) or \
			not board.get("ok", false) or \
			str(board.get("level_id", "")) != str(root.get_meta("source_level_id", "")):
		return _fail("EXP019_A02_UNTRUSTED_TASK_BOARD")
	if typeof(board.get("host_revision")) != TYPE_INT or \
			int(board["host_revision"]) < int(root.get_meta("last_host_revision", -1)):
		return _fail("EXP019_A02_STALE_HOST_REVISION")
	var tasks: Variant = board.get("tasks")
	if not tasks is Array or tasks.size() != 5:
		return _fail("EXP019_A02_INVALID_TASK_SNAPSHOT")
	var prepared: Array[bool] = []
	for index: int in range(5):
		var record: Variant = tasks[index]
		var marker: Node3D = root.get_node_or_null("Task%02d" % (index + 1)) as Node3D
		if not record is Dictionary or marker == null or \
				str(record.get("id", "")) != str(marker.get_meta("task_id", "")) or \
				str(record.get("kind", "")) != str(marker.get_meta("task_kind", "")) or \
				str(record.get("binding", "")) != str(marker.get_meta("host_entity", "")) or \
				typeof(record.get("completed")) != TYPE_BOOL:
			return _fail("EXP019_A02_TASK_HOST_BINDING_DRIFT")
		prepared.append(bool(record["completed"]))
	# Validate all five before mutating any material or label.
	for index: int in range(5):
		var marker: Node3D = root.get_node("Task%02d" % (index + 1)) as Node3D
		var done: bool = prepared[index]
		var mesh: MeshInstance3D = marker.get_node("WorkArea") as MeshInstance3D
		var mat: StandardMaterial3D = mesh.material_override as StandardMaterial3D
		var label: Label3D = marker.get_node("HostTaskStatus") as Label3D
		mat.albedo_color = Color("#72CDD2") if done else Color("#66818F")
		label.text = "%s / %s / %s" % [str(marker.get_meta("task_id")),
			str(marker.get_meta("host_entity")), "HOST-COMPLETE" if done else "PENDING"]
		marker.set_meta("host_completed", done)
	root.set_meta("last_host_revision", int(board["host_revision"]))
	return {"ok": true, "completed": prepared.count(true),
		"host_revision": board["host_revision"], "qualification": QUALIFICATION}
