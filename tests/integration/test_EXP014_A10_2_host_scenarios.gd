extends "res://tests/test_case.gd"
## EXP014 A10.2: actual SessionHost envelope replay across all 25 regions.
## Distinguishes host-accepted commands from source-only A10.1 path oracles.
## No physical route, player/controller, GPU, Steam or release certification.

const Atlas := preload("res://scripts/world/dispatch_atlas.gd")
const Campaign := preload("res://scripts/progression/expedition_campaign.gd")
const Ledger := preload("res://scripts/progression/expedition_ledger.gd")
const Network := preload("res://scripts/gameplay/expedition_regional_network.gd")
const Runtime := preload("res://scripts/gameplay/expedition_host_session.gd")
const Saves := preload("res://scripts/persistence/save_service.gd")

const SAVED_AT: String = "2026-11-21T10:00:00Z"
const SPINE: Array[int] = [1, 3, 4, 6, 7, 8]
const CHECK_REGIONS: Array[int] = [0, 4, 9, 14, 19, 24]

var _position: Vector3 = Vector3.ZERO
var _root: String = ""
var _atlas: Dictionary = {}
var _routes: Dictionary = {}
var _saves: Saves


func before_each() -> void:
	Network.clear_host_memory_for_test()
	_position = Vector3.ZERO
	_root = "user://a102_host_" + str(Time.get_ticks_usec()) + "_" + str(randi() % 100000)
	_atlas = Atlas.load_catalog()
	_routes = Campaign.load_routes()
	_saves = Saves.new()
	_saves.configure(1, "a10-2-test-build", "a10-2-test-content")


func after_each() -> void:
	Network.clear_host_memory_for_test()
	_remove_tree(_root)


func _remove_tree(path: String) -> void:
	var dir: DirAccess = DirAccess.open(path)
	if dir == null:
		return
	for filename: String in dir.get_files():
		DirAccess.remove_absolute(path.path_join(filename))
	for sub: String in dir.get_directories():
		_remove_tree(path.path_join(sub))
	DirAccess.remove_absolute(path)


func _host_position(_player: String) -> Vector3:
	return _position


func _level(base: int, slot: int) -> String:
	return "LV_%03d" % (base + slot)


func _receipt(account: String, level_id: String) -> Dictionary:
	var level: Dictionary = Atlas.find_level(_atlas, level_id)
	return Ledger.make_receipt(account, level_id,
		str(level["tasks"][4]["id"]), "restoration")


func _restore(profile: Dictionary, id: String) -> void:
	var receipt: Dictionary = _receipt(str(profile["account_key"]), id)
	var result: Dictionary = Ledger.apply_receipt(profile, receipt, _atlas)
	assert_true(bool(result.get("applied", false)), "%s: %s" % [id, str(result)])


func _seed(region: int, strategy: String, account: String) -> Dictionary:
	var profile: Dictionary = Ledger.new_profile(account)
	# Real EXP05 prerequisite history, not an orphaned previous-chapter finale.
	for prior: int in range(region):
		var base: int = prior * 8
		for slot: int in SPINE:
			_restore(profile, _level(base, slot))
	var base: int = region * 8
	_restore(profile, _level(base, 1))
	_restore(profile, _level(base, 2 if strategy == "resilience_first" else 3))
	return profile


func _write_profile(root: String, profile: Dictionary) -> void:
	var account: String = str(profile["account_key"])
	var target: String = root.path_join("profiles").path_join(account).path_join(
		Ledger.PROFILE_FILE)
	var saved: Dictionary = _saves.write_record(target, Ledger.KIND_PROFILE,
		account, profile, SAVED_AT)
	assert_true(bool(saved.get("ok", false)), "%s: %s" % [target, str(saved)])


func _start(level_id: String, account: String, root: String) -> Dictionary:
	var host: Runtime = Runtime.new()
	var started: Dictionary = host.start(level_id, Callable(self, "_host_position"),
		Callable(), account, true, root, true, true, true, true, true,
		true, true, true, true, true, true, true, true, true, true)
	return {"ok": bool(started.get("ok", false)), "reply": started, "host": host}


func _board(host: Runtime) -> String:
	return str(host.worksite.definition_snapshot()["board"])


func _stand(host: Runtime, target: String) -> void:
	_position = host.definition_snapshot()["positions"][target]


