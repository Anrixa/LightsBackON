extends RefCounted
## DS14 original procedural hero geometry. This class creates presentation-only nodes:
## no collision, input, authoritative state, timestamps, lights, or scene-path changes.
## Appearance is loaded from assets/ rather than content/ so cosmetic updates never
## invalidate saved C01 content hashes. All shapes use stock Godot mesh primitives.

const ART_PATH: String = "res://assets/design/ds14_hero_art.json"
const TOOLS: Array[String] = ["meter", "screwdriver", "puller", "cutter", "crimper"]

var _config: Dictionary = {}
var _palette: Dictionary = {}
var _materials: Dictionary = {}


func _init() -> void:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(ART_PATH))
	_config = data if data is Dictionary else {}
	_palette = _config.get("palette", {})


func configuration() -> Dictionary:
	return _config.duplicate(true)


func build_tool(tool_id: String) -> Node3D:
	var root: Node3D = Node3D.new()
	root.name = "Tool_" + tool_id
	match tool_id:
		"meter":
			_meter(root)
		"screwdriver":
			_screwdriver(root)
		"puller":
			_puller(root)
		"cutter":
			_cutter(root)
		"crimper":
			_crimper(root)
		_:
			# No guessed equipment icon if the authoritative tool list changes.
			root.set_meta("ds14_unknown_tool", true)
	return root


func build_hands() -> Node3D:
	var root: Node3D = Node3D.new()
	root.name = "GlovedHands"
	var spread: float = float((_config.get("view", {}) as Dictionary).get("glove_spread_m", 0.16))
	for side: int in [-1, 1]:
		var direction: float = float(side)
		var arm: Node3D = Node3D.new()
		arm.name = "Left" if side < 0 else "Right"
		arm.position = Vector3(direction * spread, -0.10, 0.08)
		arm.rotation_degrees.z = -direction * 17.0
		root.add_child(arm)
		_rod(arm, "WeatherproofSleeve", Vector3(0.0, -0.20, 0.15), Vector3(0.0, -0.015, 0.00), 0.065, "fabric")
		_box(arm, "CuffReflector", Vector3(0.0, -0.055, 0.02), Vector3(0.13, 0.036, 0.12), "reflective")
		_box(arm, "PalmGlove", Vector3(0.0, 0.02, -0.04), Vector3(0.135, 0.105, 0.155), "glove")
		_box(arm, "KnuckleGuard", Vector3(0.0, 0.08, -0.07), Vector3(0.14, 0.027, 0.095), "glove_pad")
		for finger: int in 4:
			_box(arm, "Finger_%d" % finger,
				Vector3((float(finger) - 1.5) * 0.029, 0.11, -0.105),
				Vector3(0.027, 0.085, 0.07), "glove")
		_box(arm, "Thumb", Vector3(-direction * 0.078, 0.025, -0.075),
			Vector3(0.04, 0.08, 0.065), "glove")
	return root


## The five canonical repair tools are visibly different at first-person scale.
## There is deliberately no generic tool pickup/collision or invented measurement.
func _meter(root: Node3D) -> void:
	_box(root, "ImpactHousing", Vector3.ZERO, Vector3(0.16, 0.25, 0.075), "rubber")
	_box(root, "CaseBezel", Vector3(0, 0.055, -0.043), Vector3(0.135, 0.105, 0.015), "steel")
	_box(root, "DarkDisplay", Vector3(0, 0.055, -0.053), Vector3(0.112, 0.078, 0.008), "screen_off")
	# Unlit meter glass: no fake voltage value before an authoritative inspect.
	_box(root, "GlassHighlight", Vector3(-0.035, 0.076, -0.059), Vector3(0.025, 0.008, 0.002), "screen")
	for i: int in 3:
		_box(root, "Key_%d" % i,
			Vector3((float(i) - 1.0) * 0.043, -0.055, -0.048),
			Vector3(0.033, 0.027, 0.014), "steel_dark")
	for side: int in [-1, 1]:
		_rod(root, "Probe_%d" % side,
			Vector3(float(side) * 0.04, 0.11, 0.0),
			Vector3(float(side) * 0.07, 0.29, -0.05), 0.008, "reflective")


