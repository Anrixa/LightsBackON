extends PanelContainer
## S07 network tablet (blueprint p.23, reference p.43): full-screen panel on an opaque backdrop. Top: district, title, tabs
## Network / Objectives. Left: the directed map (tablet_map.gd). Right: evidence for the selected node and Ping. Bottom:
## legend, zoom, center and Close.
## The tablet may only inspect and ping (V07 acceptance): it holds an outbox gate that allows exactly those two intents.
## Selecting a node shows what is known; Accept on a node sends inspect for its meter panel (the host checks range and
## answers); Ping sends a ping on that node. Switches, breakers and repairs operate only in the world.
## Focus (blueprint p.22): opening moves focus into the tablet, closing restores the previous control; B / Esc / Tab close.

signal closed

const ThemeTokens := preload("res://scripts/ui/theme_tokens.gd")
const UiText := preload("res://scripts/ui/ui_text.gd")
const StatusChip := preload("res://scripts/ui/status_chip.gd")
const TabletMap := preload("res://scripts/ui/tablet_map.gd")
const TabletPresenter := preload("res://scripts/ui/tablet_presenter.gd")
const FocusScroll := preload("res://scripts/ui/focus_scroll.gd")

const MAP_INTENTS: Array[String] = ["inspect", "ping"]
const DETAIL_WIDTH_PX: int = 480
const DETAIL_MAX_CONTENT_FRACTION: float = 0.44
const SECTION_GAP_PX: int = 16
const TAB_NETWORK: String = "network"
const TAB_OBJECTIVES: String = "objectives"
const MAX_PENDING_TABLET_REPLIES: int = 64  # bound delayed request bookkeeping
const LEGEND: Array[Array] = [["supply", "restored"], ["supply", "temporary"], ["supply", "dark"], ["other", "unknown"]]

var tokens: Dictionary = {}
var ui_scale_percent: int = 100
var scale_percent: float = 100.0
var device: String = UiText.DEVICE_KBM
var gate: RefCounted = null  # intent_outbox.gd Gate limited to MAP_INTENTS
var _bound_outbox: RefCounted = null  # disconnect listeners if a solo session is replaced
var map: Container
var selected: String = ""
var tab: String = TAB_NETWORK
var tab_buttons: Dictionary = {}
var ping_button: Button
var close_button: Button
var zoom_buttons: Array[Button] = []
var _view: Dictionary = {}
var _objectives: Array = []
var _context: Array[String] = ["district.alder_street", "contract.c01"]
var _status_text: String = ""
var _previous_focus: Control = null
var _visit_open: bool = false  # opening a visible modal twice must not restart its visit
var _detail: VBoxContainer
var _feedback_label: Label  # persistent action feedback outside the scrolling evidence
var detail_scroll: ScrollContainer
var _objective_scroll: ScrollContainer
var _body_left: PanelContainer
var _map_wanted_zoom: int = 2
var _map_offset: Vector2 = Vector2.ZERO
var _map_view_saved: bool = false
var _right_trigger_held: bool = false
var _left_trigger_held: bool = false
var _pending_evidence_scroll_y: int = 0
var _saved_objective_scroll_y: int = 0
var _pending_tablet_requests: Dictionary = {}  # sequence -> original action/target/session for this visit
var _latest_request_seq_by_action: Dictionary = {}  # action+target -> newest sequence


func _init() -> void:
	tokens = JSON.parse_string(FileAccess.get_file_as_string("res://content/ui/tokens.json"))
	theme_type_variation = "BackdropPanel"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP  # nothing behind the tablet is clickable while it is open
	resized.connect(_on_resized)


