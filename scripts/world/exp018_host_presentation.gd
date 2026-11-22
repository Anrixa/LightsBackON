## EXP018 A04: validate the local runtime identity before projecting it.
## No client-provided task flags, supply bits, rewards or new transport action.
extends RefCounted

const Runtime := preload("res://scripts/gameplay/expedition_host_session.gd")
const Presentation := preload("res://scripts/world/exp017_restoration_feedback.gd")


static func _fail(code: String) -> Dictionary:
	return {"ok": false, "code": code, "authority": "READ_ONLY_HOST_PROJECTION"}


static func reflect(view: Node3D, runtime: Runtime,
		require_advanced: bool = false) -> Dictionary:
	if view == null or runtime == null or runtime.grid == null:
		return _fail("EXP018_A04_RUNTIME_OR_WORLD_MISSING")
	var board: Dictionary = runtime.task_board()
	if not bool(board.get("ok", false)):
		return _fail("EXP018_A04_RETIRED_OR_INVALID_HOST")
	var level_id: String = str(view.get_meta("source_level_id", ""))
	var definitions: Dictionary = runtime.definition_snapshot()
	if level_id.is_empty() or str(board.get("level_id", "")) != level_id or 			str(definitions.get("level_id", "")) != level_id:
		return _fail("EXP018_A04_SOURCE_LEVEL_MISMATCH")
	if require_advanced:
		if runtime.advanced_cases == null or 				not board.get("advanced_cases") is Dictionary:
			return _fail("EXP018_A04_CASEWORK_NOT_BOUND")
		var cases: Dictionary = board["advanced_cases"]
		var authority: Dictionary = runtime.authoritative_state()
		if str(cases.get("level_id", "")) != level_id or 				not authority.get("exp018_advanced_cases") is Dictionary or 				authority["exp018_advanced_cases"] != cases:
			return _fail("EXP018_A04_ADVANCED_AUTHORITY_DRIFT")
		var revision: String = str(runtime.host.content_revision)
		if runtime.regional_network != null:
			var region_id: String = str(view.get_meta("source_region_id", ""))
			if not revision.begins_with("EXP018_A03_") or 					not authority.get("exp014_regional_network") is Dictionary or 					str(authority["exp014_regional_network"].get("region_id", "")) != region_id:
				return _fail("EXP018_A04_REGIONAL_HOST_SOURCE_DRIFT")
		elif not revision.begins_with("EXP016_"):
			return _fail("EXP018_A04_STANDALONE_SOURCE_REVISION_DRIFT")
	var canonical: Dictionary = runtime.grid.canonical_state()
	var projected: Dictionary = Presentation.reflect(view, board, canonical)
	if not bool(projected.get("ok", false)):
		return _fail("EXP018_A04_UNSAFE_PRESENTATION_" + str(projected.get("code", "UNKNOWN")))
	return projected
