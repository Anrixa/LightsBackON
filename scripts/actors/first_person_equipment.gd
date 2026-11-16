extends Node3D
## DS14: camera-local first-person presentation. Hands and tools are visual-only,
## not raycast targets or game actions. The existing controller still owns input.
## UI/accessibility settings may stop camera bob without changing this model.

const HeroProps := preload("res://scripts/world/hero_prop_builder.gd")
const TOOLS: Array[String] = ["meter", "screwdriver", "puller", "cutter", "crimper"]

var _tools: Dictionary = {}
var _hands: Node3D
var _tool_mount: Node3D
var _selected: String = ""
var _carrying: bool = false


func _ready() -> void:
	var art: HeroProps = HeroProps.new()
	var config: Dictionary = art.configuration()
	var v: Dictionary = config.get("view", {})
	var offset: Array = v.get("offset_m", [0.28, -0.29, -0.60])
	position = Vector3(float(offset[0]), float(offset[1]), float(offset[2]))
	_hands = art.build_hands()
	add_child(_hands)
	_tool_mount = Node3D.new()
	_tool_mount.name = "ActiveToolMount"
	var tool_offset: Array = v.get("tool_offset_m", [0.0, 0.12, -0.17])
	_tool_mount.position = Vector3(float(tool_offset[0]), float(tool_offset[1]), float(tool_offset[2]))
	_tool_mount.rotation_degrees = Vector3(-12, 0, -12)
	add_child(_tool_mount)
	for name: String in TOOLS:
		var model: Node3D = art.build_tool(name)
		model.visible = false
		_tool_mount.add_child(model)
		_tools[name] = model
	select_tool("meter")


func select_tool(tool_id: String) -> void:
	if not _tools.has(tool_id):
		# Never display a different tool for an unknown gameplay ID.
		_selected = ""
	else:
		_selected = tool_id
	for id: String in _tools:
		(_tools[id] as Node3D).visible = id == _selected and not _carrying


func set_carrying(carried: bool) -> void:
	if carried == _carrying:
		return
	_carrying = carried
	for id: String in _tools:
		(_tools[id] as Node3D).visible = id == _selected and not _carrying
	# Hands stay visible when the portable generator is being carried.


func current_tool() -> String:
	return _selected


func tool_model(id: String) -> Node3D:
	return _tools.get(id) as Node3D


func carrying() -> bool:
	return _carrying
