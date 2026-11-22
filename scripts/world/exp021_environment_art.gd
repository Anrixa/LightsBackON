extends RefCounted
## EXP021 A01 — region-authored infrastructure and weathered environmental art.
## Visual meshes only. Never changes the authoritative host, floor, physics,
## navigation, player tools, rewards, saves or original EXP017 source IDs.

const Identity := preload("res://scripts/world/exp017_region_identity.gd")
const Access := preload("res://scripts/world/exp017_site_access.gd")
const WEATHER_SHADER: Shader = preload("res://assets/shaders/exp021_weathered_facility.gdshader")
const QUALIFICATION: String = "SOURCE_HEADLESS_ONLY_PHYSICAL_HARDWARE_RELEASE_HELD"
static var _shared_box_meshes: Dictionary = {}
const CATEGORY_SHAPES: Array[String] = [
	"distribution", "transport", "health", "commerce", "waterworks",
	"communications", "education", "shelter"
]


static func inspect(plan: Dictionary) -> Dictionary:
	var identity: Dictionary = Identity.inspect(plan)
	var access: Dictionary = Access.inspect(plan)
	if not bool(identity.get("ok", false)) or not bool(access.get("ok", false)):
		return {"ok": false, "code": "EXP021_A01_PARENT_SOURCE_REJECTED"}
	if str(identity["level_id"]) != str(access["level_id"]) or \
			str(identity["region_id"]) != str(access["region_id"]):
		return {"ok": false, "code": "EXP021_A01_CROSS_SOURCE_MISMATCH"}
	var category: String = str(plan.get("category", ""))
	var serial: int = int(plan.get("serial", -1))
	if not CATEGORY_SHAPES.has(category) or serial < 1 or serial > 200:
		return {"ok": false, "code": "EXP021_A01_INVALID_LOCATION"}
	var region: String = str(identity["region_id"])
	var palette: String = str(Identity.PROFILES[region]["accent"])
	if not Color.html_is_valid(palette):
		return {"ok": false, "code": "EXP021_A01_INVALID_PALETTE"}
	var signature: String = ("%s|%s|%s|%s|%d|weather_v1" % [
		str(access["layout_signature"]), str(identity["signature"]),
		category, palette, serial
	]).sha256_text()
	return {"ok": true, "level_id": str(identity["level_id"]),
		"region_id": region, "location_id": str(access["location_id"]),
		"category": category, "serial": serial,
		"accent": palette, "source_signature": signature,
		"authority": "PRESENTATION_ONLY", "qualification": QUALIFICATION}


static func _material(base_color: Color, rust_color: Color,
		wetness: float) -> ShaderMaterial:
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = WEATHER_SHADER
	material.set_shader_parameter("base_color", base_color)
	material.set_shader_parameter("oxidation_color", rust_color)
	material.set_shader_parameter("wetness", clampf(wetness, 0.0, 1.0))
	return material


static func _box(parent: Node3D, name: String, position: Vector3,
		size: Vector3, material: Material) -> void:
	# Immutable box templates are shared across the 200 authored sites. Their
	# material instances remain site-specific and never leak host state.
	var key: String = "%.3f|%.3f|%.3f" % [size.x, size.y, size.z]
	if not _shared_box_meshes.has(key):
		var built: BoxMesh = BoxMesh.new()
		built.size = size
		_shared_box_meshes[key] = built
	var mesh: BoxMesh = _shared_box_meshes[key]
	var visual: MeshInstance3D = MeshInstance3D.new()
	visual.name = name
	visual.mesh = mesh
	visual.material_override = material
	visual.position = position
	parent.add_child(visual)


static func _section(parent: Node3D, name: String) -> Node3D:
	var node: Node3D = Node3D.new()
	node.name = name
	parent.add_child(node)
	return node


