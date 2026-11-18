extends Control
## EXP01: browsable design atlas, not a level launcher or a reward screen.
## All 200 briefs are visible in-game without touching campaign saves.

signal closed

const Atlas := preload("res://scripts/world/dispatch_atlas.gd")

var _data: Dictionary = {}
var _district: OptionButton
var _search: LineEdit
var _list: ItemList
var _details: RichTextLabel
var _count: Label
var _visible_levels: Array[Dictionary] = []
var _close_button: Button


func _ready() -> void:
	_data = Atlas.load_catalog()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var surface: ColorRect = ColorRect.new()
	surface.color = Color("#0C1823")
	surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(surface)

	var margin: MarginContainer = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	add_child(margin)
	var layout: VBoxContainer = VBoxContainer.new()
	layout.add_theme_constant_override("separation", 14)
	margin.add_child(layout)

	var header: HBoxContainer = HBoxContainer.new()
	layout.add_child(header)
	var title: Label = Label.new()
	title.text = "DISPATCH ATLAS  /  200 PROPOSED LEVELS"
	title.theme_type_variation = "StrongLabel"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_close_button = Button.new()
	_close_button.name = "CloseAtlasButton"
	_close_button.text = "Back to main menu"
	_close_button.custom_minimum_size = Vector2(170, 48)
	_close_button.pressed.connect(func() -> void: closed.emit())
	header.add_child(_close_button)

	var ceiling: Label = Label.new()
	ceiling.text = "DESIGN PREVIEW ONLY  •  No mission launch, collectible pickup, save change, or credit award."
	ceiling.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ceiling.add_theme_color_override("font_color", Color("#F3D396"))
	layout.add_child(ceiling)

	var halves: HSplitContainer = HSplitContainer.new()
	halves.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(halves)
	var left: VBoxContainer = VBoxContainer.new()
	left.custom_minimum_size.x = 300
	halves.add_child(left)
	_district = OptionButton.new()
	_district.name = "DistrictFilter"
	_district.custom_minimum_size.y = 46
	_district.add_item("All 25 regions")
	_district.set_item_metadata(0, "")
	for region: Dictionary in _data.get("regions", []):
		_district.add_item(str(region.get("name", "")))
		_district.set_item_metadata(_district.item_count - 1, str(region.get("id", "")))
	left.add_child(_district)
	_district.item_selected.connect(func(_index: int) -> void: _refresh())
	_search = LineEdit.new()
	_search.name = "DispatchSearch"
	_search.placeholder_text = "Search level, location or story"
	_search.custom_minimum_size.y = 46
	_search.text_changed.connect(func(_value: String) -> void: _refresh())
	left.add_child(_search)
	_count = Label.new()
	left.add_child(_count)
	_list = ItemList.new()
	_list.name = "LevelList"
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.allow_reselect = true
	_list.item_selected.connect(_describe)
	left.add_child(_list)

	_details = RichTextLabel.new()
	_details.name = "LevelDetails"
	_details.selection_enabled = true
	_details.scroll_active = true
	_details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_details.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_details.bbcode_enabled = false
	halves.add_child(_details)

	var report: Dictionary = Atlas.inspect(_data)
	if not report["ok"]:
		_count.text = "Atlas source validation failed"
		_details.text = "This atlas has been disabled because its content did not pass validation.\n%s" % str(report["failures"])
		_district.disabled = true
		_search.editable = false
		_list.visible = false
		return
	_refresh()
	_close_button.grab_focus()


func _refresh() -> void:
	if _list == null or _district == null:
		return
	var region_id: String = str(_district.get_item_metadata(_district.selected))
	_visible_levels = Atlas.search_levels(_data, region_id, _search.text)
	_list.clear()
	for level: Dictionary in _visible_levels:
		_list.add_item("%s  %s" % [level["id"], level["title"]])
	_count.text = "%d levels  /  %d planned objectives" % [
		_visible_levels.size(), _visible_levels.size() * 5]
	if _visible_levels.is_empty():
		_details.text = "No dispatch matches these filters."
		return
	_list.select(0)
	_describe(0)


func _describe(index: int) -> void:
	if index < 0 or index >= _visible_levels.size():
		return
	var level: Dictionary = _visible_levels[index]
	var location: Dictionary = Atlas.find_location(_data, str(level["location_id"]))
	var lines: Array[String] = [
		str(level["title"]), "",
		"LOCATION  •  " + str(location.get("name", "")),
		"LANDMARK  •  " + str(location.get("hero_prop", "")),
		"WEATHER  •  " + str(location.get("environment", "")),
		"HAZARD  •  " + str(level.get("hazard", "")),
		"",
		str(level.get("mission_hook", "")),
		"",
		"FIVE PLANNED OBJECTIVES  (four required / one optional)", ""
	]
	for task: Dictionary in level["tasks"]:
		var extra: String = "  [OPTIONAL]" if not bool(task["required"]) else ""
		lines.append("%d. %s%s" % [int(task["ordinal"]), str(task["title"]), extra])
		lines.append("   " + str(task["briefing"]))
		lines.append("   Puzzle mechanism: %s  •  Concept points: %d" % [
			str(task["mechanic"]), int(task["field_points_preview"])])
		lines.append("")
	var find: Dictionary = level["collectible"]
	lines.append("PLANNED STORY COLLECTIBLE")
	lines.append(str(find["name"]) + "  /  " + str(find["set"]))
	lines.append("This is not yet an in-game pickup or a credit-bearing item.")
	lines.append("")
	lines.append("Concept points for all five objectives: %d (NOT real rewards)" % Atlas.preview_points(level))
	lines.append("STATUS  •  Design briefing only; no gameplay or playability certification")
	_details.text = "\n".join(lines)
	_details.scroll_to_line(0)


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		closed.emit()