func _screwdriver(root: Node3D) -> void:
	_rod(root, "InsulatedGrip", Vector3(0, -0.20, 0), Vector3(0, 0.045, 0), 0.060, "shell")
	_box(root, "HandleCollar", Vector3(0, 0.05, 0), Vector3(0.11, 0.035, 0.11), "rubber")
	for i: int in 3:
		_box(root, "GripMark_%d" % i, Vector3(-0.061, -0.13 + float(i) * 0.045, 0),
			Vector3(0.009, 0.015, 0.060), "reflective")
	_rod(root, "Shaft", Vector3(0, 0.065, 0), Vector3(0, 0.37, 0), 0.023, "steel")
	_box(root, "FlatTip", Vector3(0, 0.387, 0), Vector3(0.065, 0.047, 0.012), "steel_dark")


func _puller(root: Node3D) -> void:
	_rod(root, "Handle", Vector3(0, -0.24, 0), Vector3(0, 0.035, 0), 0.056, "shell")
	_box(root, "MilledHead", Vector3(0, 0.075, 0), Vector3(0.17, 0.075, 0.075), "steel_dark")
	for side: int in [-1, 1]:
		var x: float = float(side)
		_rod(root, "CurvedJaw_%d" % side,
			Vector3(x * 0.07, 0.105, 0), Vector3(x * 0.095, 0.26, -0.025), 0.023, "steel")
		_box(root, "JawTooth_%d" % side, Vector3(x * 0.065, 0.285, -0.025),
			Vector3(0.061, 0.044, 0.060), "steel")
	_sphere(root, "Pivot", Vector3(0, 0.09, -0.055), 0.032, "reflective")


func _cutter(root: Node3D) -> void:
	_forcep_handles(root, "shell", 0.22)
	for side: int in [-1, 1]:
		var x: float = float(side)
		_rod(root, "ShearBlade_%d" % side,
			Vector3(x * 0.018, 0.06, 0), Vector3(x * 0.055, 0.255, -0.012),
			0.021, "steel")
		_box(root, "SharpenedEdge_%d" % side,
			Vector3(x * 0.023, 0.21, -0.025), Vector3(0.018, 0.12, 0.016), "steel_dark")
	_sphere(root, "ShearPivot", Vector3(0, 0.065, -0.05), 0.035, "reflective")


func _crimper(root: Node3D) -> void:
	_forcep_handles(root, "hi_vis_alt", 0.265)
	_box(root, "DieHousing", Vector3(0, 0.17, 0), Vector3(0.17, 0.15, 0.085), "steel_dark")
	for side: int in [-1, 1]:
		var x: float = float(side)
		_box(root, "CrimpDie_%d" % side,
			Vector3(x * 0.047, 0.255, -0.015), Vector3(0.043, 0.075, 0.075), "steel")
	_box(root, "GaugeBand", Vector3(0, 0.088, -0.055), Vector3(0.13, 0.026, 0.014), "reflective")


func _forcep_handles(root: Node3D, grip: String, length: float) -> void:
	for side: int in [-1, 1]:
		var x: float = float(side)
		_rod(root, "Lever_%d" % side,
			Vector3(0, 0.06, 0), Vector3(x * 0.105, -length, 0.02), 0.038, grip)
		_box(root, "EndGrip_%d" % side,
			Vector3(x * 0.105, -length + 0.035, 0.02), Vector3(0.085, 0.085, 0.090), "rubber")


