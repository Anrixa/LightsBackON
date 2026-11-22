extends RefCounted
## EXP014 A03: 25 source-pinned regional facility families with environmental
## evidence. Entirely visual and deterministic: no CollisionObject3D, Area3D,
## navigation, player commands, host verdicts, save or network interaction.
## AABB and stand-off tests here are DESIGN DIAGNOSTICS, never route certification.

const QUALIFICATION: String = "SOURCE_HEADLESS_ONLY_HUMAN_CONTROLLER_RELEASE_HELD"
const TILE_M: float = 52.0
const HALF_PATCH_M: float = 4.4
const MIN_TASK_STANDOFF_M: float = 2.4
const SITE_CATEGORIES: Array[String] = [
	"distribution", "transport", "health", "commerce", "waterworks",
	"communications", "education", "shelter"
]
# Each region has an explicitly authored four-form structural silhouette,
# source-matched risk, distinctive hazard apparatus and original palette tone.
# Shape tuples, not title or color strings, determine geometry-family identity.
const RECIPES: Dictionary = {
	"REG_01": {"risk":"flooded service trenches", "forms":["arch","channel","cabinet","gantry"], "cue":"trench", "tone":"#A95F4D"},
	"REG_02": {"risk":"salt-contaminated switchgear", "forms":["silo","rack","screen","mast"], "cue":"salt", "tone":"#69B3A2"},
	"REG_03": {"risk":"track-side vibration", "forms":["truss","bridge","pylon","rack"], "cue":"rail", "tone":"#8B8D91"},
	"REG_04": {"risk":"rising brackish groundwater", "forms":["channel","cistern","screen","shed"], "cue":"reed", "tone":"#879879"},
	"REG_05": {"risk":"rockfall across feeder tracks", "forms":["stair","baffle","hoist","pylon"], "cue":"rock", "tone":"#8C99A0"},
	"REG_06": {"risk":"conductive metal dust", "forms":["stack","vent","rack","arch"], "cue":"dust", "tone":"#A96C54"},
	"REG_07": {"risk":"silted utility channels", "forms":["bridge","cistern","channel","gate"], "cue":"silt", "tone":"#8CBE86"},
	"REG_08": {"risk":"jammed lock gates", "forms":["gate","hoist","bridge","vent"], "cue":"lock", "tone":"#8BADC1"},
	"REG_09": {"risk":"overwet control relays", "forms":["cistern","mast","canopy","channel"], "cue":"spray", "tone":"#57C4C5"},
	"REG_10": {"risk":"failed platform sequence control", "forms":["canopy","screen","gantry","tower"], "cue":"platform", "tone":"#869BBF"},
	"REG_11": {"risk":"overheated legacy motors", "forms":["stack","shed","vent","gantry"], "cue":"motor", "tone":"#C18865"},
	"REG_12": {"risk":"frost-loaded conductors", "forms":["tower","pylon","bridge","screen"], "cue":"frost", "tone":"#91BEDA"},
	"REG_13": {"risk":"surge shutters stuck open", "forms":["baffle","gate","channel","tower"], "cue":"surge", "tone":"#D3BD8C"},
	"REG_14": {"risk":"fallen branches over circuits", "forms":["mast","truss","stair","screen"], "cue":"branch", "tone":"#9AAF84"},
	"REG_15": {"risk":"ash-clogged filters", "forms":["vent","stack","baffle","cabinet"], "cue":"ash", "tone":"#BD7858"},
	"REG_16": {"risk":"intermittent ferry supply", "forms":["bridge","hoist","silo","canopy"], "cue":"ferry", "tone":"#A7A08A"},
	"REG_17": {"risk":"condensation shorts", "forms":["canopy","rack","cistern","truss"], "cue":"condensation", "tone":"#89B5A0"},
	"REG_18": {"risk":"coal-water leakage", "forms":["hoist","channel","stack","gate"], "cue":"coal", "tone":"#77837C"},
	"REG_19": {"risk":"inlet overflow risk", "forms":["cistern","gate","baffle","tower"], "cue":"overflow", "tone":"#65B5C0"},
	"REG_20": {"risk":"tree-root cable intrusion", "forms":["stair","mast","shed","cabinet"], "cue":"roots", "tone":"#A48C70"},
	"REG_21": {"risk":"mixed old/new electrical wiring", "forms":["arch","cabinet","screen","truss"], "cue":"wiring", "tone":"#BB9B63"},
	"REG_22": {"risk":"toxic-looking but harmless dye leaks", "forms":["silo","channel","baffle","vent"], "cue":"dye", "tone":"#A38BB8"},
	"REG_23": {"risk":"lightning-sensitive instruments", "forms":["tower","mast","rack","pylon"], "cue":"lightning", "tone":"#A5B5A0"},
	"REG_24": {"risk":"sand-blown power connectors", "forms":["shed","baffle","screen","silo"], "cue":"sand", "tone":"#CBB68C"},
	"REG_25": {"risk":"stairwell flooding and antenna loss", "forms":["stair","tower","canopy","cabinet"], "cue":"stairwell", "tone":"#BC9095"}
}
const FORMS: Array[String] = [
	"arch", "channel", "cabinet", "gantry", "silo", "rack", "screen",
	"mast", "truss", "bridge", "pylon", "cistern", "shed", "stair",
	"baffle", "hoist", "stack", "vent", "gate", "canopy", "tower"
]
const SLOT_OFFSETS: Array[Vector2] = [
	Vector2(-2.5, -2.5), Vector2(2.5, -2.5),
	Vector2(-2.5, 2.5), Vector2(2.5, 2.5)
]


