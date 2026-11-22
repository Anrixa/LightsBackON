extends RefCounted
## EXP019 A04: physical closure and reopening of source-specific bypasses.
## Collision is a read-only projection of existing host hazard and grid state.
## It never generates a new mission, damage, reward, timer or network RPC.
const Physical := preload("res://scripts/world/exp019_physical_worksite.gd")
const Profiles := preload("res://scripts/world/expedition_environment_feedback.gd")
const QUALIFICATION: String = "AUTOMATED_HOST_SOURCED_COLLISION_CONTROLLER_RELEASE_HELD"
const CLASSES: Array[String] = ["depth", "conductivity", "mechanical",
	"structure", "weather"]


static func _deny(code: String) -> Dictionary:
	return {"ok": false, "code": code, "qualification": QUALIFICATION}


static func inspect(plan: Dictionary) -> Dictionary:
	var physical: Dictionary = Physical.inspect(plan)
	if not physical.get("ok", false):
		return _deny("EXP019_A04_PHYSICAL_SOURCE_INVALID")
	var region: String = str(plan.get("region_id", ""))
	if not Profiles.PROFILES.has(region):
		return _deny("EXP019_A04_UNKNOWN_REGION")
	var category: String = str(Profiles.PROFILES[region]["apparatus"])
	if not CLASSES.has(category):
		return _deny("EXP019_A04_UNKNOWN_RISK_CLASS")
	var routes: Array = physical["routes"]
	var restrictions: Array[Dictionary] = []
	# Each class obstructs a different access segment; the collidable raised
	# crossing on every route remains accessible for worksite recovery.
	var lane_ids: Array[int] = [0, 2] if category == "depth" else \
		[1, 3] if category == "conductivity" else \
		[2] if category == "mechanical" else \
		[3] if category == "structure" else [1, 2]
	for lane: int in lane_ids:
		var original: Dictionary = routes[lane]
		var point: Vector3 = original["start"].lerp(original["detour"], 0.84)
		var normal: Vector3 = original["detour"] - original["start"]
		normal.y = 0
		restrictions.append({"lane": lane, "position": Vector3(point.x, 0.72, point.z),
			"yaw": atan2(normal.x, normal.z), "kind": category})
	var unstable: Dictionary = routes[0]
	var power_pos: Vector3 = unstable["finish"].lerp(unstable["detour"], 0.82)
	return {"ok": true, "level_id": physical["level_id"],
		"region_id": physical["region_id"], "location_id": physical["location_id"],
		"risk": plan["hazard"], "risk_class": category,
		"closures": restrictions, "power_closure": Vector3(power_pos.x, 0.62, power_pos.z),
		"power_yaw": atan2((unstable["detour"] as Vector3).x - (unstable["finish"] as Vector3).x,
			(unstable["detour"] as Vector3).z - (unstable["finish"] as Vector3).z),
		"signature": physical["signature"], "qualification": QUALIFICATION}


static func _wall(body: StaticBody3D, label: String, point: Vector3, yaw: float,
		material: Material) -> void:
	var barrier: StaticBody3D = StaticBody3D.new()
	barrier.collision_layer = 1
	barrier.collision_mask = 1
	barrier.name = label
	barrier.position = point
	barrier.rotation.y = yaw
	body.add_child(barrier)
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = Vector3(2.40, 1.44, 0.24)
	var coll: CollisionShape3D = CollisionShape3D.new()
	coll.name = "Collision"
	coll.shape = shape
	coll.disabled = true
	barrier.add_child(coll)
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = shape.size
	var visual: MeshInstance3D = MeshInstance3D.new()
	visual.name = "Barrier"
	visual.mesh = mesh
	visual.material_override = material
	visual.visible = false
	barrier.add_child(visual)


