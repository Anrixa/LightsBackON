extends RefCounted
## EXP017 A01 source-pinned, presentation-only 25 regional hero landmarks.
## Static mesh extensions: no CollisionObject3D, navigation, sensor or host signal.

const QUALIFICATION: String = "SOURCE_GEOMETRY_ONLY_NO_PLAYABILITY_OR_RELEASE"
const FAMILIES: Array[String] = ["weir", "frame", "gantry", "tank", "mast"]
const PROFILES: Dictionary = {
	"REG_01": {"family": "weir", "segments": 3, "height_cm": 190, "cue": "trench"},
	"REG_02": {"family": "frame", "segments": 4, "height_cm": 260, "cue": "salt"},
	"REG_03": {"family": "gantry", "segments": 3, "height_cm": 270, "cue": "rail"},
	"REG_04": {"family": "tank", "segments": 2, "height_cm": 240, "cue": "reed"},
	"REG_05": {"family": "mast", "segments": 4, "height_cm": 310, "cue": "rock"},
	"REG_06": {"family": "frame", "segments": 3, "height_cm": 285, "cue": "dust"},
	"REG_07": {"family": "weir", "segments": 4, "height_cm": 230, "cue": "silt"},
	"REG_08": {"family": "gantry", "segments": 5, "height_cm": 265, "cue": "lock"},
	"REG_09": {"family": "tank", "segments": 3, "height_cm": 255, "cue": "spray"},
	"REG_10": {"family": "frame", "segments": 5, "height_cm": 305, "cue": "platform"},
	"REG_11": {"family": "mast", "segments": 3, "height_cm": 340, "cue": "motor"},
	"REG_12": {"family": "gantry", "segments": 4, "height_cm": 325, "cue": "frost"},
	"REG_13": {"family": "weir", "segments": 5, "height_cm": 280, "cue": "surge"},
	"REG_14": {"family": "mast", "segments": 5, "height_cm": 350, "cue": "branch"},
	"REG_15": {"family": "frame", "segments": 2, "height_cm": 300, "cue": "ash"},
	"REG_16": {"family": "gantry", "segments": 2, "height_cm": 310, "cue": "ferry"},
	"REG_17": {"family": "tank", "segments": 4, "height_cm": 290, "cue": "condensation"},
	"REG_18": {"family": "weir", "segments": 2, "height_cm": 240, "cue": "coal"},
	"REG_19": {"family": "tank", "segments": 5, "height_cm": 295, "cue": "overflow"},
	"REG_20": {"family": "mast", "segments": 2, "height_cm": 330, "cue": "roots"},
	"REG_21": {"family": "frame", "segments": 6, "height_cm": 345, "cue": "wiring"},
	"REG_22": {"family": "weir", "segments": 6, "height_cm": 265, "cue": "dye"},
	"REG_23": {"family": "mast", "segments": 6, "height_cm": 360, "cue": "lightning"},
	"REG_24": {"family": "tank", "segments": 6, "height_cm": 315, "cue": "sand"},
	"REG_25": {"family": "gantry", "segments": 6, "height_cm": 375, "cue": "stairwell"}
}


static func inspect(region_id: String, source_cue: String) -> Dictionary:
	if not PROFILES.has(region_id):
		return {"ok": false, "code": "EXP017_A01_UNKNOWN_REGION"}
	var profile: Dictionary = PROFILES[region_id]
	if profile["cue"] != source_cue:
		return {"ok": false, "code": "EXP017_A01_RISK_CUE_DRIFT"}
	var family: String = str(profile["family"])
	var segments: int = int(profile["segments"])
	var height_cm: int = int(profile["height_cm"])
	if family not in FAMILIES or segments < 2 or segments > 6 or \
			height_cm < 180 or height_cm > 400:
		return {"ok": false, "code": "EXP017_A01_INVALID_LANDMARK_GEOMETRY"}
	var signature: String = ("%s|%d|%d" %
		[family, segments, height_cm]).sha256_text()
	return {"ok": true, "region_id": region_id, "family": family,
		"segments": segments, "height_cm": height_cm,
		"structural_signature": signature, "qualification": QUALIFICATION,
		"presentation_only": true}


