extends "res://tests/test_case.gd"
## A02: 200 individual source briefings, no solution output, real UI tabs.
const Atlas := preload("res://scripts/world/dispatch_atlas.gd")
const Campaign := preload("res://scripts/progression/expedition_campaign.gd")
const Ledger := preload("res://scripts/progression/expedition_ledger.gd")
const Networks := preload("res://scripts/gameplay/expedition_regional_network.gd")
const Consequences := preload("res://scripts/progression/expedition_campaign_consequences.gd")
const Guidance := preload("res://scripts/ui/expedition_field_guidance.gd")
const OpsPanel := preload("res://scripts/ui/expedition_field_ops.gd")


func test_EXP020_A02_all_200_host_task_and_atlas_briefings_without_spoilers() -> void:
	var atlas: Dictionary = Atlas.load_catalog()
	var routes: Dictionary = Campaign.load_routes()
	var profile: Dictionary = Ledger.new_profile("EXP020_A02_READER")
	var verified: Dictionary = Consequences.evaluate(profile, atlas,
		routes, Networks.load_book())
	assert_true(bool(verified.get("ok", false)))
	for level: Dictionary in atlas["levels"]:
		var tasks: Array = []
		for task: Dictionary in level["tasks"]:
			tasks.append({"id": task["id"], "title": str(task["kind"]).capitalize(),
				"completed": false, "required": task["required"]})
		var presentation: Dictionary = Guidance.build(atlas, routes,
			str(level["id"]), {"tasks": tasks}, verified)
		assert_true(bool(presentation.get("ok", false)), str([level["id"], presentation]))
		assert_eq(int(presentation["completed_tasks"]), 0)
		assert_false(bool(presentation["solutions_exposed"]))
		assert_eq((presentation["objectives"] as Array).size(), 5)
		assert_eq((presentation["network"] as Array).size(), 8)
		assert_eq((presentation["briefing"] as Array).size(), 4)
		assert_false(JSON.stringify(presentation).contains("seepage_reentry"))


func test_EXP020_A02_forged_task_rejected_and_tablet_readonly() -> void:
	var atlas: Dictionary = Atlas.load_catalog()
	var routes: Dictionary = Campaign.load_routes()
	var proof: Dictionary = Consequences.evaluate(Ledger.new_profile("EXP020_A02_HOLD"),
		atlas, routes, Networks.load_book())
	var bad: Dictionary = Guidance.build(atlas, routes, "LV_001",
		{"tasks": [{"id":"FORGED_JOB","title":"spoiler","completed":true}]},proof)
	assert_false(bool(bad.get("ok",false)))
	var level: Dictionary = Atlas.find_level(atlas, "LV_001")
	var tasks: Array = []
	for task: Dictionary in level["tasks"]:
		tasks.append({"id":task["id"], "title":str(task["kind"]),
			"required":task["required"],"completed":false})
	var view: Dictionary = Guidance.build(atlas,routes,"LV_001",{"tasks":tasks},proof)
	var panel: OpsPanel = OpsPanel.new()
	panel.show_data(view)
	assert_eq(panel.selected_tab(),"briefing")
	assert_true(panel.current_view_text().contains("West Junction"))
	panel._select_tab("network")
	assert_eq(panel.selected_tab(),"network")
	assert_true(panel.current_view_text().contains("restored") or
		panel.current_view_text().contains("LOCKED") or
		panel.current_view_text().contains("AVAILABLE"))
	panel.show_data({})
	assert_true(panel.current_view_text().contains("unavailable"))
	panel.free()
