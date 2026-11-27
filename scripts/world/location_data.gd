extends RefCounted
## RB02 location format (docs/design/RB02-location-format.md): loads content/locations/<location>/ and validates it.
## A location is the authored place a contract or challenge is played on. location.json names the layout (rules), the
## dressing and the look (presentation only) and holds the physical grid (nodes at sockets, edges), landmarks, crew
## spawns with the opening shot, the extraction zone and the stage-audit backdrop.
##
## tools/lbo_location.py is the Python twin: both return diagnostics {code, message, ids} with the same codes, and
## tests/data/locations/cases.json pins them for both. No scene tree and no autoloads, so it runs in any test.

const LOCATIONS_DIR: String = "res://content/locations"
const ALDER_STREET: String = "alder_street"
const KIT_PIECES_PATH: String = "res://content/world/kit_pieces.json"
const KIT_DIMENSIONS_PATH: String = "res://content/world/kit_dimensions.json"
const SCHEMA: int = 1
const FILE_KEYS: Array[String] = ["layout", "dressing", "look"]
const LAYOUT_KEYS: Array[String] = ["buildings", "routes", "props", "markers", "zones", "kit_placements"]
const NODE_KINDS: Array[String] = ["source", "junction", "consumer"]
const SOCKET_KINDS: Array[String] = ["building", "prop", "marker", "feed"]
const MARKER_KINDS: Array[String] = ["spawn", "viewpoint", "anchor", "panel", "switch", "consumer"]
const LANDMARK_ROLES: Array[String] = ["hero", "secondary", "base"]
const FACES: Array[String] = ["south", "north", "west", "east"]
const CREW_SPAWNS: int = 4
const YAW_LIMIT_DEG: int = 180
const PITCH_LIMIT_DEG: int = 89


static func diag(code: String, message: String, ids: Array = []) -> Dictionary:
	var sorted_ids: Array = ids.duplicate()
	sorted_ids.sort()
	return {"code": code, "message": message, "ids": sorted_ids}


static func _json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))


## Bundle {dir, manifest, layout, dressing, look}; a missing or unreadable file loads as {} (validate reports it).
## Rules code (the offline session) passes presentation = false, so it never reads the dressing or the look (ADR-018).
static func load_location(dir_name: String = ALDER_STREET, presentation: bool = true) -> Dictionary:
	var out: Dictionary = {"dir": dir_name, "manifest": {}, "layout": {}, "dressing": {}, "look": {}}
	var base: String = LOCATIONS_DIR.path_join(dir_name)
	var manifest: Variant = _json(base.path_join("location.json"))
	if not manifest is Dictionary:
		return out
	out["manifest"] = manifest
	var files: Variant = (manifest as Dictionary).get("files", {})
	for key: String in FILE_KEYS:
		if not presentation and key != "layout":
			continue
		var name: Variant = (files as Dictionary).get(key) if files is Dictionary else null
		if name is String and not (name as String).contains("/") and not (name as String).contains("\\"):
			var data: Variant = _json(base.path_join(name))
			if data is Dictionary:
				out[key] = data
	return out


## location_id -> bundle for every content/locations/<dir>/location.json, in directory order.
static func all_locations() -> Dictionary:
	var out: Dictionary = {}
	var names: PackedStringArray = DirAccess.get_directories_at(LOCATIONS_DIR)
	names.sort()
	for dir_name: String in names:
		if not FileAccess.file_exists(LOCATIONS_DIR.path_join(dir_name).path_join("location.json")):
			continue
		var bundle: Dictionary = load_location(dir_name)
		out[str((bundle["manifest"] as Dictionary).get("location_id", dir_name))] = bundle
	return out


static func kit_ids() -> Array[String]:
	var out: Array[String] = []
	for p: Dictionary in (_json(KIT_PIECES_PATH) as Dictionary)["pieces"]:
		out.append(str(p["id"]))
	return out


static func dimensions() -> Dictionary:
	return _json(KIT_DIMENSIONS_PATH) as Dictionary


