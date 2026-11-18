extends RefCounted
## CT-L1/C04 P07: repeatable, read-only interaction boundary matrix.
## Virtual eyes sample the existing physics/selector limits; this module
## NEVER positions the player, sends host commands or certifies a walked route.

const Accessibility := preload("res://scripts/diagnostics/c04_scene_accessibility.gd")
const Visibility := preload("res://scripts/interaction/interaction_visibility.gd")
const Selector := preload("res://scripts/interaction/target_selector.gd")
const Offline := preload("res://scripts/gameplay/offline_c01_session.gd")

const INTERACTION_PATH: String = "res://content/interaction.json"
const EDGE_MARGIN_M: float = 0.025

## Normalized, scene-authored curb-side approach directions. The west/east
## cabinets face the street (+Z); sign/spur sites face the sidewalk (-Z).
## These are independent standing-point probes, never consecutive waypoints.
const FRONT: Dictionary = {
	"PANEL_JW": Vector3.FORWARD * -1.0,
	"SW_JW_BREAKER": Vector3.FORWARD * -1.0,
	"PANEL_JE": Vector3.FORWARD * -1.0,
	"SW_JE_BREAKER": Vector3.FORWARD * -1.0,
	"PANEL_SPUR": Vector3.FORWARD,
	"SW_SPUR_BREAKER": Vector3.FORWARD,
	"SW_EAST_SIGN": Vector3.FORWARD,
	"SW_SIGN": Vector3.FORWARD
}


static func _source() -> Dictionary:
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(INTERACTION_PATH))
	return value if value is Dictionary else {}


## Fail closed when the P06 source/geometry audit no longer qualifies.
## This is a supplementary geometry probe, not an alternative interaction
## authorization path. P07 never alters the live session's targeting rules.
static func inspect(scene: Node3D) -> Dictionary:
	if scene == null or str(scene.get("contract_id")) != "C04":
		return {"ok": false, "code": "NOT_C04", "cases": [], "failures": ["NOT_C04"]}
	var prior: Dictionary = Accessibility.inspect(scene)
	if not prior.get("ok", false):
		return {"ok": false, "code": "P06_PREFLIGHT_FAILED", "cases": [],
			"failures": prior.get("failures", ["P06_PREFLIGHT_FAILED"])}
	var session: Offline = scene.get("session") as Offline
	var player: CharacterBody3D = scene.get("player") as CharacterBody3D
	if session == null or player == null:
		return {"ok": false, "code": "SCENE_NOT_READY", "cases": [], "failures": ["SCENE_NOT_READY"]}
	var source: Dictionary = _source()
	if not source.get("ray_length_cm") is int and not source.get("ray_length_cm") is float:
		return {"ok": false, "code": "INTERACTION_SOURCE_INVALID", "cases": [],
			"failures": ["INTERACTION_SOURCE_INVALID"]}
	var ray_length_m: float = float(source["ray_length_cm"]) / 100.0
	var cone_deg: float = float(source.get("aim_assist_cone_deg", -1.0))
	if ray_length_m <= 0.0 or cone_deg < 0.0:
		return {"ok": false, "code": "INTERACTION_SOURCE_INVALID", "cases": [],
			"failures": ["INTERACTION_SOURCE_INVALID"]}
	var space: PhysicsDirectSpaceState3D = scene.get_world_3d().direct_space_state
	var exclude: Array[RID] = [player.get_rid()] as Array[RID]
	var entries: Array[Dictionary] = []
	var failures: Array[String] = []
	for id: String in FRONT:
		var target: Vector3 = session.entity_position(id)
		var radius: float = session.radius_for(id)
		if target == Vector3.INF or radius <= EDGE_MARGIN_M:
			failures.append("%s missing genuine host target/radius" % id)
			continue
		var forward: Vector3 = FRONT[id]
		var edge: float = ray_length_m + radius
		var inside_eye: Vector3 = target + forward * (edge - EDGE_MARGIN_M)
		var outside_eye: Vector3 = target + forward * (edge + EDGE_MARGIN_M)
		var inside: bool = Visibility.can_reach(
			space, inside_eye, target, ray_length_m, radius, exclude)
		var outside: bool = Visibility.can_reach(
			space, outside_eye, target, ray_length_m, radius, exclude)
		var candidate: Array[Dictionary] = [
			{"id": id, "position": target, "radius": radius}
		]
		var selected_inside: String = Selector.select(
			inside_eye, inside_eye.direction_to(target), candidate, ray_length_m, cone_deg)
		var selected_outside: String = Selector.select(
			outside_eye, outside_eye.direction_to(target), candidate, ray_length_m, cone_deg)
		var selected_away: String = Selector.select(
			inside_eye, -inside_eye.direction_to(target), candidate, ray_length_m, cone_deg)
		var passing: bool = inside and not outside and selected_inside == id \
			and selected_outside == "" and selected_away == ""
		if not passing:
			failures.append("%s near=%s far=%s aimed=%s far_aim=%s away=%s" %
				[id, str(inside), str(outside), selected_inside, selected_outside, selected_away])
		entries.append({
			"id": id, "ok": passing, "in_range_clear": inside,
			"out_of_range_denied": not outside,
			"aimed_inside": selected_inside == id,
			"aimed_outside_denied": selected_outside == "",
			"facing_away_denied": selected_away == "",
			"edge_m": snappedf(edge, 0.001),
			"margin_m": EDGE_MARGIN_M
		})
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a["id"]) < str(b["id"]))
	if entries.size() != FRONT.size():
		failures.append("only %d/%d host targets received a boundary probe" %
			[entries.size(), FRONT.size()])
	return {
		"ok": failures.is_empty(), "code": "SOURCE_HEADLESS_ONLY",
		"contract_id": "C04", "cases": entries,
		"cases_checked": entries.size(), "failures": failures,
		"not_certified": "NO_CONTINUOUS_ROUTE_OR_HUMAN_CONTROLLER_TEST"
	}