static func _reject(code: String) -> Dictionary:
	return {"ok": false, "code": code, "qualification": QUALIFICATION}


static func _overlap(a: Vector2, b: Vector2, half_a: Vector2,
		half_b: Vector2) -> bool:
	return absf(a.x - b.x) < half_a.x + half_b.x and \
		absf(a.y - b.y) < half_a.y + half_b.y


static func _free(anchor: Vector2, stations: Array) -> bool:
	if anchor.x - HALF_PATCH_M < 0.0 or anchor.y - HALF_PATCH_M < 0.0 or \
			anchor.x + HALF_PATCH_M > TILE_M or anchor.y + HALF_PATCH_M > TILE_M:
		return false
	# Existing EXP02 landmark envelopes, including their roofs/raised decks.
	var protected: Array[Dictionary] = [
		{"center":Vector2(7.5, 40.0), "half":Vector2(8.0, 5.6)},
		{"center":Vector2(43.0, 9.0), "half":Vector2(3.7, 4.2)},
		{"center":Vector2(41.5, 40.5), "half":Vector2(4.0, 3.9)}
	]
	for zone: Dictionary in protected:
		if _overlap(anchor, zone["center"], Vector2.ONE * HALF_PATCH_M, zone["half"]):
			return false
	for station: Dictionary in stations:
		var pos: Vector3 = station["position"]
		var dx: float = maxf(absf(anchor.x - pos.x) - HALF_PATCH_M, 0.0)
		var dz: float = maxf(absf(anchor.y - pos.z) - HALF_PATCH_M, 0.0)
		if Vector2(dx, dz).length() < MIN_TASK_STANDOFF_M:
			return false
	return true


static func _anchor(stations: Array, serial: int, region_number: int) -> Dictionary:
	# Scan the same bounded candidate grid for every site, beginning at a
	# deterministic source-derived offset. Never place onto an occupied slot.
	var cells: Array[Vector2] = []
	for z: float in [7.0, 17.0, 27.0, 37.0, 47.0]:
		for x: float in [7.0, 17.0, 27.0, 37.0, 47.0]:
			cells.append(Vector2(x, z))
	var first: int = (serial * 7 + region_number * 3) % cells.size()
	for index: int in range(cells.size()):
		var candidate: Vector2 = cells[(first + index) % cells.size()]
		if _free(candidate, stations):
			return {"ok": true, "anchor": candidate,
				"slot": (first + index) % cells.size()}
	return {"ok": false, "code": "EXP014_A03_NO_FREE_FACILITY_SLOT"}


