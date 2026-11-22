extends "res://tests/test_case.gd"
## EXP015 A06: 25 original regions x two EXP05 routes, each with 3 distinct
## authenticated host dispatches. Shared A09 continuity is process-local only.
## Test-only EXP04 receipts unlock sites; never represent player completions.
const Atlas := preload("res://scripts/world/dispatch_atlas.gd")
const Ledger := preload("res://scripts/progression/expedition_ledger.gd")
const Network := preload("res://scripts/gameplay/expedition_regional_network.gd")
const Runtime := preload("res://scripts/gameplay/expedition_host_session.gd")
const Saves := preload("res://scripts/persistence/save_service.gd")
const Offline := preload("res://scripts/persistence/offline_persistence.gd")
const ContentHash := preload("res://scripts/network/content_hash.gd")

const SPINE: Array[int] = [1, 3, 4, 6, 7, 8]
const STAMP: String = "2026-11-22T00:00:00Z"
var _root: String = ""
var _position: Vector3 = Vector3.ZERO


func before_each() -> void:
	Network.clear_host_memory_for_test()
	_root = "user://exp015_a06_" + str(Time.get_ticks_usec()) + "_" + str(randi())
	_position = Vector3.ZERO


func after_each() -> void:
	Network.clear_host_memory_for_test()


func _position_for(_player: String) -> Vector3:
	return _position


func _restore(profile: Dictionary, atlas: Dictionary, n: int) -> void:
	var id: String = "LV_%03d" % n
	var level: Dictionary = Atlas.find_level(atlas, id)
	var receipt: Dictionary = Ledger.make_receipt(str(profile["account_key"]),
		id, str(level["tasks"][4]["id"]), "restoration")
	assert_true(bool(Ledger.apply_receipt(profile, receipt, atlas).get("applied", false)),
		"A06 source-authoritative test fixture, not production completion")


func _profile(atlas: Dictionary, region: int,
		mode: String, account: String, stage: int) -> Dictionary:
	var profile: Dictionary = Ledger.new_profile(account)
	for earlier: int in range(region):
		for slot: int in SPINE:
			_restore(profile, atlas, earlier * 8 + slot)
	var base: int = region * 8
	_restore(profile, atlas, base + 1)
	_restore(profile, atlas, base + (3 if mode == "critical_first" else 2))
	if stage >= 7:
		_restore(profile, atlas, base + 4)
		_restore(profile, atlas, base + (6 if mode == "critical_first" else 5))
	if stage >= 8:
		_restore(profile, atlas, base + 7)
	return profile


func _new_host(region: int, mode: String, account: String, stage: int) -> Dictionary:
	var atlas: Dictionary = Atlas.load_catalog()
	var profile: Dictionary = _profile(atlas, region, mode, account, stage)
	var saves: Saves = Saves.new()
	saves.configure(1, Offline.SAVE_BUILD_ID,
		ContentHash.content_revision(), ContentHash.rules_revision())
	var root: String = _root.path_join(account).path_join("dispatch_%d" % stage)
	var path: String = root.path_join("profiles").path_join(account).path_join(
		Ledger.PROFILE_FILE)
	var written: Dictionary = saves.write_record(path, Ledger.KIND_PROFILE,
		account, profile, STAMP)
	assert_true(bool(written.get("ok", false)), str(written))
	var host: Runtime = Runtime.new()
	# All EXP015 options enabled. Only the original first join, second join,
	# or finale instantiates its corresponding active controller.
	var result: Dictionary = host.start("LV_%03d" % (region * 8 + stage),
		Callable(self, "_position_for"), Callable(), account, true, root,
		true, true, true, true, true,
		true, true, true, true, true,
		true, true, true, true, true,
		true, true, true, true, true)
	return {"host": host, "reply": result}


func _send(host: Runtime, seq: int, board: String,
		action: String, peer: int = 1) -> Dictionary:
	# Drive authentic host ticks before each envelope; no reduced network
	# protection or direct controller shortcut in the 150-session replay.
	host.host.tick(seq)
	return host.receive(peer, JSON.stringify({
		"session": host.session_id(), "seq": seq,
		"type": "operate_worksite", "entity": board,
		"payload": {"action": action}
	}).to_utf8_buffer())


func _board(host: Runtime) -> String:
	var board: String = str(host.worksite.definition_snapshot()["board"])
	_position = host.definition_snapshot()["positions"][board]
	return board