## outbox: intent_outbox.gd; the tablet keeps only a gate for inspect and ping.
func setup(outbox: RefCounted) -> void:
	if _bound_outbox == outbox:
		return  # reconnecting the same session must not register duplicate listeners
	if _bound_outbox != null:
		# An old session may still complete asynchronous calls. It must no
		# longer send tablet feedback or retain this view via signal references.
		if _bound_outbox.has_signal("sent") and _bound_outbox.is_connected("sent", _on_outbox_sent):
			_bound_outbox.disconnect("sent", _on_outbox_sent)
		if _bound_outbox.has_signal("replied") and _bound_outbox.is_connected("replied", on_reply):
			_bound_outbox.disconnect("replied", on_reply)
	_bound_outbox = outbox
	gate = outbox.call("gate", MAP_INTENTS)
	_clear_tablet_requests()
	_status_text = ""
	if _detail != null:
		_fill_detail()
	# Register the send before an in-process host has a chance to reply.
	if outbox.has_signal("sent"):
		outbox.connect("sent", _on_outbox_sent)
	if outbox.has_signal("replied"):
		outbox.connect("replied", on_reply)


## view: tablet_presenter.gd build(); objectives: mission_director objectives(); context: [district key, contract key].
func show_data(view: Dictionary, objectives: Array, context: Array[String] = []) -> void:
	_view = view
	_objectives = objectives
	if not context.is_empty():
		_context = context
	if selected == "" or not (view["nodes"] as Dictionary).has(selected):
		# A refreshed map may no longer contain the previously selected node.
		# Its pending inspection/ping banner must not be attributed to another node.
		var previous: String = selected
		selected = str(view["order"][0])
		if selected != previous:
			_status_text = ""
			_clear_tablet_requests()
			if detail_scroll != null and is_instance_valid(detail_scroll):
				detail_scroll.scroll_vertical = 0
	_rebuild()


func set_ui_scale(percent: int) -> void:
	ui_scale_percent = clampi(percent, int(tokens["ui_scale_percent"]["min"]), int(tokens["ui_scale_percent"]["max"]))
	_rebuild()


func set_device(input_device: String) -> void:
	device = input_device
	_rebuild()


func open() -> void:
	if _visit_open:
		# Duplicate open notifications must not replace the outside focus target
		# or invalidate outstanding replies from the current tablet visit.
		return
	_visit_open = true
	# Each visit starts with an armed trigger, so a held axis from a previous
	# visit cannot keep zooming repeatedly when it emits motion samples.
	_right_trigger_held = false
	_left_trigger_held = false
	# A request made on an earlier visit cannot paint the current visit,
	# even when the same node and intent appear again.
	_clear_tablet_requests()
	# The evidence pane belongs to this opening, not to a prior tablet visit.
	_status_text = ""
	if _detail != null:
		_fill_detail()
	_previous_focus = get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	visible = true
	_focus_default()


func close() -> void:
	if not _visit_open:
		return  # stale/double close must not emit twice or steal outside focus
	_visit_open = false
	visible = false
	_status_text = ""
	_clear_tablet_requests()
	if _previous_focus != null and is_instance_valid(_previous_focus) and _previous_focus.is_visible_in_tree():
		_previous_focus.grab_focus()
	elif is_inside_tree() and get_viewport().gui_get_focus_owner() != null:
		get_viewport().gui_release_focus()
	closed.emit()


## Every control the player can focus in the tablet (tests walk the focus graph from these).
func focusables() -> Array[Control]:
	var out: Array[Control] = []
	_collect_focusables(self, out)
	return out


func select(nid: String) -> void:
	if nid == selected or not (_view.get("nodes", {}) as Dictionary).has(nid):
		return
	selected = nid
	_status_text = ""
	_clear_tablet_requests()
	_pending_evidence_scroll_y = 0
	# A new branch must start at its heading, not halfway down the previous
	# branch's long meter evidence. Live refresh of the same node is unaffected.
	if detail_scroll != null and is_instance_valid(detail_scroll):
		detail_scroll.scroll_vertical = 0
	_fill_detail()
	# The evidence and Ping controls navigate back to the current node, not
	# whichever node was selected when _link_focus() last rebuilt the tablet.
	if tab == TAB_NETWORK and map != null and map.nodes.has(nid):
		var current_node: Control = map.nodes[nid] as Control
		_neighbor(detail_scroll, SIDE_LEFT, current_node)
		_neighbor(ping_button, SIDE_LEFT, current_node)


