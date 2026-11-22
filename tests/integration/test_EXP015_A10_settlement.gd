extends "res://tests/test_case.gd"
## A10: original 25-region resource mutations and host security. Fixtures
## apply EXP04 receipts only in headless tests, not as production rewards.
const Atlas := preload("res://scripts/world/dispatch_atlas.gd")
const Ledger := preload("res://scripts/progression/expedition_ledger.gd")
const Network := preload("res://scripts/gameplay/expedition_regional_network.gd")
const Settlement := preload("res://scripts/gameplay/expedition_regional_debt_settlement.gd")
const Assurance := preload("res://scripts/gameplay/expedition_regional_assurance.gd")
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
	_root = "user://exp015_a10_" + str(Time.get_ticks_usec()) + "_" + str(randi())
	_position = Vector3.ZERO


func after_each() -> void:
	Network.clear_host_memory_for_test()


func _position_for(_player: String) -> Vector3:
	return _position


func _restore(profile: Dictionary, atlas: Dictionary, n: int) -> void:
	var level_id: String = "LV_%03d" % n
	var level: Dictionary = Atlas.find_level(atlas, level_id)
	var receipt: Dictionary = Ledger.make_receipt(str(profile["account_key"]),
		level_id, str(level["tasks"][4]["id"]), "restoration")
	assert_true(bool(Ledger.apply_receipt(profile, receipt, atlas).get("applied", false)),
		"headless EXP04 source-only test fixture")


func _cold_profile(atlas: Dictionary, region: int, account: String) -> Dictionary:
	var profile: Dictionary = Ledger.new_profile(account)
	for prior: int in range(region):
		for slot: int in SPINE:
			_restore(profile, atlas, prior * 8 + slot)
	return profile


func _restore_required_anchor_ancestors(profile: Dictionary, atlas: Dictionary,
		region: int) -> void:
	# The original primary tree can route the reserve anchor through the
	# alternate slot-5 site. Never invent an energized anchor or weaken the
	# production settlement interlock to compensate for a missing receipt.
	var root: String = "LV_%03d" % (region * 8 + 1)
	var source: Dictionary = Network.entry_for(Network.load_book(), root)
	assert_false(source.is_empty(), "original regional network is mandatory")
	if source.is_empty():
		return
	var incoming: Dictionary = {}
	for edge: Dictionary in source["primary_feeders"]:
		incoming[str(edge["to"])] = str(edge["from"])
	var cursor: String = str(source["reserve_anchor_site"])
	var ancestors: Array[String] = []
	var visited: Dictionary = {}
	while cursor != root:
		assert_true(incoming.has(cursor) and not visited.has(cursor),
			"anchor must have a finite original primary feeder path")
		if not incoming.has(cursor) or visited.has(cursor):
			return
		visited[cursor] = true
		ancestors.append(cursor)
		cursor = str(incoming[cursor])
	ancestors.reverse()
	for site: String in ancestors:
		var index: int = site.trim_prefix("LV_").to_int()
		var slot: int = index - region * 8
		if slot not in [1, 2, 3, 4, 6, 7]:
			_restore(profile, atlas, index)


func _commission(region: int, debt: bool, account: String) -> Dictionary:
	var atlas: Dictionary = Atlas.load_catalog()
	var profile: Dictionary = _cold_profile(atlas, region, account)
	var root: String = "LV_%03d" % (region * 8 + 1)
	var network: Network = Network.new()
	var first: Dictionary = network.configure(atlas, profile, root)
	assert_true(bool(first.get("ok", false)), str(first))
	if not bool(first.get("ok", false)):
		return {}
	var commitment: Dictionary = network.host_transition(
		"commit_entry_debt" if debt else "commit_entry_buffer", root)
	assert_true(bool(commitment.get("ok", false)), str(commitment))
	assert_true(bool(network.prepare_site("managed" if debt else "buffer").get("ok", false)))
	for slot: int in [1, 2, 3, 4, 6, 7]:
		_restore(profile, atlas, region * 8 + slot)
	_restore_required_anchor_ancestors(profile, atlas, region)
	var finale: String = "LV_%03d" % (region * 8 + 8)
	var joined: Dictionary = network.attach_site(atlas, profile, finale)
	assert_true(bool(joined.get("ok", false)), str(joined))
	if not bool(joined.get("ok", false)):
		return {}
	return {"profile": profile, "network": network, "atlas": atlas,
		"finale": finale}


func test_EXP015_A10_25_original_source_bindings_and_mutations() -> void:
	var book: Dictionary = Settlement.load_book()
	var verdict: Dictionary = Settlement.inspect(Atlas.load_catalog(),
		book, Network.load_book(), Assurance.load_book())
	assert_true(bool(verdict.get("ok", false)), str(verdict))
	assert_eq(int(verdict["original_finales"]), 25)
	var forged: Dictionary = book.duplicate(true)
	forged["entries"][8]["reserve_anchor_site_id"] = "FORGED"
	assert_eq(Settlement.inspect(Atlas.load_catalog(), forged,
		Network.load_book(), Assurance.load_book())["code"],
		"SETTLEMENT_ORIGINAL_SOURCE_MISMATCH")


