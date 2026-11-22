extends RefCounted
## EXP017 A02: site-specific spatial grammar for the 200 original dispatches.
## Two non-colliding schematic approaches per site, vertical work platforms,
## service infrastructure and source-hazard obstructions. Neither an actual
## path/LoS solution nor new collision or interaction/routing authority.
const Regional := preload("res://scripts/world/expedition_regional_facilities.gd")
const Identity := preload("res://scripts/world/exp017_region_identity.gd")
const QUALIFICATION: String = Regional.QUALIFICATION
const TILE_M: float = 52.0
const TYPES: Array[String] = ["distribution", "transport", "health", "commerce",
	"waterworks", "communications", "education", "shelter"]
const BARRIERS: Array[String] = ["flood_gate", "service_fence", "fallen_beam",
	"washout", "cable_spool", "silt_bank", "equipment_stack", "rail_barrier"]
const ACCESS: Array[String] = ["catwalk", "overpass", "roof_service", "culvert",
	"service_ramp", "loading_bridge", "ladder_tower", "mezzanine"]


static func _reject(code: String) -> Dictionary:
	return {"ok": false, "code": code, "qualification": QUALIFICATION}


static func inspect(plan: Dictionary) -> Dictionary:
	var region: Dictionary = Regional.inspect(plan)
	if not bool(region.get("ok", false)) or not Identity.inspect(plan).get("ok", false):
		return _reject("EXP017_A02_UNQUALIFIED_REGION")
	var serial: int = int(plan.get("serial", 0))
	var level: String = str(plan.get("id", ""))
	var kind: String = str(plan.get("category", ""))
	var layout: String = str(plan.get("layout_signature", ""))
	if serial < 1 or serial > 200 or level != "LV_%03d" % serial or \
			not TYPES.has(kind) or layout.length() != 64 or \
			str(plan.get("location_id", "")) != "LOC_%03d" % serial:
		return _reject("EXP017_A02_INVALID_SOURCE_PLAN")
	var stations: Variant = plan.get("stations")
	if not stations is Array or stations.size() != 5:
		return _reject("EXP017_A02_INVALID_STATIONS")
	var source_ids: Dictionary = {}
	var route_points: Array[Vector3] = []
	for index: int in range(5):
		var station: Variant = stations[index]
		if not station is Dictionary:
			return _reject("EXP017_A02_BAD_STATION")
		var sid: String = str(station.get("id", ""))
		var position: Variant = station.get("position")
		if sid != "JOB_%03d_%d" % [serial, index + 1] or source_ids.has(sid) or \
				not position is Vector3 or not (position as Vector3).is_finite():
			return _reject("EXP017_A02_SOURCE_MARKER_DRIFT")
		var p: Vector3 = position
		if p.x < 4.0 or p.x > 48.0 or p.z < 4.0 or p.z > 48.0:
			return _reject("EXP017_A02_STATION_OUTSIDE_TILE")
		source_ids[sid] = true
		route_points.append(p)
	var profile: int = (serial * 7 + TYPES.find(kind) * 3) % ACCESS.size()
	var obstacle: int = (serial * 3 + TYPES.find(kind)) % BARRIERS.size()
	var height: float = 1.2 + float((serial + TYPES.find(kind)) % 5) * 0.55
	var signature: String = ("%s|%s|%s|%s|%d|%d|%.2f" % [
		level, layout, str(region["site_signature"]), kind, profile, obstacle, height
	]).sha256_text()
	return {"ok": true, "level_id": level, "region_id": plan["region_id"],
		"location_id": plan["location_id"], "source_task_ids": source_ids.keys(),
		"points": route_points, "access": ACCESS[profile],
		"barrier": BARRIERS[obstacle], "height_m": height,
		"layout_signature": signature, "presentation_only": true,
		"qualification": QUALIFICATION}


static func _mat(hex: String) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color(hex)
	material.metallic = 0.2
	material.roughness = 0.75
	return material


static func _box(parent: Node3D, name: String, position: Vector3,
		size: Vector3, material: Material) -> void:
	var shape: BoxMesh = BoxMesh.new()
	shape.size = size
	var model: MeshInstance3D = MeshInstance3D.new()
	model.name = name
	model.mesh = shape
	model.material_override = material
	model.position = position
	parent.add_child(model)


static func _ribbon(parent: Node3D, name: String, from: Vector3, to: Vector3,
		width: float, material: Material) -> void:
	var difference: Vector3 = to - from
	var planar: Vector2 = Vector2(difference.x, difference.z)
	if planar.length() < 0.2:
		return
	var center: Vector3 = (from + to) * 0.5
	_box(parent, name, center, Vector3(width, 0.14, planar.length()), material)
	var instance: MeshInstance3D = parent.get_node(name) as MeshInstance3D
	instance.rotation.y = atan2(difference.x, difference.z)


static func _safe(point: Vector3) -> Vector3:
	return Vector3(clampf(point.x, 3.0, 49.0), point.y,
		clampf(point.z, 3.0, 49.0))


