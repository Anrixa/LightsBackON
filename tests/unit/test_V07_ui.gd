extends "res://tests/test_case.gd"
## V07: field HUD and network tablet (S06/S07, blueprint p.23; references p.42-43; ADR-004 point 5).
## Acceptance: "Map inspects and pings only; controller focus complete; 150% scale usable." Automated here: the tablet sends
## nothing but inspect and ping whatever the player presses, and the grid is unchanged by it; the directional focus graph
## reaches every control from every control; nothing overflows its container or the safe area at 1280x720 / 1920x1080 /
## 1920x1200 x 80/100/150 % x English / 35 % pseudo-locale (UX02/UX03 layout part); every status is icon + text in its token
## color. A person pressing a real controller (UX01) and judging readability stays pending local.

const Fixture := preload("res://tests/support/ui_fixture.gd")
const Runner := preload("res://tests/support/solution_runner.gd")
const FieldHud := preload("res://scripts/ui/field_hud.gd")
const NetworkTablet := preload("res://scripts/ui/network_tablet.gd")
const IntentOutbox := preload("res://scripts/ui/intent_outbox.gd")
const ThemeTokens := preload("res://scripts/ui/theme_tokens.gd")
const UiText := preload("res://scripts/ui/ui_text.gd")
const StatusChip := preload("res://scripts/ui/status_chip.gd")
const IconRaster := preload("res://scripts/ui/icon_raster.gd")
const TabletMap := preload("res://scripts/ui/tablet_map.gd")
const PowerGrid := preload("res://scripts/simulation/power_grid.gd")

const SIZES: Array[Vector2] = [Vector2(1280, 720), Vector2(1920, 1080), Vector2(1920, 1200)]
const SCALES: Array[int] = [80, 100, 150]
const LOCALES: Array[String] = [UiText.LOCALE_EN, UiText.LOCALE_PSEUDO]
const SIDES: Array[Side] = [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]
const TABLET_PLAYER: String = "P4"  # sends nothing in the fixture, so the outbox owns its sequence numbers

var _ctx: Dictionary
var _tokens: Dictionary
var _sent: Array[Dictionary] = []
var _owned: Array[Node] = []


func before_each() -> void:
	UiText.set_locale(UiText.LOCALE_EN)
	UiText.clear_missing()
	_ctx = Fixture.mid_shift()
	assert_true((_ctx["errors"] as Array).is_empty(), str(_ctx["errors"]))
	assert_eq(_ctx["failures"], [] as Array[String], "fixture replays the first part of the C01 solution")
	_tokens = Runner.json("res://content/ui/tokens.json")
	_sent.clear()


func after_each() -> void:
	UiText.set_locale(UiText.LOCALE_EN)
	for n: Node in _owned:
		if is_instance_valid(n):
			n.get_parent().remove_child(n)
			n.free()
	_owned.clear()
	_ctx = {}


# ---------- acceptance: map inspects and pings only ----------

func test_V07_map_sends_only_inspect_and_ping_and_never_changes_the_network() -> void:
	var before: Dictionary = (_ctx["host"].authoritative_state() as Dictionary).duplicate(true)
	var tablet: PanelContainer = _tablet(Vector2(1920, 1080), 100, true)
	tablet.open()
	for nid: String in tablet.map.nodes:
		var node: Control = tablet.map.nodes[nid]
		node.grab_focus()
		node._gui_input(_action("ui_accept"))
		var click: InputEventMouseButton = InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = true
		node._gui_input(click)
		tablet.ping_button.pressed.emit()
	for action: StringName in InputMap.get_actions():
		if not tablet.visible:
			tablet.open()
		tablet._input(_action(action))
	for b: Control in Fixture.controls(tablet):
		if b is BaseButton and b != tablet.close_button and b.is_visible_in_tree():
			(b as BaseButton).pressed.emit()
	var kinds: Dictionary = {}
	for env: Dictionary in _sent:
		kinds[env["type"]] = true
	assert_eq(kinds.keys().filter(func(k: String) -> bool: return not NetworkTablet.MAP_INTENTS.has(k)), [],
		"the tablet sent only %s" % str(NetworkTablet.MAP_INTENTS))
	assert_true(kinds.has("inspect") and kinds.has("ping"), "pressing nodes inspects; Ping pings (%d intents)" % _sent.size())
	var after: Dictionary = _ctx["host"].authoritative_state()
	for part: String in ["grid", "repairs", "equipment", "mission", "crew"]:
		assert_eq(PowerGrid.serialize(after[part]), PowerGrid.serialize(before[part]), "%s unchanged by the tablet" % part)
	var refused: Dictionary = tablet.gate.send("toggle_switch", "SW_SIGN", {"value": true})
	assert_eq(refused.get("code"), "UI_INTENT_NOT_ALLOWED", "the gate refuses a switch before anything is sent")
	assert_false(_sent.any(func(e: Dictionary) -> bool: return e["type"] == "toggle_switch"))


func test_V07_inspect_goes_through_the_host_and_its_answer_is_shown() -> void:
	var tablet: PanelContainer = _tablet(Vector2(1920, 1080), 100, true)
	tablet.open()
	tablet.select("TEMP")
	tablet.inspect_selected()
	assert_eq(_sent[-1]["type"], "inspect")
	assert_eq(_sent[-1]["entity"], "PANEL_TEMP", "a node inspects its own meter panel")
	assert_eq(_ctx["host"].revision > 0, true)
	tablet.select("APT_W")
	var count: int = _sent.size()
	tablet.inspect_selected()
	assert_eq(_sent.size(), count, "a building without a meter panel sends nothing")


## QA70: tablet feedback must belong to the current open modal, never an
## asynchronous response delivered after closing or a previous visit's status.
func test_QA70_tablet_feedback_is_cleared_and_hidden_replies_are_ignored() -> void:
	var tablet: PanelContainer = _tablet(Vector2(1920, 1080), 100)
	tablet.open()
	tablet.ping_selected()
	var old_visit: Dictionary = _sent[-1].duplicate(true)
	tablet.on_reply(old_visit, {"ok": true})
	assert_true(str(tablet.get("_status_text")) != "", "the current open tablet shows outcomes")
	tablet.close()
	assert_eq(str(tablet.get("_status_text")), "", "closing clears transient feedback")
	tablet.on_reply(old_visit,
		{"ok": false, "key": "network.refused.rate_limited"})
	assert_eq(str(tablet.get("_status_text")), "", "a hidden tablet ignores delayed replies")
	tablet.open()
	assert_eq(str(tablet.get("_status_text")), "", "a new visit starts without a stale refusal")
	tablet.ping_selected()
	var new_visit: Dictionary = _sent[-1].duplicate(true)
	tablet.on_reply(new_visit, {"ok": true})
	assert_true(str(tablet.get("_status_text")) != "", "fresh outcomes still render")
	tablet.close()


## QA71: selection changes update directional links from the evidence/ping
## region; returning with a D-pad must never jump to the previous node.
func test_QA71_evidence_and_ping_left_focus_follow_current_selection() -> void:
	var tablet: PanelContainer = _tablet(Vector2(1920, 1080), 100)
	tablet.open()
	var order: Array = (tablet.get("_view") as Dictionary)["order"]
	assert_true(order.size() > 1)
	var previous: String = str(order[0])
	var next: String = str(order[1])
	assert_eq(str(tablet.selected), previous)
	tablet.select(next)
	assert_eq(tablet.detail_scroll.find_valid_focus_neighbor(SIDE_LEFT), tablet.map.nodes[next],
		"evidence D-pad Left returns to the newly selected node")
	assert_eq(tablet.ping_button.find_valid_focus_neighbor(SIDE_LEFT), tablet.map.nodes[next],
		"Ping D-pad Left returns to the newly selected node")
	tablet.select(previous)
	assert_eq(tablet.detail_scroll.find_valid_focus_neighbor(SIDE_LEFT), tablet.map.nodes[previous],
		"reversing selection also updates the evidence back-link")
	assert_eq(tablet.ping_button.find_valid_focus_neighbor(SIDE_LEFT), tablet.map.nodes[previous])
	tablet.close()