func _send(host: Runtime, seq: int, entity: String, action: String,
		peer: int = 1) -> Dictionary:
	var wire: PackedByteArray = JSON.stringify({
		"session": host.session_id(), "seq": seq, "type": "operate_worksite",
		"entity": entity, "payload": {"action": action}
	}).to_utf8_buffer()
	return host.receive(peer, wire)


func test_EXP014_A10_2_all_25_regions_both_strategies_use_real_host_ingress() -> void:
	var runs: int = 0
	var accepted: int = 0
	var rejected: int = 0
	for region: int in range(25):
		var base: int = region * 8
		for mode: String in ["resilience_first", "critical_first"]:
			var account: String = "a102_r%02d_%s" % [region + 1, mode]
			var root: String = _root.path_join(account)
			var profile: Dictionary = _seed(region, mode, account)
			assert_true(bool(Campaign.can_launch(profile, _atlas, _routes,
				_level(base, 4)).get("ok", false)), "source EXP05 path must unlock join")
			# The untouched alternative fork remains accessible after either proof.
			var other: int = 3 if mode == "resilience_first" else 2
			assert_true(bool(Campaign.can_launch(profile, _atlas, _routes,
				_level(base, other)).get("ok", false)))
			_write_profile(root, profile)
			var created: Dictionary = _start(_level(base, 4), account, root)
			assert_true(bool(created["ok"]), "%s: %s" % [account, str(created["reply"])])
			if not bool(created["ok"]):
				continue
			var host: Runtime = created["host"]
			assert_true(bool(created["reply"]["regional_network_active"]))
			assert_eq(str(host.regional_network.snapshot()["region_id"]),
				"REG_%02d" % (region + 1))
			assert_eq(str(host.task_board()["level_id"]), _level(base, 4))
			assert_false(host.regional_network.site_prepared())
			var board: String = _board(host)
			_stand(host, board)
			var request: String = ("regional_resilience" if mode == "resilience_first"
				else "regional_critical")
			var previous: Dictionary = host.regional_network.snapshot()
			var foreign: Dictionary = _send(host, 1, board, request, 777)
			assert_false(bool(foreign.get("ok", false)))
			assert_eq(host.regional_network.snapshot(), previous,
				"foreign peer must never mutate regional feeder/service state")
			rejected += 1
			var chosen: Dictionary = _send(host, 1, board, request)
			assert_true(bool(chosen.get("ok", false)), str(chosen))
			assert_eq(str(host.regional_network.snapshot()["strategy"]), mode)
			var after: Dictionary = host.regional_network.snapshot()
			assert_eq(int(after["reserve_pu"]),
				int(previous["reserve_pu"]) - (2 if mode == "critical_first" else 0))
			var replay: Dictionary = _send(host, 1, board, request)
			assert_true(bool(replay.get("duplicate", false)), str(replay))
			assert_eq(host.regional_network.snapshot(), after)
			var spoofed: Dictionary = _send(host, 2, "FORGED_NETWORK_BOARD",
				"regional_buffer")
			assert_false(bool(spoofed.get("ok", false)))
			assert_eq(host.regional_network.snapshot(), after)
			rejected += 2
			assert_eq(str(host._bespoke_guard(Runtime.PLAYER_ID,
				"request_extract", "ZONE_EXTRACT", {}).get("code", "")),
				"EXP014_A09_PREPARATION_REQUIRED")
			var prepared: Dictionary = _send(host, 3, board, "regional_managed")
			assert_true(bool(prepared.get("ok", false)), str(prepared))
			assert_true(host.regional_network.site_prepared())
			assert_false(host.completed())
			assert_eq(host.pending_rewards(account).size(), 0)
			assert_eq(int(host.regional_network.snapshot()["events"].size()), 2)
			accepted += 2
			runs += 1
		print("A10_2_HOST_PATH region=%02d mode=%s sessions=%d accepted=%d rejected=%d" %
			[region + 1, mode, runs, accepted, rejected])
	assert_eq(runs, 50)
	assert_eq(accepted, 100)
	assert_eq(rejected, 150)