## The layout as DistrictBuilder reads it (the V01 district format), with the scene path and district ID from the
## manifest so they are stated once.
static func layout(bundle: Dictionary) -> Dictionary:
	var out: Dictionary = (bundle["layout"] as Dictionary).duplicate(true)
	out["district_id"] = bundle["manifest"]["district_id"]
	out["scene"] = bundle["manifest"]["scene"]
	return out


## The look the street code reads: the shared profile with the location's environment overrides and its building
## palette under "buildings". Mirrors lbo_location.merged_look().
static func look(bundle: Dictionary) -> Dictionary:
	var loc: Dictionary = bundle["look"]
	var out: Dictionary = (_json(str(loc["profile"])) as Dictionary).duplicate(true)
	(out["environment"] as Dictionary).merge((loc.get("environment", {}) as Dictionary).duplicate(true), true)
	out["buildings"] = (loc["palette"] as Dictionary).duplicate(true)
	return out


## The dressing StreetDressing reads: the location dressing plus the street lamps from its look.
static func dressing(bundle: Dictionary) -> Dictionary:
	var out: Dictionary = (bundle["dressing"] as Dictionary).duplicate(true)
	out["lamps"] = ((bundle["look"] as Dictionary).get("lamps", []) as Array).duplicate(true)
	return out


## Marker record by ID from the layout, or {}.
static func marker(bundle: Dictionary, id: String) -> Dictionary:
	for m: Variant in (bundle["layout"] as Dictionary).get("markers", []):
		if m is Dictionary and str((m as Dictionary).get("id")) == id:
			return m
	return {}


## The player's yaw at spawn in radians (Node3D.rotation.y), from the opening shot.
static func spawn_yaw_rad(bundle: Dictionary) -> float:
	return deg_to_rad(float(bundle["manifest"]["spawn"]["opening_shot"]["yaw_deg"]))


static func spawn_marker_id(bundle: Dictionary) -> String:
	return str(bundle["manifest"]["spawn"]["opening_shot"]["from"])


# --- validation ---------------------------------------------------------------------------------------------------

static func _is_id(v: Variant) -> bool:
	return v is String and not (v as String).is_empty() and _ID.search(v as String) != null


static var _ID: RegEx = RegEx.create_from_string("^[A-Z0-9_]+$")


static func _is_num(v: Variant) -> bool:
	return v is int or v is float


static func _is_int(v: Variant) -> bool:
	return _is_num(v) and float(v) == floorf(float(v))


## n numbers as ints, or [] when the value is not a list of n numbers.
static func _ints(v: Variant, n: int) -> Array[int]:
	var out: Array[int] = []
	if not v is Array or (v as Array).size() != n:
		return out
	for x: Variant in v:
		if not _is_num(x):
			return [] as Array[int]
		out.append(int(x))
	return out


static func _records(v: Variant) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if v is Array:
		for r: Variant in v:
			if r is Dictionary:
				out.append(r)
	return out