## Only an opened Network modal may ask the host to inspect or ping. 
## The view can exist in the scene tree before its first visit, and queued UI
## callbacks may arrive after close; neither is authority to dispatch.
func _can_send_tablet_intent() -> bool:
	return _visit_open and is_visible_in_tree() and tab == TAB_NETWORK and gate != null


func inspect_selected() -> void:
	if not _can_send_tablet_intent():
		return
	var v: Dictionary = _view["nodes"].get(selected, {})
	if v.is_empty() or str(v["panel"]) == "":
		return  # consumers and sources without a meter panel only show what is visible
	gate.call("send", "inspect", str(v["panel"]), {})


func ping_selected() -> void:
	if not _can_send_tablet_intent():
		return
	var v: Dictionary = _view["nodes"].get(selected, {})
	if v.is_empty():
		return
	gate.call("send", "ping", selected, {"ping": "PING_FAULT" if TabletPresenter.shows_fault(v) else "PING_LOOK"})


## Discard both sequence maps whenever navigation changes the request context.
func _clear_tablet_requests() -> void:
	_pending_tablet_requests.clear()
	_latest_request_seq_by_action.clear()


## Include the action kind so independent Ping and Inspect replies never
## suppress one another, even when their entity IDs coincide.
func _request_key(envelope: Dictionary) -> String:
	return "%s:%s" % [str(envelope.get("type", "")), str(envelope.get("entity", ""))]


## The shared outbox may deliver replies after the tablet closes, changes
## selection, or returns to the same node. Keep only requests from this visit.
func _on_outbox_sent(envelope: Dictionary) -> void:
	if not _can_send_tablet_intent():
		return
	if MAP_INTENTS.has(str(envelope.get("type", ""))) and int(envelope.get("seq", -1)) > 0:
		# Once the player initiates a newer action, the prior result no longer
		# describes the most recent request. Clear it until the host responds.
		if _status_text != "":
			_status_text = ""
			if _detail != null:
				_fill_detail()
		var request_seq: int = int(envelope["seq"])
		_pending_tablet_requests[request_seq] = {
			"request_key": _request_key(envelope),
			"session": str(envelope.get("session", "")),
		}
		_latest_request_seq_by_action[_request_key(envelope)] = request_seq
		if _pending_tablet_requests.size() > MAX_PENDING_TABLET_REPLIES:
			# No indefinite growth when a transport drops acknowledgments.
			var oldest: int = request_seq
			for pending: Variant in _pending_tablet_requests:
				oldest = mini(oldest, int(pending))
			_pending_tablet_requests.erase(oldest)


