extends RefCounted
## DS08 "Stormglass" look: environment, moonlight, rain and re-skinned surfaces for a built district (DS07 plan section 3).
## Presentation only. It never reads or writes power state: windows, signs and lamps that show supply are driven by
## RestorationPresentation from the host snapshot. It changes no collision, gameplay node path or stable ID; graybox
## meshes it replaces are hidden, never freed, so tests and gameplay that look them up still find them.
## Compatibility renderer only (ADR-016 section 6.2): sky shader without TIME, depth fog, glow, filmic tonemap, one
## shadowed directional light. Big surfaces are re-drawn as tiles because Compatibility lights at most 8 lights per mesh.

const LOOK_PATH: String = "res://content/world/look_stormglass.json"
const KIT_PATH: String = "res://content/world/kit_pieces.json"
const SKY_SHADER: Shader = preload("res://assets/shaders/stormglass_sky.gdshader")
const SURFACE_SHADER: Shader = preload("res://assets/shaders/stormglass_surface.gdshader")
const RainFx := preload("res://scripts/world/rain_fx.gd")
const KitBuilder := preload("res://scripts/world/kit_builder.gd")
const DistrictBuilder := preload("res://scripts/world/district_builder.gd")
const KIT_ROLES: Array[String] = ["wall", "trim", "floor", "panel_recess"]
## Tiles sit just above the graybox surfaces they cover (ground top at 0 cm, paving boxes at 2 cm): far enough to never
## z-fight at 100 m on a 24-bit depth buffer, too thin to see as a step.
const GROUND_TILE_LIFT_CM: float = 0.8
const ROUTE_TILE_LIFT_CM: float = 2.2
const PERCENT: float = 100.0
const RADIANCE_SIZE: Sky.RadianceSize = Sky.RADIANCE_SIZE_64


static func load_look(path: String = LOOK_PATH) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


## Adds the WorldEnvironment and the moon to `parent`. Returns the WorldEnvironment so callers can keep a handle.
static func apply_environment(parent: Node, look: Dictionary) -> WorldEnvironment:
	var e: Dictionary = look["environment"]
	var sky_mat: ShaderMaterial = ShaderMaterial.new()
	sky_mat.shader = SKY_SHADER
	sky_mat.set_shader_parameter("zenith", Color(str(e["sky_zenith"])))
	sky_mat.set_shader_parameter("horizon", Color(str(e["sky_horizon"])))
	sky_mat.set_shader_parameter("ground", Color(str(e["sky_ground"])))
	sky_mat.set_shader_parameter("far_glow", Color(str(e["sky_far_glow"])))
	var glow_deg: Array = e["sky_far_glow_dir_deg"]
	sky_mat.set_shader_parameter("far_glow_dir", _direction(float(glow_deg[0]), float(glow_deg[1])))
	sky_mat.set_shader_parameter("far_glow_strength", float(e["sky_far_glow_percent"]) / PERCENT)
	sky_mat.set_shader_parameter("cloud_tint", Color(str(e["cloud_tint"])))
	sky_mat.set_shader_parameter("cloud_amount", float(e["cloud_percent"]) / PERCENT)
	var sky: Sky = Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = RADIANCE_SIZE
	var env: Environment = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_BG
	env.ambient_light_color = Color(str(e["ambient_color"]))
	env.ambient_light_sky_contribution = float(e["ambient_sky_contribution_percent"]) / PERCENT
	env.ambient_light_energy = float(e["ambient_energy_percent"]) / PERCENT
	env.reflected_light_source = Environment.REFLECTION_SOURCE_BG
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = float(e["exposure_percent"]) / PERCENT
	env.tonemap_white = float(e["white_percent"]) / PERCENT
	env.glow_enabled = true
	env.glow_intensity = float(e["glow_intensity_percent"]) / PERCENT
	env.glow_bloom = float(e["glow_bloom_percent"]) / PERCENT
	env.glow_hdr_threshold = float(e["glow_hdr_threshold_percent"]) / PERCENT
	env.glow_strength = float(e["glow_strength_percent"]) / PERCENT
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_light_color = Color(str(e["fog_color"]))
	env.fog_density = float(e["fog_density_x10000"]) / 10000.0
	env.fog_sky_affect = float(e["fog_sky_affect_percent"]) / PERCENT
	env.adjustment_enabled = true
	env.adjustment_saturation = float(e["adjust_saturation_percent"]) / PERCENT
	env.adjustment_contrast = float(e["adjust_contrast_percent"]) / PERCENT
	var world_env: WorldEnvironment = WorldEnvironment.new()
	world_env.name = "WorldLight"
	world_env.environment = env
	parent.add_child(world_env)
	var m: Dictionary = look["moon"]
	var moon: DirectionalLight3D = DirectionalLight3D.new()
	moon.name = "Moon"
	moon.light_color = Color(str(m["color"]))
	moon.light_energy = float(m["energy_percent"]) / PERCENT
	var r: Array = m["rotation_deg"]
	moon.rotation_degrees = Vector3(float(r[0]), float(r[1]), float(r[2]))
	moon.shadow_enabled = bool(m["shadow"])
	moon.directional_shadow_mode = (DirectionalLight3D.SHADOW_ORTHOGONAL if bool(m.get("shadow_orthogonal", false))
		else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS)
	moon.directional_shadow_max_distance = float(m["shadow_max_distance_cm"]) / PERCENT
	parent.add_child(moon)
	return world_env


