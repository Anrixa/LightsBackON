extends RefCounted
## EXP017 A03: host-snapshot-driven restoration lighting, signage and reactions.
## This class only renders the trusted Runtime.task_board() and actual
## PowerGrid.canonical_state(); it never accepts a client event, infers
## energized circuits from mission text, or changes authority/saves/points.
const Access := preload("res://scripts/world/exp017_site_access.gd")
const QUALIFICATION: String = Access.QUALIFICATION
const LOADS: Array[String] = ["LOAD_A", "LOAD_B", "LOAD_C", "SIGN"]
const DARK: Color = Color("#526573")
const LIVE: Color = Color("#F6C979")
const COMPLETE: Color = Color("#77C9CE")
const FAULT: Color = Color("#D7746C")


static func _fail(code: String) -> Dictionary:
	return {"ok": false, "code": code, "qualification": QUALIFICATION}


static func inspect(plan: Dictionary) -> Dictionary:
	var access: Dictionary = Access.inspect(plan)
	if not bool(access.get("ok", false)):
		return _fail("EXP017_A03_UNQUALIFIED_ACCESS")
	var stations: Array = plan["stations"]
	var ids: Array[String] = []
	for i: int in range(5):
		ids.append(str(stations[i]["id"]))
	return {"ok": true, "level_id": str(access["level_id"]),
		"region_id": str(access["region_id"]),
		"location_id": str(access["location_id"]),
		"task_ids": ids, "signature": str(access["layout_signature"]),
		"qualification": QUALIFICATION, "authority": "READ_ONLY_HOST_PROJECTION"}


static func _material(color: Color) -> StandardMaterial3D:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.45
	mat.emission_enabled = false
	mat.emission_energy_multiplier = 0.8
	return mat


static func _plaque(parent: Node3D, name: String, message: String,
		position: Vector3) -> Label3D:
	var label: Label3D = Label3D.new()
	label.name = name
	label.text = message
	label.position = position
	label.font_size = 48
	label.pixel_size = 0.006
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = DARK
	parent.add_child(label)
	return label


static func build(plan: Dictionary, world: Node3D) -> Node3D:
	var source: Dictionary = inspect(plan)
	if not bool(source.get("ok", false)) or world == null or \
			str(world.get_meta("source_level_id", "")) != str(source["level_id"]) or \
			world.get_node_or_null("EXP017_A02_SiteAccess") == null:
		return null
	var root: Node3D = Node3D.new()
	root.name = "EXP017_A03_HostRestorationPresentation"
	root.set_meta("source_level_id", source["level_id"])
	root.set_meta("source_region_id", source["region_id"])
	root.set_meta("source_location_id", source["location_id"])
	root.set_meta("source_task_ids", source["task_ids"])
	root.set_meta("source_layout_signature", source["signature"])
	root.set_meta("qualification", QUALIFICATION)
	root.set_meta("presentation_only", true)
	root.set_meta("last_host_revision", -1)
	root.set_meta("last_grid_tick", -1)
	var stations: Array = plan["stations"]
	var lights: Node3D = Node3D.new()
	lights.name = "HostSupplyLights"
	root.add_child(lights)
	var signs: Node3D = Node3D.new()
	signs.name = "OperationSigns"
	root.add_child(signs)
	for index: int in range(LOADS.size()):
		var load: String = LOADS[index]
		var anchor: Vector3 = stations[index]["position"]
		var assembly: Node3D = Node3D.new()
		assembly.name = "Supply_" + load
		assembly.position = Vector3(anchor.x, 0.0, anchor.z)
		assembly.set_meta("source_consumer", load)
		assembly.set_meta("visual_supply", "unknown")
		lights.add_child(assembly)
		var mesh: BoxMesh = BoxMesh.new()
		mesh.size = Vector3(0.7, 0.28, 0.5)
		var housing: MeshInstance3D = MeshInstance3D.new()
		housing.name = "Luminaire"
		housing.mesh = mesh
		housing.position = Vector3(0, 2.2, 0)
		housing.material_override = _material(DARK)
		assembly.add_child(housing)
		var lamp: OmniLight3D = OmniLight3D.new()
		lamp.name = "HostPoweredLamp"
		lamp.position = Vector3(0, 2.0, 0)
		lamp.light_color = LIVE
		lamp.omni_range = 5.0
		lamp.light_energy = 0.0
		lamp.shadow_enabled = false
		assembly.add_child(lamp)
		_plaque(assembly, "SupplySign", "%s / UNKNOWN" % load,
			Vector3(0, 3.0, 0))
	for index: int in range(5):
		var station: Dictionary = stations[index]
		var station_pos: Vector3 = station["position"]
		var name: String = "Task%d" % (index + 1)
		var label: Label3D = _plaque(signs, name,
			"%s / PENDING" % str(station["id"]),
			Vector3(station_pos.x, 2.85, station_pos.z + 0.8))
		label.set_meta("source_task_id", str(station["id"]))
	var risk: String = str(plan["hazard"])
	_plaque(signs, "EnvironmentalReaction", "RISK / UNVERIFIED: " + risk,
		Vector3(26, 4.0, 3.5))
	_plaque(signs, "OperationalFeedback", "OPS / AWAITING HOST",
		Vector3(26, 3.15, 3.5))
	_plaque(signs, "RestorationSign", "RESTORATION / NOT VERIFIED",
		Vector3(26, 5.0, 3.5))
	var finale: OmniLight3D = OmniLight3D.new()
	finale.name = "VerifiedRestorationGlow"
	finale.position = Vector3(26, 5.2, 26)
	finale.light_color = COMPLETE
	finale.omni_range = 16
	finale.light_energy = 0.0
	finale.shadow_enabled = false
	root.add_child(finale)
	return root


