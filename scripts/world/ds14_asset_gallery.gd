extends Node3D
## DS14 non-shipping art lineup. No simulated supply state, gameplay input or
## fictitious crew are introduced into the production mission.

const HeroProps := preload("res://scripts/world/hero_prop_builder.gd")


func _ready() -> void:
	var art: HeroProps = HeroProps.new()
	var camera: Camera3D = Camera3D.new()
	camera.name = "GalleryCamera"
	camera.position = Vector3(0.0, 2.55, 10.0)
	add_child(camera)
	camera.look_at(Vector3(0.0, 1.2, 0.0))
	camera.current = true

	var env: WorldEnvironment = WorldEnvironment.new()
	env.name = "GalleryEnvironment"
	var scene_env: Environment = Environment.new()
	scene_env.background_mode = Environment.BG_COLOR
	scene_env.background_color = Color("#243548")
	scene_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	scene_env.ambient_light_color = Color("#CADCE8")
	scene_env.ambient_light_energy = 0.65
	env.environment = scene_env
	add_child(env)
	var light: DirectionalLight3D = DirectionalLight3D.new()
	light.name = "SoftKey"
	light.rotation_degrees = Vector3(-35, -25, 0)
	light.light_energy = 0.8
	light.shadow_enabled = false
	add_child(light)

	var worker_names: Array[String] = ["field", "line", "supervisor"]
	for i: int in worker_names.size():
		var worker: Node3D = art.build_worker(worker_names[i])
		worker.position = Vector3(float(i - 1) * 2.5, 0.0, 0.75)
		add_child(worker)
		var plinth: MeshInstance3D = _plinth()
		plinth.position = worker.position + Vector3(0, -0.04, 0)
		add_child(plinth)

	for i: int in HeroProps.TOOLS.size():
		var model: Node3D = art.build_tool(HeroProps.TOOLS[i])
		model.name = "Gallery_" + HeroProps.TOOLS[i]
		model.position = Vector3((float(i) - 2.0) * 1.6, 0.9, -1.6)
		model.scale = Vector3.ONE * 2.3
		add_child(model)

	var reel: Node3D = art.build_reel()
	reel.name = "Gallery_CableReel"
	reel.position = Vector3(4.9, 0.65, -0.45)
	reel.scale = Vector3.ONE * 2.0
	add_child(reel)


func _plinth() -> MeshInstance3D:
	var base: MeshInstance3D = MeshInstance3D.new()
	base.name = "NoninteractivePlinth"
	var mesh: CylinderMesh = CylinderMesh.new()
	mesh.height = 0.08
	mesh.top_radius = 0.65
	mesh.bottom_radius = 0.65
	base.mesh = mesh
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color("#354755")
	mat.roughness = 0.78
	base.material_override = mat
	base.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return base