func on_reply(envelope: Dictionary, reply: Dictionary) -> void:
	# Delayed replies must not mutate a closed read-only view. In particular,
	# closing and reopening the same selected node must start without a stale
	# success or refusal from the previous tablet visit.
	if not _can_send_tablet_intent():
		# No network actions are available on Objectives or outside a visit. Their delayed replies
		# must not reappear as if they belonged to the next Network visit.
		return
	var kind: String = str(envelope.get("type", ""))
	if kind != "inspect" and kind != "ping":
		return
	# All production envelopes carry a monotonic outbox sequence. Older
	# test fixtures without a sequence still exercise the presentation path.
	if envelope.has("seq"):
		var request_seq: int = int(envelope["seq"])
		if not _pending_tablet_requests.has(request_seq):
			return
		var pending: Dictionary = _pending_tablet_requests[request_seq] as Dictionary
		# A sequence alone does not identify a request. A delayed/malformed
		# envelope must not consume another action's still-valid acknowledgment.
		if str(pending.get("request_key", "")) != _request_key(envelope) or \
			str(pending.get("session", "")) != str(envelope.get("session", "")):
			return
		_pending_tablet_requests.erase(request_seq)
		# A slower, older acknowledgment must not overwrite feedback for
		# a newer dispatch to the same action and target.
		if request_seq != int(_latest_request_seq_by_action.get(_request_key(envelope), -1)):
			return
	# An asynchronous reply is about the original target, not whichever node
	# the player happens to be reading when it arrives. Drop stale replies rather
	# than falsely labeling a different branch as inspected or pinged.
	var node: Dictionary = (_view.get("nodes", {}) as Dictionary).get(selected, {})
	if node.is_empty():
		return
	var expected: String = str(node.get("panel", "")) if kind == "inspect" else selected
	if expected == "" or str(envelope.get("entity", "")) != expected:
		return
	var accepted: bool = bool(reply.get("ok", false))
	var key: String = str(reply.get("key", ""))
	var refusal: String = UiText.t(key if UiText.has(key) else "network.refused.generic")
	if kind == "inspect":
		_status_text = UiText.t("tablet.inspected") if accepted else UiText.tf("tablet.inspect_refused", [refusal])
	else:
		var description: String = UiText.tf("tablet.ping_branch", [UiText.t(str(node["name_key"]))])
		_status_text = UiText.tf("offline.status.accepted", [description]) if accepted else "%s: %s" % [description, refusal]
	if _detail != null:
		_fill_detail()


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event.is_action_pressed("map_meter") or event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()  # Tab must not also move focus (ui_focus_next)
	elif event.is_action_pressed("ping"):
		# The tablet is modal on both tabs. Do not leak a world Ping when
		# Objectives is active; only Network is permitted to send the intent.
		if tab == TAB_NETWORK:
			ping_selected()
		get_viewport().set_input_as_handled()
	elif event is InputEventJoypadMotion:
		# A held analog trigger sends repeated motion events. Zoom exactly once
		# on the press edge and rearm only when that same trigger is released.
		# Unrelated stick movement must never release the other trigger's latch.
		var motion: InputEventJoypadMotion = event as InputEventJoypadMotion
		if motion.axis == JOY_AXIS_TRIGGER_RIGHT:
			var right_pressed: bool = motion.is_action_pressed("tool_primary")
			if right_pressed and not _right_trigger_held:
				_zoom(1)
			_right_trigger_held = right_pressed
			get_viewport().set_input_as_handled()
		elif motion.axis == JOY_AXIS_TRIGGER_LEFT:
			var left_pressed: bool = motion.is_action_pressed("tool_secondary")
			if left_pressed and not _left_trigger_held:
				_zoom(-1)
			_left_trigger_held = left_pressed
			get_viewport().set_input_as_handled()


## The screen the tablet covers: its parent's rect, else the viewport. Never its own size, which grows with its content and
## would feed back into the scale (a rebuild loop).
func screen_size() -> Vector2:
	var parent: Control = get_parent() as Control
	if parent != null:
		return parent.size
	return get_viewport_rect().size if is_inside_tree() else ThemeTokens.DESIGN_SIZE


func _on_resized() -> void:
	if not is_equal_approx(ThemeTokens.effective_percent(ui_scale_percent, screen_size()), scale_percent) and not _view.is_empty():
		_rebuild()


# ---------- build ----------