## A hostile/stale or malformed visual projection is rejected BEFORE touching
## any light or label. The board is only trusted when supplied by the local
## host caller; this is not an RPC authentication boundary.
static func _validate(scene: Node3D, board: Dictionary, grid: Dictionary) -> Dictionary:
	if scene == null or not bool(scene.get_meta("presentation_only", false)) or \
			scene.get_meta("qualification", "") != QUALIFICATION or \
			not board.get("ok", false) or \
			str(board.get("level_id", "")) != str(scene.get_meta("source_level_id", "")):
		return _fail("EXP017_A03_FOREIGN_OR_UNTRUSTED_HOST")
	var tasks: Variant = board.get("tasks")
	if not tasks is Array or tasks.size() != 5:
		return _fail("EXP017_A03_BAD_TASK_SNAPSHOT")
	var source_ids: Array = scene.get_meta("source_task_ids", [])
	for index: int in range(5):
		if not tasks[index] is Dictionary or \
				str(tasks[index].get("id", "")) != str(source_ids[index]) or \
				typeof(tasks[index].get("completed")) != TYPE_BOOL:
			return _fail("EXP017_A03_TASK_ID_OR_STATE_DRIFT")
	if typeof(board.get("host_revision")) != TYPE_INT or \
			int(board["host_revision"]) < int(scene.get_meta("last_host_revision", -1)):
		return _fail("EXP017_A03_STALE_HOST")
	if typeof(board.get("mission_verified")) != TYPE_BOOL or \
			typeof(board.get("mission_completed")) != TYPE_BOOL:
		return _fail("EXP017_A03_BAD_VERIFICATION")
	if not grid.get("nodes") is Dictionary or typeof(grid.get("tick")) != TYPE_INT or \
			int(grid["tick"]) < int(scene.get_meta("last_grid_tick", -1)):
		return _fail("EXP017_A03_STALE_GRID")
	var nodes: Dictionary = grid["nodes"]
	var source: Variant = nodes.get("GRID")
	if not source is Dictionary or \
			typeof(source.get("online")) != TYPE_BOOL:
		return _fail("EXP017_A03_UNTRUSTED_GRID_SOURCE")
	for load: String in LOADS:
		if not nodes.get(load) is Dictionary or \
				typeof(nodes[load].get("supplied")) != TYPE_BOOL or \
				(bool(nodes[load]["supplied"]) and not bool(source["online"])):
			return _fail("EXP017_A03_INVALID_CANONICAL_SUPPLY")
	return {"ok": true}


