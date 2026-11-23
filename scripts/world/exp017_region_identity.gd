extends RefCounted
## EXP017 A01: architecturally distinct, source-bound 25-region silhouettes.
## Render-only additions to the EXP014 A03 facility package. No new collision,
## traversal claims, host entities, power states, rewards or save effects.
const Regional := preload("res://scripts/world/expedition_regional_facilities.gd")
const QUALIFICATION: String = Regional.QUALIFICATION
const PROFILES: Dictionary = {
	"REG_01": {"name": "Alder Reach", "kit": ["arcade", "chimney", "levee"], "accent": "#B16D58"},
	"REG_02": {"name": "Glasswater Quay", "kit": ["harbor_crane", "pier", "beacon"], "accent": "#68B8AD"},
	"REG_03": {"name": "Iron Viaduct", "kit": ["viaduct", "signal", "gantry"], "accent": "#D0A66F"},
	"REG_04": {"name": "Lantern Marsh", "kit": ["stilt_hut", "reed_fence", "levee"], "accent": "#9AB58C"},
	"REG_05": {"name": "Slate Ridge", "kit": ["terrace", "cable_tower", "retaining_wall"], "accent": "#9AABBD"},
	"REG_06": {"name": "Bellfoundry Quarter", "kit": ["chimney", "furnace", "arcade"], "accent": "#DB8859"},
	"REG_07": {"name": "Willow Floodplain", "kit": ["levee", "footbridge", "stilt_hut"], "accent": "#9EC79B"},
	"REG_08": {"name": "North Lock", "kit": ["lock_gate", "hoist", "footbridge"], "accent": "#91B8D0"},
	"REG_09": {"name": "Kestrel Falls", "kit": ["aqueduct", "turbine", "beacon"], "accent": "#5BD0CC"},
	"REG_10": {"name": "Rainline Terminal", "kit": ["platform", "signal", "canopy"], "accent": "#94A7D1"},
	"REG_11": {"name": "Embermill Valley", "kit": ["mill", "chimney", "turbine"], "accent": "#C68D62"},
	"REG_12": {"name": "Coldharbor Point", "kit": ["pier", "beacon", "cable_tower"], "accent": "#A8D7E8"},
	"REG_13": {"name": "Sunrise Breakwater", "kit": ["seawall", "lock_gate", "beacon"], "accent": "#E1BE84"},
	"REG_14": {"name": "Briar Valley", "kit": ["terrace", "trellis", "footbridge"], "accent": "#A9B887"},
	"REG_15": {"name": "Cinder Hill", "kit": ["furnace", "retaining_wall", "chimney"], "accent": "#CA795E"},
	"REG_16": {"name": "Merrow Island", "kit": ["pier", "harbor_crane", "hoist"], "accent": "#B9AC91"},
	"REG_17": {"name": "Greenhouse Quarter", "kit": ["greenhouse", "canopy", "trellis"], "accent": "#86BE9E"},
	"REG_18": {"name": "Blackstone Works", "kit": ["mill", "aqueduct", "furnace"], "accent": "#8F9A8D"},
	"REG_19": {"name": "Crescent Reservoir", "kit": ["aqueduct", "lock_gate", "levee"], "accent": "#73BCD1"},
	"REG_20": {"name": "Wrenwood Heights", "kit": ["trellis", "terrace", "cable_tower"], "accent": "#AA967E"},
	"REG_21": {"name": "Tallow Market", "kit": ["arcade", "gantry", "signal"], "accent": "#CEB27B"},
	"REG_22": {"name": "Foxglove Basin", "kit": ["mill", "greenhouse", "aqueduct"], "accent": "#B4A1D0"},
	"REG_23": {"name": "Cedar Observatory", "kit": ["cable_tower", "beacon", "signal"], "accent": "#C4C9A7"},
	"REG_24": {"name": "Hollowpoint Dunes", "kit": ["retaining_wall", "stilt_hut", "seawall"], "accent": "#D7C092"},
	"REG_25": {"name": "Old Beacon Terrace", "kit": ["terrace", "beacon", "canopy"], "accent": "#CD9DA3"}
}
const KITS: Array[String] = [
	"arcade", "chimney", "levee", "harbor_crane", "pier", "beacon",
	"viaduct", "signal", "gantry", "stilt_hut", "reed_fence", "terrace",
	"cable_tower", "retaining_wall", "furnace", "footbridge", "lock_gate",
	"hoist", "aqueduct", "turbine", "platform", "canopy", "mill",
	"seawall", "trellis", "greenhouse"
]


