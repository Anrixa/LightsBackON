extends RefCounted
## CT-L1/C04 P06: read-only, headless scene-to-target accessibility diagnostics.
## No player translation, pathfinding, command submission, checkpoint or grid
## mutation. Staged points are NOT evidence of a continuously walkable route.

const Visibility := preload("res://scripts/interaction/interaction_visibility.gd")
const TargetSelector := preload("res://scripts/interaction/target_selector.gd")
const Offline := preload("res://scripts/gameplay/offline_c01_session.gd")

const GUIDES_PATH: String = "res://scenes/mission/c04_preview_approaches.json"
const DIMENSIONS_PATH: String = "res://content/world/kit_dimensions.json"
const INTERACTION_PATH: String = "res://content/interaction.json"
const WORLD_MASK: int = 1
const STAND_OFF_GROUND_M: float = 0.04
const SOURCE_POSITION_TOLERANCE_M: float = 0.02

## These three companion controls share P04's already staged panel approaches.
## The other five target approaches are loaded from the P05 presentation source.
const COMPANIONS: Dictionary = {
	"SW_JW_BREAKER": "PANEL_JW",
	"SW_JE_BREAKER": "PANEL_JE",
	"SW_SPUR_BREAKER": "PANEL_SPUR"
}


static func _read(path: String) -> Dictionary:
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return value if value is Dictionary else {}


static func _point(coords: Array) -> Vector3:
	return Vector3(float(coords[0]), float(coords[1]), float(coords[2])) / 100.0


static func _collider_name(hit: Dictionary) -> String:
	var collider: Variant = hit.get("collider")
	if collider is Node:
		return str((collider as Node).name)
	return "UNKNOWN"


## Physically sample an unmoved player capsule at a virtual standing point.
## The 4 cm lift prevents a floor-contact false positive, and this reports
## *instantaneous clearance only*: no sweep, step-up, route or animation test.
static func _capsule_blockers(space: PhysicsDirectSpaceState3D, stand: Vector3,
		player_rid: RID, radius_m: float, height_m: float) -> Array[String]:
	var capsule: CapsuleShape3D = CapsuleShape3D.new()
	capsule.radius = radius_m
	capsule.height = height_m
	var query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.transform = Transform3D(Basis.IDENTITY, stand)
	query.collision_mask = WORLD_MASK
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.exclude = [player_rid] as Array[RID]
	var names: Array[String] = []
	for hit: Dictionary in space.intersect_shape(query, 32):
		var id: String = _collider_name(hit)
		if not names.has(id):
			names.append(id)
	names.sort()
	return names


