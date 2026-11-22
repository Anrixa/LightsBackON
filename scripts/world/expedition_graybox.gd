extends RefCounted
const Regional := preload("res://scripts/world/expedition_regional_facilities.gd")
const RegionIdentity := preload("res://scripts/world/exp017_region_identity.gd")
const SiteAccess := preload("res://scripts/world/exp017_site_access.gd")
## EXP02: original procedural 3D level-composition previews.
## One built world per selected dispatch; never launches a player, registers
## a host target or performs pickup/reward actions. Only the floor collides.

const FLOOR_SIZE_M: float = 52.0
const FLOOR_THICKNESS_M: float = 0.4


static func _mat(color: Color, roughness: float = 0.8) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	return material


static func _mesh(parent: Node3D, node_name: String, position: Vector3,
		size: Vector3, material: Material) -> MeshInstance3D:
	var box: BoxMesh = BoxMesh.new()
	box.size = size
	var model: MeshInstance3D = MeshInstance3D.new()
	model.name = node_name
	model.mesh = box
	model.material_override = material
	model.position = position
	parent.add_child(model)
	return model


static func _group(parent: Node3D, name: String) -> Node3D:
	var node: Node3D = Node3D.new()
	node.name = name
	parent.add_child(node)
	return node


static func _segment(parent: Node3D, name: String, start: Vector3, stop: Vector3,
		material: Material) -> void:
	var delta: Vector3 = stop - start
	delta.y = 0.0
	if delta.length() <= 0.001:
		return
	var center: Vector3 = (start + stop) * 0.5
	center.y = 0.025
	var path: MeshInstance3D = _mesh(parent, name, center,
		Vector3(3.0, 0.045, delta.length()), material)
	path.rotation.y = atan2(delta.x, delta.z)


static func _primary_structure(parent: Node3D, plan: Dictionary,
		facade: Material, roof: Material, accent: Material) -> void:
	var kind: String = str(plan["category"])
	var serial: int = int(plan["serial"])
	var width: float = 5.0 + float(serial % 4)
	var height: float = 2.6 + float((serial / 7) % 4) * 0.6
	var origin: Vector3 = Vector3(7.5, height * 0.5, 40.0)
	if kind == "communications":
		# Open-frame mast (schematic). Non-colliding, simple Compatibility meshes.
		for i: int in range(4):
			_mesh(parent, "MastLeg%02d" % i, Vector3(5.0 + float(i % 2) * 2.4,
				3.3, 38.5 + float(i / 2) * 2.4), Vector3(0.3, 6.6, 0.3), facade)
		_mesh(parent, "MastCrossarm", Vector3(6.2, 6.4, 39.7), Vector3(4.8, 0.3, 0.3), accent)
	elif kind == "waterworks":
		for i: int in range(3):
			_mesh(parent, "PumpTank%02d" % i, Vector3(4.7 + float(i) * 2.1,
				2.15, 39.5), Vector3(1.65, 4.3, 2.8), facade)
		_mesh(parent, "PipeBridge", Vector3(6.8, 4.3, 39.4), Vector3(7.6, 0.35, 0.35), accent)
	elif kind == "transport":
		_mesh(parent, "CoveredPlatform", Vector3(7.5, 0.5, 40.0),
			Vector3(12.5, 1.0, 3.0), facade)
		_mesh(parent, "PlatformCanopy", Vector3(7.5, 4.0, 40.0),
			Vector3(12.5, 0.3, 5.0), roof)
	elif kind == "distribution":
		for i: int in range(3):
			_mesh(parent, "SwitchCabinet%02d" % i,
				Vector3(5.0 + float(i) * 2.4, 1.5, 39.6),
				Vector3(1.75, 3.0, 1.2), facade)
		_mesh(parent, "IncomingFeeder", Vector3(7.5, 3.5, 39.6),
			Vector3(8.5, 0.25, 0.25), accent)
	elif kind == "commerce":
		_mesh(parent, "MarketStalls", origin, Vector3(width, height, 4.8), facade)
		_mesh(parent, "MarketAwning", Vector3(7.5, height + 0.3, 39.7),
			Vector3(width + 1.8, 0.25, 5.8), roof)
	elif kind == "health":
		_mesh(parent, "ClinicWing", origin, Vector3(width, height, 6.5), facade)
		_mesh(parent, "EntryCanopy", Vector3(7.5, 2.5, 35.8),
			Vector3(width - 0.5, 0.3, 2.5), accent)
	elif kind == "education":
		_mesh(parent, "LearningHall", origin, Vector3(width, height + 1.7, 5.5), facade)
		_mesh(parent, "SignalBell", Vector3(7.5, height + 2.2, 40.0),
			Vector3(1.1, 1.1, 1.1), accent)
	else:
		_mesh(parent, "ShelterHall", origin, Vector3(width + 2.2, height, 6.7), facade)
		_mesh(parent, "ReliefAwning", Vector3(7.5, height + 0.35, 40.0),
			Vector3(width + 2.5, 0.35, 7.3), roof)


