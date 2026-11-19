extends Control
## EXP01: browsable design atlas, not a level launcher or a reward screen.
## All 200 briefs are visible in-game without touching campaign saves.

signal closed
signal mission_requested(level_id: String)

const Atlas := preload("res://scripts/world/dispatch_atlas.gd")
const LayoutPlan := preload("res://scripts/world/expedition_layout_plan.gd")
const Graybox := preload("res://scripts/world/expedition_graybox.gd")
const Ledger := preload("res://scripts/progression/expedition_ledger.gd")
const Campaign := preload("res://scripts/progression/expedition_campaign.gd")
const Saves := preload("res://scripts/persistence/save_service.gd")
const OfflinePersistence := preload("res://scripts/persistence/offline_persistence.gd")
const ContentHash := preload("res://scripts/network/content_hash.gd")

var account_key: String = ""  # assigned by MainMenu before entering scene tree
var _data: Dictionary = {}
var _field_profile: Dictionary = {}
var _field_profile_error: String = ""
var _campaign_board: Dictionary = {}
var _campaign_error: String = ""
var _status_filter: OptionButton
var _district: OptionButton
var _search: LineEdit
var _list: ItemList
var _details: RichTextLabel
var _count: Label
var _visible_levels: Array[Dictionary] = []
var _close_button: Button
var _mission_button: Button
var _preview_viewport: SubViewport
var _preview_root: Node3D
var _preview_world: Node3D


func _ready() -> void:
	_data = Atlas.load_catalog()
	# The atlas reads the experimental ledger only. No C01 legacy reward
	# profile is loaded, rewritten or upgraded by opening this browser.
	if account_key != "":
		var saves: Saves = Saves.new()
		saves.configure(1, OfflinePersistence.SAVE_BUILD_ID,
			ContentHash.content_revision(), ContentHash.rules_revision())
		var loaded: Dictionary = Ledger.load_profile(saves, account_key,
			OfflinePersistence.runtime_root())
		if loaded.get("ok", false):
			_field_profile = loaded["profile"]
		else:
			_field_profile_error = str(loaded.get("code", "UNKNOWN_FIELD_PROFILE"))
	# EXP05 restores are derived from saved EXP04 receipts. Browsing never
	# grants unlocks, applies inbox entries, or changes the original profile.
	var view_profile: Dictionary = _field_profile
	if account_key == "":
		view_profile = Ledger.new_profile("exp05_guest_preview")
	if _field_profile_error == "":
		_campaign_board = Campaign.evaluate(view_profile, _data, Campaign.load_routes())
		if not bool(_campaign_board.get("ok", false)):
			_campaign_error = str(_campaign_board.get("code", "BAD_CAMPAIGN"))
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
	ceiling.text = "Browsing is read-only. EXP04 missions are opt-in, experimental and save separate lore finds / non-spendable field points; C01 credits are unchanged. No playability certification."
	ceiling.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ceiling.add_theme_color_override("font_color", Color("#F3D396"))
	layout.add_child(ceiling)
	var collection: Label = Label.new()
	collection.name = "ExpeditionCollectionSummary"
	collection.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if _field_profile_error != "":
		collection.text = "FIELD COLLECTION HOLD • unreadable expedition profile: " + _field_profile_error
	elif _field_profile.is_empty():
		collection.text = "FIELD COLLECTION • existing local identity not available"
	else:
		collection.text = "FIELD COLLECTION • %d / %d lore finds  •  %d / %d levels restored  •  %d / %d field points" % [
			(_field_profile["lore_finds"] as Dictionary).size(), Ledger.MAX_FINDS,
			(_field_profile["completed_levels"] as Dictionary).size(), Ledger.MAX_LEVELS,
			int(_field_profile["field_points"]), Ledger.MAX_FIELD_POINTS]
	layout.add_child(collection)
	var campaign_summary: Label = Label.new()
	campaign_summary.name = "CampaignProgressionSummary"
	campaign_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if _field_profile_error != "" or _campaign_error != "":
		campaign_summary.text = "EXP05 CAMPAIGN HOLD: " + (
			_field_profile_error if _field_profile_error != "" else _campaign_error)
	elif account_key == "":
		campaign_summary.text = "EXP05 • Guest preview only; no saved regional unlocks or field points"
	else:
		campaign_summary.text = "EXP05 • %d / 200 restored  •  %d available  •  %d locked  •  %d / 25 regions cleared" % [
			int(_campaign_board["restored"]), int(_campaign_board["available"]),
			int(_campaign_board["locked"]), int(_campaign_board["cleared_regions"])]
	layout.add_child(campaign_summary)

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
	_status_filter = OptionButton.new()
	_status_filter.name = "CampaignStatusFilter"
	_status_filter.custom_minimum_size.y = 42
	for label_text: String in ["All campaign levels", "Available", "Restored", "Locked"]:
		_status_filter.add_item(label_text)
	left.add_child(_status_filter)
	_status_filter.item_selected.connect(func(_index: int) -> void: _refresh())
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

	# EXP02 one-at-a-time original 3D graybox preview. Geometry is schematic,
	# never an actionable mission scene or a human/player route claim.
	var right: VBoxContainer = VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	halves.add_child(right)
	var viewport_frame: SubViewportContainer = SubViewportContainer.new()
	viewport_frame.name = "SchematicViewportContainer"
	viewport_frame.custom_minimum_size = Vector2(360.0, 220.0)
	viewport_frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	viewport_frame.stretch = true
	right.add_child(viewport_frame)
	_preview_viewport = SubViewport.new()
	_preview_viewport.name = "SchematicViewport"
	_preview_viewport.size = Vector2i(720, 320)
	_preview_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	viewport_frame.add_child(_preview_viewport)
	_preview_root = Node3D.new()
	_preview_root.name = "SchematicStage"
	_preview_viewport.add_child(_preview_root)
	var camera: Camera3D = Camera3D.new()
	camera.name = "SchematicCamera"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 78.0
	camera.position = Vector3(26.0, 58.0, 76.0)
	_preview_root.add_child(camera)
	camera.look_at(Vector3(26.0, 0.0, 26.0))
	camera.current = true
	var light: DirectionalLight3D = DirectionalLight3D.new()
	light.name = "SchematicLight"
	light.rotation_degrees = Vector3(-55.0, -35.0, 0.0)
	_preview_root.add_child(light)
	var preview_note: Label = Label.new()
	preview_note.text = "EXP02 graybox — EXP04 host mission and lore pickups are experimental; no physical qualification"
	preview_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(preview_note)
	_mission_button = Button.new()
	_mission_button.name = "LaunchExperimentalMission"
	_mission_button.text = "Enter experimental dispatch (lore and field points; playability untested)"
	_mission_button.custom_minimum_size.y = 48
	_mission_button.pressed.connect(_request_mission)
	right.add_child(_mission_button)
	_details = RichTextLabel.new()
	_details.name = "LevelDetails"
	_details.selection_enabled = true
	_details.scroll_active = true
	_details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_details.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_details.bbcode_enabled = false
	right.add_child(_details)

	var report: Dictionary = Atlas.inspect(_data)
	if not report["ok"]:
		_count.text = "Atlas source validation failed"
		_details.text = "This atlas has been disabled because its content did not pass validation.\n%s" % str(report["failures"])
		_district.disabled = true
		_search.editable = false
		_list.visible = false
		_mission_button.disabled = true
		return
	_refresh()
	_close_button.grab_focus()