## QA75: switching selected network nodes starts the new evidence at its title.
func test_QA75_new_selected_node_resets_long_evidence_scroll() -> void:
	var tablet: PanelContainer = _tablet(Vector2(1280, 720), 150)
	tablet.open()
	var updated: Dictionary = (tablet.get("_view") as Dictionary).duplicate(true)
	var first: String = str(updated["order"][0])
	var second: String = str(updated["order"][1])
	var long_lines: Array[String] = []
	for i: int in 70:
		long_lines.append("Measured evidence line %d" % i)
	var node_views: Dictionary = updated["nodes"]
	for nid: String in [first, second]:
		var node_view: Dictionary = node_views[nid]
		node_view["lines"] = long_lines.duplicate()
		node_views[nid] = node_view
	tablet.show_data(updated, [])
	Fixture.settle(tablet)
	var evidence: ScrollContainer = tablet.detail_scroll
	var bar: VScrollBar = evidence.get_v_scroll_bar()
	assert_true(bar.max_value > bar.page + 120.0,
		"fixture has enough long evidence to expose scroll regression")
	evidence.scroll_vertical = 120
	assert_true(evidence.scroll_vertical > 0, "first node evidence can actually scroll")
	tablet.select(second)
	Fixture.settle(tablet)
	assert_eq(evidence.scroll_vertical, 0,
		"selecting a new node shows its title and first evidence instead of prior scroll position")
	tablet.close()


## QA76: rebuilding the same meter evidence must not throw a reader back to the heading.
func test_QA76_same_node_refresh_and_reflow_keep_evidence_reading_position() -> void:
	var tablet: PanelContainer = _tablet(Vector2(1280, 720), 150)
	tablet.open()
	var view: Dictionary = (tablet.get("_view") as Dictionary).duplicate(true)
	var current: String = str(tablet.selected)
	var long_lines: Array[String] = []
	for i: int in 70:
		long_lines.append("Measurement %d: branch load remains under inspection" % i)
	var nodes: Dictionary = view["nodes"]
	var node: Dictionary = nodes[current]
	node["lines"] = long_lines
	nodes[current] = node
	tablet.show_data(view, [])
	Fixture.settle(tablet)
	var scroller: ScrollContainer = tablet.detail_scroll
	assert_true(scroller.get_v_scroll_bar().max_value > scroller.get_v_scroll_bar().page + 160.0)
	scroller.scroll_vertical = 150
	assert_true(scroller.scroll_vertical > 0)
	tablet.show_data(view.duplicate(true), [])
	Fixture.settle(tablet)
	assert_eq(tablet.detail_scroll.scroll_vertical, 150,
		"a same-node authoritative update preserves the reader's position")
	tablet.set_ui_scale(130)
	Fixture.settle(tablet)
	assert_true(tablet.detail_scroll.scroll_vertical > 0,
		"accessibility reflow does not silently rewind long evidence")
	tablet.close()


## QA77: Objective reading survives live mission refreshes and returning from the Network tab.
func test_QA77_objective_scroll_survives_refresh_scale_and_tab_roundtrip() -> void:
	var tablet: PanelContainer = _tablet(Vector2(1280, 720), 150)
	tablet.open()
	var objectives: Array = []
	var sample: Dictionary = _ctx["mission"].objectives()[0]
	for i: int in 300:
		objectives.append(sample.duplicate(true))
	var view: Dictionary = (tablet.get("_view") as Dictionary).duplicate(true)
	tablet.show_data(view, objectives)
	tablet._show_tab(NetworkTablet.TAB_OBJECTIVES)
	Fixture.settle(tablet)
	var scroller: ScrollContainer = tablet.get("_objective_scroll") as ScrollContainer
	assert_true(scroller.get_v_scroll_bar().max_value > scroller.get_v_scroll_bar().page + 150.0,
		"the fixture creates a truly scrollable objectives list")
	scroller.scroll_vertical = 120
	tablet.show_data(view.duplicate(true), objectives.duplicate(true))
	Fixture.settle(tablet)
	assert_eq((tablet.get("_objective_scroll") as ScrollContainer).scroll_vertical, 120,
		"live objective progress does not rewind the reading list")
	tablet.set_ui_scale(130)
	Fixture.settle(tablet)
	assert_true((tablet.get("_objective_scroll") as ScrollContainer).scroll_vertical > 0,
		"changing accessible UI scale preserves reading position")
	tablet._show_tab(NetworkTablet.TAB_NETWORK)
	tablet._show_tab(NetworkTablet.TAB_OBJECTIVES)
	Fixture.settle(tablet)
	assert_true((tablet.get("_objective_scroll") as ScrollContainer).scroll_vertical > 0,
		"returning to Objectives preserves its previous scroll position")
	tablet.close()


## QA78: pending replies belong to the exact visible visit, not just to a node ID.
func test_QA78_delayed_same_target_reply_is_ignored_after_visit_selection_or_tab_change() -> void:
	var tablet: PanelContainer = _tablet(Vector2(1920, 1080), 100)
	tablet.open()
	var initial: String = str(tablet.selected)
	tablet.ping_selected()
	var old_visit: Dictionary = _sent[-1].duplicate(true)
	tablet.close()
	tablet.open()
	tablet.on_reply(old_visit, {"ok": false, "key": "network.refused.rate_limited"})
	assert_eq(str(tablet.get("_status_text")), "",
		"a reply from the previous tablet opening must not describe this visit")
	tablet.ping_selected()
	var old_selection: Dictionary = _sent[-1].duplicate(true)
	var next: String = str((tablet.get("_view") as Dictionary)["order"][1])
	tablet.select(next)
	tablet.select(initial)
	tablet.on_reply(old_selection, {"ok": false, "key": "network.refused.rate_limited"})
	assert_eq(str(tablet.get("_status_text")), "",
		"selecting away and back cannot revive an earlier request for that node")
	tablet.ping_selected()
	var old_tab: Dictionary = _sent[-1].duplicate(true)
	tablet._show_tab(NetworkTablet.TAB_OBJECTIVES)
	tablet._show_tab(NetworkTablet.TAB_NETWORK)
	tablet.on_reply(old_tab, {"ok": false, "key": "network.refused.rate_limited"})
	assert_eq(str(tablet.get("_status_text")), "",
		"a request issued before switching tabs is invalid on return")
	tablet.ping_selected()
	var fresh: Dictionary = _sent[-1].duplicate(true)
	tablet.on_reply(fresh, {"ok": true})
	assert_true(str(tablet.get("_status_text")) != "",
		"a fresh reply with the newly emitted sequence is still displayed")
	tablet.close()


## QA80: Ping is consumed by the modal even on its read-only Objectives tab.
func test_QA80_objectives_consume_ping_without_dispatch_and_network_still_pings() -> void:
	var tablet: PanelContainer = _tablet(Vector2(1280, 720), 150)
	tablet.open()
	tablet._show_tab(NetworkTablet.TAB_OBJECTIVES)
	var count: int = _sent.size()
	tablet._input(_action("ping"))
	assert_eq(_sent.size(), count,
		"the Objectives tab cannot dispatch a network or world Ping through the modal")
	tablet._show_tab(NetworkTablet.TAB_NETWORK)
	tablet._input(_action("ping"))
	assert_eq(_sent.size(), count + 1, "Network retains the intended Ping shortcut")
	assert_eq(str(_sent[-1]["type"]), "ping")
	tablet.close()


## QA81: actionable feedback remains visible while long evidence is scrolled.
func test_QA81_action_outcome_is_outside_long_evidence_scroll() -> void:
	var tablet: PanelContainer = _tablet(Vector2(1280, 720), 150)
	tablet.open()
	var view: Dictionary = (tablet.get("_view") as Dictionary).duplicate(true)
	var node: Dictionary = (view["nodes"] as Dictionary)[str(tablet.selected)]
	var lines: Array[String] = []
	for i: int in 75:
		lines.append("Measured branch evidence row %d" % i)
	node["lines"] = lines
	(view["nodes"] as Dictionary)[str(tablet.selected)] = node
	tablet.show_data(view, [])
	Fixture.settle(tablet)
	var evidence: ScrollContainer = tablet.detail_scroll
	assert_true(evidence.get_v_scroll_bar().max_value > evidence.get_v_scroll_bar().page + 125.0)
	evidence.scroll_vertical = 120
	tablet.ping_selected()
	var ping: Dictionary = _sent[-1].duplicate(true)
	tablet.on_reply(ping, {"ok": true})
	Fixture.settle(tablet)
	var feedback: Label = tablet.get("_feedback_label") as Label
	assert_true(feedback != null and feedback.visible, "the Ping outcome is immediately shown")
	assert_false(evidence.is_ancestor_of(feedback), "the outcome is not buried inside the evidence scroller")
	assert_true(Fixture.rect_inside(feedback.get_global_rect(), tablet.get_global_rect()),
		"the outcome remains on-screen at accessible scale and 720p")
	assert_true(evidence.scroll_vertical > 0, "showing feedback does not force the reader back to the top")
	tablet.close()