func _rebuild() -> void:
	if _view.is_empty():
		return
	var focus_token: String = _focus_token()
	# Preserve the reading position when the same evidence is reflowed by
	# a live refresh, scale change or device hint. Node changes reset it in select().
	var evidence_scroll_y: int = detail_scroll.scroll_vertical if detail_scroll != null and is_instance_valid(detail_scroll) else 0
	# Objectives is a separate reading surface and can be revisited without
	# discarding the player's progress through longer task lists.
	if _objective_scroll != null and is_instance_valid(_objective_scroll):
		_saved_objective_scroll_y = _objective_scroll.scroll_vertical
	# Recreating the map for a live state refresh, a locale/device reflow or
	# tab navigation must not reset the player\'s zoom and pan to defaults.
	if map != null:
		_map_wanted_zoom = int(map.get("_wanted_zoom_index"))
		_map_offset = map.offset
		_map_view_saved = true
	scale_percent = ThemeTokens.effective_percent(ui_scale_percent, screen_size())
	theme = ThemeTokens.build(tokens, scale_percent)
	for c: Node in get_children():
		remove_child(c)
		c.queue_free()
	tab_buttons.clear()
	zoom_buttons.clear()
	_objective_scroll = null
	var s: float = scale_percent
	var margin: MarginContainer = MarginContainer.new()
	var safe: int = ThemeTokens.safe_area(tokens, screen_size())
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, safe)
	add_child(margin)
	var page: VBoxContainer = VBoxContainer.new()
	page.add_theme_constant_override("separation", ThemeTokens.px(SECTION_GAP_PX, s))
	margin.add_child(page)
	page.add_child(_header())
	var body: HBoxContainer = HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", ThemeTokens.px(24, s))
	page.add_child(body)
	_body_left = PanelContainer.new()
	_body_left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(_body_left)
	# A map built for the Objectives tab would never be parented. Those
	# detached CanvasItems survive teardown across repeated scale/device reflow.
	map = null
	if tab == TAB_NETWORK:
		map = TabletMap.new()
		map.name = "Map"
		map.setup(tokens, s, _view)
		map.set_zoom_index(_map_wanted_zoom)
		if _map_view_saved:
			map.offset = _map_offset
		map.node_activated.connect(func(nid: String) -> void:
			select(nid)
			inspect_selected())
		map.node_focused.connect(select)
		_body_left.add_child(map)
	else:
		_objective_scroll = _objective_list()
		_objective_scroll.get_v_scroll_bar().changed.connect(_restore_objective_scroll)
		_body_left.add_child(_objective_scroll)
	var detail_panel: PanelContainer = PanelContainer.new()
	detail_panel.name = "Detail"
	# Keep a usable map at 720p instead of letting the fixed evidence width
	# consume the available screen once safe margins have been applied.
	var content_width: float = maxf(1.0, screen_size().x - float(safe * 2))
	detail_panel.custom_minimum_size.x = minf(ThemeTokens.px(DETAIL_WIDTH_PX, s), content_width * DETAIL_MAX_CONTENT_FRACTION)
	body.add_child(detail_panel)
	var detail_box: VBoxContainer = VBoxContainer.new()
	detail_panel.add_child(detail_box)
	# evidence scrolls; Ping stays below it, never under the fold (blueprint p.22 scroll panels)
	detail_scroll = FocusScroll.new()
	detail_scroll.name = "Evidence"
	detail_scroll.setup(tokens, s)
	# The scrollbar range becomes valid only when its evidence is laid out.
	detail_scroll.get_v_scroll_bar().changed.connect(_restore_evidence_scroll)
	detail_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_box.add_child(detail_scroll)
	detail_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_detail = VBoxContainer.new()
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail.add_theme_constant_override("separation", ThemeTokens.px(8, s))
	detail_scroll.add_child(_detail)
	_feedback_label = _label(detail_box, "", "StrongLabel", "action")
	_feedback_label.name = "ActionFeedback"
	_feedback_label.visible = false
	ping_button = _button(detail_box, "", "PrimaryButton")
	ping_button.name = "Ping"
	ping_button.pressed.connect(ping_selected)
	page.add_child(_footer())
	_link_focus()
	_fill_detail()
	# Cache the requested position until Godot has measured the new contents.
	# A deferred setter alone can run too early on headless/fast layouts.
	_pending_evidence_scroll_y = evidence_scroll_y
	if focus_token != "":
		_restore_focus(focus_token)


## Explicit focus exits between the regions (blueprint p.22: every control reachable by controller). Inside the map the
## stick follows the graph (tablet_map.gd); at its edges it leaves to the tabs (up), the evidence panel (right) and the footer.
func _restore_evidence_scroll() -> void:
	if _pending_evidence_scroll_y <= 0 or detail_scroll == null:
		return
	var bar: VScrollBar = detail_scroll.get_v_scroll_bar()
	if bar.max_value <= bar.page + 0.5:
		return
	var wanted: int = _pending_evidence_scroll_y
	_pending_evidence_scroll_y = 0
	detail_scroll.scroll_vertical = mini(wanted, roundi(bar.max_value - bar.page))


func _restore_objective_scroll() -> void:
	if _saved_objective_scroll_y <= 0 or _objective_scroll == null:
		return
	var bar: VScrollBar = _objective_scroll.get_v_scroll_bar()
	if bar.max_value <= bar.page + 0.5:
		return
	var wanted: int = _saved_objective_scroll_y
	_saved_objective_scroll_y = 0
	_objective_scroll.scroll_vertical = mini(wanted, roundi(bar.max_value - bar.page))