## Deterministic static envelope checks; not ray casts or physical traversal.
static func inspect(plan: Dictionary) -> Dictionary:
	if plan.get("ok") != true or plan.get("code") != "VISUAL_CANDIDATE_ONLY" or \
			plan.get("not_certified") != "NO_PHYSICAL_PLAYABILITY":
		return _reject("EXP014_A03_UNQUALIFIED_PLAN")
	var serial: int = int(plan.get("serial", -1))
	var level: String = str(plan.get("id", ""))
	if serial < 1 or serial > 200 or level != "LV_%03d" % serial:
		return _reject("EXP014_A03_INVALID_SITE")
	var region: String = str(plan.get("region_id", ""))
	var region_number: int = int((serial - 1) / 8) + 1
	if region != "REG_%02d" % region_number or not RECIPES.has(region):
		return _reject("EXP014_A03_FOREIGN_REGION")
	var recipe: Dictionary = RECIPES[region]
	if plan.get("hazard") != recipe["risk"] or \
			not SITE_CATEGORIES.has(str(plan.get("category", ""))):
		return _reject("EXP014_A03_SOURCE_RISK_DRIFT")
	var stations: Variant = plan.get("stations")
	if not stations is Array or stations.size() != 5:
		return _reject("EXP014_A03_MISSING_TASK_MARKERS")
	var seen: Dictionary = {}
	for row: Variant in stations:
		if not row is Dictionary:
			return _reject("EXP014_A03_INVALID_MARKER")
		var station: Dictionary = row
		var pos: Variant = station.get("position")
		var task_id: String = str(station.get("id", ""))
		if not pos is Vector3 or not (pos as Vector3).is_finite() or \
				(pos as Vector3).x < 0.0 or (pos as Vector3).x > TILE_M or \
				(pos as Vector3).z < 0.0 or (pos as Vector3).z > TILE_M or \
				not task_id.begins_with("JOB_%03d_" % serial) or seen.has(task_id):
			return _reject("EXP014_A03_UNBOUND_TASK_MARKER")
		seen[task_id] = true
	var forms: Array = recipe["forms"]
	if forms.size() != 4 or set_forms(forms).size() != 4:
		return _reject("EXP014_A03_INVALID_FACILITY_PROFILE")
	var site: Dictionary = _anchor(stations, serial, region_number)
	if not bool(site.get("ok", false)):
		return _reject(str(site.get("code", "EXP014_A03_NO_FREE_FACILITY_SLOT")))
	var form_names: Array[String] = []
	for form: Variant in forms:
		form_names.append(str(form))
	var geometry_sig: String = ("%s|%s" % [
		",".join(form_names), str(recipe["cue"])]).sha256_text()
	var site_sig: String = ("%s|%s|%s|%s" % [
		level, region, str(site["anchor"]), geometry_sig]).sha256_text()
	return {"ok": true, "region_id": region, "level_id": level,
		"location_id": str(plan.get("location_id", "")), "risk": recipe["risk"],
		"facility_forms": 4, "encounter_cues": 1, "geometry_signature": geometry_sig,
		"site_signature": site_sig, "anchor": site["anchor"], "slot": site["slot"],
		"source_task_markers": 5, "no_collision_shapes": true,
		"authority": "PRESENTATION_ONLY", "qualification": QUALIFICATION}


static func set_forms(forms: Array) -> Dictionary:
	var unique: Dictionary = {}
	for name: Variant in forms:
		if not FORMS.has(str(name)):
			return {}
		unique[str(name)] = true
	return unique


static func _material(color: Color) -> StandardMaterial3D:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.78
	mat.metallic = 0.15
	return mat


static func _box(parent: Node3D, name: String, offset: Vector3,
		size: Vector3, color: Color) -> void:
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = size
	var node: MeshInstance3D = MeshInstance3D.new()
	node.name = name
	node.mesh = mesh
	node.position = offset
	node.material_override = _material(color)
	parent.add_child(node)


static func _cylinder(parent: Node3D, name: String, offset: Vector3,
		radius: float, height: float, color: Color) -> void:
	var mesh: CylinderMesh = CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	var node: MeshInstance3D = MeshInstance3D.new()
	node.name = name
	node.mesh = mesh
	node.position = offset
	node.material_override = _material(color)
	parent.add_child(node)