## QA82: duplicate open requests keep the original focus target and in-flight result.
func test_QA82_open_is_idempotent_during_an_active_tablet_visit() -> void:
	var tablet: PanelContainer = _tablet(Vector2(1920, 1080), 100)
	var anchor: Button = Button.new()
	anchor.name = "OutsideFocus"
	anchor.focus_mode = Control.FOCUS_ALL
	anchor.custom_minimum_size = Vector2(100, 40)
	_root().add_child(anchor)
	_owned.append(anchor)
	anchor.grab_focus()
	assert_eq(_root().gui_get_focus_owner(), anchor)
	tablet.open()
	assert_true(_root().gui_get_focus_owner() != anchor,
		"opening the tablet transfers focus inside")
	tablet.ping_selected()
	var pending: Dictionary = _sent[-1].duplicate(true)
	tablet.open()
	tablet.on_reply(pending, {"ok": true})
	assert_true(str(tablet.get("_status_text")) != "",
		"duplicate open cannot discard a reply from the active visit")
	tablet.close()
	assert_eq(_root().gui_get_focus_owner(), anchor,
		"closing restores the control focused before the first open")


## QA83: replacing the solo session detaches old signal listeners.
func test_QA83_rebinding_tablet_outbox_detaches_stale_session_and_avoids_duplicates() -> void:
	var tablet: PanelContainer = _tablet(Vector2(1920, 1080), 100)
	var first: RefCounted = IntentOutbox.new(Runner.SESSION,
		func(_bytes: PackedByteArray) -> Dictionary: return {})
	var next: RefCounted = IntentOutbox.new(Runner.SESSION,
		func(_bytes: PackedByteArray) -> Dictionary: return {})
	tablet.setup(first)
	tablet.open()
	tablet.ping_selected()
	var old_reply: Dictionary = {"type": "ping", "entity": str(tablet.selected),
		"seq": int(first.get("_seq")), "session": Runner.SESSION}
	tablet.setup(next)
	tablet.setup(next)
	assert_eq(first.get_signal_connection_list("sent").size(), 0,
		"old session no longer holds a tablet sent callback")
	assert_eq(first.get_signal_connection_list("replied").size(), 0,
		"old session reply cannot mutate a new tablet session")
	assert_eq(next.get_signal_connection_list("sent").size(), 1,
		"repeating setup for the same session must not duplicate listeners")
	assert_eq(next.get_signal_connection_list("replied").size(), 1)
	first.emit_signal("replied", old_reply, {"ok": true})
	assert_eq(str(tablet.get("_status_text")), "",
		"old outbox responses cannot paint feedback into the replacement session")
	tablet.ping_selected()
	var fresh: Dictionary = {"type": "ping", "entity": str(tablet.selected),
		"seq": int(next.get("_seq")), "session": Runner.SESSION}
	next.emit_signal("replied", fresh, {"ok": true})
	assert_true(str(tablet.get("_status_text")) != "",
		"the replacement outbox dispatches and receives feedback normally")
	tablet.close()


## QA84: duplicate close events cannot steal focus after the modal has exited.
func test_QA84_repeated_tablet_close_emits_once_and_preserves_outside_focus() -> void:
	var tablet: PanelContainer = _tablet(Vector2(1920, 1080), 100)
	var anchor: Button = Button.new()
	anchor.name = "QA84ExternalFocus"
	anchor.focus_mode = Control.FOCUS_ALL
	anchor.custom_minimum_size = Vector2(100, 40)
	_root().add_child(anchor)
	_owned.append(anchor)
	var closes: Array[int] = [0]
	tablet.closed.connect(func() -> void: closes[0] += 1)
	anchor.grab_focus()
	tablet.open()
	tablet.close()
	assert_eq(closes[0], 1)
	assert_eq(_root().gui_get_focus_owner(), anchor)
	var next: Button = Button.new()
	next.name = "QA84NextFocus"
	next.focus_mode = Control.FOCUS_ALL
	next.custom_minimum_size = Vector2(100, 40)
	_root().add_child(next)
	_owned.append(next)
	next.grab_focus()
	tablet.close()
	assert_eq(closes[0], 1, "a duplicate close must not emit a second lifecycle signal")
	assert_eq(_root().gui_get_focus_owner(), next, "a stale close cannot steal focus")
	tablet.open()
	tablet.close()
	assert_eq(closes[0], 2, "a later legitimate visit still closes exactly once")
	assert_eq(_root().gui_get_focus_owner(), next)


## QA85: a mismatched reply envelope cannot consume another pending action.
func test_QA85_reply_must_match_original_action_target_and_session() -> void:
	var tablet: PanelContainer = _tablet(Vector2(1920, 1080), 100)
	tablet.open()
	tablet.select("TEMP")
	tablet.ping_selected()
	var ping: Dictionary = _sent[-1].duplicate(true)
	tablet.inspect_selected()
	var inspect: Dictionary = _sent[-1].duplicate(true)
	assert_eq(str(inspect["entity"]), "PANEL_TEMP")
	var pending_seq: int = int(inspect["seq"])
	var wrong_kind: Dictionary = ping.duplicate(true)
	wrong_kind["seq"] = pending_seq
	tablet.on_reply(wrong_kind, {"ok": false, "key": "network.refused.rate_limited"})
	assert_true((tablet.get("_pending_tablet_requests") as Dictionary).has(pending_seq),
		"reply with another action/target must not consume the valid inspect request")
	var wrong_session: Dictionary = inspect.duplicate(true)
	wrong_session["session"] = "prior-session"
	tablet.on_reply(wrong_session, {"ok": false, "key": "network.refused.rate_limited"})
	assert_true((tablet.get("_pending_tablet_requests") as Dictionary).has(pending_seq),
		"reply from a different session must not consume this request")
	tablet.on_reply(inspect, {"ok": true})
	assert_eq(str(tablet.get("_status_text")), UiText.t("tablet.inspected"),
		"the genuine inspect response is still accepted after mismatched envelopes")
	assert_false((tablet.get("_pending_tablet_requests") as Dictionary).has(pending_seq))
	tablet.close()


## QA86: a new action invalidates an old visible result until acknowledged.
func test_QA86_new_dispatch_clears_previous_action_result_until_new_reply() -> void:
	var tablet: PanelContainer = _tablet(Vector2(1280, 720), 150)
	tablet.open()
	tablet.select("TEMP")
	tablet.ping_selected()
	var ping: Dictionary = _sent[-1].duplicate(true)
	tablet.on_reply(ping, {"ok": true})
	var old_message: String = str(tablet.get("_status_text"))
	assert_true(old_message != "")
	var feedback: Label = tablet.get("_feedback_label") as Label
	assert_true(feedback.visible)
	tablet.inspect_selected()
	var inspect: Dictionary = _sent[-1].duplicate(true)
	assert_eq(str(inspect["type"]), "inspect")
	assert_eq(str(tablet.get("_status_text")), "",
		"old Ping success must not remain visible while a newer Inspect is pending")
	assert_false(feedback.visible, "old action banner disappears immediately")
	tablet.on_reply(ping, {"ok": false, "key": "network.refused.rate_limited"})
	assert_eq(str(tablet.get("_status_text")), "",
		"late duplicate Ping feedback cannot reappear as the new action result")
	tablet.on_reply(inspect, {"ok": false, "key": "network.refused.rate_limited"})
	assert_true(str(tablet.get("_status_text")) != "")
	assert_true(str(tablet.get("_status_text")) != old_message,
		"current Inspect refusal replaces obsolete Ping success")
	assert_true(feedback.visible, "the newest result is shown in the persistent feedback area")
	tablet.close()


