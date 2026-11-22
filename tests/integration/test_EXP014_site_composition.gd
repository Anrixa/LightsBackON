extends "res://tests/test_case.gd"
## EXP014 A01 source/headless composition. No navigation, collision or human
## playability assertion is made by these tests.

const Atlas := preload("res://scripts/world/dispatch_atlas.gd")
const Worksite := preload("res://scripts/gameplay/expedition_worksite_orders.gd")
const SiteA02 := preload("res://scripts/gameplay/expedition_site_interventions.gd")
const SiteEXP013 := preload("res://scripts/gameplay/expedition_site_exp013.gd")
const Composition := preload("res://scripts/world/expedition_site_composition.gd")
const Runtime := preload("res://scripts/gameplay/expedition_host_session.gd")


func _host_position(_player: String) -> Vector3:
	return Vector3(35.0, 0.9, 35.0)


func _cases() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry: Dictionary in SiteA02.load_book()["entries"]:
		result.append(entry)
	for book: Dictionary in SiteEXP013.load_available_books():
		for entry: Dictionary in book["entries"]:
			result.append(entry)
	return result


func _fixtures(entry: Dictionary) -> Dictionary:
	# Fixed schematic host anchors in a source-only unit fixture; integration
	# tests below separately bind to the real Runtime._definitions positions.
	var a: Vector3 = Vector3(10.0, 1.0, 12.0)
	var b: Vector3 = Vector3(22.0, 1.0, 18.0)
	var c: Vector3 = Vector3(17.0, 1.0, 28.0)
	if entry.has("station_offsets_cm"):
		var cm: Dictionary = entry["station_offsets_cm"]
		a += Vector3(float(cm["A"][0]) / 100.0, 0.0, float(cm["A"][1]) / 100.0)
		b += Vector3(float(cm["B"][0]) / 100.0, 0.0, float(cm["B"][1]) / 100.0)
		c += Vector3(float(cm["C"][0]) / 100.0, 0.0, float(cm["C"][1]) / 100.0)
	return {
		str(entry["targets"]["A"]): a,
		str(entry["targets"]["B"]): b,
		str(entry["targets"]["C"]): c}


func _no_collider(node: Node) -> bool:
	if node is CollisionObject3D or node is CollisionShape3D:
		return false
	for child: Node in node.get_children():
		if not _no_collider(child):
			return false
	return true


func test_EXP014_source_composition_all_200_cases_and_400_route_graphs() -> void:
	var atlas: Dictionary = Atlas.load_catalog()
	assert_true(bool(Atlas.inspect(atlas).get("ok", false)))
	var cases: Array[Dictionary] = _cases()
	assert_eq(cases.size(), 200)
	var fingerprints: Dictionary = {}
	for index: int in range(cases.size()):
		var entry: Dictionary = cases[index]
		assert_eq(str(entry["level_id"]), "LV_%03d" % (index + 1))
		var positions: Dictionary = _fixtures(entry)
		var audit: Dictionary = Composition.inspect(entry, positions)
		assert_true(bool(audit.get("ok", false)),
			"%s composition: %s" % [str(entry["level_id"]), str(audit)])
		if not bool(audit.get("ok", false)):
			continue
		assert_eq(int(audit["target_count"]), 3)
		assert_eq(int(audit["routes"]), 2)
		assert_eq(int(audit["operations"]), 8)
		assert_false(fingerprints.has(audit["fingerprint"]),
			"Composition fingerprint reused: " + str(entry["level_id"]))
		fingerprints[audit["fingerprint"]] = true
		var unit: Node3D = Composition.build(entry, positions)
		assert_true(unit != null, "Build failed: " + str(entry["level_id"]))
		if unit == null:
			continue
		assert_true(_no_collider(unit), "EXP014 added unauthorized physics")
		assert_eq(str(unit.get_meta("source_level_id")), str(entry["level_id"]))
		assert_true(bool(unit.get_meta("presentation_only")))
		for letter: String in ["A", "B", "C"]:
			var station: Node3D = unit.get_node("Assemblies/Station_" + letter) as Node3D
			assert_eq(station.position, positions[str(entry["targets"][letter])])
		for route: String in ["priority", "resilience"]:
			for step_index: int in range(4):
				var path: MeshInstance3D = unit.get_node(
					"Procedures/%s/Operation_%d" % [route, step_index]) as MeshInstance3D
				var expected: Dictionary = entry["routes"][route][step_index]
				assert_eq(str(path.get_meta("source_mode")), str(expected["mode"]))
				assert_eq(str(path.get_meta("source_action")), str(expected["action"]))
		unit.free()
	assert_eq(fingerprints.size(), 200)