static func _form(parent: Node3D, form: String, tint: Color) -> void:
	var iron: Color = Color("#384D5B")
	match form:
		"arch", "gate", "gantry", "canopy", "bridge", "truss":
			_box(parent, "LeftUpright", Vector3(-0.72, 1.12, 0.0), Vector3(0.22, 2.24, 0.35), iron)
			_box(parent, "RightUpright", Vector3(0.72, 1.12, 0.0), Vector3(0.22, 2.24, 0.35), iron)
			_box(parent, "Span", Vector3(0.0, 2.27, 0.0),
				Vector3(1.85, 0.22 if form != "bridge" else 0.45, 0.45), tint)
			if form == "gate":
				_box(parent, "SlidingLeaf", Vector3(0.0, 0.83, 0.0), Vector3(1.24, 1.52, 0.14), tint)
			elif form == "canopy":
				_box(parent, "Roof", Vector3(0.0, 2.48, 0.0), Vector3(2.25, 0.13, 1.85), tint)
			elif form == "truss":
				_box(parent, "TensionBrace", Vector3(0.0, 1.4, 0.0), Vector3(0.12, 2.15, 0.12), tint)
			elif form == "gantry":
				_box(parent, "GantryHead", Vector3(0.0, 2.66, 0.0), Vector3(0.52, 0.45, 0.6), tint)
		"silo", "cistern", "tower", "stack", "mast", "pylon":
			var height: float = 2.15 if form == "cistern" else 3.1
			_cylinder(parent, "Column", Vector3(0.0, height * 0.5, 0.0),
				0.72 if form in ["silo", "cistern"] else 0.29,
				height, tint)
			if form in ["tower", "pylon", "mast"]:
				_box(parent, "Crossarm", Vector3(0.0, 2.84, 0.0),
					Vector3(2.0 if form != "mast" else 1.0, 0.15, 0.21), iron)
			if form == "pylon":
				_box(parent, "StrainBrace", Vector3(0.0, 1.36, 0.0),
					Vector3(1.65, 0.14, 0.35), iron)
			elif form == "tower":
				_box(parent, "InstrumentDeck", Vector3(0.0, 2.10, 0.0),
					Vector3(1.08, 0.16, 1.08), iron)
			if form in ["silo", "cistern"]:
				_box(parent, "FeedSpur", Vector3(0.0, 0.3, 0.0),
					Vector3(2.1, 0.20, 0.25), iron)
			if form == "stack":
				_cylinder(parent, "Cowl", Vector3(0.0, 3.16, 0.0), 0.49, 0.23, iron)
		"channel", "baffle", "screen", "rack", "cabinet":
			var count: int = 4 if form in ["screen", "rack"] else 3
			for i: int in range(count):
				var x: float = -0.85 + float(i) * (1.7 / float(count - 1))
				var height: float = 1.1 + (float(i % 2) * 0.65)
				if form == "cabinet":
					height = 1.6 + float(i) * 0.23
				_box(parent, "Fin_%02d" % i, Vector3(x, height * 0.5, 0.0),
					Vector3(0.17 if form != "baffle" else 0.34, height,
						1.65 if form == "channel" else 0.5), tint)
			if form in ["rack", "cabinet"]:
				_box(parent, "ControlTop", Vector3(0.0, 2.08, 0.0),
					Vector3(2.2, 0.22, 0.8), iron)
		"shed", "vent", "stair", "hoist":
			if form == "stair":
				for i: int in range(4):
					_box(parent, "Step_%d" % i, Vector3(-0.75 + float(i) * 0.5,
						0.20 + float(i) * 0.33, 0.0),
						Vector3(0.48, 0.4 + float(i) * 0.66, 1.25), tint)
			else:
				_box(parent, "ServiceHousing", Vector3(0.0, 0.65, 0.0),
					Vector3(1.65, 1.3, 1.35), tint)
				_box(parent, "Superstructure", Vector3(0.0, 1.65, 0.0),
					Vector3(2.05, 0.16, 1.50), iron)
				if form == "hoist":
					_box(parent, "LiftPost", Vector3(-0.62, 2.35, 0.0),
						Vector3(0.18, 1.4, 0.18), tint)
					_box(parent, "Boom", Vector3(0.25, 2.9, 0.0),
						Vector3(1.6, 0.18, 0.2), tint)
				elif form == "vent":
					_cylinder(parent, "Exhaust", Vector3(0.0, 2.36, 0.0), 0.28, 1.3, tint)


