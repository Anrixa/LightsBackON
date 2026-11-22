extends RefCounted
## EXP014 A01 — source-bound worksite equipment and procedure visualization.
##
## Composes three non-colliding field assemblies and two actual authored
## operation circuits from the already audited EXP012/EXP013 source case.
## It receives host-owned snapshots only; never creates authoritative targets,
## invents client events, advances a timer, or changes a save/mission outcome.
## This is a graybox composition candidate, NOT physical-playability evidence.

const QUALIFICATION: String = "SOURCE_HEADLESS_ONLY_HUMAN_CONTROLLER_RELEASE_HELD"
const MODES: Array[String] = ["hold", "pulse", "sample", "handoff", "balance"]
const ROUTES: Array[String] = ["priority", "resilience"]
const LETTERS: Array[String] = ["A", "B", "C"]
const TILE_SIZE_M: float = 52.0
const COLOR_IDLE: Color = Color("#4A6575")
const COLOR_ACTIVE: Color = Color("#F3C874")
const COLOR_DONE: Color = Color("#72CDD2")
const COLOR_FAULT: Color = Color("#E26D6C")


static func inspect(spec: Dictionary, positions: Dictionary) -> Dictionary:
	if spec.get("qualification") != QUALIFICATION:
		return {"ok": false, "code": "EXP014_UNQUALIFIED_SOURCE"}
	var level_id: String = str(spec.get("level_id", ""))
	if not level_id.begins_with("LV_") or level_id.length() != 6 or \
			not level_id.substr(3).is_valid_int() or \
			int(level_id.substr(3)) < 1 or int(level_id.substr(3)) > 200:
		return {"ok": false, "code": "EXP014_BAD_LEVEL"}
	var targets: Variant = spec.get("targets")
	var routes: Variant = spec.get("routes")
	if not targets is Dictionary or targets.size() != 3 or \
			not routes is Dictionary or routes.size() != 2:
		return {"ok": false, "code": "EXP014_INVALID_TOPOLOGY"}
	if spec.get("recovery_target") != targets.get("C"):
		return {"ok": false, "code": "EXP014_RECOVERY_TARGET_DRIFT"}
	var unique_targets: Dictionary = {}
	var coordinates: Array[String] = []
	for letter: String in LETTERS:
		var target: String = str(targets.get(letter, ""))
		if not target.begins_with("SC_") or unique_targets.has(target) or \
				not positions.get(target) is Vector3:
			return {"ok": false, "code": "EXP014_MISSING_HOST_TARGET"}
		unique_targets[target] = true
		var point: Vector3 = positions[target]
		if not point.is_finite() or point.x < 0.0 or point.z < 0.0 or \
				point.x > TILE_SIZE_M or point.z > TILE_SIZE_M or \
				point.y < -3.0 or point.y > 10.0:
			return {"ok": false, "code": "EXP014_TARGET_OUTSIDE_TILE"}
		coordinates.append("%s:%s" % [target, str(point)])
	var route_sigs: Array[String] = []
	for route: String in ROUTES:
		var steps: Variant = routes.get(route)
		if not steps is Array or steps.size() != 4:
			return {"ok": false, "code": "EXP014_INVALID_ROUTE"}
		var pieces: Array[String] = []
		for item: Variant in steps:
			if not item is Dictionary:
				return {"ok": false, "code": "EXP014_INVALID_STEP"}
			var step: Dictionary = item
			if not MODES.has(str(step.get("mode", ""))) or \
					not unique_targets.has(str(step.get("target", ""))) or \
					not unique_targets.has(str(step.get("support_target", ""))) or \
					step.get("target") == step.get("support_target") or \
					str(step.get("action", "")).length() < 8:
				return {"ok": false, "code": "EXP014_UNBOUND_OPERATION"}
			pieces.append("%s:%s>%s:%s" % [str(step["mode"]),
				str(step["support_target"]), str(step["target"]),
				str(step["action"])])
		route_sigs.append("|".join(pieces))
	if route_sigs[0] == route_sigs[1]:
		return {"ok": false, "code": "EXP014_DUPLICATE_STRATEGIES"}
	var fingerprint: String = ("%s|%s|%s|%s|%s" % [
		level_id, str(spec.get("region_id", "")),
		";".join(coordinates), route_sigs[0], route_sigs[1]]).sha256_text()
	return {"ok": true, "level_id": level_id, "target_count": 3,
		"routes": 2, "operations": 8, "fingerprint": fingerprint,
		"authority": "PRESENTATION_ONLY", "qualification": QUALIFICATION}