## Inspect the live, committed scene and host target projection without
## moving the physical character. This is intentionally not used as a gameplay
## gate; only the existing InteractionVisibility/SessionHost can authorize
## actual commands.
static func inspect(scene: Node3D) -> Dictionary:
	var failures: Array[String] = []
	if scene == null or str(scene.get("contract_id")) != "C04":
		return {"ok": false, "code": "NOT_C04", "failures": ["NOT_C04"], "sites": []}
	var district: Node3D = scene.get_node_or_null("District") as Node3D
	var player: CharacterBody3D = scene.get("player") as CharacterBody3D
	var session: Offline = scene.get("session") as Offline
	if district == null or player == null or session == null:
		return {"ok": false, "code": "SCENE_NOT_READY", "failures": ["SCENE_NOT_READY"], "sites": []}
	var guides: Dictionary = _read(GUIDES_PATH)
	var dimensions: Dictionary = _read(DIMENSIONS_PATH)
	var tuning: Dictionary = _read(INTERACTION_PATH)
	if guides.get("contract_id") != "C04" or not (guides.get("approaches") is Array) or \
			not dimensions.has("player_radius_cm") or not dimensions.has("player_height_cm") or \
			not dimensions.has("camera_height_cm") or not tuning.has("ray_length_cm") or \
			not tuning.has("aim_assist_cone_deg"):
		return {"ok": false, "code": "SOURCE_INVALID", "failures": ["SOURCE_INVALID"], "sites": []}
	var radius_m: float = float(dimensions["player_radius_cm"]) / 100.0
	var height_m: float = float(dimensions["player_height_cm"]) / 100.0
	var eye_above_center: float = float(dimensions["camera_height_cm"]) / 100.0 - height_m * 0.5
	var reach_m: float = float(tuning["ray_length_cm"]) / 100.0
	var cone_deg: float = float(tuning["aim_assist_cone_deg"])
	if radius_m <= 0.0 or height_m < radius_m * 2.0 or reach_m <= 0.0:
		return {"ok": false, "code": "DIMENSIONS_INVALID", "failures": ["DIMENSIONS_INVALID"], "sites": []}
	var centers: Dictionary = {}
	var van_position: Vector3 = Vector3.INF
	for rec: Dictionary in guides["approaches"]:
		var id: String = str(rec.get("id", ""))
		if not (rec.get("pos_cm") is Array) or (rec["pos_cm"] as Array).size() != 3:
			return {"ok": false, "code": "SOURCE_INVALID", "failures": ["SOURCE_INVALID"], "sites": []}
		var pos: Vector3 = _point(rec["pos_cm"])
		if id == "ZONE_VAN":
			van_position = pos
		else:
			centers[id] = pos
	for id: String in COMPANIONS:
		var parent: String = COMPANIONS[id]
		if not centers.has(parent):
			return {"ok": false, "code": "SOURCE_INVALID", "failures": ["SOURCE_INVALID"], "sites": []}
		centers[id] = centers[parent]
	if centers.size() != 8 or van_position == Vector3.INF:
		return {"ok": false, "code": "SOURCE_INVALID", "failures": ["SOURCE_INVALID"], "sites": []}
	var space: PhysicsDirectSpaceState3D = scene.get_world_3d().direct_space_state
	var sites: Array[Dictionary] = []
	for id: String in centers:
		var source: Vector3 = centers[id]
		var stand: Vector3 = Vector3(source.x, height_m * 0.5 + STAND_OFF_GROUND_M, source.z)
		var eye: Vector3 = stand + Vector3.UP * eye_above_center
		var marker: Marker3D = district.get_node_or_null("Markers/" + id) as Marker3D
		var target: Vector3 = session.entity_position(id)
		var aim_radius: float = session.radius_for(id)
		var distance_m: float = eye.distance_to(target)
		var blockers: Array[String] = _capsule_blockers(space, stand, player.get_rid(),
			radius_m, height_m)
		var aligned: bool = marker != null and target != Vector3.INF and \
			marker.global_position.distance_to(target) <= SOURCE_POSITION_TOLERANCE_M
		var in_reach: bool = target != Vector3.INF and \
			Visibility.can_reach(space, eye, target, reach_m, aim_radius,
				[player.get_rid()] as Array[RID])
		var selected: String = ""
		if target != Vector3.INF and distance_m > 0.001:
			selected = TargetSelector.select(eye, eye.direction_to(target),
				[{"id": id, "position": target, "radius": aim_radius}], reach_m, cone_deg)
		var ok: bool = aligned and blockers.is_empty() and in_reach and selected == id
		if not ok:
			failures.append("%s: marker=%s capsule=%s sight=%s selector=%s" % [
				id, str(aligned), str(blockers), str(in_reach), selected])
		sites.append({"id": id, "ok": ok, "marker_aligned": aligned, "capsule_clear": blockers.is_empty(),
			"capsule_blockers": blockers, "ray_clear": in_reach, "selected": selected,
			"eye_distance_m": snappedf(distance_m, 0.001),
			"interaction_limit_m": reach_m + aim_radius})
	sites.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a["id"]) < str(b["id"]))
	var van_stand: Vector3 = Vector3(van_position.x, height_m * 0.5 + STAND_OFF_GROUND_M, van_position.z)
	var van_clear: bool = _capsule_blockers(space, van_stand, player.get_rid(),
		radius_m, height_m).is_empty()
	var van_in_zone: bool = session.inside_van(van_stand)
	if not van_clear or not van_in_zone:
		failures.append("ZONE_VAN: capsule_clear=%s inside_original_zone=%s" %
			[str(van_clear), str(van_in_zone)])
	# Negative control: looking from the back side of the real JW cabinet is
	# inside the nominal interaction radius, but its collision box must block
	# both the ray and the existing host range callback.
	var behind: Vector3 = Vector3(29.6, eye_above_center + height_m * 0.5 + STAND_OFF_GROUND_M, 22.8)
	var jw: Vector3 = session.entity_position("PANEL_JW")
	var obstruction: Dictionary = {}
	if jw != Vector3.INF:
		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
			behind, jw, WORLD_MASK, [player.get_rid()] as Array[RID])
		obstruction = space.intersect_ray(query)
	var negative_near: bool = jw != Vector3.INF and \
		behind.distance_to(jw) < reach_m + session.radius_for("PANEL_JW")
	var negative_denied: bool = jw != Vector3.INF and not Visibility.can_reach(
		space, behind, jw, reach_m, session.radius_for("PANEL_JW"),
		[player.get_rid()] as Array[RID])
	var obstruction_name: String = _collider_name(obstruction)
	if not negative_near or not negative_denied or obstruction_name != "CABINET_JW":
		failures.append("CABINET_JW_NEGATIVE: near=%s denied=%s hit=%s" %
			[str(negative_near), str(negative_denied), obstruction_name])
	return {
		"ok": failures.is_empty(),
		"code": "SOURCE_HEADLESS_ONLY",
		"contract_id": "C04",
		"sites": sites,
		"van_capsule_clear": van_clear,
		"van_inside_zone": van_in_zone,
		"cabinet_negative": {"within_range": negative_near, "denied": negative_denied,
			"first_collider": obstruction_name},
		"failures": failures,
		"not_certified": "NO_CONTINUOUS_ROUTE_OR_HUMAN_CONTROLLER_TEST"
	}
