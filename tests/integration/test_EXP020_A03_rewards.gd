extends "res://tests/test_case.gd"
## EXP020 A03 duplicate and foreign task/find receipts cannot earn anything.
const Atlas := preload("res://scripts/world/dispatch_atlas.gd")
const Ledger := preload("res://scripts/progression/expedition_ledger.gd")
const Feedback := preload("res://scripts/progression/expedition_reward_feedback.gd")


func test_EXP020_A03_only_committed_host_receipts_receive_reward_feedback() -> void:
	var atlas: Dictionary = Atlas.load_catalog()
	var profile: Dictionary = Ledger.new_profile("EXP020_SCORE")
	var before: Dictionary = profile.duplicate(true)
	var level: Dictionary = Atlas.find_level(atlas,"LV_001")
	var task: Dictionary = Ledger.make_receipt("EXP020_SCORE","LV_001",
		str(level["tasks"][0]["id"]),"investigation")
	var lore: Dictionary = Ledger.make_receipt("EXP020_SCORE","LV_001",
		str(level["collectible"]["id"]),"lore")
	assert_true(bool(Ledger.apply_receipt(profile,task,atlas).get("ok",false)))
	assert_true(bool(Ledger.apply_receipt(profile,lore,atlas).get("ok",false)))
	var delta: Dictionary = Feedback.after_commit(before,profile,[task,lore],
		atlas,"EXP020_SCORE")
	assert_true(bool(delta.get("ok",false)),str(delta))
	assert_eq(int(delta["new_host_receipts"]),2)
	assert_eq(int(delta["new_task_points"]),Ledger.TASK_POINTS["investigation"])
	assert_eq(int(delta["total_collectibles"]),1)
	var reported: Dictionary = Feedback.summary(profile,"EXP020_SCORE",delta)
	assert_true(bool(reported.get("ok",false)))
	assert_true(str(reported["lines"][3]).contains("receipt"))
	var repeat: Dictionary = Feedback.after_commit(profile.duplicate(true),profile,
		[task,lore],atlas,"EXP020_SCORE")
	assert_true(bool(repeat.get("ok",false)))
	assert_eq(int(repeat["new_task_points"]),0)
	assert_eq(int(repeat["new_host_receipts"]),0)
	assert_false(bool(Ledger.apply_receipt(profile,task,atlas)["applied"]))
	assert_false(bool(Ledger.apply_receipt(profile,lore,atlas)["applied"]))


func test_EXP020_A03_tamper_foreign_and_uncommitted_rewards_fail_closed() -> void:
	var atlas: Dictionary = Atlas.load_catalog()
	var original: Dictionary = Ledger.new_profile("EXP020_SCORE")
	var level: Dictionary = Atlas.find_level(atlas,"LV_001")
	var task: Dictionary = Ledger.make_receipt("EXP020_SCORE","LV_001",
		str(level["tasks"][0]["id"]),"investigation")
	var foreign: Dictionary = Ledger.make_receipt("OTHER_SCORE","LV_001",
		str(level["tasks"][0]["id"]),"investigation")
	assert_false(bool(Feedback.after_commit(original,original,[task],
		atlas,"EXP020_SCORE").get("ok",false)))
	assert_false(bool(Feedback.after_commit(original,original,[foreign],
		atlas,"EXP020_SCORE").get("ok",false)))
	var tampered: Dictionary = task.duplicate(true)
	tampered["points"] = 200
	assert_false(bool(Feedback.after_commit(original,original,[tampered],
		atlas,"EXP020_SCORE").get("ok",false)))
	var after: Dictionary = original.duplicate(true)
	after["field_points"] = 250
	assert_false(bool(Feedback.after_commit(after,original,[],
		atlas,"EXP020_SCORE").get("ok",false)))


func test_EXP020_A03_all_200_lore_finds_pay_zero_from_original_source() -> void:
	var atlas: Dictionary = Atlas.load_catalog()
	for level: Dictionary in atlas["levels"]:
		var item: Dictionary = level["collectible"]
		var receipt: Dictionary = Ledger.make_receipt("EXP020_SCORE",
			str(level["id"]),str(item["id"]),"lore")
		assert_eq(int(receipt["points"]),0)