static func _material(color: Color) -> StandardMaterial3D:
	var result: StandardMaterial3D = StandardMaterial3D.new()
	result.albedo_color = color
	result.roughness = 0.65
	result.metallic = 0.28
	return result


static func _box(parent: Node3D, name: String, point: Vector3,
		size: Vector3, color: Color) -> MeshInstance3D:
	var shape: BoxMesh = BoxMesh.new()
	shape.size = size
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.name = name
	instance.mesh = shape
	instance.material_override = _material(color)
	instance.position = point
	parent.add_child(instance)
	return instance


static func _caption(parent: Node3D, name: String, message: String,
		height: float, tint: Color) -> Label3D:
	var label: Label3D = Label3D.new()
	label.name = name
	label.text = message
	label.position = Vector3(0.0, height, 0.0)
	label.font_size = 40
	label.pixel_size = 0.005
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = tint
	parent.add_child(label)
	return label


static func _run(parent: Node3D, name: String, a: Vector3, b: Vector3,
		height: float, tint: Color) -> MeshInstance3D:
	# Horizontal schematic conduit; no collider and no navigation claim.
	var diff: Vector3 = b - a
	diff.y = 0.0
	var model: MeshInstance3D = _box(parent, name,
		Vector3((a.x + b.x) * 0.5, height, (a.z + b.z) * 0.5),
		Vector3(0.10, 0.10, maxf(0.10, diff.length())), tint)
	model.rotation.y = atan2(diff.x, diff.z)
	return model


static func _assembly(root: Node3D, letter: String,
		anchor: Vector3, modes: Dictionary, region_code: int) -> void:
	var node: Node3D = Node3D.new()
	node.name = "Station_" + letter
	node.position = anchor
	node.set_meta("source_station_letter", letter)
	node.set_meta("presentation_only", true)
	root.add_child(node)
	var accent: Color = [
		Color("#7BC6D7"), Color("#F4C879"), Color("#A8CEA0")][LETTERS.find(letter)]
	_box(node, "Base", Vector3(0.0, 0.14, 0.0),
		Vector3(1.35, 0.24, 0.95), Color("#324D5B"))
	_box(node, "ControlCabinet", Vector3(0.0, 0.85, 0.0),
		Vector3(0.96, 1.18, 0.42), Color("#627F88"))
	# Count *actual authored* modes touching this station, not arbitrary level
	# index decoration. The unit shape exposes the local procedure topology.
	var used: Array = modes.get(letter, [])
	for i: int in range(used.size()):
		var mode: String = str(used[i])
		var height: float = 0.95 + float(i) * 0.34
		match mode:
			"hold":
				_box(node, "HoldGauge_%d" % i, Vector3(-0.30, height, -0.29),
					Vector3(0.25, 0.20, 0.12), accent)
			"pulse":
				_box(node, "PulseRelay_%d" % i, Vector3(0.30, height, -0.29),
					Vector3(0.19, 0.25, 0.16), COLOR_ACTIVE)
			"sample":
				_box(node, "SampleProbe_%d" % i, Vector3(-0.32, height, -0.29),
					Vector3(0.12, 0.31, 0.12), COLOR_DONE)
			"handoff":
				_box(node, "HandoffLatch_%d" % i, Vector3(0.32, height, -0.29),
					Vector3(0.28, 0.10, 0.24), accent)
			"balance":
				_box(node, "TrimWheel_%d" % i, Vector3(0.0, height, -0.29),
					Vector3(0.30, 0.12, 0.22), COLOR_DONE)
	# Region equipment arrangement is non-colliding source-stage concept art.
	# Three configurations are distinguished by piping, busbar or mast fixtures.
	match region_code % 3:
		0:
			_box(node, "ServiceBusbar", Vector3(0.0, 1.67, 0.1),
				Vector3(1.55, 0.10, 0.16), accent)
		1:
			for i: int in range(2):
				_box(node, "PipeRiser_%d" % i,
					Vector3(-0.48 + float(i) * 0.96, 1.05, 0.30),
					Vector3(0.12, 1.50, 0.12), accent)
		2:
			_box(node, "ControlMast", Vector3(0.0, 1.55, 0.29),
				Vector3(0.15, 2.30, 0.15), accent)
			_box(node, "SignalArm", Vector3(0.0, 2.52, 0.29),
				Vector3(1.30, 0.10, 0.10), accent)
	_caption(node, "StationHeading", "WORKSITE %s" % letter, 2.95, accent)