func test_EXP014_A10_2_cross_dispatch_regions_keep_strategy_but_not_forged_progress() -> void:
	var dispatches: int = 0
	for region: int in CHECK_REGIONS:
		var base: int = region * 8
		for mode: String in ["resilience_first", "critical_first"]:
			var account: String = "a102_d%02d_%s" % [region + 1, mode]
			var root: String = _root.path_join(account)
			var profile: Dictionary = _seed(region, mode, account)
			_write_profile(root, profile)
			var first: Dictionary = _start(_level(base, 4), account, root)
			assert_true(bool(first["ok"]), str(first["reply"]))
			if not bool(first["ok"]):
				continue
			var host: Runtime = first["host"]
			var board: String = _board(host)
			_stand(host, board)
			var action: String = ("regional_resilience" if mode == "resilience_first"
				else "regional_critical")
			assert_true(bool(_send(host, 1, board, action).get("ok", false)))
			assert_true(bool(_send(host, 2, board, "regional_managed").get("ok", false)))
			var first_network: Network = host.regional_network
			var old_reserve: int = int(first_network.snapshot()["reserve_pu"])
			var old_events: int = first_network.snapshot()["events"].size()
			# Persist a source-valid EXP04 restoration receipt through a real
			# isolated SaveService test record (no production save touched).
			_restore(profile, _level(base, 4))
			_write_profile(root, profile)
			var next_slot: int = 5 if mode == "resilience_first" else 6
			var follow: Dictionary = _start(_level(base, next_slot), account, root)
			assert_true(bool(follow["ok"]), str(follow["reply"]))
			if not bool(follow["ok"]):
				continue
			var next_host: Runtime = follow["host"]
			assert_true(next_host.regional_network == first_network,
				"same account/region must reuse host-owned feeder context")
			assert_eq(str(next_host.regional_network.snapshot()["strategy"]), mode)
			assert_eq(int(next_host.regional_network.snapshot()["reserve_pu"]), old_reserve)
			assert_eq(int(next_host.regional_network.snapshot()["events"].size()), old_events)
			assert_false(next_host.regional_network.site_prepared(),
				"next dispatch requires its own host preparation")
			assert_true(bool(next_host.regional_network.snapshot()["sites"][
				_level(base, 4)]["restored"]))
			var next_board: String = _board(next_host)
			_stand(next_host, next_board)
			assert_true(bool(_send(next_host, 1, next_board,
				"regional_managed").get("ok", false)))
			assert_true(next_host.regional_network.site_prepared())
			assert_eq(int(next_host.regional_network.snapshot()["events"].size()), old_events + 1)
			assert_eq(next_host.pending_rewards(account).size(), 0)
			dispatches += 2
		print("A10_2_DISPATCH region=%02d mode=%s host_sessions=%d strategy=%s" %
			[region + 1, mode, dispatches, mode])
	assert_eq(dispatches, CHECK_REGIONS.size() * 4)


func test_EXP014_A10_2_host_commands_preserve_break_before_make_and_recovery() -> void:
	var account: String = "a102_live_isolation"
	var root: String = _root.path_join(account)
	var profile: Dictionary = _seed(0, "critical_first", account)
	_restore(profile, "LV_004")
	_write_profile(root, profile)
	var started: Dictionary = _start("LV_006", account, root)
	assert_true(bool(started["ok"]), str(started["reply"]))
	if not bool(started["ok"]):
		return
	var host: Runtime = started["host"]
	var board: String = _board(host)
	_stand(host, board)
	assert_true(bool(_send(host, 1, board, "regional_critical").get("ok", false)))
	var reserve: int = int(host.regional_network.snapshot()["reserve_pu"])
	assert_eq(reserve, 4)
	assert_true(bool(_send(host, 2, board, "regional_isolate:NET_01_F05").get("ok", false)))
	assert_true(bool(_send(host, 3, board, "regional_engage:NET_01_T01").get("ok", false)))
	var transfer: Dictionary = host.regional_network.snapshot()
	assert_true(bool(transfer["ties"]["NET_01_T01"]["engaged"]))
	assert_eq(int(transfer["reserve_pu"]), reserve - 2)
	assert_false(bool(_send(host, 4, board,
		"regional_reset:NET_01_F05").get("ok", false)),
		"normal feeder may not make before standby opens")
	assert_eq(host.regional_network.snapshot(), transfer)
	assert_true(bool(_send(host, 5, board, "regional_release:NET_01_T01").get("ok", false)))
	assert_true(bool(_send(host, 6, board, "regional_reset:NET_01_F05").get("ok", false)))
	var restored: Dictionary = host.regional_network.snapshot()
	assert_false(bool(restored["ties"]["NET_01_T01"]["engaged"]))
	assert_false(bool(restored["feeders"]["NET_01_F05"]["isolated"]))
	assert_eq(int(restored["reserve_pu"]), reserve - 2,
		"released tie must not duplicate or refund spent standby reserve")
	assert_false(bool(_send(host, 7, board,
		"regional_recharge").get("ok", false)),
		"unrestored/dark reserve anchor cannot generate free capacity")
	assert_eq(host.regional_network.snapshot(), restored)
	assert_false(host.completed())
	assert_eq(host.pending_rewards(account).size(), 0)