func _refresh() -> void:
	if _list == null or _district == null:
		return
	var region_id: String = str(_district.get_item_metadata(_district.selected))
	var candidates: Array[Dictionary] = Atlas.search_levels(_data, region_id, _search.text)
	_visible_levels.clear()
	var filter: int = _status_filter.selected if _status_filter != null else 0
	var states: Dictionary = _campaign_board.get("states", {})
	for level: Dictionary in candidates:
		var id: String = str(level["id"])
		var status: String = str((states.get(id, {}) as Dictionary).get("status", "LOCKED"))
		if filter == 1 and status != "AVAILABLE":
			continue
		if filter == 2 and status != "RESTORED":
			continue
		if filter == 3 and status != "LOCKED":
			continue
		_visible_levels.append(level)
	_list.clear()
	for level: Dictionary in _visible_levels:
		var id: String = str(level["id"])
		var status: String = str((states.get(id, {}) as Dictionary).get("status", "PREVIEW"))
		_list.add_item("[%s]  %s  %s" % [status, id, level["title"]])
	_count.text = "%d levels  /  %d planned objectives" % [
		_visible_levels.size(), _visible_levels.size() * 5]
	if _visible_levels.is_empty():
		_details.text = "No dispatch matches these filters."
		_mission_button.disabled = true
		return
	_list.select(0)
	_describe(0)


