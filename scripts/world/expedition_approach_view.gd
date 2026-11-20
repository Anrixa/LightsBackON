extends RefCounted
## EXP014 A05 read-only schematic approach geometry.
## Both entrance branches terminate at real, existing host-bound SC target
## markers; corridor ribbons are non-colliding diagrams, NOT a path/LoS,
## player-clearance, accessibility or controller-playability qualification.

const Intelligence := preload("res://scripts/gameplay/expedition_approach_intelligence.gd")
const QUALIFICATION: String = Intelligence.QUALIFICATION


static func _material(color: Color) -> StandardMaterial3D:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.82
	return mat


static func _segment(parent: Node3D, label: String,
		start: Vector3, finish: Vector3, width: float, mat: Material) -> void:
	var delta: Vector3 = finish - start
	delta.y = 0.0
	if delta.length() < 0.2:
		return
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = Vector3(width, 0.07, delta.length())
	var ribbon: MeshInstance3D = MeshInstance3D.new()
	ribbon.name = label
	ribbon.mesh = mesh
	ribbon.material_override = mat
	ribbon.position = (start + finish) * 0.5
	ribbon.position.y = 0.09
	ribbon.rotation.y = atan2(delta.x, delta.z)
	parent.add_child(ribbon)


static func build(plan: Dictionary, source: Dictionary,
		positions: Dictionary) -> Node3D:
	var inspected: Dictionary = Intelligence.inspect(plan, source)
	if not bool(inspected.get("ok", false)):
		return null
	var profile: Dictionary = Intelligence.PROFILES[str(plan["region_id"])]
	for letter: String in ["A", "B", "C"]:
		var target_id: String = str(source["targets"][letter])
		if not positions.has(target_id) or not positions[target_id] is Vector3:
			return null
		var p: Vector3 = positions[target_id]
		if not p.is_finite() or p.x < 3.0 or p.z < 3.0 or p.x > 49.0 or p.z > 49.0:
			return null
	var root: Node3D = Node3D.new()
	root.name = "EXP014_A05_ApproachRoutes"
	root.set_meta("presentation_only", true)
	root.set_meta("source_level_id", str(plan["id"]))
	root.set_meta("source_region_id", str(plan["region_id"]))
	root.set_meta("source_risk", str(plan["hazard"]))
	root.set_meta("qualification", QUALIFICATION)
	root.set_meta("host_phase", "unverified")
	var targets: Dictionary = source["targets"]
	var entrance: Vector3 = positions[str(targets[str(profile["entry"])])]
	var first: Vector3 = positions[str(targets[str(profile["first"])])]
	var second: Vector3 = positions[str(targets[str(profile["second"])])]
	var guarded: Node3D = Node3D.new()
	guarded.name = "GuardedApproach"
	root.add_child(guarded)
	var urgent: Node3D = Node3D.new()
	urgent.name = "UrgentApproach"
	root.add_child(urgent)
	var vector: Vector3 = (first - entrance).normalized()
	if vector.length() < 0.01:
		vector = Vector3(0, 0, -1)
	var sidestep: Vector3 = Vector3(-vector.z, 0.0, vector.x) * 2.1
	var ingress: Vector3 = entrance - vector * 3.0
	_segment(guarded, "GuardedSurveyLeg", ingress + sidestep,
		first + sidestep, 0.85, _material(Color("#72CDD2")))
	_segment(guarded, "GuardedWitnessLeg", first + sidestep,
		first, 0.85, _material(Color("#72CDD2")))
	_segment(guarded, "GuardedEntryLeg", first, entrance,
		0.85, _material(Color("#72CDD2")))
	_segment(urgent, "UrgentDirectLeg", ingress, entrance,
		0.65, _material(Color("#E5A15C")))
	_segment(root, "InvestigationSequence", first, second,
		0.28, _material(Color("#A2AEBC")))
	guarded.visible = true
	urgent.visible = true
	return root


## Never trust a client-selected route or reveal unobserved intelligence.
## Called with the already committed host snapshot only.
static func reflect(scene: Node3D, state: Dictionary) -> Dictionary:
	if scene == null or not bool(scene.get_meta("presentation_only", false)) or \
			scene.get_meta("qualification") != QUALIFICATION:
		return {"ok": false, "code": "EXP014_A05_UNTRUSTED_SCENE"}
	if str(state.get("level_id", "")) != str(scene.get_meta("source_level_id", "")) or \
			str(state.get("region_id", "")) != str(scene.get_meta("source_region_id", "")):
		return {"ok": false, "code": "EXP014_A05_FOREIGN_HOST_STATE"}
	var approach: String = str(state.get("approach", ""))
	var phase: String = str(state.get("phase", ""))
	if approach not in ["", "guarded", "urgent"] or \
			phase not in ["arrival", "transit", "investigate", "decision",
				"prepare", "fault", "certified"]:
		return {"ok": false, "code": "EXP014_A05_INVALID_HOST_PROJECTION"}
	var guarded: Node3D = scene.get_node_or_null("GuardedApproach") as Node3D
	var urgent: Node3D = scene.get_node_or_null("UrgentApproach") as Node3D
	if guarded == null or urgent == null:
		return {"ok": false, "code": "EXP014_A05_MISSING_ROUTE_GEOMETRY"}
	guarded.visible = approach != "urgent"
	urgent.visible = approach != "guarded"
	scene.set_meta("host_phase", phase)
	scene.set_meta("host_approach", approach)
	return {"ok": true, "authority": "READ_ONLY_PRESENTATION",
		"qualification": QUALIFICATION}