static func inspect(plan: Dictionary) -> Dictionary:
	var regional: Dictionary = Regional.inspect(plan)
	if not bool(regional.get("ok", false)):
		return {"ok": false, "code": "EXP017_A01_REGION_SOURCE_REJECTED"}
	var id: String = str(regional["region_id"])
	if not PROFILES.has(id):
		return {"ok": false, "code": "EXP017_A01_UNKNOWN_REGION"}
	var profile: Dictionary = PROFILES[id]
	var kits: Array = profile["kit"]
	if kits.size() != 3 or str(profile["name"]).is_empty():
		return {"ok": false, "code": "EXP017_A01_BAD_KIT"}
	var unique: Dictionary = {}
	var kit_names: Array[String] = []
	for item: Variant in kits:
		if not KITS.has(str(item)) or unique.has(str(item)):
			return {"ok": false, "code": "EXP017_A01_DUPLICATE_OR_UNSUPPORTED_FORM"}
		unique[str(item)] = true
		kit_names.append(str(item))
	var signature: String = ("%s|%s|%s|%s" % [
		id, ",".join(kit_names), str(profile["accent"]), str(regional["geometry_signature"])
	]).sha256_text()
	return {"ok": true, "level_id": regional["level_id"],
		"region_id": id, "name": profile["name"], "kit": kits,
		"signature": signature, "qualification": QUALIFICATION,
		"authority": "PRESENTATION_ONLY", "forms": 3}


static func _mat(hex: String, emissive: bool = false) -> StandardMaterial3D:
	var result: StandardMaterial3D = StandardMaterial3D.new()
	result.albedo_color = Color(hex)
	result.roughness = 0.73
	if emissive:
		result.emission_enabled = true
		result.emission = Color(hex)
		result.emission_energy_multiplier = 0.4
	return result


static func _box(parent: Node3D, name: String, pos: Vector3,
		size: Vector3, material: Material) -> void:
	var box: BoxMesh = BoxMesh.new()
	box.size = size
	var node: MeshInstance3D = MeshInstance3D.new()
	node.name = name
	node.mesh = box
	node.material_override = material
	node.position = pos
	parent.add_child(node)