static func build(plan: Dictionary, world: Node3D) -> Node3D:
	var audit: Dictionary = inspect(plan)
	if not audit.get("ok", false) or world == null or \
			str(world.get_meta("source_level_id", "")) != str(audit["level_id"]) or \
			world.get_node_or_null("EXP019_A01_PhysicalWorksite") == null:
		return null
	var root: Node3D = Node3D.new()
	root.name = "EXP019_A04_HostContingencies"
	root.set_meta("source_level_id", audit["level_id"])
	root.set_meta("source_region_id", audit["region_id"])
	root.set_meta("risk_class", audit["risk_class"])
	root.set_meta("source_signature", audit["signature"])
	root.set_meta("last_host_revision", -1)
	root.set_meta("last_grid_tick", -1)
	root.set_meta("qualification", QUALIFICATION)
	var holder: StaticBody3D = StaticBody3D.new()
	holder.name = "ControlledAccessBarriers"
	holder.collision_layer = 1
	holder.collision_mask = 1
	root.add_child(holder)
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color("#A65B4C")
	for i: int in range((audit["closures"] as Array).size()):
		var closure: Dictionary = audit["closures"][i]
		_wall(holder, "Hazard%02d" % i, closure["position"], closure["yaw"], material)
	_wall(holder, "GridUnstable", audit["power_closure"], float(audit["power_yaw"]), material)
	return root


## No partial collision changes: validate identity, risk and monotonic source
## revisions before updating any wall. set_deferred avoids physics flush mutation.
static func reflect(root: Node3D, board: Dictionary, grid: Dictionary) -> Dictionary:
	if root == null or root.get_meta("qualification", "") != QUALIFICATION or \
			not board.get("ok", false) or \
			str(board.get("level_id", "")) != str(root.get_meta("source_level_id", "")):
		return _deny("EXP019_A04_INVALID_HOST_SOURCE")
	if typeof(board.get("host_revision")) != TYPE_INT or \
			int(board["host_revision"]) < int(root.get_meta("last_host_revision", -1)) or \
			typeof(grid.get("tick")) != TYPE_INT or \
			int(grid["tick"]) < int(root.get_meta("last_grid_tick", -1)):
		return _deny("EXP019_A04_STALE_HOST_OR_GRID")
	var worksite: Variant = board.get("worksite")
	if not worksite is Dictionary or not worksite.get("site_hazards") is Dictionary:
		return _deny("EXP019_A04_MISSING_HOST_HAZARD")
	var hazard: Dictionary = worksite["site_hazards"]
	if str(hazard.get("level_id", "")) != str(root.get_meta("source_level_id", "")) or \
			str(hazard.get("region_id", "")) != str(root.get_meta("source_region_id", "")) or \
			str(hazard.get("risk_class", "")) != str(root.get_meta("risk_class", "")) or \
			typeof(hazard.get("solved")) != TYPE_BOOL or \
			not hazard.get("fault") is String:
		return _deny("EXP019_A04_HAZARD_IDENTITY_DRIFT")
	if not grid.get("nodes") is Dictionary:
		return _deny("EXP019_A04_MISSING_GRID")
	var nodes: Dictionary = grid["nodes"]
	if not nodes.get("GRID") is Dictionary or not nodes.get("WEST") is Dictionary or \
			typeof(nodes["GRID"].get("online")) != TYPE_BOOL or \
			typeof(nodes["WEST"].get("tripped")) != TYPE_BOOL or \
			typeof(nodes["WEST"].get("failed")) != TYPE_BOOL:
		return _deny("EXP019_A04_BAD_GRID_STATE")
	var host_hazard_active: bool = not bool(hazard["solved"]) or str(hazard["fault"]) != ""
	var unstable: bool = not bool(nodes["GRID"]["online"]) or \
			bool(nodes["WEST"]["tripped"]) or bool(nodes["WEST"]["failed"])
	var holder: StaticBody3D = root.get_node("ControlledAccessBarriers") as StaticBody3D
	for station: Node in holder.get_children():
		var barrier: Node3D = station as Node3D
		var active: bool = unstable if barrier.name == "GridUnstable" else host_hazard_active
		var shape: CollisionShape3D = barrier.get_node("Collision") as CollisionShape3D
		var visual: MeshInstance3D = barrier.get_node("Barrier") as MeshInstance3D
		shape.set_deferred("disabled", not active)
		visual.visible = active
		barrier.set_meta("closed_by_host", active)
	root.set_meta("last_host_revision", board["host_revision"])
	root.set_meta("last_grid_tick", grid["tick"])
	return {"ok": true, "hazard_blocked": host_hazard_active,
		"supply_blocked": unstable, "qualification": QUALIFICATION}