static func _environment(parent: Node3D, cue: String, tint: Color, risk: String) -> void:
	var relief: Node3D = Node3D.new()
	relief.name = "SourceHazard_" + cue
	relief.set_meta("source_risk", risk)
	relief.set_meta("encounter_form", cue)
	parent.add_child(relief)
	# The scene is an interpretive environmental cue; it has no sensor Area3D,
	# collision, gameplay action, lethal trigger or authoritative hazard status.
	_box(relief, "EvidenceBed", Vector3(0.0, 0.05, 0.0),
		Vector3(1.55, 0.1, 1.55), Color("#2B4351"))
	var index: int = [
		"trench", "salt", "rail", "reed", "rock", "dust", "silt",
		"lock", "spray", "platform", "motor", "frost", "surge", "branch",
		"ash", "ferry", "condensation", "coal", "overflow", "roots",
		"wiring", "dye", "lightning", "sand", "stairwell"].find(cue)
	# Each of the 25 authored environmental risks selects a different
	# ordered relief: profiles vary in height, pitch, count and fixture type.
	for j: int in range(1 + index % 4):
		var offset: float = (float(j) - float(index % 4) * 0.5) * 0.32
		var height: float = 0.2 + float((index + 2 * j) % 5) * 0.15
		if index % 3 == 0:
			_box(relief, "Weir_%d" % j, Vector3(offset, height * 0.5 + 0.11, 0.0),
				Vector3(0.16, height, 1.16 - float(j) * 0.08), tint)
		elif index % 3 == 1:
			_cylinder(relief, "Probe_%d" % j,
				Vector3(offset, height * 0.5 + 0.11, 0.0), 0.09, height, tint)
		else:
			_box(relief, "Debris_%d" % j,
				Vector3(offset, height * 0.5 + 0.11, 0.0),
				Vector3(0.32, height, 0.18 + float(j) * 0.13), tint)
	var label: Label3D = Label3D.new()
	label.name = "EnvironmentalEvidence"
	label.text = risk.to_upper()
	label.position = Vector3(0.0, 1.8, 0.0)
	label.font_size = 22
	label.pixel_size = 0.004
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = tint
	relief.add_child(label)


## Builds an isolated presentation-only object for the selected 200-site tile.
## No physics body, collision shape, navigation agent or controller is created.
static func build(plan: Dictionary) -> Node3D:
	var audit: Dictionary = inspect(plan)
	if not bool(audit.get("ok", false)):
		return null
	var recipe: Dictionary = RECIPES[str(audit["region_id"])]
	var root: Node3D = Node3D.new()
	root.name = "EXP014_A03_RegionalFacilities"
	var anchor: Vector2 = audit["anchor"]
	root.position = Vector3(anchor.x, 0.0, anchor.y)
	root.set_meta("source_level_id", str(audit["level_id"]))
	root.set_meta("source_region_id", str(audit["region_id"]))
	root.set_meta("source_location_id", str(audit["location_id"]))
	root.set_meta("geometry_signature", str(audit["geometry_signature"]))
	root.set_meta("site_signature", str(audit["site_signature"]))
	root.set_meta("qualification", QUALIFICATION)
	root.set_meta("presentation_only", true)
	var complex: Node3D = Node3D.new()
	complex.name = "FacilitySilhouettes"
	root.add_child(complex)
	var color: Color = Color(str(recipe["tone"]))
	var forms: Array = recipe["forms"]
	var shift: int = SITE_CATEGORIES.find(str(plan["category"])) % 4
	for i: int in range(4):
		var unit: Node3D = Node3D.new()
		unit.name = "Facility_%d_%s" % [i + 1, str(forms[i])]
		var offset: Vector2 = SLOT_OFFSETS[(i + shift) % 4]
		unit.position = Vector3(offset.x, 0.0, offset.y)
		unit.set_meta("facility_form", str(forms[i]))
		unit.set_meta("source_region", str(audit["region_id"]))
		complex.add_child(unit)
		_form(unit, str(forms[i]), color)
	var encounter: Node3D = Node3D.new()
	encounter.name = "EnvironmentalEncounter"
	root.add_child(encounter)
	_environment(encounter, str(recipe["cue"]), color, str(recipe["risk"]))
	# An individual site chooses its nearest original task marker as the
	# source of the encounter approach cue. This points at evidence only;
	# it never installs or modifies a host interactable.
	var nearest_id: String = ""
	var nearest_delta: Vector2 = Vector2.ZERO
	var best_distance: float = INF
	for station: Dictionary in plan["stations"]:
		var position: Vector3 = station["position"]
		var delta: Vector2 = Vector2(position.x - anchor.x,
			position.z - anchor.y)
		if delta.length() < best_distance:
			best_distance = delta.length()
			nearest_id = str(station["id"])
			nearest_delta = delta
	encounter.set_meta("source_task_evidence", nearest_id)
	encounter.set_meta("distance_to_source_task_m", best_distance)
	var bearing: Node3D = Node3D.new()
	bearing.name = "SiteSpecificEvidenceBearing"
	bearing.rotation.y = atan2(nearest_delta.x, nearest_delta.y)
	bearing.set_meta("source_task_id", nearest_id)
	encounter.add_child(bearing)
	_box(bearing, "DirectionNeedle", Vector3(0.0, 0.07, 1.15),
		Vector3(0.13, 0.06, 0.65), color)
	return root
