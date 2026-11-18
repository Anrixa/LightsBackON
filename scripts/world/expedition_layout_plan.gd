extends RefCounted
## EXP02: deterministic level-composition and capacity-puzzle planning for the
## 200 authored EXP01 dispatches. No host commands, player motion or save writes.
## These are candidate grayboxes, not demonstrated playable routes.

const TASK_KINDS: Array[String] = [
	"investigation", "power_routing", "field_repair",
	"optional_discovery", "restoration"
]
const SITE_TYPES: Array[String] = [
	"distribution", "transport", "health", "commerce", "waterworks",
	"communications", "education", "shelter"
]
const FLOOR_SIZE_M: float = 52.0
const STATION_MIN_CLEARANCE_M: float = 4.2


static func _reject(code: String) -> Dictionary:
	return {"ok": false, "code": code, "stations": [], "not_certified": "NO_PHYSICAL_PLAYABILITY"}


static func _serial(id: String) -> int:
	if not id.begins_with("LV_"):
		return -1
	var numeric: String = id.trim_prefix("LV_")
	if numeric.length() != 3 or not numeric.is_valid_int():
		return -1
	var value: int = numeric.to_int()
	return value if value >= 1 and value <= 200 else -1


static func _rotate(x_cm: int, z_cm: int, turn: int) -> Vector3:
	match turn:
		0:
			return Vector3(float(x_cm) / 100.0, 0.13, float(z_cm) / 100.0)
		1:
			return Vector3(float(z_cm) / 100.0, 0.13, float(5200 - x_cm) / 100.0)
		2:
			return Vector3(float(5200 - x_cm) / 100.0, 0.13, float(5200 - z_cm) / 100.0)
		_:
			return Vector3(float(5200 - z_cm) / 100.0, 0.13, float(x_cm) / 100.0)


## This planning model does NOT simulate the existing authoritative grid.
## It is a bounded, provably feasible candidate design: essential loads fit
## their dedicated feeders, optional load fits a distinct spare, while the
## deliberately unsafe shortcut would exceed the west feeder. Future EXP03
## must translate any accepted model into original host definitions/intents.
static func capacity_candidate(serial: int) -> Dictionary:
	var a: int = 2 + (serial % 4)
	var b: int = 3 + ((serial / 2) % 4)
	var c: int = 2 + ((serial / 7) % 4)
	var optional: int = 1 + ((serial * 7) % 4)
	var mandatory: int = a + b + c
	return {
		"required_pu": [a, b, c],
		"required_total_pu": mandatory,
		"optional_pu": optional,
		"source_capacity_pu": mandatory + optional + 2,
		"west_capacity_pu": a + b,
		"east_capacity_pu": c + 1,
		"dedicated_spur_capacity_pu": optional + 1,
		"wrong_west_route_overloads": (a + b + optional) > (a + b),
		"verified_ticks_candidate": 80 + (serial % 8) * 10,
		"status": "PLANNED_NOT_HOST_ENABLED"
	}


## Every authored level gets five non-interactive inspection stations,
## a unique layout geometry fingerprint, an original district setting,
## and a numerical safe/unsafe tradeoff candidate.
static func make_plan(level: Dictionary, location: Dictionary) -> Dictionary:
	var id: String = str(level.get("id", ""))
	var serial: int = _serial(id)
	if serial < 0:
		return _reject("INVALID_LEVEL_ID")
	if level.get("runtime_status") != "DESIGN_BRIEFING_ONLY" or \
			level.get("scoring_authority") != "PREVIEW_POINTS_ONLY":
		return _reject("UNAUTHORIZED_LEVEL")
	if location.get("production_status") != "UNBUILT_LOCATION":
		return _reject("NOT_AUTHORED_CANDIDATE")
	if str(location.get("id", "")) != ("LOC_%03d" % serial) or \
			level.get("location_id") != location.get("id") or \
			level.get("region_id") != location.get("district_id"):
		return _reject("FOREIGN_LOCATION")
	var category: String = str(location.get("archetype", ""))
	if not SITE_TYPES.has(category):
		return _reject("UNSUPPORTED_ARCHETYPE")
	var raw_tasks: Variant = level.get("tasks")
	if not raw_tasks is Array or (raw_tasks as Array).size() != TASK_KINDS.size():
		return _reject("MISSING_STATIONS")
	var tasks: Array = raw_tasks
	var stations: Array[Dictionary] = []
	var turn: int = (serial + SITE_TYPES.find(category)) % 4
	for k: int in range(TASK_KINDS.size()):
		if not tasks[k] is Dictionary:
			return _reject("INVALID_TASK_RECORD")
		var task: Dictionary = tasks[k]
		if task.get("kind") != TASK_KINDS[k] or task.get("ordinal") != k + 1 or \
				task.get("status") != "DESIGN_ONLY_NOT_HOST_ENABLED":
			return _reject("INVALID_TASK_STAGE")
		var suffix: String = "%03d_%d" % [serial, k + 1]
		if task.get("id") != "JOB_" + suffix:
			return _reject("TASK_ID_MISMATCH")
		# Bounded coordinates within a standalone 52m schematic tile.
		# No path/capsule or terrain feasibility is inferred from these points.
		var x_cm: int = 880 + k * 800 + (((serial * 37 + k * 19) % 5) - 2) * 40
		var z_cm: int = 1150 + k * 690 + (((serial * 11 + k * 29) % 7) - 3) * 50
		x_cm += ((serial * 73) % 200) - 100
		z_cm += ((serial * 97) % 180) - 90
		var position: Vector3 = _rotate(x_cm, z_cm, turn)
		if position.x < 4.0 or position.z < 4.0 or \
				position.x > FLOOR_SIZE_M - 4.0 or position.z > FLOOR_SIZE_M - 4.0:
			return _reject("STATION_OUTSIDE_SCHEMATIC")
		for earlier: Dictionary in stations:
			if position.distance_to(earlier["position"]) < STATION_MIN_CLEARANCE_M:
				return _reject("STATIONS_TOO_CLOSE")
		stations.append({
			"id": str(task["id"]), "kind": TASK_KINDS[k], "position": position,
			"ordinal": k + 1, "target_authority": "NONE_PREVIEW_ONLY"
		})
	var puzzle: Dictionary = capacity_candidate(serial)
	var region_index: int = (serial - 1) / 8
	var coordinates: Array[String] = []
	for station: Dictionary in stations:
		coordinates.append(str(station["position"]))
	var signature: String = ("%s|%s|%s|%s|%s" % [
		id, location["id"], category, turn, ",".join(coordinates)]).sha256_text()
	return {
		"ok": true, "code": "VISUAL_CANDIDATE_ONLY",
		"id": id, "location_id": location["id"], "region_id": location["district_id"],
		"name": location["name"], "environment": location["environment"],
		"hazard": location["risk"], "category": category,
		"serial": serial, "region_index": region_index, "turn": turn,
		"stations": stations, "puzzle": puzzle,
		"layout_signature": signature,
		"not_certified": "NO_PHYSICAL_PLAYABILITY"
	}