static func _material(color: Color) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.76
	material.metallic = 0.18
	return material


static func _beam(parent: Node3D, name: String, at: Vector3,
		size: Vector3, color: Color) -> void:
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = size
	var piece: MeshInstance3D = MeshInstance3D.new()
	piece.name = name
	piece.mesh = mesh
	piece.position = at
	piece.material_override = _material(color)
	parent.add_child(piece)


static func _column(parent: Node3D, name: String, at: Vector3,
		radius: float, height: float, color: Color) -> void:
	var mesh: CylinderMesh = CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	var piece: MeshInstance3D = MeshInstance3D.new()
	piece.name = name
	piece.mesh = mesh
	piece.position = at
	piece.material_override = _material(color)
	parent.add_child(piece)


static func build(region_id: String, source_cue: String,
		tint: Color) -> Node3D:
	var audited: Dictionary = inspect(region_id, source_cue)
	if not bool(audited.get("ok", false)):
		return null
	var profile: Dictionary = PROFILES[region_id]
	var count: int = int(profile["segments"])
	var height: float = float(profile["height_cm"]) / 100.0
	var family: String = str(profile["family"])
	var support: Color = Color("#334C58")
	var root: Node3D = Node3D.new()
	root.name = "EXP017_A01_RegionalLandmark"
	root.set_meta("region_id", region_id)
	root.set_meta("source_cue", source_cue)
	root.set_meta("structural_signature", str(audited["structural_signature"]))
	root.set_meta("presentation_only", true)
	root.set_meta("qualification", QUALIFICATION)
	# Distinct families produce different physical shapes, not renamed
	# plaques or recolored copies. All remain within the original visual
	# envelope: they add no new collidable play surfaces.
	match family:
		"weir":
			_beam(root, "WaterChannel", Vector3(0.0, 0.16, 0.0),
				Vector3(1.15, 0.30, 1.30), support)
			for i: int in range(count):
				var z: float = -0.5 + float(i) / float(count - 1)
				_beam(root, "StepWeir_%02d" % i,
					Vector3(0.0, 0.38 + float(i) * 0.08, z),
					Vector3(0.96, 0.19, 0.11), tint)
			_beam(root, "FlowGauge", Vector3(0.0, height * 0.5, -0.45),
				Vector3(0.12, height, 0.12), tint)
		"frame":
			_beam(root, "LowerBase", Vector3.ZERO,
				Vector3(1.26, 0.16, 1.20), support)
			for i: int in range(count):
				var y: float = 0.25 + float(i) * (height - 0.35) / float(count)
				_beam(root, "Segment_%02d" % i, Vector3(0.0, y, 0.0),
					Vector3(1.18 - float(i % 2) * 0.26, 0.12, 0.55), tint)
			_beam(root, "Spine", Vector3(0.0, height * 0.5, 0.0),
				Vector3(0.18, height, 0.18), support)
		"gantry":
			for side: int in [-1, 1]:
				_beam(root, "Column_%d" % side,
					Vector3(float(side) * 0.48, height * 0.5, 0.0),
					Vector3(0.14, height, 0.19), support)
			for i: int in range(count):
				var y: float = 0.4 + float(i) * (height - 0.5) / float(count)
				_beam(root, "Crosshead_%02d" % i,
					Vector3(0.0, y, 0.0), Vector3(1.20, 0.09, 0.30), tint)
		"tank":
			_column(root, "StorageBody",
				Vector3(0.0, height * 0.45, 0.0), 0.38, height * 0.9, tint)
			for i: int in range(count):
				var y: float = 0.22 + float(i) * (height - 0.4) / float(count)
				_beam(root, "MeterBand_%02d" % i,
					Vector3(0.0, y, 0.0), Vector3(0.91, 0.08, 0.20), support)
		"mast":
			_column(root, "ServiceMast",
				Vector3(0.0, height * 0.5, 0.0), 0.15, height, support)
			for i: int in range(count):
				var y: float = 0.45 + float(i) * (height - 0.5) / float(count)
				_beam(root, "Crossarm_%02d" % i,
					Vector3(0.0, y, 0.0),
					Vector3(0.65 if i % 2 else 1.05, 0.08, 0.14), tint)
	return root
