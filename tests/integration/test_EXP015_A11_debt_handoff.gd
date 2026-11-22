extends "res://tests/test_case.gd"
## EXP015 A11: 100 original cold-root -> finale source-only transactions.
## One same A09 process-local network, NO production save/reward/play claims.
const Atlas := preload("res://scripts/world/dispatch_atlas.gd")
const Ledger := preload("res://scripts/progression/expedition_ledger.gd")
const Network := preload("res://scripts/gameplay/expedition_regional_network.gd")
const Entry := preload("res://scripts/gameplay/expedition_regional_entry_commissioning.gd")
const Settlement := preload("res://scripts/gameplay/expedition_regional_debt_settlement.gd")

const PREVIOUS_SPINE: Array[int] = [1, 3, 4, 6, 7, 8]


func before_each() -> void:
	Network.clear_host_memory_for_test()


func after_each() -> void:
	Network.clear_host_memory_for_test()


func _restore(atlas: Dictionary, profile: Dictionary, index: int) -> void:
	var site: String = "LV_%03d" % index
	var level: Dictionary = Atlas.find_level(atlas, site)
	var receipt: Dictionary = Ledger.make_receipt(
		str(profile["account_key"]), site, str(level["tasks"][4]["id"]),
		"restoration")
	assert_true(bool(Ledger.apply_receipt(profile, receipt, atlas).get("applied", false)),
		"A11 ephemeral EXP04 fixture, NOT gameplay restoration")


func _profile(atlas: Dictionary, region: int, account: String) -> Dictionary:
	var profile: Dictionary = Ledger.new_profile(account)
	for previous: int in range(region):
		for offset: int in PREVIOUS_SPINE:
			_restore(atlas, profile, previous * 8 + offset)
	return profile


func _restore_original_anchor_ancestors(atlas: Dictionary,
		profile: Dictionary, region: int) -> void:
	# An original anchor may lie behind an alternate slot-5 feeder.
	# Preserve the real rooted tree; do not fabricate an energized anchor.
	var root: String = "LV_%03d" % (region * 8 + 1)
	var source: Dictionary = Network.entry_for(Network.load_book(), root)
	assert_false(source.is_empty(), "original source network required")
	if source.is_empty():
		return
	var incoming: Dictionary = {}
	for edge: Dictionary in source["primary_feeders"]:
		incoming[str(edge["to"])] = str(edge["from"])
	var cursor: String = str(source["reserve_anchor_site"])
	var route: Array[String] = []
	var visited: Dictionary = {}
	while cursor != root:
		assert_true(incoming.has(cursor) and not visited.has(cursor),
			"original reserve anchor must be reachable in the primary tree")
		if not incoming.has(cursor) or visited.has(cursor):
			return
		visited[cursor] = true
		route.append(cursor)
		cursor = str(incoming[cursor])
	route.reverse()
	for site: String in route:
		var index: int = site.trim_prefix("LV_").to_int()
		var slot: int = index - region * 8
		if slot not in [1, 2, 3, 4, 6, 7]:
			_restore(atlas, profile, index)