## Grafted onto the existing host-driven DS11 generator. The physical load
## readout, trip ring, sound and cable route visibility are untouched.
func dress_generator(generator: Node3D, size: Vector3) -> Node3D:
	var root: Node3D = Node3D.new()
	root.name = "DS14HeroDetails"
	generator.add_child(root)
	var spec: Dictionary = _config.get("generator", {})
	var wheel_r: float = float(spec.get("wheel_radius_m", 0.13))
	var wheel_w: float = float(spec.get("wheel_thickness_m", 0.07))
	for side: int in [-1, 1]:
		var x: float = float(side)
		_rod(root, "RollBar_%d" % side, Vector3(x * size.x * 0.47, 0.16, size.z * 0.35),
			Vector3(x * size.x * 0.47, size.y * 0.95, size.z * 0.35), 0.023, "steel")
		var wheel: MeshInstance3D = _cylinder(root, "TransportWheel_%d" % side,
			Vector3(x * (size.x * 0.48), wheel_r, -size.z * 0.32),
			wheel_r, wheel_w, "rubber")
		wheel.rotation.z = PI * 0.5
		var hub: MeshInstance3D = _cylinder(root, "WheelHub_%d" % side,
			wheel.position + Vector3(x * wheel_w * 0.52, 0, 0),
			wheel_r * 0.38, 0.014, "steel")
		hub.rotation.z = PI * 0.5
	_box(root, "Handle", Vector3(0, size.y * 1.045, -size.z * 0.25),
		Vector3(size.x * 0.69, 0.05, 0.045), "rubber")
	# Passive ventilation is a constant surface detail, not a fake running fan.
	for i: int in int(spec.get("vent_rows", 5)):
		_box(root, "Louvre_%d" % i,
			Vector3(size.x * 0.14, size.y * (0.23 + 0.08 * float(i)), -size.z * 0.516),
			Vector3(size.x * 0.48, 0.025, 0.018), "shell_dark")
	_box(root, "SafetyTrim", Vector3(0, size.y * 0.92, -size.z * 0.525),
		Vector3(size.x * 0.64, 0.028, 0.016), "reflective")
	var reel: Node3D = build_reel()
	reel.name = "CableReel"
	reel.position = Vector3(-size.x * 0.57, size.y * 0.50, 0)
	root.add_child(reel)
	return root


## Cable reel is an inert prop, separate from the DS11 authored/host-routed cables.
func build_reel() -> Node3D:
	var root: Node3D = Node3D.new()
	root.name = "CableReel"
	var spec: Dictionary = _config.get("generator", {})
	var radius: float = float(spec.get("reel_radius_m", 0.23))
	var width: float = float(spec.get("reel_width_m", 0.28))
	for side: int in [-1, 1]:
		var x: float = float(side)
		var flange: MeshInstance3D = _cylinder(root, "Flange_%d" % side,
			Vector3(x * width * 0.5, 0, 0), radius, 0.026, "shell")
		flange.rotation.z = PI * 0.5
		var rim: MeshInstance3D = _cylinder(root, "Hub_%d" % side,
			Vector3(x * (width * 0.5 + 0.017), 0, 0), radius * 0.34, 0.020, "steel")
		rim.rotation.z = PI * 0.5
	# Segment bands show a wrapped cable rather than an imaginary deployed route.
	for i: int in int(spec.get("wire_turns", 7)):
		var ring: MeshInstance3D = _cylinder(root, "CableWrap_%d" % i,
			Vector3((float(i) / float(maxi(1, int(spec.get("wire_turns", 7)) - 1)) - 0.5) * width * 0.84, 0, 0),
			radius * 0.80, 0.025, "rubber")
		ring.rotation.z = PI * 0.5
	_rod(root, "FoldHandle", Vector3(width * 0.57, 0, 0),
		Vector3(width * 0.57, -radius * 0.58, -radius * 0.55), 0.028, "steel_dark")
	_box(root, "HandleGrip", Vector3(width * 0.57, -radius * 0.58, -radius * 0.55),
		Vector3(0.12, 0.048, 0.075), "rubber")
	return root