## QA96: a preconstructed visible tablet is not yet a modal input owner.
func test_QA96_inactive_prebuilt_tablet_does_not_consume_controller_zoom() -> void:
	var tablet: PanelContainer = _tablet(Vector2(1280, 720), 150)
	assert_false(bool(tablet.get("_visit_open")))
	assert_true(tablet.is_visible_in_tree(), "prebuilt view is present before its first modal visit")
	var map: Container = tablet.get("map") as Container
	var initial: int = int(map.get("_wanted_zoom_index"))
	var trigger: InputEventJoypadMotion = InputEventJoypadMotion.new()
	trigger.axis = JOY_AXIS_TRIGGER_RIGHT
	trigger.axis_value = 1.0
	tablet._input(trigger)
	assert_eq(int(map.get("_wanted_zoom_index")), initial,
		"inactive UI must leave the world/controller trigger alone")
	assert_false(bool(tablet.get("_right_trigger_held")),
		"an inactive event cannot arm the modal's trigger latch")
	tablet.open()
	tablet._input(trigger)
	assert_eq(int(map.get("_wanted_zoom_index")), initial + 1,
		"the same controller trigger works after the modal explicitly opens")
	tablet.close()
	var after_close: int = int(map.get("_wanted_zoom_index"))
	var left: InputEventJoypadMotion = InputEventJoypadMotion.new()
	left.axis = JOY_AXIS_TRIGGER_LEFT
	left.axis_value = 1.0
	tablet._input(left)
	assert_eq(int(map.get("_wanted_zoom_index")), after_close,
		"a closed visit cannot zoom through late input")
	assert_false(bool(tablet.get("_left_trigger_held")))


## QA95: synchronous outbox callbacks must not trigger nested sends from
## the same tablet, which would overwrite the expected sequence for the first.
func test_QA95_reentrant_tablet_action_cannot_corrupt_original_dispatch() -> void:
	var tablet: PanelContainer = _tablet(Vector2(1280, 720), 150)
	tablet.open()
	tablet.select("TEMP")
	var outbox: RefCounted = tablet.get("_bound_outbox")
	var attempted: Array[bool] = [false]
	var nested: Callable = func(_envelope: Dictionary) -> void:
		if attempted[0]:
			return
		attempted[0] = true
		tablet.ping_selected()
	outbox.sent.connect(nested)
	var start_count: int = _sent.size()
	tablet.ping_selected()
	outbox.sent.disconnect(nested)
	assert_true(attempted[0], "fixture attempted to reenter the same tablet while sending")
	assert_eq(_sent.size(), start_count + 1, "one user action emits one request, not two")
	var original: Dictionary = _sent[-1].duplicate(true)
	assert_true((tablet.get("_pending_tablet_requests") as Dictionary).has(int(original["seq"])),
		"the first request remains properly correlated")
	tablet.on_reply(original, {"ok": true})
	assert_true(str(tablet.get("_status_text")) != "",
		"the original acknowledgment remains visible after the nested attempt")
	tablet.close()


## QA94: never turn malformed host reply values into success via Variant coercion.
func test_QA94_malformed_result_flag_cannot_consume_correlated_reply() -> void:
	var tablet: PanelContainer = _tablet(Vector2(1280, 720), 150)
	tablet.open()
	tablet.select("TEMP")
	tablet.ping_selected()
	var sent: Dictionary = _sent[-1].duplicate(true)
	for malformed: Dictionary in [{"ok": "false"}, {"ok": 1}, {"ok": null}, {}]:
		tablet.on_reply(sent, malformed)
		assert_eq(str(tablet.get("_status_text")), "", "invalid result cannot paint a successful Ping")
		assert_true((tablet.get("_pending_tablet_requests") as Dictionary).has(int(sent["seq"])),
			"bad response cannot consume the outstanding authentic request")
	tablet.on_reply(sent, {"ok": false, "key": "network.refused.rate_limited"})
	assert_true(str(tablet.get("_status_text")).contains(UiText.t("network.refused.rate_limited")),
		"genuine boolean refusal is still visible")
	tablet.inspect_selected()
	var inspected: Dictionary = _sent[-1].duplicate(true)
	tablet.on_reply(inspected, {"ok": true})
	assert_eq(str(tablet.get("_status_text")), UiText.t("tablet.inspected"),
		"genuine boolean success remains usable")
	tablet.close()


## QA93: incomplete or mismatched snapshots may arrive during modal refresh.
## Reject them without losing the last known map, selection, focus or reply.
func test_QA93_tablet_rejects_malformed_refresh_without_losing_focus_or_reply() -> void:
	var tablet: PanelContainer = _tablet(Vector2(1280, 720), 150)
	tablet.open()
	tablet.select("TEMP")
	# Selection and controller focus are distinct. Model a real navigation
	# to TEMP so a valid rebuild correctly restores that node's focus.
	var target: Control = (tablet.map.nodes["TEMP"] as Control)
	target.grab_focus()
	var focus_before: Control = _root().gui_get_focus_owner()
	tablet.ping_selected()
	var pending: Dictionary = _sent[-1].duplicate(true)
	var view: Dictionary = tablet.get("_view")
	var originals: Array = [view.duplicate(true), view.duplicate(true), view.duplicate(true)]
	originals[0]["order"] = []
	(originals[1]["nodes"] as Dictionary).erase(str((originals[1]["order"] as Array)[0]))
	originals[2].erase("edges")
	for broken: Dictionary in originals:
		tablet.show_data(broken, [])
		assert_eq(tablet.get("_view"), view, "malformed refresh retains the previous valid view")
		assert_eq(str(tablet.get("selected")), "TEMP")
		assert_eq(_root().gui_get_focus_owner(), focus_before)
		assert_true((tablet.get("_pending_tablet_requests") as Dictionary).has(int(pending["seq"])))
	tablet.on_reply(pending, {"ok": true})
	assert_true(str(tablet.get("_status_text")) != "", "valid delayed feedback still displays")
	tablet.show_data(view.duplicate(true), [])
	assert_eq(str(tablet.get("selected")), "TEMP", "valid refresh remains usable")
	tablet.close()


## QA92: invalid or premature tab callbacks cannot break modal focus
## or discard a pending correlated action result.
func test_QA92_tablet_ignores_invalid_and_preinit_tab_transitions() -> void:
	var uninitialized: PanelContainer = NetworkTablet.new()
	_root().add_child(uninitialized)
	_owned.append(uninitialized)
	uninitialized.visible = false
	uninitialized.call("_show_tab", NetworkTablet.TAB_OBJECTIVES)
	assert_eq(str(uninitialized.get("tab")), NetworkTablet.TAB_NETWORK,
		"tab navigation before the first snapshot does not initialize broken views")
	var tablet: PanelContainer = _tablet(Vector2(1280, 720), 150)
	tablet.open()
	tablet.select("TEMP")
	tablet.ping_selected()
	var pending: Dictionary = _sent[-1].duplicate(true)
	var focused: Control = _root().gui_get_focus_owner()
	tablet.call("_show_tab", "invalid_or_stale")
	assert_eq(str(tablet.get("tab")), NetworkTablet.TAB_NETWORK)
	assert_eq(_root().gui_get_focus_owner(), focused,
		"rejected tab callbacks preserve controller focus")
	assert_true((tablet.get("_pending_tablet_requests") as Dictionary).has(int(pending["seq"])),
		"unsupported tab callback does not discard the pending action")
	tablet.on_reply(pending, {"ok": true})
	assert_true(str(tablet.get("_status_text")) != "", "the genuine reply remains visible")
	tablet.call("_show_tab", NetworkTablet.TAB_OBJECTIVES)
	assert_eq(str(tablet.get("tab")), NetworkTablet.TAB_OBJECTIVES)
	tablet.call("_show_tab", "")
	assert_eq(str(tablet.get("tab")), NetworkTablet.TAB_OBJECTIVES,
		"empty callbacks do not silently return to another tab")
	tablet.call("_show_tab", NetworkTablet.TAB_NETWORK)
	assert_eq(str(tablet.get("tab")), NetworkTablet.TAB_NETWORK,
		"valid tab navigation continues to work after rejected input")
	tablet.close()


