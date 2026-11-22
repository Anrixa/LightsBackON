extends "res://tests/test_case.gd"
## EXP020 A04 25/200/1000 exact source narrative and host evidence gating.
const Atlas := preload("res://scripts/world/dispatch_atlas.gd")
const Campaign := preload("res://scripts/progression/expedition_campaign.gd")
const Networks := preload("res://scripts/gameplay/expedition_regional_network.gd")
const Story := preload("res://scripts/gameplay/expedition_story_workorders.gd")


func test_EXP020_A04_all_original_regions_work_orders_and_host_finds() -> void:
	var atlas: Dictionary = Atlas.load_catalog()
	var book: Dictionary = Story.load_book()
	var gate: Dictionary = Story.inspect(atlas,Campaign.load_routes(),
		Networks.load_book(),book)
	assert_true(bool(gate.get("ok",false)),str(gate))
	assert_eq(int(gate["work_orders"]),200)
	assert_eq(int(gate["source_task_ids"]),1000)
	var titles: Dictionary = {}
	for level: Dictionary in atlas["levels"]:
		var tasks: Array = []
		for job: Dictionary in level["tasks"]:
			tasks.append({"id":job["id"],"completed":false})
		var cold: Dictionary = Story.compose(book,atlas,str(level["id"]),
			{"tasks":tasks,"lore_collected":false})
		assert_true(bool(cold.get("ok",false)),str([level["id"],cold]))
		assert_false(bool(cold["found"]))
		assert_false(JSON.stringify(cold).contains(str(level["collectible"]["name"])))
		assert_false(titles.has(str(cold["headline"])))
		titles[str(cold["headline"])] = true
		tasks[0]["completed"] = true
		var observed: Dictionary = Story.compose(book,atlas,str(level["id"]),
			{"tasks":tasks,"lore_collected":true})
		assert_true(bool(observed.get("ok",false)))
		assert_eq(int(observed["verified_tasks"]),1)
		assert_true(JSON.stringify(observed).contains(str(level["collectible"]["name"])))


func test_EXP020_A04_misbound_site_and_unverified_job_fail_closed() -> void:
	var atlas: Dictionary = Atlas.load_catalog()
	var book: Dictionary = Story.load_book()
	var wrong: Dictionary = book.duplicate(true)
	wrong["work_orders"][0]["optional_find_id"] = "FIND_999"
	assert_false(bool(Story.inspect(atlas,Campaign.load_routes(),
		Networks.load_book(),wrong).get("ok",false)))
	assert_false(bool(Story.compose(book,atlas,"LV_001",
		{"tasks":[{"id":"JOB_FORGED","completed":true}]}
		).get("ok",false)))