static func _index(lay: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for key: String in LAYOUT_KEYS:
		var by_id: Dictionary = {}
		for r: Dictionary in _records(lay.get(key)):
			by_id[str(r.get("id"))] = r
		out[key] = by_id
	return out


## A reference is a one-key object {kind: id}; returns [kind, id] or [].
static func _ref(ref: Variant, allowed: Array[String]) -> Array[String]:
	if ref is Dictionary and (ref as Dictionary).size() == 1:
		var kind: String = str((ref as Dictionary).keys()[0])
		var rid: Variant = (ref as Dictionary)[kind]
		if allowed.has(kind) and rid is String and not (rid as String).is_empty():
			return [kind, rid as String]
	return [] as Array[String]


static func _resolves(kind: String, rid: String, idx: Dictionary, dress: Dictionary) -> bool:
	if kind == "feed":
		return dress.get(rid) is Dictionary
	return (idx[kind + "s"] as Dictionary).has(rid)


static func _validate_layout(lay: Dictionary, kit: Array[String], dims: Dictionary, errs: Array[Dictionary]) -> void:
	var module: int = int(dims["module_cm"])
	var step: int = int(dims["placement_increment_cm"])
	var env: Array[int] = _ints(lay.get("envelope_cm"), 2)
	if env.is_empty() or mini(env[0], env[1]) <= 0:
		errs.append(diag("BAD_LAYOUT", "envelope_cm must be two positive ints"))
		return
	var seen: Dictionary = {}
	for key: String in LAYOUT_KEYS:
		if not lay.get(key) is Array:
			errs.append(diag("BAD_LAYOUT", "layout needs a %s list" % key))
		for r: Dictionary in _records(lay.get(key)):
			var rid: Variant = r.get("id")
			if not _is_id(rid):
				errs.append(diag("INVALID_ID", "%s: every record needs an id matching ^[A-Z0-9_]+$" % key))
				continue
			if seen.has(rid):
				errs.append(diag("DUPLICATE_ID", "layout id %s is used twice" % rid, [rid]))
			seen[rid] = true
	for b: Dictionary in _records(lay.get("buildings")):
		var rid: String = str(b.get("id"))
		var lo: Array[int] = _ints(b.get("min_cm"), 2)
		var size: Array[int] = _ints(b.get("size_cm"), 2)
		if lo.is_empty() or size.is_empty() or mini(size[0], size[1]) <= 0:
			errs.append(diag("BAD_LAYOUT", "%s needs min_cm and size_cm" % rid, [rid]))
			continue
		if size[0] % module != 0 or size[1] % module != 0:
			errs.append(diag("OFF_GRID", "%s size is not on the %d cm module" % [rid, module], [rid]))
		_on_step(rid, lo, step, errs)
		_inside(rid, lo[0], lo[1], size[0], size[1], env, errs)
		for storey: String in ["ground", "upper"]:
			var faces: Variant = b.get(storey, {})
			if not faces is Dictionary:
				errs.append(diag("BAD_FACE", "%s %s must map faces to piece lists" % [rid, storey], [rid]))
				continue
			for face: Variant in (faces as Dictionary):
				var pieces: Variant = (faces as Dictionary)[face]
				var want: int = (size[0] if face == "south" or face == "north" else size[1]) / module
				if not FACES.has(str(face)) or not pieces is Array or (pieces as Array).size() != want:
					errs.append(diag("BAD_FACE", "%s %s %s needs one piece per module (%d)" % [rid, storey, face, want], [rid]))
					continue
				for p: Variant in pieces:
					if not kit.has(str(p)):
						errs.append(diag("UNKNOWN_PIECE", "%s %s %s names a piece the kit does not have" % [rid, storey, face], [rid]))
						break
	for r: Dictionary in _records(lay.get("routes")):
		var rid: String = str(r.get("id"))
		var lo: Array[int] = _ints(r.get("min_cm"), 2)
		var size: Array[int] = _ints(r.get("size_cm"), 2)
		if lo.is_empty() or size.is_empty():
			errs.append(diag("BAD_LAYOUT", "%s needs min_cm and size_cm" % rid, [rid]))
			continue
		_on_step(rid, lo + size, step, errs)
		_inside(rid, lo[0], lo[1], size[0], size[1], env, errs)
	for key: String in ["props", "zones"]:
		for p: Dictionary in _records(lay.get(key)):
			var rid: String = str(p.get("id"))
			var lo: Array[int] = _ints(p.get("min_cm"), 3)
			var size: Array[int] = _ints(p.get("size_cm"), 3)
			if lo.is_empty() or size.is_empty():
				errs.append(diag("BAD_LAYOUT", "%s needs 3D min_cm and size_cm" % rid, [rid]))
				continue
			if key == "props":  # zones are trigger volumes, not placed modules
				_on_step(rid, [lo[0], lo[2], size[0], size[2]] as Array[int], step, errs)
			_inside(rid, lo[0], lo[2], size[0], size[2], env, errs)
	for p: Dictionary in _records(lay.get("kit_placements")):
		var rid: String = str(p.get("id"))
		var pos: Array[int] = _ints(p.get("pos_cm"), 3)
		if pos.is_empty():
			errs.append(diag("BAD_LAYOUT", "%s needs pos_cm" % rid, [rid]))
			continue
		if not kit.has(str(p.get("piece"))):
			errs.append(diag("UNKNOWN_PIECE", "%s names a piece the kit does not have" % rid, [rid]))
		_on_step(rid, pos, step, errs)
	for m: Dictionary in _records(lay.get("markers")):
		var rid: String = str(m.get("id"))
		var pos: Array[int] = _ints(m.get("pos_cm"), 3)
		if pos.is_empty() or not MARKER_KINDS.has(str(m.get("kind"))):
			errs.append(diag("BAD_MARKER", "%s needs pos_cm and a kind in %s" % [rid, str(MARKER_KINDS)], [rid]))
			continue
		_inside(rid, pos[0], pos[2], 0, 0, env, errs)


static func _on_step(rid: String, values: Array[int], step: int, errs: Array[Dictionary]) -> void:
	for v: int in values:
		if v % step != 0:
			errs.append(diag("OFF_GRID", "%s is off the %d cm placement grid" % [rid, step], [rid]))
			return


static func _inside(rid: String, x: int, z: int, w: int, d: int, env: Array[int], errs: Array[Dictionary]) -> void:
	if x < 0 or z < 0 or x + w > env[0] or z + d > env[1]:
		errs.append(diag("OUTSIDE_ENVELOPE", "%s leaves the %d x %d cm envelope" % [rid, env[0], env[1]], [rid]))


static func _validate_grid(grid: Variant, idx: Dictionary, dress: Dictionary, errs: Array[Dictionary]) -> void:
	if not grid is Dictionary or not (grid as Dictionary).get("nodes") is Array or not (grid as Dictionary).get("edges") is Array:
		errs.append(diag("BAD_GRID", "grid needs nodes and edges lists"))
		return
	var kinds: Dictionary = {}
	for n: Dictionary in _records(grid["nodes"]):
		var nid: Variant = n.get("id")
		if not _is_id(nid):
			errs.append(diag("INVALID_ID", "grid node ids must match ^[A-Z0-9_]+$"))
			continue
		if kinds.has(nid):
			errs.append(diag("DUPLICATE_ID", "grid node %s is listed twice" % nid, [nid]))
		if not NODE_KINDS.has(str(n.get("kind"))):
			errs.append(diag("BAD_GRID", "%s kind must be one of %s" % [nid, str(NODE_KINDS)], [nid]))
		kinds[nid] = str(n.get("kind"))
		var ref: Array[String] = _ref(n.get("socket"), SOCKET_KINDS)
		if ref.is_empty():
			errs.append(diag("BAD_SOCKET", "%s socket must be one of %s" % [nid, str(SOCKET_KINDS)], [nid]))
		elif not _resolves(ref[0], ref[1], idx, dress):
			errs.append(diag("UNKNOWN_REF", "%s socket %s %s is not in the location" % [nid, ref[0], ref[1]], [nid]))
		elif ref[0] == "building" and not bool((idx["buildings"][ref[1]] as Dictionary).get("service", false)):
			errs.append(diag("BAD_SOCKET", "%s sits in %s, which is not a service building" % [nid, ref[1]], [nid]))
	var edge_ids: Dictionary = {}
	for e: Dictionary in _records(grid["edges"]):
		var eid: Variant = e.get("id")
		if not _is_id(eid):
			errs.append(diag("INVALID_ID", "grid edge ids must match ^[A-Z0-9_]+$"))
			continue
		if edge_ids.has(eid) or kinds.has(eid):
			errs.append(diag("DUPLICATE_ID", "grid edge %s is listed twice" % eid, [eid]))
		edge_ids[eid] = true
		var a: Variant = e.get("from")
		var b: Variant = e.get("to")
		if not kinds.has(a) or not kinds.has(b) or a == b or kinds.get(b) == "source" or kinds.get(a) == "consumer":
			errs.append(diag("BAD_GRID", "%s must run from a source or junction to a junction or consumer" % eid, [eid]))


## Structural and referential checks; [] means the location can be built, dressed and audited.
static func validate(bundle: Dictionary, kit: Array[String] = [], dims: Dictionary = {}) -> Array[Dictionary]:
	if kit.is_empty():
		kit = kit_ids()
	if dims.is_empty():
		dims = dimensions()
	var m: Dictionary = bundle["manifest"]
	var errs: Array[Dictionary] = []
	if m.is_empty():
		return [diag("MISSING_FILE", "location.json is missing or unreadable")]
	if not _is_int(m.get("schema")) or int(m.get("schema")) != SCHEMA:
		errs.append(diag("BAD_SCHEMA", "schema must be %d" % SCHEMA))
	for key: String in ["location_id", "district_id"]:
		if not _is_id(m.get(key)):
			errs.append(diag("INVALID_ID", "%s must match ^[A-Z0-9_]+$" % key))
	if not m.get("name_key") is String or str(m.get("name_key")).is_empty():
		errs.append(diag("BAD_VALUE", "name_key must be a text key"))
	var scene: Variant = m.get("scene")
	if not scene is String or not (scene as String).begins_with("res://") or not (scene as String).ends_with(".tscn"):
		errs.append(diag("BAD_VALUE", "scene must be a res:// .tscn path"))
	var missing: bool = false
	for key: String in FILE_KEYS:
		if (bundle.get(key, {}) as Dictionary).is_empty():
			errs.append(diag("MISSING_FILE", "files.%s is missing or unreadable" % key))
			missing = true
	if missing:
		return errs
	var lk: Dictionary = bundle["look"]
	if not lk.get("profile") is String or not FileAccess.file_exists(str(lk.get("profile"))) \
			or not lk.get("environment") is Dictionary or not lk.get("palette") is Dictionary or not lk.get("lamps") is Array:
		errs.append(diag("BAD_LOOK", "look needs a profile file, environment overrides, a palette and lamps"))
	var lay: Dictionary = bundle["layout"]
	var dress: Dictionary = bundle["dressing"]
	_validate_layout(lay, kit, dims, errs)
	var idx: Dictionary = _index(lay)
	_validate_grid(m.get("grid"), idx, dress, errs)

	var heroes: int = 0
	for lm: Dictionary in _records(m.get("landmarks")):
		var ref: Array[String] = _ref(lm.get("ref"), ["building", "prop"] as Array[String])
		if ref.is_empty() or not LANDMARK_ROLES.has(str(lm.get("role"))):
			errs.append(diag("BAD_LANDMARK", "a landmark needs a building or prop ref and a role in %s" % str(LANDMARK_ROLES)))
			continue
		if not _resolves(ref[0], ref[1], idx, dress):
			errs.append(diag("UNKNOWN_REF", "landmark %s %s is not in the layout" % [ref[0], ref[1]], [ref[1]]))
		if str(lm["role"]) == "hero":
			heroes += 1
	if heroes != 1:
		errs.append(diag("BAD_LANDMARK", "a location has exactly one hero landmark, not %d" % heroes))

	var spawn: Dictionary = m.get("spawn") if m.get("spawn") is Dictionary else {}
	var spawns: Array = spawn.get("markers") if spawn.get("markers") is Array else []
	var distinct: Dictionary = {}
	var spawns_ok: bool = spawns.size() == CREW_SPAWNS
	for s: Variant in spawns:
		distinct[str(s)] = true
		if str(((idx["markers"] as Dictionary).get(str(s), {}) as Dictionary).get("kind")) != "spawn":
			spawns_ok = false
	if not spawns_ok or distinct.size() != CREW_SPAWNS:
		errs.append(diag("BAD_SPAWN", "spawn.markers must name %d distinct spawn markers" % CREW_SPAWNS))
		spawns = []
	var shot: Dictionary = spawn.get("opening_shot") if spawn.get("opening_shot") is Dictionary else {}
	var yaw: Variant = shot.get("yaw_deg")
	var pitch: Variant = shot.get("pitch_deg")
	var near: Variant = shot.get("max_near_wall_percent")
	var job: Array[String] = _ref(shot.get("first_job"), ["building", "prop", "marker"] as Array[String])
	if not spawns.has(shot.get("from")) or not _is_int(yaw) or absi(int(yaw)) > YAW_LIMIT_DEG \
			or not _is_int(pitch) or absi(int(pitch)) > PITCH_LIMIT_DEG \
			or not _is_int(near) or int(near) < 0 or int(near) > 100 or job.is_empty():
		errs.append(diag("BAD_SPAWN", "opening_shot needs from (a spawn), yaw_deg, pitch_deg, first_job and max_near_wall_percent"))
	elif not _resolves(job[0], job[1], idx, dress):
		errs.append(diag("UNKNOWN_REF", "opening_shot first_job %s %s is not in the layout" % [job[0], job[1]], [job[1]]))

	var ext: Variant = m.get("extraction")
	var zone: Variant = (ext as Dictionary).get("zone") if ext is Dictionary else null
	if not zone is String or not (idx["zones"] as Dictionary).has(zone):
		errs.append(diag("UNKNOWN_REF", "extraction zone %s is not in the layout" % str(zone), [str(zone)]))
	var audit: Variant = m.get("audit")
	var backdrop_ok: bool = audit is Dictionary and (audit as Dictionary).get("backdrop") is Array
	if backdrop_ok:
		for p: Variant in audit["backdrop"]:
			backdrop_ok = backdrop_ok and p is String and not (p as String).is_empty()
	if not backdrop_ok:
		errs.append(diag("BAD_VALUE", "audit.backdrop must list node paths"))
	var contracts_ok: bool = m.get("contracts") is Array
	if contracts_ok:
		for c: Variant in m["contracts"]:
			contracts_ok = contracts_ok and c is String and DirAccess.dir_exists_absolute(str(c))
	if not contracts_ok:
		errs.append(diag("MISSING_FILE", "contracts must list existing contract folders"))
	return errs


# --- cross-checks: what is played on a location must fit it ----------------------------------------------------------

static func _grid_fits(bundle: Dictionary, grid: Dictionary, code: String, errs: Array[Dictionary]) -> void:
	var loc: Dictionary = bundle["manifest"]["grid"]
	var kinds: Dictionary = {}
	for n: Dictionary in loc["nodes"]:
		kinds[str(n["id"])] = str(n["kind"])
	var ends: Dictionary = {}
	for e: Dictionary in loc["edges"]:
		ends[str(e["id"])] = [str(e["from"]), str(e["to"])]
	for n: Dictionary in grid.get("nodes", []):
		if kinds.get(str(n["id"])) != str(n["kind"]):
			errs.append(diag(code, "node %s (%s) has no matching socket on this location" % [n["id"], n["kind"]], [str(n["id"])]))
	for e: Dictionary in grid.get("edges", []):
		if ends.get(str(e["id"])) != [str(e["from"]), str(e["to"])]:
			errs.append(diag(code, "edge %s %s->%s is not a route on this location" % [e["id"], e["from"], e["to"]], [str(e["id"])]))


static func _marker_is(idx: Dictionary, mid: String, kind: String) -> bool:
	return str(((idx["markers"] as Dictionary).get(mid, {}) as Dictionary).get("kind")) == kind


## A story contract pinned to the location: its grid uses the location's sockets and routes, its repair panels,
## switches and generator anchors are layout markers of the right kind (anchors at the same position), and it extracts
## from the location's extraction zone.
static func check_contract(bundle: Dictionary, contract_dir: String) -> Array[Dictionary]:
	var code: String = "CONTRACT_MISMATCH"
	var errs: Array[Dictionary] = []
	var idx: Dictionary = _index(bundle["layout"])
	_grid_fits(bundle, _json(contract_dir.path_join("grid.json")) as Dictionary, code, errs)
	for r: Dictionary in (_json(contract_dir.path_join("repairs.json")) as Dictionary)["repairs"]:
		if not _marker_is(idx, str(r["panel"]), "panel"):
			errs.append(diag(code, "repair panel %s is not a panel marker" % r["panel"], [str(r["panel"])]))
	for s: Dictionary in (_json(contract_dir.path_join("switches.json")) as Dictionary)["switches"]:
		if not _marker_is(idx, str(s["id"]), "switch"):
			errs.append(diag(code, "switch %s is not a switch marker" % s["id"], [str(s["id"])]))
	var eq: Dictionary = _json(contract_dir.path_join("equipment.json")) as Dictionary
	for a: Dictionary in eq.get("anchors", []):
		var id: String = str(a["id"])
		if not _marker_is(idx, id, "anchor") or (idx["markers"][id] as Dictionary)["pos_cm"] != a.get("position_cm"):
			errs.append(diag(code, "anchor %s is not an anchor marker at the same position" % id, [id]))
	var recovery: String = str(eq.get("recovery_anchor", ""))
	if not recovery.is_empty() and not _marker_is(idx, recovery, "anchor"):
		errs.append(diag(code, "recovery_anchor is not an anchor marker", [recovery]))
	var mission: Dictionary = _json(contract_dir.path_join("mission.json")) as Dictionary
	var zone: String = str((mission.get("extraction", {}) as Dictionary).get("zone"))
	if zone != str(bundle["manifest"]["extraction"]["zone"]):
		errs.append(diag(code, "the contract extracts from %s, not the location's extraction zone" % zone, [zone]))
	return errs


## An RB03 challenge authored on the location (challenge.location_id): same location, grid inside the location's
## sockets and routes, fault panels, switches and temporary-supply anchors are layout markers of the right kind.
static func check_challenge(bundle: Dictionary, challenge: Dictionary) -> Array[Dictionary]:
	var code: String = "CHALLENGE_MISMATCH"
	var errs: Array[Dictionary] = []
	if str(challenge.get("location_id")) != str(bundle["manifest"].get("location_id")):
		return [diag("WRONG_LOCATION", "challenge is authored on %s" % str(challenge.get("location_id")), [str(challenge.get("id"))])]
	var idx: Dictionary = _index(bundle["layout"])
	_grid_fits(bundle, challenge.get("grid", {}), code, errs)
	for f: Dictionary in challenge.get("faults", []):
		if not _marker_is(idx, str(f["panel"]), "panel"):
			errs.append(diag(code, "fault panel %s is not a panel marker" % f["panel"], [str(f["panel"])]))
	for s: Dictionary in challenge.get("switches", []):
		if not _marker_is(idx, str(s["id"]), "switch"):
			errs.append(diag(code, "switch %s is not a switch marker" % s["id"], [str(s["id"])]))
	for t: Dictionary in challenge.get("temporary_supply", []):
		for a: Dictionary in t.get("anchors", []):
			if not _marker_is(idx, str(a["id"]), "anchor"):
				errs.append(diag(code, "anchor %s is not an anchor marker" % a["id"], [str(a["id"])]))
	return errs


## Applies {"path": [...], "set": v} / {"delete": true} / {"append": v} ops to a deep copy (tests/data/locations/cases.json).
static func apply_patch(bundle: Dictionary, ops: Array) -> Dictionary:
	var out: Dictionary = bundle.duplicate(true)
	for op: Dictionary in ops:
		var path: Array = op["path"]
		var node: Variant = out
		for i: int in path.size() - 1:
			node = node[_key(node, path[i])]
		var last: Variant = _key(node, path[path.size() - 1])
		if bool(op.get("delete", false)):
			if node is Array:
				(node as Array).remove_at(int(last))
			else:
				(node as Dictionary).erase(last)
		elif op.has("append"):
			(node[last] as Array).append(op["append"] if not op["append"] is Dictionary else (op["append"] as Dictionary).duplicate(true))
		else:
			node[last] = op["set"]
	return out


## JSON numbers load as floats; an array index must be an int.
static func _key(container: Variant, k: Variant) -> Variant:
	return int(k) if container is Array else k
