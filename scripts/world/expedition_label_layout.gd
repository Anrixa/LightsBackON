extends RefCounted
## Presentation-only layout for the experimental dispatch stage's world labels. Several independent layers (host targets,
## EXP014 worksites, EXP017 signs, EXP019 task anchors, EXP020 placards) each label the same station, which put about 15
## Label3D signs within 2.4 m of station 01 and stacked five of them in one column at overlapping heights.
## 1. Device labels (one per host target) are revealed only for the device under the reticle, the usual focus pattern; the
##    HUD "Target:" line already names it. Plates stay visible, so devices remain discoverable.
## 2. Every other visible label within CLUSTER_RADIUS_M of a cluster's anchor on the ground plane is re-stacked bottom-up,
##    on one shared vertical axis, so no two text boxes in a station cluster overlap from any viewing angle.
## Never touches host state, colliders, target positions or text; only Label3D.visible and Label3D positions.

const DEVICE_LABEL_NAME: String = "WorksiteLabel"
const CLUSTER_RADIUS_M: float = 1.6
const STACK_GAP_M: float = 0.08
const LINE_HEIGHT_FACTOR: float = 1.25
## A device label whose box would overlap a stacked station sign is drawn this far below its device origin instead
## (under the 0.43 m plate), where nothing else is placed.
const DEVICE_BELOW_PLATE_M: float = 0.45


## Hide every device label and re-stack shared clusters. Returns {"device_labels": n, "columns": n, "moved": n}.
static func apply(world: Node) -> Dictionary:
	# Device labels sit on their own device and show one at a time (focus reveal), so they are not stacked.
	var device: Array[Label3D] = []
	var free: Array[Label3D] = []
	for node: Node in world.find_children("*", "Label3D", true, false):
		var label: Label3D = node as Label3D
		if label.name == DEVICE_LABEL_NAME:
			device.append(label)
		elif label.is_visible_in_tree():
			free.append(label)
	var columns: Array[Array] = []
	for label: Label3D in free:
		var placed: bool = false
		for column: Array in columns:
			if _flat_distance(column[0] as Label3D, label) <= CLUSTER_RADIUS_M:
				column.append(label)
				placed = true
				break
		if not placed:
			columns.append([label])
	var moved: int = 0
	var shared: int = 0
	for column: Array in columns:
		if column.size() < 2:
			continue
		shared += 1
		column.sort_custom(func(a: Label3D, b: Label3D) -> bool: return a.global_position.y < b.global_position.y)
		# One shared vertical axis (the lowest sign's): signs at different depths overlap on screen through
		# perspective however they are spaced in height, so the cluster becomes a single readable column.
		var axis: Vector3 = (column[0] as Label3D).global_position
		var top: float = -INF
		for label: Label3D in column:
			if not is_equal_approx(label.global_position.x, axis.x) or not is_equal_approx(label.global_position.z, axis.z):
				label.global_position = Vector3(axis.x, label.global_position.y, axis.z)
				moved += 1
			var half: float = text_height_m(label) * 0.5
			var y: float = label.global_position.y
			if y - half < top + STACK_GAP_M:
				var lifted: float = top + STACK_GAP_M + half
				label.global_position.y = lifted
				y = lifted
				moved += 1
			top = y + half
	var relocated: int = 0
	for label: Label3D in device:
		for other: Label3D in free:
			if _flat_distance(label, other) <= CLUSTER_RADIUS_M and _boxes_overlap(label, other):
				label.position.y = -DEVICE_BELOW_PLATE_M
				relocated += 1
				break
		label.visible = false
	moved += relocated
	return {"device_labels": device.size(), "columns": shared, "moved": moved}


## Show only the device label of the aimed host target (empty id hides them all).
static func reveal_device(world: Node, target_id: String) -> void:
	for node: Node in world.find_children(DEVICE_LABEL_NAME, "Label3D", true, false):
		var label: Label3D = node as Label3D
		var owner_id: String = str(label.get_parent().name)
		label.visible = target_id != "" and owner_id == target_id


## Estimated world height of a label's text box (lines x font size x pixel size, with line spacing).
static func text_height_m(label: Label3D) -> float:
	var lines: int = maxi(1, label.text.count("\n") + 1)
	var scale_y: float = label.global_transform.basis.get_scale().y
	return float(lines) * float(label.font_size) * label.pixel_size * LINE_HEIGHT_FACTOR * scale_y


static func _flat_distance(a: Node3D, b: Node3D) -> float:
	return Vector2(a.global_position.x - b.global_position.x, a.global_position.z - b.global_position.z).length()


static func _boxes_overlap(a: Label3D, b: Label3D) -> bool:
	var ha: float = text_height_m(a) * 0.5
	var hb: float = text_height_m(b) * 0.5
	return absf(a.global_position.y - b.global_position.y) < ha + hb + STACK_GAP_M