func test_EXP015_A10_25_real_debt_retirements_and_no_forged_supply() -> void:
	var successful: int = 0
	for region: int in range(25):
		var context: Dictionary = _commission(region, true,
			"a10_debt_%02d" % (region + 1))
		if context.is_empty():
			continue
		var network: Network = context["network"]
		var original: Dictionary = Network.entry_for(Network.load_book(),
			str(context["finale"]))
		var anchor: String = str(original["reserve_anchor_site"])
		var before: int = int(network.snapshot()["reserve_pu"])
		assert_true(bool(network.snapshot()["sites"][anchor]["restored"]))
		assert_true(bool(network.snapshot()["sites"][anchor]["energized"]))
		assert_eq(int(network.site_conditions()["service_debt"]), 2)
		var result: Dictionary = network.host_transition("retire_service_debt", anchor)
		assert_true(bool(result.get("ok", false)), str(result))
		assert_eq(int(network.snapshot()["reserve_pu"]), before - 2)
		assert_eq(int(network.site_conditions()["service_debt"]), 0)
		assert_eq(str(network.host_transition(
			"retire_service_debt", anchor).get("code", "")),
			"DEBT_SETTLEMENT_SOURCE_OR_RESERVE_DENIED")
		successful += 1
	assert_eq(successful, 25)


func test_EXP015_A10_dark_original_anchor_requires_real_upstream_receipt() -> void:
	# Two original primary trees require a restored slot-5 intermediate
	# (LV_085 or LV_197); their restored anchors remain dark without it.
	for region: int in [10, 24]:
		var atlas: Dictionary = Atlas.load_catalog()
		var profile: Dictionary = _cold_profile(atlas, region,
			"a10_dark_source_%02d" % (region + 1))
		var root: String = "LV_%03d" % (region * 8 + 1)
		var network: Network = Network.new()
		assert_true(bool(network.configure(atlas, profile, root).get("ok", false)))
		assert_true(bool(network.host_transition("commit_entry_debt", root).get("ok", false)))
		assert_true(bool(network.prepare_site("managed").get("ok", false)))
		for slot: int in [1, 2, 3, 4, 6, 7]:
			_restore(profile, atlas, region * 8 + slot)
		var finale: String = "LV_%03d" % (region * 8 + 8)
		assert_true(bool(network.attach_site(atlas, profile, finale).get("ok", false)))
		var original: Dictionary = Network.entry_for(Network.load_book(), finale)
		var anchor: String = str(original["reserve_anchor_site"])
		assert_true(bool(network.snapshot()["sites"][anchor]["restored"]))
		assert_false(bool(network.snapshot()["sites"][anchor]["energized"]))
		var held: Dictionary = network.snapshot()
		assert_eq(str(network.host_transition("retire_service_debt", anchor)["code"]),
			"DEBT_SETTLEMENT_SOURCE_OR_RESERVE_DENIED")
		assert_eq(network.snapshot(), held, "dark-anchor denial cannot spend reserve")
		_restore(profile, atlas, region * 8 + 5)
		assert_true(bool(network.refresh_receipts(atlas, profile).get("ok", false)))
		assert_true(bool(network.snapshot()["sites"][anchor]["energized"]))
		assert_true(bool(network.host_transition("retire_service_debt", anchor).get("ok", false)))
		assert_eq(int(network.site_conditions()["service_debt"]), 0)


func test_EXP015_A10_zero_debt_and_wrong_asset_fail_closed() -> void:
	var clean: Dictionary = _commission(0, false, "a10_zero_debt")
	assert_false(clean.is_empty())
	if clean.is_empty():
		return
	var network: Network = clean["network"]
	assert_eq(int(network.site_conditions()["service_debt"]), 0)
	var asset: String = str(network.snapshot()["reserve_anchor"])
	assert_eq(str(network.host_transition("retire_service_debt", asset)["code"]),
		"DEBT_SETTLEMENT_SOURCE_OR_RESERVE_DENIED")
	var unpaid: Dictionary = _commission(1, true, "a10_wrong_anchor")
	assert_false(unpaid.is_empty())
	if unpaid.is_empty():
		return
	var other: Network = unpaid["network"]
	var balance: int = int(other.snapshot()["reserve_pu"])
	assert_eq(str(other.host_transition("retire_service_debt", "FAKE")["code"]),
		"DEBT_SETTLEMENT_SOURCE_OR_RESERVE_DENIED")
	assert_eq(int(other.snapshot()["reserve_pu"]), balance)
	assert_eq(int(other.site_conditions()["service_debt"]), 2)


func _send(host: Runtime, seq: int, board: String, action: String,
		peer: int = 1) -> Dictionary:
	host.host.tick(seq)
	return host.receive(peer, JSON.stringify({
		"session": host.session_id(), "seq": seq, "type": "operate_worksite",
		"entity": board, "payload": {"action": action}
	}).to_utf8_buffer())