## Idempotent per revision; a later host fault/darkening removes glow.
## Supply comes from the grid's canonical consumer supplied bit, never from
## task completion or a cosmetic animation timer.
static func reflect(scene: Node3D, board: Dictionary, grid: Dictionary) -> Dictionary:
	var checked: Dictionary = _validate(scene, board, grid)
	if not checked.get("ok", false):
		return checked
	var nodes: Dictionary = grid["nodes"]
	var lit: int = 0
	for load: String in LOADS:
		var supplied: bool = bool(nodes[load]["supplied"])
		if supplied:
			lit += 1
		var unit: Node3D = scene.get_node("HostSupplyLights/Supply_" + load) as Node3D
		var lamp: OmniLight3D = unit.get_node("HostPoweredLamp") as OmniLight3D
		var housing: MeshInstance3D = unit.get_node("Luminaire") as MeshInstance3D
		var mat: StandardMaterial3D = housing.material_override as StandardMaterial3D
		var plaque: Label3D = unit.get_node("SupplySign") as Label3D
		lamp.light_energy = 0.85 if supplied else 0.0
		mat.albedo_color = LIVE if supplied else DARK
		mat.emission_enabled = supplied
		mat.emission = LIVE if supplied else DARK
		plaque.text = "%s / %s" % [load, "GRID-SUPPLIED" if supplied else "DARK"]
		plaque.modulate = LIVE if supplied else DARK
		unit.set_meta("visual_supply", "grid" if supplied else "dark")
	var tasks: Array = board["tasks"]
	for index: int in range(5):
		var done: bool = bool(tasks[index]["completed"])
		var plaque: Label3D = scene.get_node("OperationSigns/Task%d" % (index + 1)) as Label3D
		plaque.text = "%s / %s" % [str(tasks[index]["id"]),
			"HOST COMPLETE" if done else "OPTIONAL" if not bool(tasks[index].get("required", true)) else "PENDING"]
		plaque.modulate = COMPLETE if done else DARK
	var verified: bool = bool(board["mission_verified"]) and \
			bool(nodes["LOAD_A"]["supplied"]) and \
			bool(nodes["LOAD_B"]["supplied"]) and \
			bool(nodes["LOAD_C"]["supplied"])
	var finale: OmniLight3D = scene.get_node("VerifiedRestorationGlow") as OmniLight3D
	finale.light_energy = 1.25 if verified else 0.0
	var end_sign: Label3D = scene.get_node("OperationSigns/RestorationSign") as Label3D
	end_sign.text = "RESTORATION / HOST VERIFIED" if verified else "RESTORATION / NOT VERIFIED"
	end_sign.modulate = COMPLETE if verified else DARK
	var env: Label3D = scene.get_node("OperationSigns/EnvironmentalReaction") as Label3D
	var ops: Label3D = scene.get_node("OperationSigns/OperationalFeedback") as Label3D
	var worksite: Dictionary = board.get("worksite", {})
	var hazard: Dictionary = worksite.get("site_hazards", {})
	var mitigated: bool = bool(hazard.get("solved", false))
	env.text = "ENVIRONMENT / HOST MITIGATED" if mitigated else "ENVIRONMENT / UNVERIFIED"
	env.modulate = COMPLETE if mitigated else FAULT
	var outcome: Dictionary = worksite.get("site_outcomes", {})
	var phase: String = str(outcome.get("phase", "not_active"))
	ops.text = "OPS / %s / %d SUPPLIED" % [phase.to_upper(), lit]
	ops.modulate = LIVE if lit > 0 else DARK
	scene.set_meta("last_host_revision", int(board["host_revision"]))
	scene.set_meta("last_grid_tick", int(grid["tick"]))
	return {"ok": true, "level_id": board["level_id"], "supplied": lit,
		"verified": verified, "mitigated": mitigated,
		"host_revision": board["host_revision"], "grid_tick": grid["tick"],
		"authority": "READ_ONLY_HOST_PROJECTION", "qualification": QUALIFICATION}