## Camera-following rain volume (particles stay in world space). Added under `parent`.
static func add_rain(parent: Node, look: Dictionary) -> GPUParticles3D:
	var rain: GPUParticles3D = RainFx.new()
	rain.name = "Rain"
	(rain as RainFx).configure(look["rain"])
	parent.add_child(rain)
	return rain


## Re-skins every graybox surface of a built district with the look's materials and per-building palettes, and re-draws
## ground and routes as tiles. `d` is the district data (content/world/<district>.json).
static func skin_world(world: Node3D, look: Dictionary, d: Dictionary) -> void:
	var kit: Dictionary = KitBuilder.load_kit(KIT_PATH)
	var kit_roles: Dictionary = _color_roles(kit["materials"])
	var district_keys: Dictionary = _color_roles(d["materials"])
	var cache: Dictionary = {}
	var buildings: Node = world.get_node_or_null("Buildings")
	if buildings != null:
		for b: Node in buildings.get_children():
			var palette: Dictionary = (look["buildings"] as Dictionary).get(str(b.name), {})
			_skin_building(b, palette, look, kit_roles, cache)
	for group: String in ["KitPlacements", "Props", "Boundary"]:
		var node: Node = world.get_node_or_null(group)
		if node == null:
			continue
		for mi: MeshInstance3D in _meshes(node):
			var key: String = "boundary" if group == "Boundary" else _key_for(mi, district_keys, kit_roles)
			if key == "trim":
				key = "trim_default"
			var mats: Dictionary = look["materials"]
			if mats.has(key) and key != "water":
				mi.material_override = surface_material(mats[key], cache, key)
	_tile_ground(world, look, d, cache)


## One ShaderMaterial per surface definition, shared through `cache` so equal surfaces batch.
static func surface_material(def: Dictionary, cache: Dictionary, cache_key: String) -> ShaderMaterial:
	if cache.has(cache_key):
		return cache[cache_key]
	var m: ShaderMaterial = ShaderMaterial.new()
	m.shader = SURFACE_SHADER
	m.set_shader_parameter("pattern", int(def.get("pattern", 0)))
	m.set_shader_parameter("base_color", Color(str(def["base"])))
	m.set_shader_parameter("accent_color", Color(str(def.get("accent", def["base"]))))
	m.set_shader_parameter("roughness_base", float(def.get("roughness_percent", 85)) / PERCENT)
	m.set_shader_parameter("wetness", float(def.get("wetness_percent", 40)) / PERCENT)
	m.set_shader_parameter("scale", float(def.get("scale_cm", 100)) / PERCENT)
	cache[cache_key] = m
	return m


static func _skin_building(b: Node, palette: Dictionary, look: Dictionary, kit_roles: Dictionary, cache: Dictionary) -> void:
	var mats: Dictionary = look["materials"]
	var id: String = str(b.name)
	for mi: MeshInstance3D in _meshes(b):
		var role: String = _key_for(mi, {}, kit_roles)
		var mat: ShaderMaterial
		if role == "wall" and palette.has("wall"):
			var wall: Dictionary = (palette["wall"] as Dictionary).duplicate()
			wall["roughness_percent"] = 88
			wall["wetness_percent"] = 45
			wall["scale_cm"] = 150
			mat = surface_material(wall, cache, "wall_" + id)
		elif role == "trim" and palette.has("trim"):
			var trim: Dictionary = {"pattern": 4, "base": palette["trim"], "roughness_percent": 65, "wetness_percent": 40}
			mat = surface_material(trim, cache, "trim_" + id)
		elif mats.has(role):
			mat = surface_material(mats[role], cache, role)
		elif role == "trim":
			mat = surface_material(mats["trim_default"], cache, "trim_default")
		if mat != null:
			mi.material_override = mat


