extends RefCounted
## RB01 release text check (ADR-019 point 4): no developer text on a player screen.
## Every word a player reads comes from content/ui/strings/en.json with a real name. This audit finds what slipped past:
## internal IDs (Job_001, SW_PUMP), raw snake_case (load_a), backlog and phase labels (EXP011, DS07, C01) and developer
## wording (certification, headless, host verified, dev preview).
##
## Three callers share it:
## - tests/integration/test_RB01_player_text.gd: rules, the string table, every shipped scene, the live C01 screens;
## - tools/godot/check_player_text.gd (`bash tools/check_player_text.sh`): the same scene walk as a release gate;
## - scripts/diagnostics/c01_playthrough_driver.gd: every visible text at every step of a bot-played C01 shift.
## The text nodes walked are Label, Label3D, Button (and every BaseButton with text), RichTextLabel (parsed text),
## LineEdit (text and placeholder) and AcceptDialog (title and body).

const BuildFlavor := preload("res://scripts/ui/build_flavor.gd")

const RELEASE_PRESET_NAME: String = "Windows Desktop"
const EXPORT_PRESETS_PATH: String = "res://export_presets.cfg"
const STRINGS_PATH: String = "res://content/ui/strings/en.json"
## A node in this group (and its subtree) is engineering detail, such as an F3 diagnostics overlay. It is skipped only in
## internal builds; in a release build it must not be visible at all.
const INTERNAL_ONLY_GROUP: StringName = &"internal_only_text"
## Scenes that are still packed into the release export but that no release screen can open. Each needs a reason and a
## test that proves the release path to it is closed (test_RB01_player_text.gd). They are removed in RB14.
const INTERNAL_ONLY_SCENES: Dictionary = {
	"res://scenes/expeditions/mission_stage.tscn":
		"EXP dispatch stage: opened only from the dispatch atlas, which release builds hide (ADR-019 point 5); removed in RB14",
}

## [rule name, PCRE pattern]. Text is checked as shown, after format arguments are filled in.
const RULES: Array[Array] = [
	# Job_001, JOB_7, load_3: a word glued to a number with an underscore.
	["internal_id", "\\b[A-Za-z]+_\\d+"],
	# SW_PUMP, GEN_PORTABLE, LATCH_PUMP_DRAIN: an upper-case authored entity ID.
	["internal_id", "\\b[A-Z][A-Z0-9]*(?:_[A-Z0-9]+)+\\b"],
	["internal_id", "(?i)\\bjob_"],
	# load_a, offline_resume: raw snake_case.
	["snake_case", "\\b[a-z][a-z0-9]*(?:_[a-z0-9]+)+\\b"],
	# EXP011, EXP, DS07, QA140, RB01 and backlog / contract codes (C01, CT03, F02). Function keys (F1-F12) are key names.
	["phase_label", "\\bEXP\\b|\\bDS\\b"],
	["phase_label", "\\b(?!F\\d{1,2}\\b)[A-Z]{1,4}-?\\d{2,3}\\b"],
	["developer_wording", "(?i)certif|headless|host[ -]verifi|playability|qualif|gr[ae]y ?box|lookdev|placeholder" +
		"|\\bdebug\\b|\\btodo\\b|\\bfixme\\b|\\bdev\\b|development (?:build|preview)|approach cue|not host state" +
		"|source[ -](?:bound|pinned|only)|experimental"],
	["file_path", "res://|user://"],
]

static var _compiled: Array[Array] = []


## Rule names the text breaks, sorted and unique; empty when the text is fit for a player.
static func violations(text: String) -> Array[String]:
	var found: Dictionary = {}
	if text.strip_edges() == "":
		return []
	for rule: Array in _rules():
		var regex: RegEx = rule[1]
		if regex.search(text) != null:
			found[str(rule[0])] = true
	var out: Array[String] = []
	out.assign(found.keys())
	out.sort()
	return out


## Every player-readable string a node carries (empty for nodes that show no text).
static func node_texts(node: Node) -> Array[String]:
	var out: Array[String] = []
	if node is RichTextLabel:
		out.append((node as RichTextLabel).get_parsed_text())
	elif node is Label:
		out.append((node as Label).text)
	elif node is Label3D:
		out.append((node as Label3D).text)
	elif node is Button:
		out.append((node as Button).text)
		out.append((node as Button).tooltip_text)
	elif node is LineEdit:
		out.append((node as LineEdit).text)
		out.append((node as LineEdit).placeholder_text)
	if node is AcceptDialog:
		out.append((node as AcceptDialog).title)
		out.append((node as AcceptDialog).dialog_text)
	return out.filter(func(t: String) -> bool: return t.strip_edges() != "")


static func is_text_node(node: Node) -> bool:
	return node is Label or node is Label3D or node is Button or node is RichTextLabel or node is LineEdit \
		or node is AcceptDialog