func _describe(index: int) -> void:
	if index < 0 or index >= _visible_levels.size():
		return
	var level: Dictionary = _visible_levels[index]
	var location: Dictionary = Atlas.find_location(_data, str(level["location_id"]))
	_update_schematic(level, location)
	var route: Dictionary = (_campaign_board.get("states", {}) as Dictionary).get(
		str(level["id"]), {})
	var gate: String = str(route.get("status", "HOLD"))
	_mission_button.disabled = _field_profile_error != "" or _campaign_error != "" or (
		account_key != "" and gate == "LOCKED")
	_mission_button.text = "Launch restored/replayable dispatch" if gate == "RESTORED" else (
		"Enter EXP05 dispatch (experimental; untested)" if not _mission_button.disabled else
		"Locked: complete one prerequisite restoration")
	var blockers: Array = route.get("requires_any", [])
	var route_lines: Array[String] = [
		"EXP05 ROUTE  •  " + str(route.get("route_label", "UNKNOWN")),
		"STATUS  •  " + gate,
		"UNLOCK  •  " + ("Chapter entry" if blockers.is_empty() else
			"Restore ANY of " + ", ".join(PackedStringArray(blockers))),
		str(route.get("narrative", "")), ""
	]
	var lines: Array[String] = []
	lines.append_array(route_lines)
	lines.append_array([
		str(level["title"]), "",
		"LOCATION  •  " + str(location.get("name", "")),
		"LANDMARK  •  " + str(location.get("hero_prop", "")),
		"WEATHER  •  " + str(location.get("environment", "")),
		"HAZARD  •  " + str(level.get("hazard", "")),
		"",
		str(level.get("mission_hook", "")),
		"",
		"FIVE PLANNED OBJECTIVES  (four required / one optional)", ""
	])
	for task: Dictionary in level["tasks"]:
		var extra: String = "  [OPTIONAL]" if not bool(task["required"]) else ""
		lines.append("%d. %s%s" % [int(task["ordinal"]), str(task["title"]), extra])
		lines.append("   " + str(task["briefing"]))
		lines.append("   Puzzle mechanism: %s  •  Concept points: %d" % [
			str(task["mechanic"]), int(task["field_points_preview"])])
		lines.append("")
	var find: Dictionary = level["collectible"]
	lines.append("PLANNED STORY COLLECTIBLE / EXP04 UNIQUE LORE PICKUP")
	lines.append(str(find["name"]) + "  /  " + str(find["set"]))
	lines.append("Personal collection: " +
		("ACQUIRED" if (_field_profile.get("lore_finds", {}) as Dictionary).has(
			str(find["id"])) else "NOT YET ACQUIRED"))
	lines.append("EXP04: interact with the relic after host-confirmed optional inspection. Adds one non-spendable collection entry; never awards C01 credits or modifies the grid.")
	lines.append("")
	lines.append("Concept points for all five objectives: %d (NOT real rewards; EXP04 field score is host-verified separately)" % Atlas.preview_points(level))
	lines.append("STATUS  •  Design-browser preview; explicit EXP04 host dispatch remains experimental")
	_details.text = "\n".join(lines)
	_details.scroll_to_line(0)


## A selection replaces exactly one prior preview scene. No saved state, players,
## colliders beyond the visual candidate floor, or host entities are retained.
func _update_schematic(level: Dictionary, location: Dictionary) -> void:
	if _preview_root == null or _preview_viewport == null:
		return
	if _preview_world != null:
		_preview_root.remove_child(_preview_world)
		_preview_world.free()
		_preview_world = null
	var plan: Dictionary = LayoutPlan.make_plan(level, location)
	if not bool(plan.get("ok", false)):
		return
	_preview_world = Graybox.build(plan)
	if _preview_world == null:
		return
	_preview_root.add_child(_preview_world)
	_preview_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		closed.emit()


## The atlas stays a non-authoritative browser. Only a source-pinned level ID
## crosses this opt-in boundary; the mission scene independently revalidates it.
func _request_mission() -> void:
	if _mission_button == null or _mission_button.disabled or _list == null:
		return
	var selected: PackedInt32Array = _list.get_selected_items()
	if selected.is_empty():
		return
	var index: int = selected[0]
	if index < 0 or index >= _visible_levels.size():
		return
	var chosen: String = str(_visible_levels[index]["id"])
	if account_key != "":
		var access: Dictionary = Campaign.can_launch(_field_profile, _data,
			Campaign.load_routes(), chosen)
		if not bool(access.get("ok", false)):
			return
	mission_requested.emit(chosen)