func test_EXP014_presenter_tracks_real_host_steps_and_recovery_without_writes() -> void:
	var entry: Dictionary = _cases()[100]
	var positions: Dictionary = _fixtures(entry)
	var site: SiteA02 = SiteA02.new()
	assert_true(bool(site.configure(entry).get("ok", false)))
	var view: Node3D = Composition.build(entry, positions)
	assert_true(view != null)
	if view == null:
		return
	var facts: Dictionary = {"worksite_opened": true, "worksite_route": "priority",
		"balancing_solved": true, "logistics_solved": true,
		"consequences_solved": true, "faults_solved": true,
		"west_restored": true, "east_on": true, "hazard_active": false}
	var unchanged: Dictionary = site.snapshot()
	Composition.reflect(view, unchanged)
	assert_eq(site.snapshot(), unchanged, "Presentation mutated host state")
	assert_true(bool(site.choose_route("priority").get("ok", false)))
	var chosen: Dictionary = site.snapshot()
	Composition.reflect(view, chosen)
	assert_false((view.get_node("Procedures/resilience") as Node3D).visible)
	var segment: MeshInstance3D = view.get_node(
		"Procedures/priority/Operation_0") as MeshInstance3D
	assert_eq(str(segment.get_meta("visual_status")), "active")
	var initial: Dictionary = chosen["next"]
	assert_true(bool(site.operate(str(initial["target"]),
		str(initial["action"]), facts).get("ok", false)))
	# An early commit creates an actual host fault requiring station C.
	var refused: Dictionary = site.operate(str(initial["target"]), "confirm", facts)
	assert_false(bool(refused.get("ok", true)))
	var faulted: Dictionary = site.snapshot()
	Composition.reflect(view, faulted)
	assert_eq(str(segment.get_meta("visual_status")), "fault")
	assert_eq(str((view.get_node("ProcedureStatus") as Label3D).text),
		"SITE FAULT / RECOVER AT STATION C")
	assert_true(bool(site.operate(str(entry["recovery_target"]),
		"recover", facts).get("ok", false)))
	var reset: Dictionary = site.snapshot()
	Composition.reflect(view, reset)
	assert_eq(str(segment.get_meta("visual_status")), "active")
	assert_eq(site.snapshot(), reset, "Reflect must never advance a host tick")
	view.free()


func test_EXP014_negative_splices_and_out_of_bounds_are_fail_closed() -> void:
	var entry: Dictionary = _cases()[1]
	var positions: Dictionary = _fixtures(entry)
	assert_true(bool(Composition.inspect(entry, positions)["ok"]))
	var mutated: Dictionary = positions.duplicate(true)
	mutated.erase(str(entry["targets"]["A"]))
	assert_eq(str(Composition.inspect(entry, mutated)["code"]),
		"EXP014_MISSING_HOST_TARGET")
	mutated = positions.duplicate(true)
	mutated[str(entry["targets"]["B"])] = Vector3(85.0, 0.0, 6.0)
	assert_eq(str(Composition.inspect(entry, mutated)["code"]),
		"EXP014_TARGET_OUTSIDE_TILE")
	var tampered: Dictionary = entry.duplicate(true)
	tampered["recovery_target"] = str(entry["targets"]["A"])
	assert_eq(str(Composition.inspect(tampered, positions)["code"]),
		"EXP014_RECOVERY_TARGET_DRIFT")
	tampered = entry.duplicate(true)
	tampered["routes"]["resilience"] = tampered["routes"]["priority"].duplicate(true)
	assert_eq(str(Composition.inspect(tampered, positions)["code"]),
		"EXP014_DUPLICATE_STRATEGIES")
	tampered = entry.duplicate(true)
	tampered["routes"]["priority"][0]["target"] = "FORGED_INTERACTABLE"
	assert_eq(str(Composition.inspect(tampered, positions)["code"]),
		"EXP014_UNBOUND_OPERATION")


func test_EXP014_real_runtime_host_positions_bind_all_source_ranges() -> void:
	for number: int in [1, 40, 41, 80, 81, 120, 121, 160, 161, 200]:
		var runtime: Runtime = Runtime.new()
		var start: Dictionary = runtime.start("LV_%03d" % number,
			Callable(self, "_host_position"), Callable(),
			"", false, "", true, true, true, true, true, true, true, true, true)
		assert_true(bool(start.get("ok", false)), str(start))
		if not bool(start.get("ok", false)):
			continue
		var engine: Variant = runtime.site_a02 if runtime.site_a02 != null else runtime.site_exp013
		assert_true(engine != null, "Missing source case at level %d" % number)
		if engine == null:
			continue
		var original_positions: Dictionary = runtime.definition_snapshot()["positions"]
		var spec: Dictionary = engine.definition_snapshot()
		var result: Dictionary = Composition.inspect(spec, original_positions)
		assert_true(bool(result.get("ok", false)),
			"Host positions at level %d: %s" % [number, str(result)])
		if bool(result.get("ok", false)):
			var node: Node3D = Composition.build(spec, original_positions)
			assert_true(node != null)
			if node != null:
				assert_true(_no_collider(node))
				node.free()
