extends "res://tests/test_case.gd"
## EXP015 A07: 100 ORIGINAL branch locations, 125+ actual A09 route replays.
## No synthetic task completion or protected electric dispatch bypasses.
const Atlas := preload("res://scripts/world/dispatch_atlas.gd")
const Ledger := preload("res://scripts/progression/expedition_ledger.gd")
const Regional := preload("res://scripts/gameplay/expedition_regional_network.gd")
const Alt := preload("res://scripts/gameplay/expedition_regional_alt_routes.gd")
const Runtime := preload("res://scripts/gameplay/expedition_host_session.gd")
const Saves := preload("res://scripts/persistence/save_service.gd")
const Offline := preload("res://scripts/persistence/offline_persistence.gd")
const ContentHash := preload("res://scripts/network/content_hash.gd")

const SPINE: Array[int] = [1, 3, 4, 6, 7, 8]
const STAMP: String = "2026-11-22T00:00:00Z"
var _root: String = ""
var _position: Vector3 = Vector3.ZERO


func before_each() -> void:
	Regional.clear_host_memory_for_test()
	_root = "user://exp015_a07_" + str(Time.get_ticks_usec()) + "_" + str(randi())
	_position = Vector3.ZERO


func after_each() -> void:
	Regional.clear_host_memory_for_test()


func _position_for(_player: String) -> Vector3:
	return _position


func _restore(profile: Dictionary, atlas: Dictionary, number: int) -> void:
	var level_id: String = "LV_%03d" % number
	var level: Dictionary = Atlas.find_level(atlas, level_id)
	var receipt: Dictionary = Ledger.make_receipt(str(profile["account_key"]),
		level_id, str(level["tasks"][4]["id"]), "restoration")
	assert_true(bool(Ledger.apply_receipt(profile, receipt, atlas).get("applied", false)),
		"EXP04 source-only fixture; not real gameplay or a stored reward")


func _profile(atlas: Dictionary, region: int, slot: int,
		route: String, account: String) -> Dictionary:
	var profile: Dictionary = Ledger.new_profile(account)
	for previous: int in range(region):
		for completed: int in SPINE:
			_restore(profile, atlas, previous * 8 + completed)
	var base: int = region * 8
	_restore(profile, atlas, base + 1)
	if slot >= 4:
		_restore(profile, atlas, base + (2 if route == "a" else 3))
		_restore(profile, atlas, base + 4)
	return profile


func _context(region: int, slot: int, route: String) -> Dictionary:
	var atlas: Dictionary = Atlas.load_catalog()
	var site_id: String = "LV_%03d" % (region * 8 + slot + 1)
	var profile: Dictionary = _profile(atlas, region, slot, route,
		"a07_direct_%02d_%d_%s" % [region + 1, slot, route])
	var network: Regional = Regional.new()
	var ready: Dictionary = network.configure(atlas, profile, site_id)
	assert_true(bool(ready.get("ok", false)), str(ready))
	if not bool(ready.get("ok", false)):
		return {}
	var recipe: Dictionary = Alt.entry_for(Alt.load_book(), site_id)
	var controller: Alt = Alt.new()
	var prepared: Dictionary = controller.configure(recipe, network)
	assert_true(bool(prepared.get("ok", false)), str(prepared))
	if not bool(prepared.get("ok", false)):
		return {}
	return {"network": network, "controller": controller, "recipe": recipe}


func _send(host: Runtime, seq: int, board: String, action: String,
		peer: int = 1) -> Dictionary:
	# Maintain real host tick and original 20-command/10-tick rate limit.
	host.host.tick(seq)
	return host.receive(peer, JSON.stringify({
		"session": host.session_id(), "seq": seq, "type": "operate_worksite",
		"entity": board, "payload": {"action": action}
	}).to_utf8_buffer())


