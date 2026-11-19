extends RefCounted
## EXP03: translate an immutable EXP01/EXP02 level into real G01-G05/V02/F03
## definitions. This is never read from an untrusted client or a save file.
## The original C01-C12 definitions and their rules revision stay untouched.

const STAGE_KINDS: Array[String] = [
	"investigation", "power_routing", "field_repair",
	"optional_discovery", "restoration"
]


static func build(level: Dictionary, plan: Dictionary) -> Dictionary:
	if not bool(plan.get("ok", false)) or plan.get("code") != "VISUAL_CANDIDATE_ONLY" \
			or plan.get("id") != level.get("id") or plan.get("not_certified") != "NO_PHYSICAL_PLAYABILITY":
		return {"ok": false, "code": "INVALID_SOURCE_PLAN"}
	var stations: Array = plan.get("stations", [])
	var tasks: Array = level.get("tasks", [])
	if stations.size() != 5 or tasks.size() != 5:
		return {"ok": false, "code": "INVALID_TASK_COUNT"}
	for i: int in range(5):
		if not tasks[i] is Dictionary or not stations[i] is Dictionary:
			return {"ok": false, "code": "INVALID_TASK_RECORD"}
		if tasks[i].get("id") != stations[i].get("id") or \
				tasks[i].get("kind") != STAGE_KINDS[i] or \
				stations[i].get("target_authority") != "NONE_PREVIEW_ONLY":
			return {"ok": false, "code": "UNTRUSTED_TASK_MAPPING"}
	var p: Dictionary = plan["puzzle"]
	if p.get("status") != "PLANNED_NOT_HOST_ENABLED":
		return {"ok": false, "code": "UNTRUSTED_CAPACITY_PLAN"}
	var required: Array = p.get("required_pu", [])
	if required.size() != 3:
		return {"ok": false, "code": "BAD_CAPACITY"}
	var a: int = int(required[0])
	var b: int = int(required[1])
	var c: int = int(required[2])
	var bonus: int = int(p.get("optional_pu", 0))
	if mini(a, mini(b, mini(c, bonus))) < 1 or \
			a + b != int(p.get("west_capacity_pu", 0)) or \
			c + 1 != int(p.get("east_capacity_pu", 0)) or \
			bonus + 1 != int(p.get("dedicated_spur_capacity_pu", 0)) or \
			a + b + c + bonus + 2 != int(p.get("source_capacity_pu", 0)):
		return {"ok": false, "code": "BAD_CAPACITY"}
	var grid: Dictionary = {
		"contract_id": str(level["id"]), "trip_ticks": 15,
		"nodes": [
			{"id": "GRID", "kind": "source", "capacity": a + b + c + bonus + 2, "online": true},
			{"id": "WEST", "kind": "junction", "isolated": false, "failed": true, "tripped": true},
			{"id": "EAST", "kind": "junction", "isolated": false, "failed": false, "tripped": false},
			{"id": "SPUR", "kind": "junction", "isolated": false, "failed": false, "tripped": false},
			{"id": "LOAD_A", "kind": "consumer", "demand": a, "enabled": true, "healthy": true},
			{"id": "LOAD_B", "kind": "consumer", "demand": b, "enabled": true, "healthy": true},
			{"id": "LOAD_C", "kind": "consumer", "demand": c, "enabled": true, "healthy": true},
			{"id": "SIGN", "kind": "consumer", "demand": bonus, "enabled": false, "healthy": true}
		],
		"edges": [
			{"id": "E_GRID_WEST", "from": "GRID", "to": "WEST", "capacity": a + b, "enabled": true, "healthy": true},
			{"id": "E_GRID_EAST", "from": "GRID", "to": "EAST", "capacity": c + 1, "enabled": false, "healthy": true},
			{"id": "E_WEST_A", "from": "WEST", "to": "LOAD_A", "capacity": a, "enabled": true, "healthy": true},
			{"id": "E_WEST_B", "from": "WEST", "to": "LOAD_B", "capacity": b, "enabled": true, "healthy": true},
			{"id": "E_EAST_C", "from": "EAST", "to": "LOAD_C", "capacity": c, "enabled": true, "healthy": true},
			{"id": "E_GRID_SPUR", "from": "GRID", "to": "SPUR", "capacity": bonus + 1, "enabled": false, "healthy": true},
			{"id": "E_WEST_SPUR", "from": "WEST", "to": "SPUR", "capacity": bonus + 1, "enabled": false, "healthy": true},
			{"id": "E_SPUR_SIGN", "from": "SPUR", "to": "SIGN", "capacity": bonus + 1, "enabled": true, "healthy": true}
		],
		"protections": [
			{"id": "BRK_WEST", "element": "E_GRID_WEST", "breaker": "WEST"},
			{"id": "BRK_EAST", "element": "E_GRID_EAST", "breaker": "EAST"},
			{"id": "BRK_SPUR", "element": "E_GRID_SPUR", "breaker": "SPUR"}
		]
	}
	var meter: Dictionary = {"contract_id": level["id"],
		"panels": [{"id": "PANEL_WEST", "target": "WEST"},
			{"id": "PANEL_SPUR", "target": "SPUR"}],
		"initial_breaker_reasons": {"WEST": "fault"}}
	var repairs: Dictionary = {"contract_id": level["id"], "supplies": {"FUSE_W": 1},
		"repairs": [{
			"id": "R_WEST", "panel": "PANEL_WEST", "isolate": "WEST",
			"component": "FUSE_W", "name_key": "repair.c01.west_fuse",
			"fix": {"op": "set", "id": "WEST", "field": "failed", "value": false},
			"tools": {"open": "screwdriver", "remove": "puller",
				"install": "puller", "test": "meter"},
			"hold_ticks": {"open": 6, "remove": 8, "install": 8, "close": 6}
		}]}
	# Zero portable equipment is valid: an empty, host-validated storage station
	# means the ordinary mission director can enforce all-stowed extraction.
	var equipment: Dictionary = {"contract_id": level["id"],
		"equipment": [], "anchors": [{"id": "DEPOT", "storage": true,
			"routes": [], "position_cm": [2600, 0, 2600]}],
		"recovery_anchor": "DEPOT"}
	var switches: Dictionary = {"contract_id": level["id"], "switches": [
		{"id": "SW_EAST", "target": "E_GRID_EAST", "field": "enabled"},
		{"id": "SW_GRID_SPUR", "target": "E_GRID_SPUR", "field": "enabled"},
		{"id": "SW_WEST_SPUR", "target": "E_WEST_SPUR", "field": "enabled"},
		{"id": "SW_SIGN", "target": "SIGN", "field": "enabled"}
	]}
	var mission: Dictionary = {
		"contract_id": level["id"], "grid_source": "GRID",
		"required_consumers": ["LOAD_A", "LOAD_B", "LOAD_C"], "excluded_loads": [],
		"access_latches": [],
		"final_verification_ticks": int(p["verified_ticks_candidate"]),
		"extraction": {"zone": "ZONE_EXTRACT", "countdown_ticks": 50},
		"objectives": [
			{"id": "OBJ_WEST", "text_key": "objective.c01.restore_west",
				"done_when": {"supplied_from_grid": ["LOAD_A", "LOAD_B"]}},
			{"id": "OBJ_EAST", "text_key": "objective.c01.restore_east",
				"done_when": {"supplied_from_grid": ["LOAD_C"]}},
			{"id": "OBJ_OPTIONAL", "text_key": "objective.c04.restore_sign",
				"done_when": {"supplied_from_grid": ["SIGN"]}},
			{"id": "OBJ_VERIFY", "text_key": "objective.c01.verify_supply",
				"done_when": {"verified": true}},
			{"id": "OBJ_EXTRACT", "text_key": "objective.c01.extract",
				"done_when": {"completed": true}}
		],
		"max_visible_objectives": 3, "optional_services": ["SIGN"],
		"tutorial_trip_allowance": 0
	}
	var bindings: Dictionary = {}
	var roles: Array[String] = ["PANEL_WEST", "SW_EAST", "R_WEST",
		"PANEL_SPUR", "ZONE_EXTRACT"]
	for i: int in range(5):
		bindings[str(tasks[i]["id"])] = {
			"kind": STAGE_KINDS[i], "task_id": str(tasks[i]["id"]),
			"entity": roles[i], "position": stations[i]["position"],
			"required": tasks[i]["required"]
		}
	# The EXP02 station positions describe ground-painted plates (y=0.13).
	# Real reticle/host targets sit at worksite height. Companion switches are
	# separated so the reticle can distinguish their actual host entities.
	var site1: Vector3 = stations[0]["position"] + Vector3.UP * 1.25
	var site2: Vector3 = stations[1]["position"] + Vector3.UP * 1.25
	var site3: Vector3 = stations[2]["position"] + Vector3.UP * 1.25
	var site4: Vector3 = stations[3]["position"] + Vector3.UP * 1.25
	var locations: Dictionary = {
		"PANEL_WEST": site1,
		"SW_EAST": site2,
		"R_WEST": site3,
		"PANEL_SPUR": site4,
		"SW_GRID_SPUR": site4 + Vector3(-1.15, 0.0, 1.05),
		"SW_WEST_SPUR": site4 + Vector3(1.15, 0.0, -1.05),
		"SW_SIGN": site4 + Vector3(1.15, 0.0, 1.05),
		"ZONE_EXTRACT": stations[4]["position"]
	}
	var fingerprint: String = ("%s|%s|%s" % [level["id"],
		plan["layout_signature"], JSON.stringify(p)]).sha256_text()
	return {
		"ok": true, "code": "HEADLESS_CONTRACT_CANDIDATE",
		"level_id": str(level["id"]), "source_fingerprint": fingerprint,
		"grid": grid, "meter": meter, "repairs": repairs,
		"equipment": equipment, "switches": switches, "mission": mission,
		"bindings": bindings, "positions": locations,
		"verification_ticks": int(p["verified_ticks_candidate"]),
		"not_certified": "NO_WALKED_ROUTE_CONTROLLER_GPU_STEAM_OR_RELEASE"
	}