## A five-part ramp shows an actual rise; separate, non-colliding schematics
## prevent claims of validated body step height or capsule clearance.
static func _ramp(parent: Node3D, name: String, from: Vector3, to: Vector3,
		material: Material) -> void:
	for j: int in range(5):
		var t: float = (float(j) + 0.5) / 5.0
		var point: Vector3 = from.lerp(to, t)
		_box(parent, "%s_Step%02d" % [name, j],
			point, Vector3(0.8, 0.18, 0.65), material)


static func _barrier(parent: Node3D, style: String, position: Vector3,
		brown: Material, danger: Material) -> void:
	var group: Node3D = Node3D.new()
	group.name = "EnvironmentalObstruction_" + style
	group.position = _safe(position)
	group.set_meta("source_barrier_kind", style)
	group.set_meta("visual_only", true)
	parent.add_child(group)
	match style:
		"flood_gate", "service_fence", "rail_barrier":
			for i: int in range(3):
				_box(group, "Post%d" % i, Vector3((i - 1) * 0.8, 0.8, 0),
					Vector3(0.14, 1.6, 0.14), brown)
			_box(group, "Crossbar", Vector3(0, 1.15, 0),
				Vector3(2.1, 0.2, 0.2), danger)
		"fallen_beam", "cable_spool", "equipment_stack":
			for i: int in range(3):
				_box(group, "Block%d" % i,
					Vector3((i - 1) * 0.6, 0.25 + float(i % 2) * 0.25, 0),
					Vector3(0.6, 0.5, 0.8), brown)
		"washout", "silt_bank":
			for i: int in range(3):
				_box(group, "Bank%d" % i,
					Vector3((i - 1) * 0.65, 0.08 + i * 0.11, 0),
					Vector3(0.68, 0.16 + i * 0.2, 1.1), danger)


static func build(plan: Dictionary, regional: Node3D) -> Node3D:
	var audit: Dictionary = inspect(plan)
	if not audit.get("ok", false) or regional == null or \
			str(regional.get_meta("source_level_id", "")) != str(audit["level_id"]) or \
			str(regional.get_meta("source_region_id", "")) != str(audit["region_id"]) or \
			regional.get_meta("qualification", "") != QUALIFICATION or \
			regional.get_node_or_null("EXP017_A01_ArchitecturalIdentity") == null:
		return null
	var root: Node3D = Node3D.new()
	root.name = "EXP017_A02_SiteAccess"
	root.set_meta("source_level_id", audit["level_id"])
	root.set_meta("source_location_id", audit["location_id"])
	root.set_meta("source_region_id", audit["region_id"])
	root.set_meta("layout_signature", audit["layout_signature"])
	root.set_meta("access_type", audit["access"])
	root.set_meta("barrier_type", audit["barrier"])
	root.set_meta("qualification", QUALIFICATION)
	root.set_meta("presentation_only", true)
	var service: Node3D = Node3D.new()
	service.name = "ElevatedServiceAccess"
	root.add_child(service)
	var emergency: Node3D = Node3D.new()
	emergency.name = "ObstructedEmergencyApproach"
	root.add_child(emergency)
	var obstructions: Node3D = Node3D.new()
	obstructions.name = "EnvironmentalObstructions"
	root.add_child(obstructions)
	var structure: Material = _mat("#6D8592")
	var upper: Material = _mat("#83B6BF")
	var detour: Material = _mat("#D9AA75")
	var hazard: Material = _mat("#B66B59")
	var points: Array = audit["points"]
	var height: float = float(audit["height_m"])
	var kind: String = str(audit["access"])
	for i: int in range(4):
		var start: Vector3 = points[i]
		var end: Vector3 = points[i + 1]
		var planar: Vector3 = end - start
		planar.y = 0.0
		var sideways: Vector3 = Vector3(-planar.z, 0, planar.x).normalized()
		var raised_start: Vector3 = _safe(start + Vector3.UP * height)
		var raised_end: Vector3 = _safe(end + Vector3.UP * height)
		_ribbon(service, "%s_Span%d" % [kind, i], raised_start, raised_end, 0.9, upper)
		_ramp(service, "EntryRise%d" % i, start, raised_start, structure)
		_ramp(service, "ServiceDescent%d" % i, raised_end, end, structure)
		var midpoint: Vector3 = (start + end) * 0.5
		var detour_point: Vector3 = _safe(midpoint + sideways * (3.0 + float(i % 2)))
		detour_point.y = 0.18
		_ribbon(emergency, "Approach%d_a" % i, start, detour_point, 0.55, detour)
		_ribbon(emergency, "Approach%d_b" % i, detour_point, end, 0.55, detour)
		_barrier(obstructions, str(audit["barrier"]),
			midpoint + sideways * (-2.9 if i % 2 == 0 else 2.9), structure, hazard)
		_box(service, "ServicePylon%d" % i,
			Vector3(raised_start.x, height * 0.5, raised_start.z),
			Vector3(0.22, height, 0.22), structure)
	var label: Label3D = Label3D.new()
	label.name = "AccessBriefing"
	label.text = ("%s / %s" % [str(audit["access"]), str(audit["barrier"])]).to_upper()
	label.font_size = 44
	label.pixel_size = 0.006
	label.position = _safe(points[0] + Vector3(0, 2.8, -1.5))
	root.add_child(label)
	return root