func _start_host(region: int, slot: int, route: String, account: String,
		enable_alternate: bool) -> Dictionary:
	var atlas: Dictionary = Atlas.load_catalog()
	var profile: Dictionary = _profile(atlas, region, slot, route, account)
	var saves: Saves = Saves.new()
	saves.configure(1, Offline.SAVE_BUILD_ID,
		ContentHash.content_revision(), ContentHash.rules_revision())
	var root: String = _root.path_join(account)
	var path: String = root.path_join("profiles").path_join(account).path_join(
		Ledger.PROFILE_FILE)
	assert_true(bool(saves.write_record(path, Ledger.KIND_PROFILE,
		account, profile, STAMP).get("ok", false)))
	var host: Runtime = Runtime.new()
	var ready: Dictionary = host.start("LV_%03d" % (region * 8 + slot + 1),
		Callable(self, "_position_for"), Callable(), account, true, root,
		true, true, true, true, true,
		true, true, true, true, true,
		true, true, true, true, true,
		enable_alternate, enable_alternate, enable_alternate,
		enable_alternate, enable_alternate, enable_alternate)
	return {"host": host, "reply": ready}


func _run_source_scenario(region: int, slot: int, route: String) -> Dictionary:
	var state: Dictionary = _context(region, slot, route)
	if state.is_empty():
		return {}
	var network: Regional = state["network"]
	var controller: Alt = state["controller"]
	var recipe: Dictionary = state["recipe"]
	var role: String = str(recipe["campaign_role"])
	var before: Dictionary = network.snapshot()
	var reserve_start: int = int(before["reserve_pu"])
	var site_id: String = str(recipe["route_site_id"])
	assert_false(bool(before["sites"][site_id]["restored"]),
		"Real EXP04 completion must NOT be forged for active branch site")
	assert_eq(controller.operate("route_reset")["code"], "ALT_RESET_NOT_READY")
	assert_true(bool(controller.operate("route_survey").get("ok", false)))
	assert_true(bool(controller.operate("route_trip").get("ok", false)))
	assert_false(controller.closed())
	assert_eq(str(network.snapshot()["feeders"][str(
		recipe["normal_feeder_id"])]["fault"]), recipe["original_fault_signature"])
	assert_eq(controller.operate("route_reset")["code"], "ALT_RESET_NOT_READY")
	var used_transfer: bool = false
	if role == "first_route_a":
		assert_eq(controller.operate("route_buffer")["code"],
			"ALT_BUFFER_ONLY_SECOND_A")
		var rapid: Dictionary = controller.operate("route_rapid")
		if int(recipe["capacity_pu"]) < 16:
			assert_eq(str(rapid.get("code", "")), "ALT_RAPID_NEEDS_REAL_UPSTREAM_CAPACITY")
			assert_true(bool(controller.operate("route_managed").get("ok", false)))
		else:
			assert_true(bool(rapid.get("ok", false)), str(rapid))
		assert_eq(controller.operate("route_contain:FORGED")["code"],
			"ALT_UNKNOWN_ACTION_OR_RISK_PROTOCOL")
		assert_true(bool(controller.operate("route_contain:" +
			str(recipe["risk_containment_protocol"])).get("ok", false)))
	elif role == "first_route_b":
		assert_true(bool(controller.operate("route_critical_priority").get("ok", false)))
		assert_false(bool(controller.snapshot()["original_critical_energized"]),
			"A site is not electrically restored without its EXP04 receipt")
		assert_true(bool(controller.operate("route_contain:" +
			str(recipe["risk_containment_protocol"])).get("ok", false)))
	elif role == "second_route_a":
		assert_true(bool(controller.operate("route_buffer").get("ok", false)))
		assert_eq(int(controller.snapshot()["reserve_spent_pu"]), 2)
		assert_true(network.site_prepared())
	else:
		var transfer: Dictionary = controller.operate("route_transfer")
		if bool(transfer.get("ok", false)):
			used_transfer = true
			assert_eq(int(controller.snapshot()["reserve_spent_pu"]), 2)
			assert_true(bool(network.snapshot()["ties"][
				str(recipe["standby_tie_id"])]["engaged"]))
		else:
			assert_eq(str(transfer.get("code", "")), "BREAK_BEFORE_MAKE_INTERLOCK")
			assert_true(bool(controller.operate("route_managed").get("ok", false)))
		assert_true(bool(controller.operate("route_prepare").get("ok", false)))
		assert_true(network.site_prepared())
	assert_true(bool(controller.operate("route_clear").get("ok", false)))
	if role == "second_route_b":
		assert_eq(controller.operate("route_reset")["code"], "ALT_RESET_NOT_READY")
		assert_true(bool(controller.operate("route_release").get("ok", false)))
	assert_true(bool(controller.operate("route_reset").get("ok", false)))
	assert_true(bool(controller.operate("route_verify").get("ok", false)))
	assert_true(bool(controller.operate("route_signoff").get("ok", false)))
	assert_true(controller.closed())
	assert_eq(int(network.snapshot()["reserve_pu"]),
		reserve_start - int(controller.snapshot()["reserve_spent_pu"]))
	assert_false(bool(controller.snapshot()["site_has_restoration_receipt"]))
	assert_eq(bool(controller.snapshot()["site_now_supply_ready"]),
		bool(controller.snapshot()["original_supply_ready"]))
	assert_eq(str(network.snapshot()["feeders"][str(
		recipe["normal_feeder_id"])]["fault"]), "")
	if role == "second_route_b":
		assert_false(bool(network.snapshot()["ties"][
			str(recipe["standby_tie_id"])]["engaged"]))
	return {"ok": true, "role": role, "used_transfer": used_transfer,
		"reserve_spent": int(controller.snapshot()["reserve_spent_pu"])}