## Source-bound presentation. No collision shape, area, character controller,
## host registration or network call is added to the actual game scene.
static func build(spec: Dictionary, positions: Dictionary) -> Node3D:
	var audit: Dictionary = inspect(spec, positions)
	if not bool(audit.get("ok", false)):
		return null
	var root: Node3D = Node3D.new()
	root.name = "EXP014_Worksite"
	root.set_meta("source_level_id", str(spec["level_id"]))
	root.set_meta("source_fingerprint", str(audit["fingerprint"]))
	root.set_meta("qualification", QUALIFICATION)
	root.set_meta("presentation_only", true)
	var facilities: Node3D = Node3D.new()
	facilities.name = "Assemblies"
	root.add_child(facilities)
	var routes: Node3D = Node3D.new()
	routes.name = "Procedures"
	root.add_child(routes)
	var targets: Dictionary = spec["targets"]
	var modes: Dictionary = {}
	for letter: String in LETTERS:
		modes[letter] = []
	for route: String in ROUTES:
		for step: Dictionary in spec["routes"][route]:
			for letter: String in LETTERS:
				if step["target"] == targets[letter] and \
						not (modes[letter] as Array).has(step["mode"]):
					(modes[letter] as Array).append(step["mode"])
	var region_code: int = int(str(spec.get("region_id", "")).trim_prefix("REG_"))
	for letter: String in LETTERS:
		_assembly(facilities, letter, positions[str(targets[letter])],
			modes, region_code)
	for route: String in ROUTES:
		var group: Node3D = Node3D.new()
		group.name = route
		group.set_meta("source_route", route)
		routes.add_child(group)
		for i: int in range(4):
			var step: Dictionary = spec["routes"][route][i]
			var support: Vector3 = positions[str(step["support_target"])]
			var target: Vector3 = positions[str(step["target"])]
			var conduit: MeshInstance3D = _run(group,
				"Operation_%d" % i, support, target,
				2.10 if route == "priority" else 2.35, COLOR_IDLE)
			conduit.set_meta("source_mode", str(step["mode"]))
			conduit.set_meta("source_action", str(step["action"]))
			conduit.set_meta("source_target", str(step["target"]))
			conduit.set_meta("source_support", str(step["support_target"]))
			conduit.set_meta("visual_status", "idle")
	var legend: Label3D = _caption(root, "ProcedureStatus",
		"OPERATING ORDER NOT SELECTED", 0.0, COLOR_IDLE)
	legend.position = (positions[str(targets["A"])] +
		positions[str(targets["B"])] + positions[str(targets["C"])]) / 3.0 + \
		Vector3(0.0, 3.3, 0.0)
	return root