func test_EXP014_A10_2_saved_receipt_rollback_rejected_by_existing_live_host() -> void:
	var account: String = "a102_rollback"
	var root: String = _root.path_join(account)
	var profile: Dictionary = _seed(0, "critical_first", account)
	_write_profile(root, profile)
	var started: Dictionary = _start("LV_004", account, root)
	assert_true(bool(started["ok"]), str(started["reply"]))
	if not bool(started["ok"]):
		return
	var host: Runtime = started["host"]
	var board: String = _board(host)
	_stand(host, board)
	assert_true(bool(_send(host, 1, board, "regional_critical").get("ok", false)))
	_restore(profile, "LV_004")
	_write_profile(root, profile)
	var continuation: Dictionary = _start("LV_006", account, root)
	assert_true(bool(continuation["ok"]), str(continuation["reply"]))
	if not bool(continuation["ok"]):
		return
	var old_state: Dictionary = host.regional_network.snapshot()
	# Profile remains structurally consistent; only the proof that the live
	# host previously accepted is revoked. Refuse silent feeder-state rollback.
	var proof: Dictionary = _receipt(account, "LV_003")
	(profile["completed_levels"] as Dictionary).erase("LV_003")
	(profile["earned_tasks"] as Dictionary).erase("JOB_003_5")
	(profile["applied_receipts"] as Dictionary).erase(str(proof["receipt_key"]))
	assert_true(bool(Campaign.can_launch(profile, _atlas, _routes,
		"LV_006").get("ok", false)))
	_write_profile(root, profile)
	var attack: Dictionary = _start("LV_006", account, root)
	assert_false(bool(attack["ok"]), str(attack["reply"]))
	assert_eq(str(attack["reply"].get("code", "")),
		"EXP014_A09_REGIONAL_PROFILE_HOLD")
	assert_eq(str(attack["reply"].get("details", {}).get("code", "")),
		"RESTORATION_RECEIPT_ROLLBACK")
	assert_eq(host.regional_network.snapshot(), old_state,
		"failed attach cannot mutate live host state or erase earlier events")


func test_EXP014_A10_2_regional_preparation_does_not_bypass_a07_a08_host_gates() -> void:
	var evaluated: int = 0
	for region: int in [0, 9, 24]:
		var account: String = "a102_chain_%02d" % (region + 1)
		var root: String = _root.path_join(account)
		var profile: Dictionary = _seed(region, "critical_first", account)
		_write_profile(root, profile)
		var opened: Dictionary = _start(_level(region * 8, 4), account, root)
		assert_true(bool(opened["ok"]), str(opened["reply"]))
		if not bool(opened["ok"]):
			continue
		var host: Runtime = opened["host"]
		var decision: String = str(host.worksite.definition_snapshot()["decision"])
		var board: String = _board(host)
		_stand(host, decision)
		var no_regional_prep: Dictionary = _send(host, 1, decision, "priority")
		assert_eq(str(no_regional_prep.get("code", "")),
			"EXP014_A09_REGIONAL_PREPARATION_REQUIRED")
		_stand(host, board)
		assert_true(bool(_send(host, 2, board, "regional_critical").get("ok", false)))
		assert_true(bool(_send(host, 3, board, "regional_managed").get("ok", false)))
		assert_true(host.regional_network.site_prepared())
		_stand(host, decision)
		var no_hazard_proof: Dictionary = _send(host, 4, decision, "priority")
		assert_eq(str(no_hazard_proof.get("code", "")),
			"EXP014_A07_HAZARD_LOCKED")
		assert_false(host.site_hazards.can_operate())
		assert_false(host.site_puzzles.solved())
		assert_false(bool(host.task_board()["mission_completed"]))
		assert_eq(host.pending_rewards(account).size(), 0)
		evaluated += 1
		print("A10_2_CROSS_SYSTEM region=%02d regional=prepared hazard=held investigation=held" %
			[region + 1])
	assert_eq(evaluated, 3)