## Findings under root: [{path, text, rules, visible}]. visible_only=false also reports hidden text nodes, because a hidden
## panel (pause, results, tablet) is a screen the player opens later.
static func scan_tree(root: Node, visible_only: bool) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	_scan(root, root, visible_only, out)
	return out


## Number of text nodes a scan would read (a scan of zero nodes proves nothing).
static func count_text_nodes(root: Node, visible_only: bool) -> int:
	var n: int = 0
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node.is_in_group(INTERNAL_ONLY_GROUP):
			continue
		if is_text_node(node) and (not visible_only or _visible(node)):
			n += 1
		for child: Node in node.get_children(true):
			stack.append(child)
	return n


## Every string in the table: [{key, text, rules}]. Placeholders (%s, %d) are checked by the callers that fill them.
static func scan_table(strings: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var keys: Array = strings.keys()
	keys.sort()
	for key: Variant in keys:
		var text: String = str(strings[key])
		var rules: Array[String] = violations(text)
		if not rules.is_empty():
			out.append({"key": str(key), "text": text, "rules": rules})
	return out


static func load_table() -> Dictionary:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(STRINGS_PATH))
	return (data as Dictionary).get("strings", {}) if data is Dictionary else {}


## Every .tscn the release export packs: all scenes under res:// minus the release preset's exclude filter, minus folders
## Godot does not import (.gdignore) and hidden folders. Sorted, so reports are stable.
static func shipped_scenes() -> Array[String]:
	var excludes: PackedStringArray = release_exclude_filters()
	var all: Array[String] = []
	_collect_scenes("res://", all)
	var out: Array[String] = []
	for path: String in all:
		var rel: String = path.trim_prefix("res://")
		var excluded: bool = false
		for pattern: String in excludes:
			if rel.match(pattern):
				excluded = true
				break
		if not excluded:
			out.append(path)
	out.sort()
	return out


static func release_exclude_filters() -> PackedStringArray:
	var cfg: ConfigFile = ConfigFile.new()
	var out: PackedStringArray = []
	if cfg.load(EXPORT_PRESETS_PATH) != OK:
		return out
	for section: String in cfg.get_sections():
		if str(cfg.get_value(section, "name", "")) != RELEASE_PRESET_NAME:
			continue
		for part: String in str(cfg.get_value(section, "exclude_filter", "")).split(",", false):
			if part.strip_edges() != "":
				out.append(part.strip_edges())
	return out


static func format_findings(findings: Array[Dictionary]) -> String:
	var lines: Array[String] = []
	for f: Dictionary in findings:
		lines.append("%s %s: \"%s\"" % [str(f.get("rules", [])), str(f.get("path", f.get("key", ""))),
			str(f.get("text", "")).replace("\n", " / ").left(160)])
	return "\n".join(lines)


static func _scan(root: Node, node: Node, visible_only: bool, out: Array[Dictionary]) -> void:
	if _skip_subtree(node):
		return
	if node.is_in_group(INTERNAL_ONLY_GROUP):
		# Release build: engineering text may exist only while hidden; on screen it is a finding.
		if _visible(node):
			out.append({"path": str(root.get_path_to(node)), "text": "(internal-only text visible in a release build)",
				"rules": ["internal_overlay"], "visible": true})
		return
	if is_text_node(node) and (not visible_only or _visible(node)):
		for text: String in node_texts(node):
			var rules: Array[String] = violations(text)
			if not rules.is_empty():
				out.append({"path": str(root.get_path_to(node)), "text": text, "rules": rules, "visible": _visible(node)})
	for child: Node in node.get_children(true):
		_scan(root, child, visible_only, out)


static func _skip_subtree(node: Node) -> bool:
	return node.is_in_group(INTERNAL_ONLY_GROUP) and BuildFlavor.is_internal()


static func _visible(node: Node) -> bool:
	if node is CanvasItem:
		return (node as CanvasItem).is_visible_in_tree()
	if node is Node3D:
		return (node as Node3D).is_visible_in_tree()
	if node is Window:
		return (node as Window).visible
	return true


static func _collect_scenes(dir_path: String, out: Array[String]) -> void:
	var d: DirAccess = DirAccess.open(dir_path)
	if d == null:
		return
	if dir_path != "res://" and d.file_exists(".gdignore"):
		return
	for sub: String in d.get_directories():
		if sub.begins_with("."):
			continue
		_collect_scenes(dir_path.path_join(sub), out)
	for file: String in d.get_files():
		if file.ends_with(".tscn"):
			out.append(dir_path.path_join(file))


static func _rules() -> Array[Array]:
	if _compiled.is_empty():
		for rule: Array in RULES:
			var regex: RegEx = RegEx.new()
			if regex.compile(str(rule[1])) == OK:
				_compiled.append([rule[0], regex])
			else:
				push_error("player_text_audit: bad pattern for %s" % rule[0])
	return _compiled