func _link_focus() -> void:
	var footer: Array[Button] = []
	for b: Button in zoom_buttons:
		if b.visible:
			footer.append(b)
	footer.append(close_button)
	for i: int in footer.size():
		if i > 0:
			_neighbor(footer[i], SIDE_LEFT, footer[i - 1])
		if i < footer.size() - 1:
			_neighbor(footer[i], SIDE_RIGHT, footer[i + 1])
		_neighbor(footer[i], SIDE_TOP, ping_button if footer[i].visible and tab == TAB_NETWORK else detail_scroll)
	var tabs: Array = tab_buttons.values()
	var first: Control = map.nodes[_view["order"][0]] if tab == TAB_NETWORK else _objective_scroll
	for b: Button in tabs:
		_neighbor(b, SIDE_BOTTOM, first)
	_neighbor(tabs[0], SIDE_RIGHT, tabs[1])
	_neighbor(tabs[1], SIDE_LEFT, tabs[0])
	_neighbor(tabs[1], SIDE_RIGHT, detail_scroll)
	_neighbor(detail_scroll, SIDE_TOP, tabs[1])
	_neighbor(detail_scroll, SIDE_BOTTOM, ping_button if tab == TAB_NETWORK else close_button)
	_neighbor(ping_button, SIDE_TOP, detail_scroll)
	_neighbor(ping_button, SIDE_BOTTOM, close_button)
	if tab == TAB_NETWORK:
		_neighbor(detail_scroll, SIDE_LEFT, map.nodes[selected] if map.nodes.has(selected) else first)
		_neighbor(ping_button, SIDE_LEFT, map.nodes[selected] if map.nodes.has(selected) else first)
		map.exits = {SIDE_TOP: tabs[0], SIDE_RIGHT: detail_scroll, SIDE_BOTTOM: footer[0]}
		map.queue_sort()
	else:
		_neighbor(_objective_scroll, SIDE_TOP, tabs[1])
		_neighbor(_objective_scroll, SIDE_RIGHT, detail_scroll)
		_neighbor(_objective_scroll, SIDE_BOTTOM, close_button)
		_neighbor(detail_scroll, SIDE_LEFT, _objective_scroll)


## Identify the semantic focused control before rebuilding the tablet. Retain the
## same focus after UI-scale or device-hint changes: rebuilding must not strand a
## gamepad user back at the top-left map node during an inspection.
func _focus_token() -> String:
	if not is_inside_tree():
		return ""
	var current: Control = get_viewport().gui_get_focus_owner()
	if current == null or not is_ancestor_of(current):
		return ""
	if current == close_button:
		return "close"
	if current == ping_button:
		return "ping"
	if current == detail_scroll:
		return "evidence"
	if current == _objective_scroll:
		return "objectives"
	for key: String in tab_buttons:
		if current == tab_buttons[key]:
			return "tab:" + key
	for i: int in zoom_buttons.size():
		if current == zoom_buttons[i]:
			return "zoom:" + str(i)
	if map != null and tab == TAB_NETWORK:
		for nid: String in map.nodes:
			if current == map.nodes[nid]:
				return "node:" + nid
	return "default"


func _restore_focus(token: String) -> void:
	var next: Control = null
	if token == "close":
		next = close_button
	elif token == "ping":
		next = ping_button if ping_button.visible else close_button
	elif token == "evidence":
		next = detail_scroll
	elif token == "objectives":
		next = _objective_scroll if tab == TAB_OBJECTIVES else detail_scroll
	elif token.begins_with("tab:"):
		next = tab_buttons.get(token.trim_prefix("tab:"), null) as Control
	elif token.begins_with("zoom:"):
		var idx: int = token.trim_prefix("zoom:").to_int()
		if idx >= 0 and idx < zoom_buttons.size() and zoom_buttons[idx].visible:
			next = zoom_buttons[idx]
	elif token.begins_with("node:") and tab == TAB_NETWORK:
		next = map.nodes.get(token.trim_prefix("node:"), null) as Control
	if next != null and next.is_visible_in_tree():
		next.grab_focus()
	else:
		_focus_default()


