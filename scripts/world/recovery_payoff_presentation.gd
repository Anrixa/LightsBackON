extends RefCounted
## DS12: host-authored power recovery earns a visible and audible reward.
## The production street's signs, pavement spill and extractor fans respond
## only to the same grid snapshot RestorationPresentation uses for windows.
## No generated state, no repair knowledge, no save data and no physics added.

const TabletPresenter := preload("res://scripts/ui/tablet_presenter.gd")
const RestorationPresentation := preload("res://scripts/world/restoration_presentation.gd")
const Soundscape := preload("res://scripts/world/storm_soundscape.gd")
const DRESSING_PATH: String = "res://content/world/alder_street_dressing.json"
const CM_PER_M: float = 100.0

var _world: Node3D
var _config: Dictionary = {}
var _root: Node3D
var _audio: Soundscape
var _sign_materials: Dictionary = {}
var _spills: Dictionary = {}
var _fan_rotors: Dictionary = {}
var _status: Dictionary = {}
var _levels: Dictionary = {}  # service -> {sign, spill}
var _fades: Dictionary = {}
var _reduce_flashes: bool = true
var _reduce_motion: bool = false


static func load_config() -> Dictionary:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(DRESSING_PATH))
	if not data is Dictionary:
		return {}
	return (data as Dictionary).get("recovery_payoff", {})


func setup(world: Node3D) -> void:
	_world = world
	_config = load_config()
	_status.clear()
	_levels.clear()
	_fades.clear()
	_sign_materials.clear()
	_spills.clear()
	_fan_rotors.clear()
	if _config.is_empty():
		return
	_root = Node3D.new()
	_root.name = "DS12RecoveryPayoff"
	world.add_child(_root)
	for service: String in RestorationPresentation.SERVICES:
		var fascia: Node3D = world.get_node_or_null(NodePath("Dressing/Fascia_" + service)) as Node3D
		if fascia == null:
			continue
		var name_label: Label3D = fascia.get_node_or_null("Name") as Label3D
		if name_label == null:
			continue
		_build_sign(service, fascia, name_label)
		_build_spill(service, fascia)
		_levels[service] = {"sign": 0.0, "spill": 0.0}
	_audio = Soundscape.new()
	_audio.setup(world, _config["audio"])


func _build_sign(service: String, fascia: Node3D, name_label: Label3D) -> void:
	var width: float = minf(4.0, name_label.width * name_label.pixel_size)
	var thickness: float = float(_config["fascia_tube_thickness_cm"]) / CM_PER_M
	var inset: float = float(_config["fascia_tube_inset_cm"]) / CM_PER_M
	var vertical: float = 0.40
	var front: float = name_label.position.z + 0.035
	var color: Color = Color(str((_config["sign_colors"] as Dictionary)[service]))
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color("#3A4A50")
	material.emission = color
	material.emission_enabled = false
	material.emission_energy_multiplier = 0.0
	_sign_materials[service] = material
	var holder: Node3D = Node3D.new()
	holder.name = "DS12Sign"
	fascia.add_child(holder)
	for h: float in [-vertical * 0.5, vertical * 0.5]:
		_box(holder, Vector3(0, h, front), Vector3(width - inset * 2.0, thickness, thickness), material)
	for x: float in [-(width - inset * 2.0) * 0.5, (width - inset * 2.0) * 0.5]:
		_box(holder, Vector3(x, 0, front), Vector3(thickness, vertical, thickness), material)
	_build_vent(service, holder, width, front)


func _build_vent(service: String, holder: Node3D, width: float, front: float) -> void:
	var vent: Node3D = Node3D.new()
	vent.name = "DS12VentRotor"
	vent.position = Vector3(width * 0.34, -0.39, front + 0.04)
	holder.add_child(vent)
	var rim_mat: StandardMaterial3D = _flat(Color("#33454C"))
	var blade_mat: StandardMaterial3D = _flat(Color("#A3B3B8"))
	var radius: float = float(_config["fan_radius_cm"]) / CM_PER_M
	_box(vent, Vector3.ZERO, Vector3(0.065, 0.065, 0.05), rim_mat)
	for i: int in int(_config["fan_blades"]):
		var blade: MeshInstance3D = _box(vent,
			Vector3(0, radius * 0.55, 0),
			Vector3(radius * 0.38, radius, 0.025), blade_mat)
		blade.rotation.z = float(i) * TAU / float(int(_config["fan_blades"]))
		# Rotate the offset too so the radial blades do not overlap.
		blade.position = Vector3(-sin(blade.rotation.z) * radius * 0.55,
			cos(blade.rotation.z) * radius * 0.55, 0.0)
	_fan_rotors[service] = vent


func _build_spill(service: String, fascia: Node3D) -> void:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	var color: Color = Color(str((_config["sign_colors"] as Dictionary)[service]))
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(color.r, color.g, color.b, 0.0)
	material.emission_enabled = false
	material.emission = color
	material.emission_energy_multiplier = 0.0
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var plane: PlaneMesh = PlaneMesh.new()
	var dimensions: Array = _config["spill_size_cm"]
	plane.size = Vector2(float(dimensions[0]), float(dimensions[1])) / CM_PER_M
	var glow: MeshInstance3D = MeshInstance3D.new()
	glow.name = "DS12Spill_" + service
	glow.mesh = plane
	glow.material_override = material
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_root.add_child(glow)
	var outward: Vector3 = fascia.global_transform.basis.z.normalized()
	glow.global_position = (Vector3(fascia.global_position.x, 0.065, fascia.global_position.z) +
		outward * float(_config["spill_offset_cm"]) / CM_PER_M)
	glow.visible = false
	_spills[service] = glow


