extends PanelContainer
## EXP014 A09.4 — presentation-only view of SessionHost's regional state.
## All changes are emitted as existing authenticated operate_worksite intents.
## The panel never owns feeder, receipt, capacity, timer or strategy authority.

signal action_requested(action: String)

var _heading: Label
var _summary: Label
var _nodes: Label
var _assets: Label
var _reply: Label
var _feeder_button: Button
var _tie_button: Button
var _feeder: int = 0
var _tie: int = 0
var _snapshot: Dictionary = {}


func _init() -> void:
	name = "EXP014RegionalOperationsPanel"
	custom_minimum_size = Vector2(480, 0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var root: VBoxContainer = VBoxContainer.new()
	root.add_theme_constant_override("separation", 5)
	add_child(root)
	_heading = _label(root, "REGIONAL OPERATIONS / HOST-VALIDATED", "#88E2E6")
	_summary = _label(root, "No regional state", "#F3D396")
	_nodes = _label(root, "", "#DAE9E9")
	_assets = _label(root, "", "#B4C9D8")
	var strategy: HBoxContainer = HBoxContainer.new()
	root.add_child(strategy)
	_button(strategy, "Critical-first", "regional_critical")
	_button(strategy, "Resilience-first", "regional_resilience")
	var supply: HBoxContainer = HBoxContainer.new()
	root.add_child(supply)
	_button(supply, "Buffer supply", "regional_buffer")
	_button(supply, "Managed outage", "regional_managed")
	var switching: HBoxContainer = HBoxContainer.new()
	root.add_child(switching)
	_button(switching, "Previous feeder", "prev_feeder")
	_feeder_button = _button(switching, "Isolate feeder", "toggle_feeder")
	_button(switching, "Next feeder", "next_feeder")
	var standby: HBoxContainer = HBoxContainer.new()
	root.add_child(standby)
	_button(standby, "Previous tie", "prev_tie")
	_tie_button = _button(standby, "Engage tie", "toggle_tie")
	_button(standby, "Next tie", "next_tie")
	_button(root, "Replenish from restored reserve anchor", "regional_recharge")
	_reply = _label(root, "Actions require proximity to the original host worksite board.", "#F1D6B2")


func _label(parent: Control, message: String, color: String) -> Label:
	var label: Label = Label.new()
	label.text = message
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", Color(color))
	parent.add_child(label)
	return label


func _button(parent: Control, message: String, action: String) -> Button:
	var button: Button = Button.new()
	button.text = message
	button.focus_mode = Control.FOCUS_ALL
	button.pressed.connect(Callable(self, "_handle").bind(action))
	parent.add_child(button)
	return button


func _keys(source: Dictionary) -> Array[String]:
	var keys: Array[String] = []
	for key: String in source:
		keys.append(key)
	keys.sort()
	return keys


func _handle(action: String) -> void:
	if _snapshot.is_empty():
		return
	var feeders: Dictionary = _snapshot.get("feeders", {})
	var ties: Dictionary = _snapshot.get("ties", {})
	var feed_keys: Array[String] = _keys(feeders)
	var tie_keys: Array[String] = _keys(ties)
	match action:
		"prev_feeder":
			_feeder = posmod(_feeder - 1, maxi(1, feed_keys.size()))
			show_network(_snapshot)
		"next_feeder":
			_feeder = posmod(_feeder + 1, maxi(1, feed_keys.size()))
			show_network(_snapshot)
		"prev_tie":
			_tie = posmod(_tie - 1, maxi(1, tie_keys.size()))
			show_network(_snapshot)
		"next_tie":
			_tie = posmod(_tie + 1, maxi(1, tie_keys.size()))
			show_network(_snapshot)
		"toggle_feeder":
			if not feed_keys.is_empty():
				var id: String = feed_keys[_feeder % feed_keys.size()]
				var verb: String = "regional_reset:" if feeders[id]["isolated"] else "regional_isolate:"
				action_requested.emit(verb + id)
		"toggle_tie":
			if not tie_keys.is_empty():
				var id: String = tie_keys[_tie % tie_keys.size()]
				var verb: String = "regional_release:" if ties[id]["engaged"] else "regional_engage:"
				action_requested.emit(verb + id)
		_:
			action_requested.emit(action)


func show_network(state: Dictionary) -> void:
	_snapshot = state.duplicate(true)
	if state.is_empty():
		_heading.text = "REGIONAL OPERATIONS / NOT ENABLED"
		_summary.text = "No host-owned A09 regional snapshot."
		_nodes.text = ""
		_assets.text = ""
		return
	var states: Dictionary = state.get("sites", {})
	var conditions: Dictionary = state.get("site_conditions", {})
	var restored: int = 0
	var energized: int = 0
	for site: Dictionary in states.values():
		if bool(site.get("restored", false)):
			restored += 1
		if bool(site.get("energized", false)):
			energized += 1
	_heading.text = "%s / %s / SOURCE-BOUND REGIONAL NETWORK" % [
		str(state["region_id"]), str(state["level_id"])]
	_summary.text = "Risk %s | strategy %s | standby %d/%d PU | debt %d | restored %d/8 | live %d/8" % [
		str(state["source_risk"]), str(state.get("strategy", "unselected")),
		int(state["reserve_pu"]), int(state["reserve_initial_pu"]),
		int(conditions.get("service_debt", 0)), restored, energized]
	var critical: String = str(state["critical_service"])
	var danger: String = "ENDANGERED" if not states.get(critical, {}).get("energized", false) else "ENERGIZED"
	var lines: Array[String] = ["Critical %s: %s | reserve anchor %s" % [
		critical, danger, str(state["reserve_anchor"])]]
	for id: String in _keys(states):
		var site: Dictionary = states[id]
		var status: String = "LIVE" if site["energized"] else "RESTORED/DARK" if site["restored"] else "PENDING"
		lines.append("%s  %s  | next supply: %s" % [id, status,
			"READY" if site["supply_ready"] else "ISLANDED"])
	_nodes.text = "\n".join(lines)
	var feeder_ids: Array[String] = _keys(state["feeders"])
	var tie_ids: Array[String] = _keys(state["ties"])
	var asset_lines: Array[String] = []
	if not feeder_ids.is_empty():
		_feeder = posmod(_feeder, feeder_ids.size())
		var fid: String = feeder_ids[_feeder]
		var feeder: Dictionary = state["feeders"][fid]
		asset_lines.append("Feeder %s (%s → %s) / %s / fault: %s / %d PU" % [
			fid, str(feeder["from"]), str(feeder["to"]),
			"ISOLATED" if feeder["isolated"] else "CLOSED",
			str(feeder["fault"]) if feeder["fault"] != "" else "none",
			int(feeder["capacity_pu"])])
		_feeder_button.text = "Reset feeder" if feeder["isolated"] else "Isolate feeder"
	if not tie_ids.is_empty():
		_tie = posmod(_tie, tie_ids.size())
		var tid: String = tie_ids[_tie]
		var tie: Dictionary = state["ties"][tid]
		asset_lines.append("Standby %s (%s → %s) / %s / %d PU, break-before-make" % [
			tid, str(tie["from"]), str(tie["to"]),
			"ENGAGED" if tie["engaged"] else "OPEN", int(tie["capacity_pu"])])
		_tie_button.text = "Release tie" if tie["engaged"] else "Engage tie"
	asset_lines.append("Current site: %s | %s | risk pressure %d | preparation %s" % [
		"SUPPLY READY" if conditions.get("supply_ready", false) else "ISLANDED",
		"PRIMARY" if conditions.get("primary_ready", false) else "BACKUP/MANAGED",
		int(conditions.get("risk_pressure", 0)),
		str(conditions.get("prepared", "")) if conditions.get("prepared", "") != "" else "REQUIRED"])
	_assets.text = "\n".join(asset_lines)


func show_reply(reply: Dictionary) -> void:
	_reply.text = "HOST ACCEPTED: " + str(reply.get("strategy", reply.get("reserve", "state updated"))) \
		if bool(reply.get("ok", false)) else "HOST DENIED: " + str(reply.get("code", "UNKNOWN"))