## QA91: even while a tablet gate call is executing, nested shared-outbox
## sends must not borrow the tablet's origin or overwrite its latest sequence.
func test_QA91_reentrant_shared_outbox_send_cannot_hijack_tablet_request() -> void:
	var tablet: PanelContainer = _tablet(Vector2(1280, 720), 150)
	tablet.open()
	tablet.select("TEMP")
	var outbox: RefCounted = tablet.get("_bound_outbox")
	var did_inject: Array[bool] = [false]
	var nested_send: Callable = func(_envelope: Dictionary) -> void:
		if did_inject[0]:
			return
		did_inject[0] = true
		outbox.call("send", "ping", "TEMP", {"ping": "PING_LOOK"})
	outbox.sent.connect(nested_send)
	tablet.ping_selected()
	outbox.sent.disconnect(nested_send)
	assert_true(did_inject[0], "fixture nested an external Ping inside the tablet's send")
	assert_true(_sent.size() >= 2)
	var tablet_ping: Dictionary = _sent[-2].duplicate(true)
	var nested_ping: Dictionary = _sent[-1].duplicate(true)
	var pending: Dictionary = tablet.get("_pending_tablet_requests") as Dictionary
	assert_true(pending.has(int(tablet_ping["seq"])), "own tablet send is registered")
	assert_false(pending.has(int(nested_ping["seq"])), "nested external send cannot be registered")
	tablet.on_reply(nested_ping, {"ok": false, "key": "network.refused.rate_limited"})
	assert_eq(str(tablet.get("_status_text")), "", "nested refusal is not painted in the tablet")
	tablet.on_reply(tablet_ping, {"ok": true})
	assert_true(str(tablet.get("_status_text")) != "", "legitimate tablet reply still displays")
	tablet.close()


## QA90: a Ping from another UI sharing this outbox is not a tablet action.
func test_QA90_shared_outbox_activity_does_not_replace_tablet_feedback() -> void:
	var tablet: PanelContainer = _tablet(Vector2(1280, 720), 150)
	tablet.open()
	tablet.select("TEMP")
	tablet.ping_selected()
	var first: Dictionary = _sent[-1].duplicate(true)
	tablet.on_reply(first, {"ok": true})
	var tablet_feedback: String = str(tablet.get("_status_text"))
	assert_true(tablet_feedback != "")
	var outbox: RefCounted = tablet.get("_bound_outbox")
	outbox.call("send", "ping", "TEMP", {"ping": "PING_LOOK"})
	var external: Dictionary = _sent[-1].duplicate(true)
	assert_ne(int(external["seq"]), int(first["seq"]))
	assert_eq(str(tablet.get("_status_text")), tablet_feedback,
		"another caller's Ping must not clear the current tablet result")
	assert_false((tablet.get("_pending_tablet_requests") as Dictionary).has(int(external["seq"])),
		"another view's shared-outbox action must not become a tablet request")
	tablet.on_reply(external, {"ok": false, "key": "network.refused.rate_limited"})
	assert_eq(str(tablet.get("_status_text")), tablet_feedback,
		"other view's refusal cannot paint or replace the tablet result")
	tablet.inspect_selected()
	var own_inspect: Dictionary = _sent[-1].duplicate(true)
	tablet.on_reply(own_inspect, {"ok": true})
	assert_eq(str(tablet.get("_status_text")), UiText.t("tablet.inspected"),
		"real tablet Inspect continues working after unrelated sends")
	tablet.close()


## QA89: no unsent or malformed acknowledgment can manufacture a result.
func test_QA89_tablet_requires_integer_sequence_and_pending_request() -> void:
	var tablet: PanelContainer = _tablet(Vector2(1280, 720), 150)
	tablet.open()
	tablet.select("TEMP")
	tablet.on_reply({"type": "ping", "entity": "TEMP"}, {"ok": true})
	assert_eq(str(tablet.get("_status_text")), "",
		"unsolicited sequence-less replies must never display")
	tablet.ping_selected()
	var valid: Dictionary = _sent[-1].duplicate(true)
	var malformed: Dictionary = valid.duplicate(true)
	malformed["seq"] = str(valid["seq"])
	tablet.on_reply(malformed, {"ok": true})
	assert_eq(str(tablet.get("_status_text")), "",
		"numeric-string sequence is not a genuine outbox acknowledgment")
	assert_true((tablet.get("_pending_tablet_requests") as Dictionary).has(int(valid["seq"])),
		"invalid replies cannot consume pending valid requests")
	var unknown: Dictionary = valid.duplicate(true)
	unknown["seq"] = int(valid["seq"]) + 1000
	tablet.on_reply(unknown, {"ok": true})
	assert_eq(str(tablet.get("_status_text")), "", "unknown sequence does not render")
	tablet.on_reply(valid, {"ok": false, "key": "network.refused.rate_limited"})
	assert_true(str(tablet.get("_status_text")).contains(UiText.t("network.refused.rate_limited")),
		"a correlated host refusal still displays correctly")
	tablet.close()


## QA88: the shared feedback area belongs to the newest dispatch even across
## distinct Ping/Inspect action kinds. Separate action/target sequence tracking
## alone cannot guarantee latest-action-wins presentation.
func test_QA88_older_cross_action_reply_cannot_preempt_latest_pending_action() -> void:
	var tablet: PanelContainer = _tablet(Vector2(1280, 720), 150)
	tablet.open()
	tablet.select("TEMP")
	tablet.ping_selected()
	var older_ping: Dictionary = _sent[-1].duplicate(true)
	tablet.inspect_selected()
	var newer_inspect: Dictionary = _sent[-1].duplicate(true)
	assert_eq(str(newer_inspect["type"]), "inspect")
	tablet.on_reply(older_ping, {"ok": true})
	assert_eq(str(tablet.get("_status_text")), "",
		"late Ping success must not appear while newer Inspect is unanswered")
	assert_true((tablet.get("_pending_tablet_requests") as Dictionary).has(int(newer_inspect["seq"])),
		"the newer Inspect stays pending despite the old Ping reply")
	tablet.on_reply(newer_inspect, {"ok": true})
	assert_eq(str(tablet.get("_status_text")), UiText.t("tablet.inspected"),
		"the latest Inspect receives the persistent feedback area")
	# Reverse the kinds: an older Inspect may not preempt the next Ping.
	tablet.inspect_selected()
	var older_inspect: Dictionary = _sent[-1].duplicate(true)
	tablet.ping_selected()
	var newer_ping: Dictionary = _sent[-1].duplicate(true)
	tablet.on_reply(older_inspect, {"ok": false, "key": "network.refused.rate_limited"})
	assert_eq(str(tablet.get("_status_text")), "",
		"late Inspect refusal must not appear while newer Ping is pending")
	tablet.on_reply(newer_ping, {"ok": true})
	assert_true(str(tablet.get("_status_text")) != "",
		"latest Ping confirmation displays normally")
	tablet.close()


## QA87: only an active visible Network visit may send or display actions.
func test_QA87_tablet_intents_require_active_network_visit() -> void:
	var tablet: PanelContainer = _tablet(Vector2(1920, 1080), 100)
	tablet.select("TEMP")
	var count: int = _sent.size()
	tablet.inspect_selected()
	tablet.ping_selected()
	assert_eq(_sent.size(), count, "an instantiated but unopened tablet cannot send")
	tablet.on_reply({"type": "ping", "entity": "TEMP"}, {"ok": true})
	assert_eq(str(tablet.get("_status_text")), "",
		"an unopened tablet cannot display unexpected replies")
	tablet.open()
	tablet._show_tab(NetworkTablet.TAB_OBJECTIVES)
	tablet.inspect_selected()
	tablet.ping_selected()
	assert_eq(_sent.size(), count,
		"the Objectives tab cannot invoke hidden inspect or ping actions")
	tablet._show_tab(NetworkTablet.TAB_NETWORK)
	tablet.inspect_selected()
	tablet.ping_selected()
	assert_eq(_sent.size(), count + 2, "both read-only actions work during active Network visit")
	assert_eq(str(_sent[-2]["type"]), "inspect")
	assert_eq(str(_sent[-1]["type"]), "ping")
	tablet.close()
	tablet.inspect_selected()
	tablet.ping_selected()
	assert_eq(_sent.size(), count + 2, "queued actions cannot dispatch after closing")
	tablet.on_reply({"type": "ping", "entity": "TEMP"}, {"ok": true})
	assert_eq(str(tablet.get("_status_text")), "", "closed tablet ignores replies")


## QA79: slow replies cannot replace the outcome of a newer same-target action.
func test_QA79_newest_same_target_reply_wins_and_pending_requests_are_bounded() -> void:
	var tablet: PanelContainer = _tablet(Vector2(1920, 1080), 100)
	tablet.open()
	tablet.ping_selected()
	var older: Dictionary = _sent[-1].duplicate(true)
	tablet.ping_selected()
	var newer: Dictionary = _sent[-1].duplicate(true)
	tablet.on_reply(older, {"ok": false, "key": "network.refused.rate_limited"})
	assert_eq(str(tablet.get("_status_text")), "",
		"an older reply cannot preempt the newer pending action")
	tablet.on_reply(newer, {"ok": true})
	var accepted: String = str(tablet.get("_status_text"))
	assert_true(accepted != "", "the most recent reply remains legible")
	tablet.on_reply(older, {"ok": false, "key": "network.refused.rate_limited"})
	assert_eq(str(tablet.get("_status_text")), accepted,
		"an older refusal cannot overwrite a newer success")
	# Missing network replies must not cause an unbounded tablet request cache.
	for i: int in NetworkTablet.MAX_PENDING_TABLET_REPLIES + 8:
		tablet.ping_selected()
	assert_true((tablet.get("_pending_tablet_requests") as Dictionary).size() <= NetworkTablet.MAX_PENDING_TABLET_REPLIES,
		"pending UI request bookkeeping remains bounded")
	tablet.on_reply(_sent[-1], {"ok": true})
	assert_true(str(tablet.get("_status_text")) != "", "the last tracked response still works after eviction")
	tablet.close()