func _replay(host: Runtime, board: String,
		actions: Array[String], start_seq: int = 1) -> int:
	var seq: int = start_seq
	for action: String in actions:
		var result: Dictionary = _send(host, seq, board, action)
		assert_true(bool(result.get("ok", false)), "A06 " + action + " " + str(result))
		seq += 1
	return seq


func test_EXP015_A06_50_auth_host_cross_dispatch_full_region_chains() -> void:
	var completed: int = 0
	var recharges: Dictionary = {"critical_first": 0, "resilience_first": 0}
	for region: int in range(25):
		for mode: String in ["critical_first", "resilience_first"]:
			Network.clear_host_memory_for_test()
			var account: String = "a06_r%02d_%s" % [region + 1, mode]
			var first: Dictionary = _new_host(region, mode, account, 4)
			assert_true(bool(first["reply"].get("ok", false)), str(first["reply"]))
			if not bool(first["reply"].get("ok", false)):
				continue
			var a01: Runtime = first["host"]
			var shared: Network = a01.regional_network
			assert_true(a01.incident_response != null)
			assert_true(a01.service_cascade == null)
			assert_true(a01.regional_finale == null)
			assert_true(a01.regional_assurance == null)
			assert_true(str(first["reply"]["content_revision"]).begins_with("EXP015_A01_"))
			var board1: String = _board(a01)
			assert_false(bool(_send(a01, 1, board1, "incident_survey", 999).get("ok", false)))
			_replay(a01, board1, ["regional_critical" if mode == "critical_first" else
				"regional_resilience", "incident_survey", "incident_isolate",
				"incident_managed", "incident_prepare",
				"incident_recover", "incident_certify"])
			assert_true(a01.incident_response.certified())
			var after_first: Dictionary = shared.snapshot()
			var reserve_after_first: int = int(after_first["reserve_pu"])
			var events_after_first: int = after_first["events"].size()
			assert_eq(str(after_first["strategy"]), mode)
			assert_false(a01.completed())
			assert_eq(a01.pending_rewards(account).size(), 0)

			var second: Dictionary = _new_host(region, mode, account, 7)
			assert_true(bool(second["reply"].get("ok", false)), str(second["reply"]))
			if not bool(second["reply"].get("ok", false)):
				continue
			var a02: Runtime = second["host"]
			assert_true(a02.regional_network == shared)
			assert_false(shared.site_prepared(), "Never reuse earlier site's preparation")
			assert_eq(int(shared.snapshot()["reserve_pu"]), reserve_after_first)
			assert_eq(int(shared.snapshot()["events"].size()), events_after_first)
			assert_true(a02.service_cascade != null)
			assert_true(a02.incident_response == null)
			assert_true(a02.regional_aftercare == null)
			assert_true(str(second["reply"]["content_revision"]).begins_with("EXP015_A02_"))
			var board2: String = _board(a02)
			assert_false(bool(_send(a02, 1, board2, "cascade_assess", 999).get("ok", false)))
			_replay(a02, board2, ["cascade_assess", "cascade_trip",
				"cascade_managed", "cascade_prepare", "cascade_clear",
				"cascade_reconnect", "cascade_attest"])
			assert_true(a02.service_cascade.resolved())
			assert_false(a02.completed())
			assert_eq(a02.pending_rewards(account).size(), 0)
			var reserve_after_second: int = int(shared.snapshot()["reserve_pu"])
			var events_after_second: int = shared.snapshot()["events"].size()
			assert_true(events_after_second > events_after_first)

			var final: Dictionary = _new_host(region, mode, account, 8)
			assert_true(bool(final["reply"].get("ok", false)), str(final["reply"]))
			if not bool(final["reply"].get("ok", false)):
				continue
			var a05: Runtime = final["host"]
			assert_true(a05.regional_network == shared)
			assert_true(a05.regional_finale != null)
			assert_true(a05.regional_aftercare != null)
			assert_true(a05.regional_assurance != null)
			assert_false(shared.site_prepared(), "Third dispatch requires its own preparation")
			assert_eq(int(shared.snapshot()["reserve_pu"]), reserve_after_second)
			assert_true(str(final["reply"]["content_revision"]).begins_with("EXP015_A05_"))
			var board3: String = _board(a05)
			var final_seq: int = _replay(a05, board3, ["finale_assess",
				"finale_critical_verified" if mode == "critical_first" else
					"finale_critical_contingency",
				"finale_buffer" if mode == "critical_first" else "finale_managed",
				"finale_verify", "finale_signoff"])
			assert_true(a05.regional_finale.closed())
			final_seq = _replay(a05, board3, ["aftercare_assess", "aftercare_trip",
				"aftercare_managed", "aftercare_clear",
				"aftercare_release", "aftercare_reset",
				"aftercare_verify", "aftercare_signoff"], final_seq)
			assert_true(a05.regional_aftercare.closed())
			assert_eq(str(a05._bespoke_guard(Runtime.PLAYER_ID,
				"request_extract", "ZONE_EXTRACT", {}).get("code", "")),
				"EXP015_A05_CRITICAL_ASSURANCE_REQUIRED")
			assert_false(a05.completed())
			assert_eq(a05.pending_rewards(account).size(), 0)

			final_seq = _replay(a05, board3, ["assurance_assess"], final_seq)
			var reserve_before_choice: int = int(shared.snapshot()["reserve_pu"])
			var recharge: Dictionary = _send(a05, final_seq, board3, "assurance_recharge")
			final_seq += 1
			if bool(recharge.get("ok", false)):
				recharges[mode] = int(recharges[mode]) + 1
				assert_true(int(shared.snapshot()["reserve_pu"]) > reserve_before_choice)
			else:
				assert_eq(str(recharge.get("code", "")), "RESERVE_RECHARGE_DENIED")
				assert_eq(int(shared.snapshot()["reserve_pu"]), reserve_before_choice)
				final_seq = _replay(a05, board3, ["assurance_conserve"], final_seq)

			assert_eq(str(_send(a05, final_seq, board3, "regional_recharge").get("code", "")),
				"EXP015_A05_PROTECTED_RESERVE")
			final_seq += 1
			final_seq = _replay(a05, board3, ["assurance_trip",
				"assurance_priority" if mode == "critical_first" else "assurance_managed",
				"assurance_clear", "assurance_reset",
				"assurance_verify", "assurance_signoff"], final_seq)
			assert_true(a05.regional_assurance.closed())
			assert_true(a05.regional_aftercare.closed())
			assert_true(a05.regional_finale.closed())
			assert_eq(str(shared.snapshot()["strategy"]), mode)
			assert_true(bool(_send(a05, final_seq - 1, board3,
				"assurance_signoff").get("duplicate", false)))
			assert_true(a05.authoritative_state().has("exp015_regional_assurance"))
			assert_false(a05.completed(), "No source-only side effect completes mission")
			assert_eq(a05.pending_rewards(account).size(), 0)
			completed += 1
			print("EXP015_A06_CHAIN region=%02d mode=%s dispatches=3 reserve=%d reboot=false reward=0" %
				[region + 1, mode, int(shared.snapshot()["reserve_pu"])])
	assert_eq(completed, 50)
	assert_eq(int(recharges["critical_first"]), 3)
	assert_eq(int(recharges["resilience_first"]), 0)