func _neighbor(from: Control, side: Side, to: Control) -> void:
	from.set_focus_neighbor(side, from.get_path_to(to))


func _header() -> Control:
	var s: float = scale_percent
	# Stack title and tabs: a 35% longer pseudo-locale must not push the
	# Network/Objectives controller tabs out of the viewport at 720p.
	var row: VBoxContainer = VBoxContainer.new()
	var titles: VBoxContainer = VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.add_theme_constant_override("separation", ThemeTokens.px(4, s))
	row.add_child(titles)
	var ctx: Label = _label(titles, "%s  /  %s" % [UiText.t(_context[0]), UiText.t(_context[1])], "StrongLabel", "restored")
	ctx.uppercase = true
	_label(titles, UiText.t("tablet.title"), "HeaderLarge")
	_label(titles, UiText.t("tablet.subtitle"), "MutedLabel")
	var tabs: HFlowContainer = HFlowContainer.new()
	tabs.name = "Tabs"
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(tabs)
	var group: ButtonGroup = ButtonGroup.new()
	for t: String in [TAB_NETWORK, TAB_OBJECTIVES]:
		var b: Button = _button(tabs, UiText.t("tablet.tab." + t))
		b.name = "Tab_" + t
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = t == tab
		b.pressed.connect(_show_tab.bind(t))
		tab_buttons[t] = b
	return row


func _footer() -> Control:
	# Legends and primary actions get independent wrapping rows. A single
	# horizontal strip overflows at 720p and with the +35% pseudo-locale.
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", ThemeTokens.px(8, scale_percent))
	var legend: HFlowContainer = HFlowContainer.new()
	legend.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	legend.add_theme_constant_override("h_separation", ThemeTokens.px(24, scale_percent))
	column.add_child(legend)
	for entry: Array in LEGEND:
		legend.add_child(StatusChip.make(tokens, scale_percent, entry[0], entry[1]))
	var actions: HFlowContainer = HFlowContainer.new()
	actions.name = "FooterActions"
	actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_theme_constant_override("h_separation", ThemeTokens.px(8, scale_percent))
	column.add_child(actions)
	for z: Array in [["tablet.zoom_out", -1], ["tablet.zoom_in", 1]]:
		var b: Button = _button(actions, UiText.t(z[0]))
		b.name = "Zoom_%s" % ("out" if int(z[1]) < 0 else "in")
		b.pressed.connect(_zoom.bind(int(z[1])))
		zoom_buttons.append(b)
	var center: Button = _button(actions, UiText.t("tablet.center"))
	center.name = "Center"
	center.pressed.connect(func() -> void:
		if map != null:
			map.center_view())
	zoom_buttons.append(center)
	for b: Button in zoom_buttons:
		b.visible = tab == TAB_NETWORK
	close_button = _button(actions, UiText.tf("prompt.binding", [UiText.binding("map_meter", device), UiText.t("tablet.close")]))
	close_button.name = "Close"
	close_button.pressed.connect(close)
	return column


func _objective_list() -> ScrollContainer:
	# Objective descriptions can exceed the remaining panel height in pseudo-
	# locale. Keep the list scrollable by D-pad/right stick and the footer fixed.
	var scroll: FocusScroll = FocusScroll.new()
	scroll.name = "ObjectivesScroll"
	scroll.setup(tokens, scale_percent)
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var box: VBoxContainer = VBoxContainer.new()
	box.name = "ObjectiveList"
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	for o: Dictionary in _objectives:
		box.add_child(StatusChip.make(tokens, scale_percent, "objectives", str(o["status"]), UiText.t(str(o["text_key"])), true))
	return scroll