## QA74: delayed network replies must not populate a different tab.
func test_QA74_objectives_tab_clears_and_ignores_network_action_feedback() -> void:
	var tablet: PanelContainer = _tablet(Vector2(1920, 1080), 100)
	tablet.open()
	tablet.ping_selected()
	var before_tab: Dictionary = _sent[-1].duplicate(true)
	tablet.on_reply(before_tab, {"ok": true})
	assert_true(str(tablet.get("_status_text")) != "")
	tablet._show_tab(NetworkTablet.TAB_OBJECTIVES)
	assert_eq(str(tablet.get("_status_text")), "",
		"network-only feedback must not survive into Objectives")
	tablet.on_reply(before_tab,
		{"ok": false, "key": "network.refused.rate_limited"})
	assert_eq(str(tablet.get("_status_text")), "",
		"a late reply in Objectives must not resurrect a previous network action")
	tablet._show_tab(NetworkTablet.TAB_NETWORK)
	assert_eq(str(tablet.get("_status_text")), "",
		"returning to Network does not present old asynchronous feedback")
	tablet.ping_selected()
	var after_tab: Dictionary = _sent[-1].duplicate(true)
	tablet.on_reply(after_tab, {"ok": true})
	assert_true(str(tablet.get("_status_text")) != "",
		"fresh responses on the active Network tab remain readable")
	tablet.close()


## QA73: analog trigger samples must step tablet zoom only on press edges.
func test_QA73_held_joypad_triggers_do_not_repeat_zoom_or_rearm_on_stick_motion() -> void:
	var tablet: PanelContainer = _tablet(Vector2(1920, 1080), 100)
	tablet.open()
	var network_map: Container = tablet.map
	var initial: int = int(network_map.get("_wanted_zoom_index"))
	var trigger: InputEventJoypadMotion = InputEventJoypadMotion.new()
	trigger.axis = JOY_AXIS_TRIGGER_RIGHT
	trigger.axis_value = 1.0
	tablet._input(trigger)
	assert_eq(int(network_map.get("_wanted_zoom_index")), initial + 1)
	tablet._input(trigger)
	assert_eq(int(network_map.get("_wanted_zoom_index")), initial + 1,
		"held trigger samples cannot race the zoom to maximum")
	var stick: InputEventJoypadMotion = InputEventJoypadMotion.new()
	stick.axis = JOY_AXIS_RIGHT_X
	stick.axis_value = 0.4
	tablet._input(stick)
	tablet._input(trigger)
	assert_eq(int(network_map.get("_wanted_zoom_index")), initial + 1,
		"unrelated stick motion does not rearm a held trigger")
	trigger.axis_value = 0.0
	tablet._input(trigger)
	trigger.axis_value = 1.0
	tablet._input(trigger)
	assert_eq(int(network_map.get("_wanted_zoom_index")), initial + 2,
		"a real release and re-press requests exactly one more zoom step")
	var left: InputEventJoypadMotion = InputEventJoypadMotion.new()
	left.axis = JOY_AXIS_TRIGGER_LEFT
	left.axis_value = 1.0
	tablet._input(left)
	tablet._input(left)
	assert_eq(int(network_map.get("_wanted_zoom_index")), initial + 1,
		"left trigger also steps exactly once when held")
	tablet.close()


## QA72: a refreshed node catalog cannot carry old-node feedback to a new selection.
func test_QA72_refresh_rehomes_removed_selection_without_stale_feedback() -> void:
	var tablet: PanelContainer = _tablet(Vector2(1920, 1080), 100)
	tablet.open()
	var view: Dictionary = tablet.get("_view")
	var first: String = str(view["order"][0])
	var second: String = str(view["order"][1])
	tablet.call("select", first)
	tablet.ping_selected()
	var first_ping: Dictionary = _sent[-1].duplicate(true)
	tablet.call("on_reply", first_ping, {"ok": true})
	assert_true(str(tablet.get("_status_text")) != "")
	var updated: Dictionary = view.duplicate(true)
	updated["order"] = [second]
	updated["nodes"] = {second: (view["nodes"] as Dictionary)[second]}
	updated["edges"] = []
	tablet.call("show_data", updated, [])
	assert_eq(tablet.selected, second, "selection must be valid in refreshed authoritative view")
	assert_eq(str(tablet.get("_status_text")), "", "old node feedback cannot describe the replacement")
	assert_true(tablet.map.nodes.has(second), "replacement selection is focusable")
	assert_eq(_root().gui_get_focus_owner(), tablet.map.nodes[second],
		"controller focus recovers when its previous node has disappeared")
	tablet.close()


# ---------- acceptance: controller focus complete ----------

func test_V07_directional_focus_reaches_every_control_from_every_control() -> void:
	for size: Vector2 in [Vector2(1920, 1080), Vector2(1280, 720)]:
		for scale: int in [100, 150]:
			for tab: String in [NetworkTablet.TAB_NETWORK, NetworkTablet.TAB_OBJECTIVES]:
				var tablet: PanelContainer = _tablet(size, scale)
				if tab != tablet.tab:
					tablet._show_tab(tab)
					Fixture.settle(tablet)
				var where: String = "%dx%d @%d%% %s" % [size.x, size.y, scale, tab]
				var all: Array[Control] = tablet.focusables()
				assert_true(all.size() >= (18 if tab == NetworkTablet.TAB_NETWORK else 3), "%s: %d focusable controls" % [where, all.size()])
				var graph: Dictionary = {}
				for c: Control in all:
					var next: Array[Control] = []
					for side: Side in SIDES:
						var n: Control = c.find_valid_focus_neighbor(side)
						if n != null and n != c and all.has(n):
							next.append(n)
					assert_false(next.is_empty(), "%s: %s has a way out" % [where, c.name])
					graph[c] = next
				for start: Control in all:
					var seen: Dictionary = _reach(graph, start)
					var missing: Array = all.filter(func(c: Control) -> bool: return not seen.has(c)).map(func(c: Control) -> String:
						return str(c.name))
					if not missing.is_empty():
						assert_eq(missing, [], "%s: from %s the stick/D-pad cannot reach" % [where, start.name])
						break
				for c: Control in all:
					var target: float = ThemeTokens.px(float(_tokens["min_target_px"]), tablet.scale_percent) - 0.5
					assert_true(c.size.x >= target and c.size.y >= target, "%s: %s is at least the 48 px target" % [where, c.name])
				_free(tablet)


func test_V07_opening_moves_focus_in_and_closing_restores_it() -> void:
	var host: Button = Button.new()
	_root().add_child(host)
	_owned.append(host)
	host.grab_focus()
	var tablet: PanelContainer = _tablet(Vector2(1920, 1080), 100)
	tablet.visible = false
	tablet.open()
	var owner: Control = _root().gui_get_focus_owner()
	assert_true(owner != null and tablet.is_ancestor_of(owner), "focus moved into the tablet")
	assert_eq(owner, tablet.map.nodes[tablet.selected], "first focus is the selected node")
	tablet._input(_action("ui_cancel"))
	assert_false(tablet.visible, "B / Esc closes")
	assert_eq(_root().gui_get_focus_owner(), host, "closing restores the previous control")
	tablet.open()
	tablet._input(_action("map_meter"))
	assert_false(tablet.visible, "the tablet key closes it again")