## Ground slab tops and route paving re-drawn as tiles. Slab boxes stay visible (their sides are the basement pit walls);
## the tiles cover their tops. Route boxes are hidden: they are visual paving only, with no collision.
static func _tile_ground(world: Node3D, look: Dictionary, d: Dictionary, cache: Dictionary) -> void:
	var tile_cm: int = int(look["ground_tile_cm"])
	var holder: Node3D = Node3D.new()
	holder.name = "LookTiles"
	world.add_child(holder)
	var mats: Dictionary = look["materials"]
	var ground_key: String = str(d["ground"]["material"])
	var ground_mat: ShaderMaterial = surface_material(mats[ground_key], cache, ground_key)
	for s: Dictionary in DistrictBuilder.ground_slabs(d):
		var lo: Array = s["min"]
		var size: Array = s["size"]
		var top_cm: float = float(lo[1]) + float(size[1]) + GROUND_TILE_LIFT_CM
		_tiles(holder, Rect2(float(lo[0]), float(lo[2]), float(size[0]), float(size[2])), top_cm, tile_cm, ground_mat)
	var routes: Node = world.get_node_or_null("Routes")
	for r: Dictionary in d["routes"]:
		var lo: Array = r["min_cm"]
		var size: Array = r["size_cm"]
		var key: String = str(r["material"])
		_tiles(holder, Rect2(float(lo[0]), float(lo[1]), float(size[0]), float(size[1])), ROUTE_TILE_LIFT_CM, tile_cm,
			surface_material(mats[key], cache, key))
		if routes != null:
			var mesh: Node3D = routes.get_node_or_null(str(r["id"])) as Node3D
			if mesh != null:
				mesh.visible = false


static func _tiles(holder: Node3D, rect_cm: Rect2, y_cm: float, tile_cm: int, mat: Material) -> void:
	var x: float = rect_cm.position.x
	while x < rect_cm.end.x - 0.5:
		var w: float = minf(float(tile_cm), rect_cm.end.x - x)
		var z: float = rect_cm.position.y
		while z < rect_cm.end.y - 0.5:
			var dz: float = minf(float(tile_cm), rect_cm.end.y - z)
			var plane: PlaneMesh = PlaneMesh.new()
			plane.size = Vector2(w, dz) / PERCENT
			var mi: MeshInstance3D = MeshInstance3D.new()
			mi.mesh = plane
			mi.material_override = mat
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.position = Vector3(x + w * 0.5, y_cm, z + dz * 0.5) / PERCENT
			holder.add_child(mi)
			z += dz
		x += w


## Surface key of a graybox mesh from its material colour: district keys first, then kit roles.
static func _key_for(mi: MeshInstance3D, district_keys: Dictionary, kit_roles: Dictionary) -> String:
	var mat: StandardMaterial3D = mi.material_override as StandardMaterial3D
	if mat == null:
		return ""
	var hex: String = mat.albedo_color.to_html(false).to_upper()
	if district_keys.has(hex):
		return district_keys[hex]
	return str(kit_roles.get(hex, ""))


static func _color_roles(materials: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for key: String in materials.keys():
		if key.begins_with("_"):
			continue
		var hex: String = Color(str(materials[key])).to_html(false).to_upper()
		if not out.has(hex):
			out[hex] = key
	return out


static func _meshes(root: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for n: Node in root.find_children("*", "MeshInstance3D", true, false):
		out.append(n as MeshInstance3D)
	return out


## Unit vector from elevation and azimuth in degrees (azimuth 0 = -Z, clockwise seen from above).
static func _direction(elevation_deg: float, azimuth_deg: float) -> Vector3:
	var el: float = deg_to_rad(elevation_deg)
	var az: float = deg_to_rad(azimuth_deg)
	return Vector3(sin(az) * cos(el), sin(el), -cos(az) * cos(el))