static func reflect(root: Node3D, host_state: Dictionary) -> void:
	if root == null or not bool(root.get_meta("presentation_only", false)):
		return
	if str(root.get_meta("source_level_id", "")) != \
			str(host_state.get("level_id", "")):
		return
	var route: String = str(host_state.get("route", ""))
	var current: int = clampi(int(host_state.get("step", 0)), 0, 4)
	var faulted: bool = str(host_state.get("fault", "")) != ""
	var solved: bool = bool(host_state.get("solved", false))
	for route_name: String in ROUTES:
		var group: Node3D = root.get_node("Procedures/" + route_name) as Node3D
		group.visible = route == "" or route == route_name
		for i: int in range(4):
			var conduit: MeshInstance3D = group.get_node("Operation_%d" % i) as MeshInstance3D
			var status: String = "idle"
			var color: Color = COLOR_IDLE
			if route == route_name:
				if i < current:
					status = "complete"
					color = COLOR_DONE
				elif i == current and not solved:
					status = "fault" if faulted else "active"
					color = COLOR_FAULT if faulted else COLOR_ACTIVE
			conduit.set_meta("visual_status", status)
			# Never mutate a shared material, so another level cannot inherit
			# a previous site's fault color on a reused mesh resource.
			conduit.material_override = _material(color)
	var label: Label3D = root.get_node("ProcedureStatus") as Label3D
	if solved:
		label.text = "SITE RESTORED / HOST VERIFIED"
		label.modulate = COLOR_DONE
	elif faulted:
		label.text = "SITE FAULT / RECOVER AT STATION C"
		label.modulate = COLOR_FAULT
	elif route == "":
		label.text = "CHOOSE OPERATING ORDER AT WORKSITE BOARD"
		label.modulate = COLOR_IDLE
	else:
		var next: Dictionary = host_state.get("next", {})
		label.text = "%s  %d/4  %s  %s" % [
			route.to_upper(), current + 1,
			str(next.get("mode", "")).to_upper(),
			str(host_state.get("phase", ""))]
		label.modulate = COLOR_ACTIVE


## EXP014 A02: after the four original host-authoritative intervention
## operations finish, reuse the same route display to expose three new
## conditional mechanical stages. No scene or host state is mutated.
static func reflect_contingency(root: Node3D, host_state: Dictionary) -> void:
	if root == null or not bool(root.get_meta("presentation_only", false)):
		return
	if str(root.get_meta("source_level_id", "")) != str(host_state.get("level_id", "")):
		return
	var route: String = str(host_state.get("route", ""))
	var step_index: int = clampi(int(host_state.get("step", 0)), 0, 3)
	var faulted: bool = str(host_state.get("fault", "")) != ""
	var solved: bool = bool(host_state.get("solved", false))
	for route_name: String in ROUTES:
		var group: Node3D = root.get_node("Procedures/" + route_name) as Node3D
		group.visible = route == "" or route == route_name
		for i: int in range(4):
			var line: MeshInstance3D = group.get_node("Operation_%d" % i) as MeshInstance3D
			var tint: Color = COLOR_IDLE
			var phase: String = "inactive"
			if route == route_name:
				if i == 3 or i < step_index:
					tint = COLOR_DONE
					phase = "complete"
				elif i == step_index and not solved:
					tint = COLOR_FAULT if faulted else COLOR_ACTIVE
					phase = "fault" if faulted else "active"
			line.set_meta("contingency_status", phase)
			line.material_override = _material(tint)
	var label: Label3D = root.get_node("ProcedureStatus") as Label3D
	if solved:
		label.text = "CONTINGENCY VERIFIED / SOURCE AUTHORITY"
		label.modulate = COLOR_DONE
	elif faulted:
		label.text = "CONTINGENCY FAULT / RETURN TO STATION C"
		label.modulate = COLOR_FAULT
	elif route == "":
		label.text = "CHOOSE OPERATING STRATEGY AT WORKSITE BOARD"
		label.modulate = COLOR_IDLE
	else:
		var next: Dictionary = host_state.get("next", {})
		label.text = "CONTINGENCY %s %d/3 • %s • %s" % [
			route.to_upper(), step_index + 1,
			str(next.get("mode", "")).to_upper(),
			str(host_state.get("phase", ""))]
		label.modulate = COLOR_ACTIVE