func test_V07_controller_bindings_show_the_device_and_follow_remapping() -> void:
	assert_eq(UiText.binding("interact", UiText.DEVICE_KBM), "E")
	assert_eq(UiText.binding("interact", UiText.DEVICE_PAD), "A")
	assert_eq(UiText.binding("ping", UiText.DEVICE_KBM), "MMB")
	assert_eq(UiText.binding("ping", UiText.DEVICE_PAD), "LB")
	assert_eq(UiText.binding("ui_accept", UiText.DEVICE_PAD), "A", "controller Accept is A on the tablet")
	assert_eq(UiText.binding("ui_cancel", UiText.DEVICE_PAD), "B", "controller Back is B")
	var original: Array[InputEvent] = InputMap.action_get_events("interact")
	InputMap.action_erase_events("interact")
	var f: InputEventKey = InputEventKey.new()
	f.physical_keycode = KEY_F
	InputMap.action_add_event("interact", f)
	assert_eq(UiText.binding("interact", UiText.DEVICE_KBM), "F", "a remapped action shows its new key")
	InputMap.action_erase_events("interact")
	for e: InputEvent in original:
		InputMap.action_add_event("interact", e)


# ---------- acceptance: 150 % usable; reflow under longer text ----------

func test_V07_hud_fits_the_safe_area_at_every_size_scale_and_locale() -> void:
	for locale: String in LOCALES:
		UiText.set_locale(locale)
		var view: Dictionary = Fixture.worst_hud_view()
		for size: Vector2 in SIZES:
			for scale: int in SCALES:
				var hud: Container = _hud(size, scale, view)
				var where: String = "HUD %dx%d @%d%% %s" % [size.x, size.y, scale, locale]
				var safe: float = ThemeTokens.safe_area(_tokens, size)
				var inner: Rect2 = Rect2(Vector2(safe, safe), size - Vector2(safe, safe) * 2.0)
				var regions: Array[Control] = hud.regions()
				for r: Control in regions:
					assert_true(Fixture.rect_inside(r.get_rect(), inner), "%s: %s inside the 80 px safe area %s" % [where, r.name, r.get_rect()])
				for i: int in regions.size():
					for j: int in range(i + 1, regions.size()):
						assert_false(regions[i].get_rect().intersects(regions[j].get_rect()),
							"%s: %s overlaps %s" % [where, regions[i].name, regions[j].name])
					assert_false(regions[i].get_rect().intersects(hud.reticle.get_rect()), "%s: %s covers the reticle" % [where, regions[i].name])
				assert_true(hud.prompt_card.position.y > hud.reticle.get_rect().end.y, "%s: prompt below the reticle" % where)
				_assert_no_overflow(hud, where)
				_free(hud)
	assert_eq(UiText.missing(), [] as Array[String], "every HUD string has English text")


func test_V07_tablet_fits_and_every_node_scrolls_fully_into_view() -> void:
	for locale: String in LOCALES:
		UiText.set_locale(locale)
		for size: Vector2 in SIZES:
			for scale: int in SCALES:
				var tablet: PanelContainer = _tablet(size, scale)
				var where: String = "tablet %dx%d @%d%% %s" % [size.x, size.y, scale, locale]
				for nid: String in ["JE", "GRID"]:  # JE carries the longest evidence list
					tablet.select(nid)
					Fixture.settle(tablet)
					_assert_no_overflow(tablet, where + " " + nid, [tablet.map, tablet.detail_scroll])
					var bar: VScrollBar = tablet.detail_scroll.get_v_scroll_bar()
					var content_h: float = tablet.detail_scroll.get_child(0).get_combined_minimum_size().y
					if content_h > tablet.detail_scroll.size.y + 0.5:
						assert_true(bar.visible, "%s %s: long evidence shows a scroll position indicator" % [where, nid])
					assert_true(Fixture.rect_inside(tablet.ping_button.get_global_rect(), tablet.get_global_rect()),
						"%s %s: Ping is never below the fold" % [where, nid])
				var map: Container = tablet.map
				for nid: String in map.nodes:
					map.ensure_visible(nid)
					Fixture.settle(tablet)
					var r: Rect2 = map.node_rect(nid)
					if r.size.x <= map.size.x and r.size.y <= map.size.y:
						assert_true(Fixture.rect_inside(r, Rect2(Vector2.ZERO, map.size)), "%s: node %s scrolls fully into view" % [where, nid])
					else:
						assert_true(false, "%s: node %s %s is larger than the map %s" % [where, nid, r.size, map.size])
					_assert_no_overflow(map.nodes[nid], "%s node %s" % [where, nid])
				_free(tablet)
	assert_eq(UiText.missing(), [] as Array[String], "every tablet string has English text")


func test_V07_hud_follows_the_reference_layout_at_100_percent() -> void:
	var hud: Container = _hud(Vector2(1920, 1080), 100, Fixture.hud_view(_ctx))
	assert_eq(hud.objective_card.position, Vector2(80, 80), "objective top-left at the safe area (S06 x=80)")
	assert_eq(hud.objective_card.size.x, 420.0, "420 px objective card")
	assert_eq(hud.crew_card.get_rect().end.x, 1840.0, "crew top-right")
	assert_eq(hud.reticle.get_rect().get_center(), Vector2(960, 540), "reticle at the center")
	assert_eq(hud.prompt_card.position, Vector2(680, 680), "prompt at x=680, y=680, 560 px wide (S06)")
	assert_eq(hud.prompt_card.size.x, 560.0)
	assert_eq(hud.tool_card.position.x, 80.0, "tools bottom-left")
	assert_eq(hud.tool_card.get_rect().end.y, 1000.0)
	assert_eq(hud.event_card.get_rect().end, Vector2(1840, 1000), "event bottom-right")
	var rows: Array[Node] = hud.objective_card.find_children("Objective_*", "", true, false)
	assert_true(rows.size() <= 3, "at most three objective rows (blueprint p.11)")


func test_V07_objective_card_never_shows_more_than_three_rows() -> void:
	var view: Dictionary = Fixture.worst_hud_view()
	var many: Array[Dictionary] = []
	for i: int in 6:
		many.append({"id": "O%d" % i, "text_key": "objective.c01.extract", "status": "active"})
	view["objectives"] = many
	var hud: Container = _hud(Vector2(1920, 1080), 100, view)
	assert_eq(hud.objective_card.find_children("Objective_*", "", true, false).size(), int(_tokens["max_objective_rows"]))


# ---------- status: icon + text + token color ----------

func test_V07_every_status_widget_is_icon_text_and_token_color() -> void:
	var hud: Container = _hud(Vector2(1920, 1080), 150, Fixture.worst_hud_view())
	var tablet: PanelContainer = _tablet(Vector2(1920, 1080), 150)
	tablet.select("JE")
	var chips: Array[Control] = []
	for root: Control in [hud, tablet]:
		for c: Control in Fixture.controls(root):
			if c.get_script() == StatusChip:
				chips.append(c)
	assert_true(chips.size() >= 25, "chips found: %d" % chips.size())
	var groups: Dictionary = {}
	for chip: Control in chips:
		var e: Dictionary = StatusChip.entry(chip.group, chip.state)
		var where: String = "%s.%s" % [chip.group, chip.state]
		groups[chip.group] = true
		assert_false(e.is_empty(), "%s is a state in status_states.json" % where)
		var tint: Color = ThemeTokens.color(_tokens, str(e["color"]))
		var label: Label = chip.label
		var icon: TextureRect = chip.icon_rect
		assert_false(label.text.strip_edges().is_empty(), "%s has text, not color alone" % where)
		assert_eq(label.get_theme_color("font_color"), tint, "%s text in its token color" % where)
		assert_eq(icon.self_modulate, tint, "%s icon tinted with its token color" % where)
		assert_true(icon.texture != null, "%s has an icon" % where)
		if icon.texture != null:
			assert_eq(icon.texture.resource_path, IconRaster.export_path(str(e["icon"]),
				IconRaster.export_px_for_scale(ceili(icon.get_meta("scale_percent")))), "%s draws its own icon at the scale's export" % where)
		assert_true(icon.is_visible_in_tree() and label.is_visible_in_tree(), "%s icon and text both shown" % where)
	for g: String in ["objectives", "other", "supply", "findings", "equipment"]:
		assert_true(groups.has(g), "chips cover %s" % g)