func _fill_detail() -> void:
	if _detail == null:
		return
	for c: Node in _detail.get_children():
		_detail.remove_child(c)
		c.queue_free()
	# A reply must stay legible even while the player reads far down a long
	# evidence record. Keep the outcome visible outside the scroll panel.
	if _feedback_label != null and is_instance_valid(_feedback_label):
		_feedback_label.text = _status_text
		_feedback_label.visible = _status_text != ""
	var v: Dictionary = _view["nodes"].get(selected, {})
	if v.is_empty():
		return
	var name_text: String = UiText.t(str(v["name_key"]))
	var head: Label = _label(_detail, UiText.tf("tablet.selected", [name_text]), "StrongLabel", "action")
	head.uppercase = true
	_detail.add_child(StatusChip.make(tokens, scale_percent, v["status_group"], v["status_state"], "", true, "HeaderMedium"))
	if v.has("source_text"):
		_section(UiText.t("tablet.section.source"), [v["source_text"]])
	var evidence: Array = []
	for f: Dictionary in v["findings"]:
		evidence.append(f)
	if evidence.is_empty():
		_section(UiText.t("tablet.section.evidence"), v["lines"])
	else:
		_section(UiText.t("tablet.section.evidence"), v["lines"])
		for f: Dictionary in evidence:
			_detail.add_child(StatusChip.make(tokens, scale_percent, "findings", str(f["code"]), "", true))
	if v.has("access_key"):
		_section(UiText.t("tablet.section.access"), [UiText.t(str(v["access_key"]))])
	if str(v["panel"]) != "":
		_section(UiText.t("tablet.section.worker"), [v.get("worker_text", UiText.t("tablet.no_worker"))])
		_label(_detail, UiText.tf("tablet.inspect_hint", ["[%s]" % UiText.binding("ui_accept", device)]), "MutedLabel")
	_label(_detail, UiText.t("tablet.footnote"), "MutedLabel")
	ping_button.text = UiText.tf("prompt.binding", [UiText.binding("ping", device), UiText.tf("tablet.ping_branch", [name_text])])
	ping_button.visible = tab == TAB_NETWORK


func _section(title: String, lines: Array) -> void:
	var t: Label = _label(_detail, title, "StrongLabel", "text_muted")
	t.uppercase = true
	for line: Variant in lines:
		_label(_detail, str(line))


func _show_tab(t: String) -> void:
	if t == tab:
		return
	if t != TAB_NETWORK:
		# Inspection/ping results and outstanding requests are scoped to the
		# Network tab, not to an eventual return from Objectives.
		_status_text = ""
		_clear_tablet_requests()
	tab = t
	_rebuild()
	(tab_buttons[t] as Button).grab_focus()


func _zoom(step: int) -> void:
	# Controller tool actions may still arrive while the Objectives tab is open.
	if tab != TAB_NETWORK or map == null:
		return
	# Step from the requested level. The effective level may be temporarily
	# capped by a narrow viewport, and must not erase that choice.
	map.set_zoom_index(int(map.get("_wanted_zoom_index")) + step)
	map.ensure_visible(selected)


func _focus_default() -> void:
	if tab == TAB_NETWORK and map != null and map.nodes.has(selected):
		(map.nodes[selected] as Control).grab_focus()
	elif tab_buttons.has(tab):
		(tab_buttons[tab] as Button).grab_focus()


func _collect_focusables(n: Node, out: Array[Control]) -> void:
	for c: Node in n.get_children():
		if c is Control and (c as Control).is_visible_in_tree():
			var ctl: Control = c
			if ctl.focus_mode == Control.FOCUS_ALL and not (ctl is BaseButton and (ctl as BaseButton).disabled):
				out.append(ctl)
			_collect_focusables(c, out)


func _label(parent: Control, text: String, variation: String = "", color_token: String = "") -> Label:
	var l: Label = Label.new()
	l.text = text
	l.theme_type_variation = variation
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if color_token != "":
		l.add_theme_color_override("font_color", ThemeTokens.color(tokens, color_token))
	parent.add_child(l)
	return l


func _button(parent: Control, text: String, variation: String = "") -> Button:
	var b: Button = Button.new()
	b.text = text
	b.theme_type_variation = variation
	b.custom_minimum_size.y = ThemeTokens.px(ThemeTokens.BUTTON_HEIGHT_PX, scale_percent)
	b.focus_mode = Control.FOCUS_ALL
	parent.add_child(b)
	return b