func _replay(region: int, branch: String, policy: String) -> bool:
	var atlas: Dictionary = Atlas.load_catalog()
	var account: String = "a11_source_%02d_%s_%s" % [region + 1, branch, policy]
	var profile: Dictionary = _profile(atlas, region, account)
	var root: String = "LV_%03d" % (8 * region + 1)
	var network: Network = Network.new()
	var configured: Dictionary = network.configure(atlas, profile, root)
	assert_true(bool(configured.get("ok", false)), str(configured))
	if not bool(configured.get("ok", false)):
		return false
	var original: Dictionary = Entry.entry_for(Entry.load_book(), root)
	var controller: Entry = Entry.new()
	assert_true(bool(controller.configure(original, network).get("ok", false)))
	var initial: int = int(network.snapshot()["reserve_pu"])
	assert_eq(int(network.site_conditions()["service_debt"]), 0)
	for action: String in ["entry_survey", "entry_isolate",
		"entry_critical" if branch == "critical" else "entry_transport",
		"entry_contain:" + str(original["entry_risk_proof"]),
		"entry_buffer" if policy == "buffer" else "entry_managed",
		"entry_unblock", "entry_verify", "entry_signoff"]:
		var reply: Dictionary = controller.operate(action)
		assert_true(bool(reply.get("ok", false)), str(reply) + " " + action)
	assert_true(controller.closed())
	assert_false(bool(network.snapshot()["sites"][root]["restored"]))
	assert_eq(int(network.snapshot()["reserve_pu"]),
		initial - (2 if policy == "buffer" else 0))
	assert_eq(int(network.site_conditions()["service_debt"]),
		2 if policy == "managed" else 0)
	var original_events: Array = network.snapshot()["events"]
	assert_eq(original_events.filter(func(e: Dictionary) -> bool:
		return str(e["action"]) == ("commit_entry_buffer" if policy == "buffer"
			else "commit_entry_debt")).size(), 1)
	# Do not claim a real player restored the region: source fixtures only.
	# Both original A09 first routes must be complete for the joined evidence.
	for offset: int in [1, 2, 3, 4, 6, 7]:
		_restore(atlas, profile, 8 * region + offset)
	_restore_original_anchor_ancestors(atlas, profile, region)
	var finale: String = "LV_%03d" % (8 * region + 8)
	var joined: Dictionary = network.attach_site(atlas, profile, finale)
	assert_true(bool(joined.get("ok", false)), str(joined))
	if not bool(joined.get("ok", false)):
		return false
	var after: Dictionary = network.snapshot()
	assert_eq(str(after["level_id"]), finale)
	assert_eq(int(after["reserve_pu"]),
		initial - (2 if policy == "buffer" else 0))
	assert_eq(int(network.site_conditions()["service_debt"]),
		2 if policy == "managed" else 0)
	assert_eq(after["events"].size(), original_events.size())
	var final_source: Dictionary = Settlement.entry_for(
		Settlement.load_book(), finale)
	assert_eq(str(final_source["root_source_site_id"]), root)
	assert_eq(str(final_source["region_id"]), str(after["region_id"]))
	var anchor: String = str(final_source["reserve_anchor_site_id"])
	assert_true(bool(after["sites"][anchor]["restored"]))
	assert_true(bool(after["sites"][anchor]["energized"]))
	if policy == "managed":
		var paid: Dictionary = network.host_transition("retire_service_debt", anchor)
		assert_true(bool(paid.get("ok", false)), str(paid))
		assert_eq(int(network.snapshot()["reserve_pu"]), initial - 2)
		assert_eq(int(network.site_conditions()["service_debt"]), 0)
		var spent_once: Dictionary = network.snapshot()
		assert_eq(str(network.host_transition("retire_service_debt", anchor)["code"]),
			"DEBT_SETTLEMENT_SOURCE_OR_RESERVE_DENIED")
		assert_eq(network.snapshot(), spent_once, "duplicate settlement is side-effect-free")
	else:
		assert_eq(str(network.host_transition("retire_service_debt", anchor)["code"]),
			"DEBT_SETTLEMENT_SOURCE_OR_RESERVE_DENIED")
		assert_eq(int(network.snapshot()["reserve_pu"]), initial - 2)
	# Both finite paths end at same actual resource balance, with no debts
	# invented or silently erased at an unrelated dispatch.
	assert_eq(int(network.site_conditions()["service_debt"]), 0)
	assert_eq(int(network.snapshot()["reserve_pu"]), initial - 2)
	return true


func test_EXP015_A11_100_original_root_to_finale_receipt_provenance() -> void:
	var total: int = 0
	for region: int in range(25):
		for branch: String in ["critical", "transport"]:
			for policy: String in ["buffer", "managed"]:
				if _replay(region, branch, policy):
					total += 1
					print("EXP015_A11_CROSS_DISPATCH region=%02d first=%s reserve=%s VERIFIED_SOURCE_ONLY" %
						[region + 1, branch, policy])
	assert_eq(total, 100)