func test_EXP015_A06_separate_accounts_do_not_share_network_state() -> void:
	var one: Dictionary = _new_host(0, "critical_first", "a06_isolated_one", 4)
	assert_true(bool(one["reply"].get("ok", false)), str(one["reply"]))
	if not bool(one["reply"].get("ok", false)):
		return
	var a: Runtime = one["host"]
	var ba: String = _board(a)
	assert_true(bool(_send(a, 1, ba, "regional_critical").get("ok", false)))
	var first_reserve: int = int(a.regional_network.snapshot()["reserve_pu"])
	var other: Dictionary = _new_host(0, "resilience_first", "a06_isolated_other", 4)
	assert_true(bool(other["reply"].get("ok", false)), str(other["reply"]))
	if not bool(other["reply"].get("ok", false)):
		return
	var b: Runtime = other["host"]
	assert_false(b.regional_network == a.regional_network)
	assert_true(str(b.regional_network.snapshot()["strategy"]).is_empty())
	assert_eq(int(a.regional_network.snapshot()["reserve_pu"]), first_reserve)
	assert_eq(b.pending_rewards("a06_isolated_other").size(), 0)


## EXP015 A13 — complete original source across *three* dispatch epochs.
## Unlike A06 this probes interleaved stale replays after each actual phase
## transition, without direct controller shortcuts or synthetic reward claims.
func test_EXP015_A13_50_region_branch_replays_refuse_two_retired_hosts() -> void:
	var qualified: int = 0
	for region: int in range(25):
		for mode: String in ["critical_first", "resilience_first"]:
			Network.clear_host_memory_for_test()
			var account: String = "a13_%02d_%s" % [region, mode]
			var root_ctx: Dictionary = _new_host(region, mode, account, 4)
			assert_true(bool(root_ctx["reply"].get("ok", false)),
				str(root_ctx["reply"]))
			if not bool(root_ctx["reply"].get("ok", false)):
				continue
			var root: Runtime = root_ctx["host"]
			var network: Network = root.regional_network
			var root_board: String = _board(root)
			_replay(root, root_board, [
				"regional_critical" if mode == "critical_first" else
					"regional_resilience",
				"incident_survey", "incident_isolate", "incident_managed",
				"incident_prepare", "incident_recover", "incident_certify"
			])
			assert_true(root.incident_response.certified())
			var after_root: Dictionary = network.snapshot()
			var second_ctx: Dictionary = _new_host(region, mode, account, 7)
			assert_true(bool(second_ctx["reply"].get("ok", false)),
				str(second_ctx["reply"]))
			if not bool(second_ctx["reply"].get("ok", false)):
				continue
			var second: Runtime = second_ctx["host"]
			assert_true(second.regional_network == network)
			assert_eq(int(network.snapshot()["reserve_pu"]),
				int(after_root["reserve_pu"]))
			var retired_root_hash: String = root.host.state_hash()
			var stale_root_duplicate: Dictionary = _send(root, 1, root_board,
				"incident_survey")
			assert_eq(str(stale_root_duplicate.get("code", "")),
				"EXP015_A12_15_STALE_REPLAY")
			var stale_root_fresh: Dictionary = _send(root, 8, root_board,
				"incident_survey")
			assert_eq(str(stale_root_fresh.get("code", "")),
				"EXP015_A12_9_STALE_HOST_DISPATCH")
			assert_eq(root.host.state_hash(), retired_root_hash)
			assert_eq(root.host.publish(), {})
			assert_eq(str(root.host.snapshot().get("code", "")),
				"EXP015_A12_13_STALE_HOST_SNAPSHOT")
			var middle_board: String = _board(second)
			_replay(second, middle_board, [
				"cascade_assess", "cascade_trip", "cascade_managed",
				"cascade_prepare", "cascade_clear", "cascade_reconnect",
				"cascade_attest"
			])
			assert_true(second.service_cascade.resolved())
			var after_second: Dictionary = network.snapshot()
			assert_true(after_second["events"].size() >
				after_root["events"].size())
			var finale_ctx: Dictionary = _new_host(region, mode, account, 8)
			assert_true(bool(finale_ctx["reply"].get("ok", false)),
				str(finale_ctx["reply"]))
			if not bool(finale_ctx["reply"].get("ok", false)):
				continue
			var finale: Runtime = finale_ctx["host"]
			assert_true(finale.regional_network == network)
			var retired_middle_hash: String = second.host.state_hash()
			assert_eq(str(_send(second, 1, middle_board,
				"cascade_assess").get("code", "")),
				"EXP015_A12_15_STALE_REPLAY")
			assert_eq(str(_send(second, 8, middle_board,
				"cascade_assess").get("code", "")),
				"EXP015_A12_9_STALE_HOST_DISPATCH")
			assert_eq(second.host.state_hash(), retired_middle_hash)
			assert_eq(root.host.state_hash(), retired_root_hash)
			var before_finale: int = int(network.snapshot()["reserve_pu"])
			assert_eq(before_finale, int(after_second["reserve_pu"]))
			var final_board: String = _board(finale)
			_replay(finale, final_board, [
				"finale_assess",
				"finale_critical_verified" if mode == "critical_first" else
					"finale_critical_contingency",
				"finale_buffer" if mode == "critical_first" else
					"finale_managed",
				"finale_verify", "finale_signoff"
			])
			assert_true(finale.regional_finale.closed())
			assert_eq(str(network.snapshot()["strategy"]), mode)
			assert_true(int(network.snapshot()["reserve_pu"]) >= 0)
			assert_true(finale.host.snapshot().has("manifest"))
			assert_eq(finale.pending_rewards(account).size(), 0)
			assert_false(finale.completed())
			qualified += 1
			print("EXP015_A13 region=%02d branch=%s epochs=%d old_replay=DENIED" %
				[region + 1, mode, network.current_dispatch_epoch()])
	assert_eq(qualified, 50)