## The 25 distinct inherited skyline kits are preserved. This assembly adds
## material/shape grammar relevant to each worksite's real infrastructure class,
## not 200 labels painted onto identical primitives.
static func attach(plan: Dictionary, regional: Node3D) -> Node3D:
	var audit: Dictionary = inspect(plan)
	if not bool(audit.get("ok", false)) or regional == null:
		return null
	if str(regional.get_meta("source_level_id", "")) != str(audit["level_id"]) or \
			str(regional.get_meta("source_region_id", "")) != str(audit["region_id"]) or \
			str(regional.get_meta("source_location_id", "")) != str(audit["location_id"]) or \
			regional.get_node_or_null("EXP017_A01_ArchitecturalIdentity") == null or \
			regional.get_meta("qualification", "") != Access.QUALIFICATION or \
			regional.get_node_or_null("EXP021_A01_EnvironmentArt") != null:
		return null
	var root: Node3D = Node3D.new()
	root.name = "EXP021_A01_EnvironmentArt"
	root.set_meta("source_level_id", audit["level_id"])
	root.set_meta("source_region_id", audit["region_id"])
	root.set_meta("source_location_id", audit["location_id"])
	root.set_meta("source_signature", audit["source_signature"])
	root.set_meta("qualification", QUALIFICATION)
	root.set_meta("presentation_only", true)
	root.set_meta("source_category", audit["category"])
	var accent: Color = Color(str(audit["accent"]))
	var serial: int = int(audit["serial"])
	var panel_mat: Material = _material(Color("#596C79").lerp(accent, 0.33),
		Color("#5F443B"), 0.25 + 0.07 * float(serial % 5))
	var steel_mat: Material = _material(Color("#354B58"), Color("#86634D"), 0.65)
	var masonry_mat: Material = _material(Color("#78848A").lerp(accent, 0.10),
		Color("#504F4B"), 0.48)
	var facade: Node3D = _section(root, "WeatheredFacade")
	var service: Node3D = _section(root, "Infrastructure")
	var detail: Node3D = _section(root, "MaintenanceDetail")
	# All pieces stay near the original regional facility anchor, above its
	# footing. No arbitrary props intrude into source-defined task stations.
	_box(facade, "ServiceWall", Vector3(0, 1.65, 2.65),
		Vector3(5.4, 3.3, 0.34), masonry_mat)
	_box(facade, "WaterproofCornice", Vector3(0, 3.39, 2.65),
		Vector3(6.0, 0.22, 0.56), panel_mat)
	for i: int in range(4):
		_box(facade, "StructuralRib%02d" % i,
			Vector3(-2.1 + float(i) * 1.4, 1.5, 2.35),
			Vector3(0.12, 2.8, 0.20), steel_mat)
	for i: int in range(3):
		_box(detail, "RainStreak%02d" % i,
			Vector3(-1.7 + float(i) * 1.6, 1.25, 2.22),
			Vector3(0.16, 1.8 - 0.25 * float(i), 0.05), panel_mat)
	# Mechanically meaningful equipment silhouettes use existing archetypes.
	match str(audit["category"]):
		"distribution", "communications":
			_box(service, "FeederCabinet", Vector3(-1.1, 1.0, 1.65),
				Vector3(1.35, 2.0, 0.65), panel_mat)
			_box(service, "BusbarCanopy", Vector3(0.5, 2.65, 1.4),
				Vector3(2.8, 0.20, 0.55), steel_mat)
		"transport", "commerce":
			_box(service, "PlatformBeam", Vector3(0, 1.75, 1.55),
				Vector3(5.7, 0.30, 0.33), steel_mat)
			_box(service, "LoadingRampLip", Vector3(0, 0.20, 1.15),
				Vector3(4.2, 0.24, 1.10), masonry_mat)
		"waterworks", "shelter":
			_box(service, "SupplyPipe", Vector3(0, 0.92, 1.63),
				Vector3(5.5, 0.38, 0.38), steel_mat)
			_box(service, "BypassValveHousing", Vector3(1.35, 1.30, 1.55),
				Vector3(0.76, 0.54, 0.68), panel_mat)
		"health", "education":
			_box(service, "RoofVent", Vector3(-1.5, 3.94, 2.5),
				Vector3(0.83, 0.9, 0.82), panel_mat)
			_box(service, "ProtectedIntake", Vector3(1.4, 2.05, 1.8),
				Vector3(1.35, 1.05, 0.68), steel_mat)
	# Distinct serial-order inspection marks are geometry, not billboard labels.
	for i: int in range(3):
		var offset: float = 0.32 * float((serial + i) % 4)
		_box(detail, "MaintenanceSeam%02d" % i,
			Vector3(-1.65 + float(i) * 1.6, 0.15 + offset, 2.15),
			Vector3(0.95, 0.07, 0.05), panel_mat)
	regional.add_child(root)
	return root


## Bounded variant count is useful for source/headless memory diagnostics.
static func cached_box_mesh_count() -> int:
	return _shared_box_meshes.size()