func test_V07_tablet_shows_measured_values_only() -> void:
	var view: Dictionary = Fixture.tablet_view(_ctx)
	var n: Dictionary = view["nodes"]
	assert_eq([n["APT_W"]["status_state"], n["MARKET"]["status_state"]], ["restored", "restored"], "west on grid supply")
	assert_eq(n["PUMP"]["status_state"], "temporary", "pump on the generator")
	assert_eq(n["PUB"]["status_state"], "dark")
	assert_eq([n["JE"]["status_group"], n["JE"]["status_state"]], ["findings", "NO_SOURCE"], "JE: Mira's measurement")
	assert_true((n["JE"]["findings"] as Array).any(func(f: Dictionary) -> bool: return f["code"] == "FEED_OPEN"), "broken trunk measured")
	assert_eq([n["TEMP"]["status_group"], n["TEMP"]["status_state"]], ["other", "unknown"], "never inspected: unknown")
	assert_has_text(n["TEMP"]["lines"], UiText.t("tablet.unknown_measure"))
	assert_true(n["JW"]["needs_reinspect"], "JW changed since P1 measured it before the repair")
	assert_has_text(n["JW"]["lines"], UiText.t("tablet.reinspect"))
	assert_has_text(n["GRID"]["lines"], UiText.tf("tablet.source_load", [9, 24]))
	assert_eq(n["JE"].get("worker_text"), UiText.tf("tablet.worker", ["Mira", UiText.t("repair.c01.east_trunk")]), "lock owner shown")
	assert_false(n["JE"].has("access_key"), "the drained basement opened the east repair")
	var hud: Dictionary = Fixture.hud_view(_ctx)
	var mira: Dictionary = (hud["crew"] as Array).filter(func(r: Dictionary) -> bool: return r["player"] == "P2")[0]
	assert_eq([mira["task_state"], mira["task_text"]], ["lock_owner", UiText.t("repair.c01.east_trunk")], "crew row shows the lock")
	assert_eq((hud["crew"] as Array)[0]["player"], "P1", "the local player is listed first")
	var styles: Dictionary = {}
	for e: Dictionary in view["edges"]:
		styles[e["id"]] = e["style"]
	assert_eq(styles["E_GRID_JW"], "energized_grid")
	assert_eq(styles["E_GEN_TEMP"], "energized_temp")
	assert_eq(styles["E_GRID_JE"], "fault", "the broken trunk shows only because the meter measured it")
	assert_eq(styles["E_TEMP_PUB"], "unknown", "an unmeasured dead route is not shown as fact")
	var tablet_nodes: Array = []
	for cell: Dictionary in Fixture.content()["tablet"]["nodes"]:
		tablet_nodes.append(cell["id"])
	tablet_nodes.sort()
	var grid_nodes: Array = (Fixture.content()["grid"]["nodes"] as Array).map(func(x: Dictionary) -> String: return x["id"])
	grid_nodes.sort()
	assert_eq(tablet_nodes, grid_nodes, "tablet.json places every grid node exactly once")


func test_V07_every_content_text_key_has_english_text() -> void:
	var keys: Dictionary = {}
	_keys_in(Runner.json("res://content/ui/status_states.json"), keys)
	_keys_in(Runner.json("res://content/comms.json"), keys)
	for f: String in ["mission.json", "repairs.json", "tablet.json"]:
		_keys_in(Runner.json(Fixture.C01.path_join(f)), keys)
	assert_true(keys.size() > 60, "keys found: %d" % keys.size())
	var missing: Array = keys.keys().filter(func(k: String) -> bool: return not UiText.has(k))
	missing.sort()
	assert_eq(missing, [], "content keys without English text in content/ui/strings/en.json")


func test_V07_pseudo_locale_is_35_percent_longer_and_keeps_placeholders() -> void:
	var text: String = UiText.pseudo("Measured: %d / %d PU")
	assert_true(text.length() >= ceili("Measured: %d / %d PU".length() * 1.35), text)
	assert_eq(text.count("%d"), 2, "placeholders survive")
	assert_eq((text % [9, 12]).contains("9"), true)
	UiText.set_locale(UiText.LOCALE_PSEUDO)
	assert_ne(UiText.t("tablet.title"), "Network tablet")
	assert_eq(UiText.binding("interact", UiText.DEVICE_KBM), "E", "key caps are not pseudo-localized")


# ---------- helpers ----------

func assert_has_text(lines: Array, text: String) -> void:
	assert_true(lines.has(text), "%s in %s" % [text, str(lines)])


func _assert_no_overflow(root: Control, where: String, skip_below: Array = []) -> void:
	var screen: Rect2 = root.get_global_rect()
	for c: Control in Fixture.controls(root):
		if not c.is_visible_in_tree() or c == root:
			continue
		if skip_below.any(func(s: Control) -> bool: return s != c and s.is_ancestor_of(c)):
			continue
		var parent: Control = c.get_parent() as Control
		if parent != null and not (parent is ScrollContainer):
			if not Fixture.rect_inside(c.get_global_rect(), parent.get_global_rect()):
				assert_true(false, "%s: %s %s spills out of %s %s" % [where, c.name, c.get_global_rect(), parent.name, parent.get_global_rect()])
				return
		var min_size: Vector2 = c.get_combined_minimum_size()
		if c.size.x + 0.75 < min_size.x or c.size.y + 0.75 < min_size.y:
			assert_true(false, "%s: %s squeezed below its minimum %s < %s" % [where, c.name, c.size, min_size])
			return
		if c is Label:
			var l: Label = c
			if l.autowrap_mode != TextServer.AUTOWRAP_OFF and l.get_line_count() > l.get_visible_line_count():
				assert_true(false, "%s: label '%s' hides lines" % [where, l.text])
				return
		if not Fixture.rect_inside(c.get_global_rect(), screen):
			assert_true(false, "%s: %s outside the screen" % [where, c.name])
			return
	assert_true(true)


func _hud(size: Vector2, scale: int, view: Dictionary) -> Container:
	var hud: Container = FieldHud.new()
	_root().add_child(hud)
	_owned.append(hud)
	hud.set_anchors_preset(Control.PRESET_TOP_LEFT)
	hud.size = size
	hud.ui_scale_percent = scale
	hud.apply(view)
	Fixture.settle(hud)
	return hud


func _tablet(size: Vector2, scale: int, live: bool = false) -> PanelContainer:
	var frame: Control = Control.new()  # the screen: the tablet takes its scale from its parent, never from itself
	_root().add_child(frame)
	frame.size = size
	var tablet: PanelContainer = NetworkTablet.new()
	frame.add_child(tablet)
	_owned.append(frame)
	tablet.set_anchors_preset(Control.PRESET_TOP_LEFT)
	tablet.size = size
	tablet.ui_scale_percent = scale
	var peer: int = _ctx["peers"][TABLET_PLAYER]
	var outbox: RefCounted = IntentOutbox.new(Runner.SESSION, func(bytes: PackedByteArray) -> Dictionary:
		return _ctx["host"].receive(peer, bytes) if live else {})
	outbox.sent.connect(func(env: Dictionary) -> void: _sent.append(env))
	tablet.setup(outbox)
	tablet.show_data(Fixture.tablet_view(_ctx), _ctx["mission"].objectives())
	Fixture.settle(tablet)
	return tablet


func _free(n: Node) -> void:
	if n is NetworkTablet:
		n = n.get_parent()  # its screen frame
	_owned.erase(n)
	n.get_parent().remove_child(n)
	n.free()


func _root() -> Window:
	return (Engine.get_main_loop() as SceneTree).root


func _action(action: StringName) -> InputEventAction:
	var ev: InputEventAction = InputEventAction.new()
	ev.action = action
	ev.pressed = true
	return ev


func _reach(graph: Dictionary, start: Control) -> Dictionary:
	var seen: Dictionary = {start: true}
	var queue: Array[Control] = [start]
	while not queue.is_empty():
		var c: Control = queue.pop_front()
		for n: Control in graph[c]:
			if not seen.has(n):
				seen[n] = true
				queue.append(n)
	return seen


func _keys_in(v: Variant, out: Dictionary) -> void:
	if v is Dictionary:
		for k: Variant in v:
			if str(k) in ["text_key", "name_key"] and v[k] is String:
				out[v[k]] = true
			else:
				_keys_in(v[k], out)
	elif v is Array:
		for x: Variant in v:
			_keys_in(x, out)


func test_V07_hud_and_tablet_scenes_load_their_scripts() -> void:
	for pair: Array in [["res://scenes/ui/field_hud.tscn", FieldHud], ["res://scenes/ui/network_tablet.tscn", NetworkTablet]]:
		var ps: PackedScene = load(pair[0]) as PackedScene
		assert_true(ps != null, "%s loads" % pair[0])
		if ps == null:
			continue
		var n: Node = ps.instantiate()
		assert_eq(n.get_script(), pair[1], "%s root runs its view script" % pair[0])
		n.free()