## Optional preview variants: they do not spawn fake network players or
## replace the existing deterministic kit worker scene.
func build_worker(variant: String) -> Node3D:
	var root: Node3D = Node3D.new()
	root.name = "Worker_" + variant
	var hi_vis: String = "hi_vis_alt" if variant == "supervisor" else "hi_vis"
	_rod(root, "LeftLeg", Vector3(-0.105, 0.49, 0), Vector3(-0.11, 0.09, 0), 0.087, "fabric")
	_rod(root, "RightLeg", Vector3(0.105, 0.49, 0), Vector3(0.11, 0.09, 0), 0.087, "fabric")
	for side: int in [-1, 1]:
		var x: float = float(side)
		_box(root, "Boot_%d" % side, Vector3(x * 0.11, 0.07, -0.055),
			Vector3(0.20, 0.14, 0.30), "rubber")
		_rod(root, "JacketArm_%d" % side, Vector3(x * 0.23, 1.44, 0), Vector3(x * 0.28, 1.06, 0), 0.079, "shell")
		_box(root, "Glove_%d" % side, Vector3(x * 0.28, 1.04, 0),
			Vector3(0.13, 0.14, 0.14), "glove")
	_box(root, "WeatherproofJacket", Vector3(0, 1.25, 0),
		Vector3(0.43, 0.64, 0.24), "shell")
	_box(root, "VisibilityVest", Vector3(0, 1.27, -0.127),
		Vector3(0.36, 0.50, 0.03), hi_vis)
	for side: int in [-1, 1]:
		_box(root, "VestStripe_%d" % side,
			Vector3(float(side) * 0.095, 1.30, -0.153),
			Vector3(0.045, 0.43, 0.016), "reflective")
	_box(root, "EquipmentBelt", Vector3(0, 1.00, -0.05),
		Vector3(0.45, 0.075, 0.30), "rubber")
	_box(root, "ToolPouch", Vector3(0.27, 0.92, -0.02),
		Vector3(0.16, 0.22, 0.15), "shell_dark")
	_sphere(root, "Head", Vector3(0, 1.70, 0), 0.12, "fabric")
	_box(root, "HardHat", Vector3(0, 1.84, 0),
		Vector3(0.29, 0.11, 0.28), hi_vis)
	_box(root, "HelmetBrim", Vector3(0, 1.80, -0.09),
		Vector3(0.35, 0.035, 0.19), "steel")
	_box(root, "Visor", Vector3(0, 1.71, -0.13),
		Vector3(0.20, 0.06, 0.025), "screen_off")
	if variant == "line":
		_box(root, "HelmetStripe", Vector3(0, 1.902, 0),
			Vector3(0.05, 0.018, 0.25), "reflective")
	elif variant == "supervisor":
		_box(root, "SupervisorPlate", Vector3(0, 1.40, -0.152),
			Vector3(0.19, 0.075, 0.020), "shell_dark")
	return root


func _material(role: String) -> StandardMaterial3D:
	if _materials.has(role):
		return _materials[role] as StandardMaterial3D
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(str(_palette.get(role, "#777777")))
	mat.roughness = 0.68 if role != "steel" else 0.38
	mat.metallic = 0.72 if role == "steel" or role == "steel_dark" else 0.0
	_materials[role] = mat
	return mat


func _box(parent: Node3D, name: String, pos: Vector3, size: Vector3, role: String) -> MeshInstance3D:
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = size
	var item: MeshInstance3D = MeshInstance3D.new()
	item.name = name
	item.mesh = mesh
	item.material_override = _material(role)
	item.position = pos
	item.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(item)
	return item


func _cylinder(parent: Node3D, name: String, pos: Vector3, radius: float,
		height: float, role: String) -> MeshInstance3D:
	var mesh: CylinderMesh = CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 12
	mesh.rings = 1
	var item: MeshInstance3D = MeshInstance3D.new()
	item.name = name
	item.mesh = mesh
	item.material_override = _material(role)
	item.position = pos
	item.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(item)
	return item


func _rod(parent: Node3D, name: String, start: Vector3, finish: Vector3,
		radius: float, role: String) -> MeshInstance3D:
	var axis: Vector3 = finish - start
	var item: MeshInstance3D = _cylinder(parent, name, (start + finish) * 0.5,
		radius, axis.length(), role)
	if axis.length_squared() > 0.000001:
		item.basis = Basis(Quaternion(Vector3.UP, axis.normalized()))
	return item


func _sphere(parent: Node3D, name: String, pos: Vector3, radius: float, role: String) -> MeshInstance3D:
	var mesh: SphereMesh = SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 12
	mesh.rings = 6
	var item: MeshInstance3D = MeshInstance3D.new()
	item.name = name
	item.mesh = mesh
	item.material_override = _material(role)
	item.position = pos
	item.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(item)
	return item
