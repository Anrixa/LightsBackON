extends "res://tests/test_case.gd"
## Dispatch-stage label declutter: station signs from independent layers must not overlap, and per-device labels
## appear only for the aimed device. Presentation only; host state is not inspected or changed here.
const Stage := preload("res://scenes/expeditions/mission_stage.tscn")
const Layout := preload("res://scripts/world/expedition_label_layout.gd")


func _with_stage(level_id: String, check: Callable) -> void:
	var holder: Node3D = Node3D.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(holder)
	var stage: Node3D = Stage.instantiate()
	stage.set("level_id", level_id)
	holder.add_child(stage)
	var world: Node3D = stage.get_node_or_null("ExpeditionWorld") as Node3D
	assert_true(world != null, "%s: ExpeditionWorld missing" % level_id)
	if world != null:
		check.call(stage, world)
	holder.remove_child(stage)
	stage.free()
	holder.get_parent().remove_child(holder)
	holder.free()


func _visible_free_labels(world: Node3D) -> Array[Label3D]:
	var out: Array[Label3D] = []
	for node: Node in world.find_children("*", "Label3D", true, false):
		var label: Label3D = node as Label3D
		if label.name != Layout.DEVICE_LABEL_NAME and label.is_visible_in_tree():
			out.append(label)
	return out


func test_EXP_DECLUTTER_station_signs_share_a_column_without_overlap() -> void:
	for level_id: String in ["LV_001", "LV_077", "LV_200"]:
		_with_stage(level_id, func(stage: Node3D, world: Node3D) -> void:
			var report: Dictionary = stage.get_meta("label_layout", {})
			assert_true(int(report.get("device_labels", 0)) > 0, "%s: no device labels found" % level_id)
			assert_true(int(report.get("columns", 0)) > 0, "%s: no shared sign cluster found" % level_id)
			var labels: Array[Label3D] = _visible_free_labels(world)
			for i: int in labels.size():
				for j: int in range(i + 1, labels.size()):
					var a: Label3D = labels[i]
					var b: Label3D = labels[j]
					var flat: float = Vector2(a.global_position.x - b.global_position.x,
						a.global_position.z - b.global_position.z).length()
					if flat > Layout.CLUSTER_RADIUS_M:
						continue
					# Within one cluster: one vertical axis and disjoint text boxes.
					assert_true(flat < 0.001, "%s: %s and %s are clustered but off-axis (%.3f m)" % [
						level_id, a.text, b.text, flat])
					var gap: float = absf(a.global_position.y - b.global_position.y) \
						- (Layout.text_height_m(a) + Layout.text_height_m(b)) * 0.5
					assert_true(gap >= Layout.STACK_GAP_M - 0.001, "%s: '%s' overlaps '%s' (gap %.3f m)" % [
						level_id, a.text, b.text, gap]))


func test_EXP_DECLUTTER_device_labels_reveal_only_the_aimed_device() -> void:
	_with_stage("LV_077", func(_stage: Node3D, world: Node3D) -> void:
		var device: Array[Node] = world.find_children(Layout.DEVICE_LABEL_NAME, "Label3D", true, false)
		assert_true(device.size() >= 2)
		for node: Node in device:
			assert_false((node as Label3D).visible, "device label visible before any aim")
		var target: String = str(device[1].get_parent().name)
		Layout.reveal_device(world, target)
		var shown: Array[String] = []
		for node: Node in device:
			if (node as Label3D).visible:
				shown.append(str(node.get_parent().name))
		assert_eq(shown, [target])
		Layout.reveal_device(world, "")
		for node: Node in device:
			assert_false((node as Label3D).visible, "empty target must hide every device label"))