func test_EXP015_A07_original_100_alternatives_and_source_mutations() -> void:
	var gate: Dictionary = Alt.inspect(Atlas.load_catalog(),
		Alt.load_book(), Regional.load_book())
	assert_true(bool(gate.get("ok", false)), str(gate))
	assert_eq(int(gate["original_sites"]), 100)
	for role: String in Alt.ROLES:
		assert_eq(int(gate["role_counts"][role]), 25)
	var changed: Dictionary = Alt.load_book()
	changed["entries"][55]["standby_tie_id"] = "FAKED_SOURCE"
	assert_false(bool(Alt.inspect(Atlas.load_catalog(),
		changed, Regional.load_book()).get("ok", false)))


func test_EXP015_A07_150_authentic_role_and_branch_mechanical_replays() -> void:
	var total: int = 0
	var transfer_count: Dictionary = {"a": 0, "b": 0}
	var rapid: int = 0
	for region: int in range(25):
		for slot: int in [1, 2, 4, 5]:
			var routes: Array[String] = ["a", "b"] if slot >= 4 else ["a"]
			for route: String in routes:
				var result: Dictionary = _run_source_scenario(region, slot, route)
				assert_true(bool(result.get("ok", false)), str(result))
				if bool(result.get("ok", false)):
					total += 1
					if slot == 1 and str(result["role"]) == "first_route_a" and \
							int(result["reserve_spent"]) == 0:
						rapid += 1
					if slot == 5 and bool(result["used_transfer"]):
						transfer_count[route] = int(transfer_count[route]) + 1
					print("EXP015_A07_ORIGINAL_ROUTE region=%02d slot=%d first=%s role=%s standby=%s reserve=%d" %
						[region + 1, slot + 1, route, str(result["role"]),
						str(result["used_transfer"]), int(result["reserve_spent"])])
	assert_eq(total, 150)
	assert_eq(int(transfer_count["a"]), 12)
	assert_eq(int(transfer_count["b"]), 17)


func test_EXP015_A07_signoff_revoked_by_actual_reisolation() -> void:
	var context: Dictionary = _context(0, 1, "a")
	assert_false(context.is_empty())
	if context.is_empty():
		return
	var network: Regional = context["network"]
	var controller: Alt = context["controller"]
	var recipe: Dictionary = context["recipe"]
	for action: String in ["route_survey", "route_trip", "route_managed",
		"route_contain:" + str(recipe["risk_containment_protocol"]),
		"route_clear", "route_reset", "route_verify", "route_signoff"]:
		assert_true(bool(controller.operate(action).get("ok", false)), action)
	assert_true(controller.closed())
	var feeder: String = str(recipe["normal_feeder_id"])
	assert_true(controller.protects_original_asset("regional_isolate:" + feeder))
	assert_true(controller.protects_original_asset("regional_reset:" + feeder + ":suffix"))
	assert_false(controller.protects_original_asset("regional_isolate:OTHER_FEEDER"))
	assert_true(bool(network.host_transition("isolate_feeder", feeder).get("ok", false)))
	assert_false(controller.closed())
	assert_true(bool(network.host_transition("reset_feeder", feeder).get("ok", false)))
	assert_true(controller.closed())