func test_EXP015_A10_authenticated_finale_debt_choice_and_opt_out() -> void:
	# Source fixture first commits real managed debt to the original cold
	# root. The same host process then reuses that actual A09 state on finale.
	var account: String = "a10_original_finite_debt"
	var context: Dictionary = _commission(0, true, account)
	assert_false(context.is_empty())
	if context.is_empty():
		return
	var atlas: Dictionary = context["atlas"]
	var profile: Dictionary = context["profile"]
	var region_network: Network = context["network"]
	# Rebind the original account/region instance in the process-local host map.
	# A10 runtime must not silently seed an independent reserve ledger.
	Network.clear_host_memory_for_test()
	var profile_cold: Dictionary = _cold_profile(atlas, 0, account)
	var acquired: Dictionary = Network.acquire(atlas, profile_cold, "LV_001")
	assert_true(bool(acquired.get("ok", false)), str(acquired))
	if not bool(acquired.get("ok", false)):
		return
	var owned: Network = acquired["network"]
	assert_true(bool(owned.host_transition("commit_entry_debt", "LV_001").get("ok", false)))
	assert_true(bool(owned.prepare_site("managed").get("ok", false)))
	var store: Saves = Saves.new()
	store.configure(1, Offline.SAVE_BUILD_ID,
		ContentHash.content_revision(), ContentHash.rules_revision())
	var path: String = _root.path_join("profiles").path_join(account).path_join(
		Ledger.PROFILE_FILE)
	assert_true(bool(store.write_record(path, Ledger.KIND_PROFILE,
		account, profile, STAMP).get("ok", false)))
	var host: Runtime = Runtime.new()
	var ready: Dictionary = host.start("LV_008", Callable(self, "_position_for"),
		Callable(), account, true, _root,
		true, true, true, true, true,
		true, true, true, true, true,
		true, true, true, true, true,
		true, true, true, true, true,
		false, false, false, true)
	assert_true(bool(ready.get("ok", false)), str(ready))
	if not bool(ready.get("ok", false)):
		return
	assert_true(bool(ready["regional_settlement_active"]))
	assert_true(str(ready["content_revision"]).begins_with("EXP015_A10_"))
	assert_eq(int(host.regional_network.site_conditions()["service_debt"]), 2)
	var board: String = str(host.worksite.definition_snapshot()["board"])
	_position = host.definition_snapshot()["positions"][board]
	assert_false(bool(_send(host, 1, board, "settlement_audit", 888).get("ok", false)))
	assert_eq(_send(host, 1, board, "settlement_audit")["code"],
		"SETTLEMENT_ASSURANCE_AND_ROOT_REQUIRED")
	var seq: int = 2
	for action: String in ["regional_critical", "finale_assess",
		"finale_critical_verified", "finale_buffer", "finale_verify",
		"finale_signoff", "aftercare_assess", "aftercare_trip",
		"aftercare_managed", "aftercare_clear", "aftercare_release",
		"aftercare_reset", "aftercare_verify", "aftercare_signoff",
		"assurance_assess", "assurance_conserve", "assurance_trip",
		"assurance_priority", "assurance_clear", "assurance_reset",
		"assurance_verify", "assurance_signoff"]:
		var response: Dictionary = _send(host, seq, board, action)
		assert_true(bool(response.get("ok", false)), str(response) + " " + action)
		seq += 1
	assert_true(host.regional_assurance.closed())
	assert_eq(str(host._bespoke_guard(Runtime.PLAYER_ID,
		"request_extract", "ZONE_EXTRACT", {}).get("code", "")),
		"EXP015_A10_DEBT_SETTLEMENT_REQUIRED")
	assert_eq(_send(host, seq, board, "regional_recharge")["code"],
		"EXP015_A10_PROTECTED_RESERVE")
	seq += 1
	for action: String in ["settlement_audit",
		"settlement_proof:settle_dry_feeder_audit", "settlement_pay",
		"settlement_verify", "settlement_signoff"]:
		var response: Dictionary = _send(host, seq, board, action)
		assert_true(bool(response.get("ok", false)), str(response) + " " + action)
		seq += 1
	assert_true(host.regional_settlement.closed())
	assert_eq(int(host.regional_network.site_conditions()["service_debt"]), 0)
	assert_eq(str(host.task_board()["regional_settlement"]["policy"]),
		"finite_settlement")
	assert_true(host.authoritative_state().has("exp015_regional_settlement"))
	assert_true(bool(_send(host, seq - 1, board,
		"settlement_signoff").get("duplicate", false)))
	assert_false(host.completed())
	assert_eq(host.pending_rewards(account).size(), 0)
	assert_true(region_network != owned, "test fixture instances remain isolated")


func test_EXP015_A10_optout_does_not_require_source_settlement() -> void:
	assert_eq(Settlement.entry_for(Settlement.load_book(), "LV_001"), {})
	assert_eq(Settlement.entry_for(Settlement.load_book(), "LV_008")["risk_class"],
		"depth")