## Build a complete 52x52m 3D graybox for exactly one EXP01 level.
## For source engineering this creates a real ground collider, visual landmarks,
## 4m-kit-like perimeter features, five station markers, and road ribbons.
## Roads are meshes only, NOT proven traversable paths.
static func build(plan: Dictionary) -> Node3D:
	if not bool(plan.get("ok", false)) or plan.get("code") != "VISUAL_CANDIDATE_ONLY" or \
			plan.get("not_certified") != "NO_PHYSICAL_PLAYABILITY":
		return null
	var root: Node3D = Node3D.new()
	root.name = "Preview_" + str(plan["id"])
	root.set_meta("source_level_id", str(plan["id"]))
	root.set_meta("qualification", "SCHEMATIC_NOT_PLAYABLE")
	var serial: int = int(plan["serial"])
	var hue: float = fposmod(0.31 + float(serial) * 0.037, 1.0)
	var ground_mat: Material = _mat(Color("#203443"))
	var walkway_mat: Material = _mat(Color("#596D78"))
	var facade_mat: Material = _mat(Color.from_hsv(hue, 0.43, 0.74))
	var roof_mat: Material = _mat(Color.from_hsv(hue, 0.20, 0.31))
	var accent_mat: Material = _mat(Color("#F3C874"), 0.5)
	var task_mat: Material = _mat(Color("#72CDD2"))
	var optional_mat: Material = _mat(Color("#DCC18D"))
	var ground: StaticBody3D = StaticBody3D.new()
	ground.name = "CandidateGround"
	ground.collision_layer = 1
	ground.collision_mask = 1
	root.add_child(ground)
	_mesh(ground, "Foundation", Vector3(FLOOR_SIZE_M * 0.5,
		-FLOOR_THICKNESS_M * 0.5, FLOOR_SIZE_M * 0.5),
		Vector3(FLOOR_SIZE_M, FLOOR_THICKNESS_M, FLOOR_SIZE_M), ground_mat)
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = Vector3(FLOOR_SIZE_M, FLOOR_THICKNESS_M, FLOOR_SIZE_M)
	var collider: CollisionShape3D = CollisionShape3D.new()
	collider.name = "FoundationCollision"
	collider.shape = shape
	collider.position = Vector3(FLOOR_SIZE_M * 0.5,
		-FLOOR_THICKNESS_M * 0.5, FLOOR_SIZE_M * 0.5)
	ground.add_child(collider)
	var roads: Node3D = _group(root, "RoadRibbons")
	var stations: Node3D = _group(root, "Stations")
	var structures: Node3D = _group(root, "Landmarks")
	var first: Array = plan["stations"]
	# A design-tile visual path links planned stages, not the character body
	# and not the host's actual entity range calculations.
	for i: int in range(first.size() - 1):
		_segment(roads, "CandidatePath%02d" % i,
			first[i]["position"], first[i + 1]["position"], walkway_mat)
	_primary_structure(structures, plan, facade_mat, roof_mat, accent_mat)
	_mesh(structures, "AuxiliaryService", Vector3(43.0, 2.0, 9.0),
		Vector3(5.5, 4.0 + float(serial % 3), 6.3), facade_mat)
	_mesh(structures, "EmergencyDepot", Vector3(41.5, 1.5, 40.5),
		Vector3(6.0, 3.0, 5.0), roof_mat)
	# Painted hazard indicators are source previews, not new obstacle physics.
	for index: int in range(3):
		var x: float = 14.0 + float((serial * (index + 5)) % 24)
		var z: float = 7.0 + float((serial * (index + 11)) % 30)
		_mesh(structures, "HazardNote%02d" % index, Vector3(x, 0.022, z),
			Vector3(1.2 + float(index) * 0.5, 0.035, 1.9), accent_mat)
	for i: int in range(first.size()):
		var station: Dictionary = first[i]
		var pos: Vector3 = station["position"]
		var marker: Marker3D = Marker3D.new()
		marker.name = "Station%02d" % (i + 1)
		marker.position = pos
		marker.set_meta("task_id", str(station["id"]))
		marker.set_meta("task_kind", str(station["kind"]))
		marker.set_meta("authority", "NONE_PREVIEW_ONLY")
		stations.add_child(marker)
		var plate: CylinderMesh = CylinderMesh.new()
		plate.top_radius = 0.85
		plate.bottom_radius = 0.85
		plate.height = 0.09
		var visual: MeshInstance3D = MeshInstance3D.new()
		visual.name = "StagePlate"
		visual.mesh = plate
		visual.material_override = optional_mat if i == 3 else task_mat
		visual.position = Vector3(0.0, 0.05, 0.0)
		marker.add_child(visual)
		var text: Label3D = Label3D.new()
		text.name = "StageNumber"
		text.text = "%02d" % (i + 1)
		text.font_size = 64
		text.pixel_size = 0.007
		text.position = Vector3(0.0, 1.4, 0.0)
		text.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		text.modulate = Color("#F0F3EE")
		marker.add_child(text)
	# EXP014 A03: one source-validated regional facility package per selected
	# worksite. Mesh-only schematic evidence; no new world collision or host input.
	var regional: Node3D = Regional.build(plan)
	if regional == null:
		root.free()
		return null
	root.add_child(regional)
	var identity: Node3D = RegionIdentity.attach(plan, regional)
	if identity == null:
		root.free()
		return null
	var access: Node3D = SiteAccess.build(plan, regional)
	if access == null:
		root.free()
		return null
	root.add_child(access)
	return root