## Actual host edge reachability, not a cosmetic light state, selects the
## target. Cues do not expose why a repair has failed or predict completion.
static func supply_states(snapshot: Dictionary) -> Dictionary:
	var grid: Dictionary = snapshot.get("grid", {})
	var nodes: Dictionary = grid.get("nodes", {})
	var edges: Dictionary = grid.get("edges", {})
	var result: Dictionary = {}
	for service: String in RestorationPresentation.SERVICES:
		var root: String = TabletPresenter.root_source(service, nodes, edges) if nodes.has(service) else ""
		result[service] = "dark" if root == "" else ("grid" if root == "GRID" else "temporary")
	return result


func apply(snapshot: Dictionary) -> void:
	if _root == null:
		return
	var next_states: Dictionary = supply_states(snapshot)
	for service: String in RestorationPresentation.SERVICES:
		var next: String = str(next_states[service])
		var previous: String = str(_status.get(service, ""))
		if previous == next:
			continue
		_status[service] = next
		if not _levels.has(service):
			continue
		var level: Dictionary = _levels[service]
		var target: float = 1.0 if next == "grid" else 0.0
		if previous == "":
			# An already-restored checkpoint is not a new player victory.
			# Do not animate all five signs/stingers on first load.
			level["sign"] = target
			level["spill"] = target
			_levels[service] = level
			_render(service, target, target)
			continue
		_fades[service] = {
			"start_sign": float(level["sign"]),
			"start_spill": float(level["spill"]),
			"target": target, "elapsed": 0.0
		}
	var nodes: Dictionary = (snapshot.get("grid", {}) as Dictionary).get("nodes", {})
	var generator_online: bool = bool((nodes.get("GEN", {}) as Dictionary).get("online", false))
	_audio.apply(next_states, generator_online)


## Immediate settings effect without a pop: rebase each in-progress fade
## from its LAST rendered value. Reduce Camera Motion also stops rotor spin.
func set_reduce_flashes(enabled: bool) -> void:
	if _reduce_flashes == enabled:
		return
	_reduce_flashes = enabled
	for service: String in _fades.keys():
		var f: Dictionary = _fades[service]
		var current: Dictionary = _levels[service]
		f["start_sign"] = float(current["sign"])
		f["start_spill"] = float(current["spill"])
		f["elapsed"] = 0.0
		_fades[service] = f


func set_reduce_motion(enabled: bool) -> void:
	_reduce_motion = enabled


func advance(delta: float) -> void:
	if _root == null:
		return
	var duration: float = float(_config["reduced_flash_transition_ms"] if _reduce_flashes else _config["normal_transition_ms"]) / 1000.0
	for service: String in _fades.keys():
		var fade: Dictionary = _fades[service]
		var elapsed: float = float(fade["elapsed"]) + maxf(0.0, delta)
		var progress: float = clampf(elapsed / maxf(0.001, duration), 0.0, 1.0)
		var rising: bool = float(fade["target"]) > float(fade["start_sign"])
		var sign_progress: float = _delayed(progress, float(_config["sign_delay_percent"]) / 100.0) if rising else progress
		var spill_progress: float = _delayed(progress, float(_config["spill_delay_percent"]) / 100.0) if rising else progress
		var sign: float = lerpf(float(fade["start_sign"]), float(fade["target"]), _ease(sign_progress))
		var spill: float = lerpf(float(fade["start_spill"]), float(fade["target"]), _ease(spill_progress))
		_levels[service] = {"sign": sign, "spill": spill}
		_render(service, sign, spill)
		if progress >= 1.0:
			_fades.erase(service)
		else:
			fade["elapsed"] = elapsed
			_fades[service] = fade
	if not _reduce_motion:
		for service: String in _fan_rotors:
			var level: float = float((_levels.get(service, {}) as Dictionary).get("sign", 0.0))
			if level > 0.0:
				(_fan_rotors[service] as Node3D).rotation.z += deg_to_rad(float(_config["fan_speed_deg_per_second"])) * maxf(0.0, delta) * level
	_audio.advance(delta)


func _render(service: String, sign: float, spill: float) -> void:
	var material: StandardMaterial3D = _sign_materials[service]
	var color: Color = Color(str((_config["sign_colors"] as Dictionary)[service]))
	material.albedo_color = Color("#3A4A50").lerp(color, sign)
	material.emission_enabled = sign > 0.0001
	material.emission_energy_multiplier = sign * 1.6
	var plane: MeshInstance3D = _spills[service]
	plane.visible = spill > 0.0001
	var ground: StandardMaterial3D = plane.material_override as StandardMaterial3D
	ground.albedo_color = Color(color.r, color.g, color.b,
		clampf(spill * float(_config["spill_brightness_percent"]) / 100.0, 0.0, 0.8))
	ground.emission_enabled = spill > 0.0001
	ground.emission_energy_multiplier = spill * 0.45


static func _delayed(progress: float, delay: float) -> float:
	return clampf((progress - delay) / maxf(0.01, 1.0 - delay), 0.0, 1.0)


static func _ease(progress: float) -> float:
	return progress * progress * (3.0 - 2.0 * progress)


func state_of(service: String) -> String:
	return str(_status.get(service, ""))


func sign_intensity(service: String) -> float:
	return float((_levels.get(service, {}) as Dictionary).get("sign", 0.0))


func spill_intensity(service: String) -> float:
	return float((_levels.get(service, {}) as Dictionary).get("spill", 0.0))


func soundscape() -> Soundscape:
	return _audio


func active_transitions() -> int:
	return _fades.size()


static func _flat(color: Color) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.56
	return material


static func _box(parent: Node3D, position: Vector3, dimensions: Vector3, material: StandardMaterial3D) -> MeshInstance3D:
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = dimensions
	var node: MeshInstance3D = MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material
	node.position = position
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
	return node