## Every kit builds real depth and a readable skyline; labels alone never
## distinguish two regions. All meshes are explicitly non-colliding.
static func _kit(parent: Node3D, kind: String, accent: Material,
		steel: Material, stone: Material) -> void:
	match kind:
		"arcade", "viaduct", "footbridge", "aqueduct":
			var height: float = 3.4 if kind == "viaduct" else 2.4
			for x: int in [-1, 1]:
				_box(parent, "Pier%d" % x, Vector3(x * 1.0, height * 0.5, 0),
					Vector3(0.3, height, 0.55), stone)
			_box(parent, "Deck", Vector3(0, height, 0), Vector3(2.6, 0.25, 0.85), accent)
			if kind == "aqueduct":
				_box(parent, "WaterChannel", Vector3(0, height + 0.16, 0),
					Vector3(2.4, 0.12, 0.65), steel)
		"chimney", "beacon", "cable_tower", "signal":
			var height: float = 5.8 if kind == "cable_tower" else 4.5 if kind == "chimney" else 3.6
			_box(parent, "Tower", Vector3(0, height * 0.5, 0),
				Vector3(0.65, height, 0.65), stone)
			_box(parent, "Crown", Vector3(0, height + 0.24, 0),
				Vector3(1.25, 0.48, 1.0), accent)
			if kind == "cable_tower":
				_box(parent, "Crossarm", Vector3(0, height - 0.75, 0),
					Vector3(2.65, 0.15, 0.24), steel)
		"harbor_crane", "hoist", "gantry":
			_box(parent, "Mast", Vector3(-0.85, 2.0, 0), Vector3(0.34, 4.0, 0.36), steel)
			_box(parent, "Spar", Vector3(0.1, 4.0, 0), Vector3(2.9, 0.22, 0.34), accent)
			_box(parent, "Cable", Vector3(1.2, 3.1, 0), Vector3(0.10, 1.7, 0.1), steel)
		"pier", "platform", "seawall", "levee", "retaining_wall":
			var height: float = 1.65 if kind in ["seawall", "retaining_wall"] else 0.9
			_box(parent, "Base", Vector3(0, height * 0.5, 0),
				Vector3(2.8, height, 1.35), stone)
			_box(parent, "Lip", Vector3(0, height + 0.10, 0),
				Vector3(3.0, 0.2, 1.45), accent)
			if kind in ["pier", "platform"]:
				for x: int in [-1, 1]:
					_box(parent, "Post%d" % x, Vector3(x * 1.1, 1.9, -0.4),
						Vector3(0.12, 2.0, 0.12), steel)
		"stilt_hut", "greenhouse", "mill", "furnace":
			for x: int in [-1, 1]:
				_box(parent, "Support%d" % x, Vector3(x * 0.85, 0.9, 0),
					Vector3(0.22, 1.8, 0.22), steel)
			_box(parent, "Hall", Vector3(0, 2.5, 0),
				Vector3(2.3, 1.8, 1.55), accent)
			_box(parent, "Roof", Vector3(0, 3.56, 0),
				Vector3(2.7, 0.3, 1.9), stone)
			if kind == "furnace":
				_box(parent, "Flue", Vector3(0.65, 4.1, 0),
					Vector3(0.38, 1.0, 0.38), steel)
		"lock_gate", "reed_fence", "trellis":
			for x: int in [-1, 0, 1]:
				_box(parent, "Post%d" % x, Vector3(x * 0.85, 1.15, 0),
					Vector3(0.2, 2.3, 0.2), steel)
			_box(parent, "Header", Vector3(0, 2.2, 0), Vector3(2.3, 0.21, 0.2), accent)
			if kind == "lock_gate":
				_box(parent, "GateLeaf", Vector3(0, 0.9, 0), Vector3(1.7, 1.55, 0.14), stone)
		"terrace":
			for i: int in range(3):
				_box(parent, "Step%d" % i, Vector3(0, 0.3 + i * 0.6, i * 0.5),
					Vector3(2.5 - i * 0.35, 0.6 + i * 0.25, 0.7), stone)
		"turbine":
			# Housing on a plinth: it used to start 0.6 m above the ground with nothing under it (DS stage audit).
			_box(parent, "RotorPlinth", Vector3(0, 0.3, 0), Vector3(1.6, 0.6, 1.1), steel)
			_box(parent, "RotorHousing", Vector3(0, 1.9, 0), Vector3(2.0, 2.6, 1.4), steel)
			for i: int in range(4):
				_box(parent, "Vane%d" % i, Vector3(
					0 if i < 2 else (1.0 if i == 2 else -1.0),
					1.9 + (0.95 if i == 0 else -0.95 if i == 1 else 0),
					-0.8), Vector3(0.35, 0.35, 0.2), accent)
		"canopy":
			for x: int in [-1, 1]:
				_box(parent, "Column%d" % x, Vector3(x * 1.1, 1.5, 0),
					Vector3(0.15, 3.0, 0.15), steel)
			_box(parent, "Roof", Vector3(0, 3.1, 0), Vector3(3.0, 0.25, 2.0), accent)


static func attach(plan: Dictionary, regional_node: Node3D) -> Node3D:
	var audit: Dictionary = inspect(plan)
	if not bool(audit.get("ok", false)) or regional_node == null or \
			str(regional_node.get_meta("source_level_id", "")) != str(audit["level_id"]) or \
			str(regional_node.get_meta("source_region_id", "")) != str(audit["region_id"]) or \
			regional_node.get_meta("qualification", "") != QUALIFICATION:
		return null
	var root: Node3D = Node3D.new()
	root.name = "EXP017_A01_ArchitecturalIdentity"
	root.set_meta("presentation_only", true)
	root.set_meta("source_level_id", audit["level_id"])
	root.set_meta("source_region_id", audit["region_id"])
	root.set_meta("architectural_signature", audit["signature"])
	root.set_meta("qualification", QUALIFICATION)
	var accent: Material = _mat(str(PROFILES[str(audit["region_id"])]["accent"]))
	var steel: Material = _mat("#394956")
	var stone: Material = _mat("#71818A")
	var kits: Array = audit["kit"]
	for i: int in range(kits.size()):
		var assembly: Node3D = Node3D.new()
		assembly.name = "Landmark%d_%s" % [i + 1, str(kits[i])]
		assembly.position = Vector3((i - 1) * 3.0, 0.0, -3.25)
		assembly.set_meta("architectural_form", str(kits[i]))
		root.add_child(assembly)
		_kit(assembly, str(kits[i]), accent, steel, stone)
	var sign: Label3D = Label3D.new()
	sign.name = "RegionIdentitySign"
	sign.text = str(audit["name"]).to_upper()
	sign.font_size = 40
	sign.pixel_size = 0.006
	sign.position = Vector3(0, 5.75, -3.25)
	sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	root.add_child(sign)
	regional_node.add_child(root)
	return root