func test_EXP015_A07_authenticated_worksite_on_four_real_alternate_roles() -> void:
	for slot: int in [1, 2, 4, 5]:
		Regional.clear_host_memory_for_test()
		var account: String = "a07_host_%02d" % (slot + 1)
		var opened: Dictionary = _start_host(0, slot, "b", account, true)
		assert_true(bool(opened["reply"].get("ok", false)), str(opened["reply"]))
		if not bool(opened["reply"].get("ok", false)):
			continue
		var host: Runtime = opened["host"]
		assert_true(bool(opened["reply"]["alternate_route_active"]))
		assert_true(str(opened["reply"]["content_revision"]).begins_with("EXP015_A07_"))
		assert_true(host.alternate_route != null)
		assert_true(host.incident_response == null)
		assert_true(host.service_cascade == null)
		assert_true(host.regional_finale == null)
		var board: String = str(host.worksite.definition_snapshot()["board"])
		_position = host.definition_snapshot()["positions"][board]
		var recipe: Dictionary = host.alternate_route.definition_snapshot()
		assert_false(bool(_send(host, 1, board, "route_survey", 999).get("ok", false)))
		assert_eq(str(_send(host, 1, board, "route_reset").get("code", "")),
			"ALT_RESET_NOT_READY")
		assert_eq(str(host._bespoke_guard(Runtime.PLAYER_ID,
			"request_extract", "ZONE_EXTRACT", {}).get("code", "")),
			"EXP015_A07_ORIGINAL_ROUTE_RECOVERY_REQUIRED")
		var actions: Array[String] = ["route_survey", "route_trip"]
		var role: String = str(recipe["campaign_role"])
		if role == "first_route_a":
			actions.append("route_managed" if int(recipe["capacity_pu"]) < 16 else
				"route_rapid")
			actions.append("route_contain:" + str(recipe["risk_containment_protocol"]))
		elif role == "first_route_b":
			actions.append("route_critical_priority")
			actions.append("route_contain:" + str(recipe["risk_containment_protocol"]))
		elif role == "second_route_a":
			actions.append("route_buffer")
		else:
			actions.append("route_managed")
			actions.append("route_prepare")
		actions.append("route_clear")
		if role == "second_route_b":
			actions.append("route_release")
		actions.append_array(["route_reset", "route_verify", "route_signoff"])
		var seq: int = 2
		for action: String in actions:
			var reply: Dictionary = _send(host, seq, board, action)
			assert_true(bool(reply.get("ok", false)), str(reply) + " " + action)
			seq += 1
		assert_true(host.alternate_route.closed())
		assert_true(bool(_send(host, seq - 1, board, "route_signoff").get("duplicate", false)))
		assert_true(host.authoritative_state().has("exp015_alternate_route"))
		assert_eq(str(host.task_board()["alternate_route"]["phase"]), "signed_off")
		assert_false(host.completed())
		assert_eq(host.pending_rewards(account).size(), 0)
		assert_eq(str(_send(host, seq, board, "regional_reset:" +
			str(recipe["normal_feeder_id"])).get("code", "")),
			"EXP015_A07_PROTECTED_SOURCE_ASSET")
		print("EXP015_A07_HOST role=%s source_original=%s rewards=0" %
			[role, recipe["route_site_id"]])


func test_EXP015_A07_default_opt_out_and_existing_A09_wire_revision() -> void:
	var opened: Dictionary = _start_host(0, 1, "a", "a07_no_optin", false)
	assert_true(bool(opened["reply"].get("ok", false)), str(opened["reply"]))
	if bool(opened["reply"].get("ok", false)):
		assert_false(bool(opened["reply"]["alternate_route_active"]))
		assert_true(str(opened["reply"]["content_revision"]).begins_with("EXP014_A09_"))
		assert_false(opened["host"].task_board().has("alternate_route"))
