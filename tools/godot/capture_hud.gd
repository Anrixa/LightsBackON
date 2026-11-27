extends SceneTree
## Renders the V07 field HUD over the V01 graybox (from the van eye toward the west services) and the network tablet, on the
## real GPU, and measures WCAG contrast of every HUD text and icon against the pixels actually rendered behind it (F05's last
## open item, ADR-004 point 3). Needs a GPU window, so it does not run headless or in CI.
##   godot --path . --resolution 1920x1080 -s "$PWD/tools/godot/capture_hud.gd" -- --out-dir=build/v07
## Writes <out-dir>/V07_hud_<light>_<scale>.png, V07_tablet_<scale>.png and V07_contrast.json. Exit 0 = every probe passes.
##
## Text is measured using an isolated ink-off capture of each label or button, not its entire control rectangle.
## Unchanged pixels (including adjacent glyphs) are not text ink. Require real changed pixels and visible contrast.
## Glyphs have separate rendered component checks. Legacy map/reticle/icon background probes remain intact.
## The two explicit device runs use different output directories. No thresholds are lowered.
## Thresholds (WCAG 2.2 AA): 4.5:1 body text, 3:1 large text (>= 24 px, blueprint large_text_px) and icons/graphics.
## Lighting (DS08): the HUD is measured over the shipping Stormglass look (scripts/world/street_look.gd + dressing + rain),
## hosted by the lookdev scene. "dark" and "restored" are that scene's labelled FAKE supply states (every C01 service dark,
## or every service on grid), driven through RestorationPresentation like the mission. The lookdev caption is hidden in
## these frames so it cannot sit under a probe; the evidence file names the state instead.

const Fixture := preload("res://tests/support/ui_fixture.gd")
const Lookdev := preload("res://scenes/lookdev/alder_lookdev.gd")
const KitBuilder := preload("res://scripts/world/kit_builder.gd")
const DistrictBuilder := preload("res://scripts/world/district_builder.gd")
const FieldHud := preload("res://scripts/ui/field_hud.gd")
const NetworkTablet := preload("res://scripts/ui/network_tablet.gd")
const IntentOutbox := preload("res://scripts/ui/intent_outbox.gd")
const Runner := preload("res://tests/support/solution_runner.gd")
const ThemeTokens := preload("res://scripts/ui/theme_tokens.gd")
const InputGlyph := preload("res://scripts/ui/input_glyph.gd")
const InputPrompt := preload("res://scripts/ui/input_prompt.gd")
const UiText := preload("res://scripts/ui/ui_text.gd")

const SETTLE_FRAMES: int = 12
const FOV_DEG: float = 75.0
const BODY_MIN: float = 4.5
const LARGE_MIN: float = 3.0
const ICON_MIN: float = 3.0
const SCALES: Array[int] = [100, 150]
const FONT_COLOR_KEYS: Array[String] = ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color",
	"font_hover_pressed_color", "font_disabled_color"]

var _tokens: Dictionary
var _report: Array[Dictionary] = []
var _failed: int = 0
const MIN_INK_PIXELS: int = 3
const PIXEL_EPSILON: float = 3.0 / 255.0


func _initialize() -> void:
	var out_dir: String = "build/v07"
	var device: String = UiText.DEVICE_KBM
	var locale: String = UiText.LOCALE_EN
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--out-dir="):
			out_dir = a.trim_prefix("--out-dir=")
		elif a == "--device=pad":
			device = UiText.DEVICE_PAD
		elif a == "--locale=pseudo":
			locale = UiText.LOCALE_PSEUDO
	UiText.set_locale(locale)
	DirAccess.make_dir_recursive_absolute(out_dir)
	_tokens = Runner.json("res://content/ui/tokens.json")
	var ctx: Dictionary = Fixture.mid_shift()
	var d: Dictionary = DistrictBuilder.load_district()
	var scene: Lookdev = (load("res://scenes/lookdev/alder_lookdev.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await process_frame  # _ready() builds the look on the first frame
	scene.set_fake_state("dark")
	scene._caption.visible = false
	var cam: Camera3D = scene.camera
	cam.fov = FOV_DEG
	var line: Dictionary = d["sightlines"][0]  # VAN_EYE -> APT_W, MARKET: the first restoration seen from the van
	var markers: Dictionary = {}
	for m: Dictionary in d["markers"]:
		markers[m["id"]] = KitBuilder.cm(m["pos_cm"])
	var buildings: Dictionary = {}
	for b: Dictionary in d["buildings"]:
		buildings[b["id"]] = b
	var look: Vector3 = Vector3.ZERO
	for id: String in line["to"]:
		look += _front_center(buildings[id])
	cam.look_at_from_position(markers[line["from"]], look / float((line["to"] as Array).size()))
	var layer := CanvasLayer.new()
	root.add_child(layer)
	var hud: Container = FieldHud.new()
	layer.add_child(hud)
	hud.apply(Fixture.hud_view(ctx))
	hud.set_device(device)
	for light: String in ["dark", "restored"]:
		scene.set_fake_state("grid" if light == "restored" else "dark")
		for scale: int in SCALES:
			hud.set_ui_scale(scale)
			await _measure(hud, "hud_%s_%d" % [light, scale], out_dir)
	hud.visible = false
	var outbox: RefCounted = IntentOutbox.new(Runner.SESSION, func(_b: PackedByteArray) -> Dictionary: return {})
	var tablet: PanelContainer = NetworkTablet.new()
	layer.add_child(tablet)
	tablet.setup(outbox)
	tablet.show_data(Fixture.tablet_view(ctx), ctx["mission"].objectives())
	tablet.select("JE")
	tablet.set_device(device)
	for scale: int in SCALES:
		tablet.set_ui_scale(scale)
		await process_frame
		tablet.open()
		await _measure(tablet, "tablet_%d" % scale, out_dir)
	var f := FileAccess.open(out_dir.path_join("V07_contrast.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify({"adapter": RenderingServer.get_video_adapter_name(), "renderer": RenderingServer.get_current_rendering_method(),
		"resolution": [root.size.x, root.size.y], "device": device, "locale": locale,
		"method": "isolated_text_ink_and_rendered_glyph_components_v3",
		"failed": _failed, "probes": _report}, "  ", false))
	f.close()
	print("CONTRAST %s: %d probes, %d below AA (%s)" % ["PASS" if _failed == 0 else "FAIL", _report.size(), _failed,
		RenderingServer.get_video_adapter_name()])
	quit(0 if _failed == 0 else 1)


func _measure(view: Control, label: String, out_dir: String) -> void:
	for i: int in SETTLE_FRAMES:
		await process_frame
	await RenderingServer.frame_post_draw
	var shown: Image = root.get_texture().get_image()
	var path: String = out_dir.path_join("V07_%s.png" % label)
	shown.save_png(path)
	print("WROTE %s (%dx%d)" % [path, shown.get_width(), shown.get_height()])
	var probes: Array[Dictionary] = _probes(view)
	_hide_ink(view, true)
	for i: int in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	var behind: Image = root.get_texture().get_image()
	_hide_ink(view, false)
	var worst: float = INF
	# Restore the normal view before the isolated captures. Keeping the rest
	# of the ink present distinguishes real overlap from harmless adjacent art.
	await process_frame
	await RenderingServer.frame_post_draw
	for p: Dictionary in probes:
		var results: Array[Dictionary] = []
		if p.has("control"):
			var control: Control = p["control"]
			var normal: Image = root.get_texture().get_image()
			var saved: Dictionary = _suppress_control_ink(control)
			await process_frame
			await RenderingServer.frame_post_draw
			var bare: Image = root.get_texture().get_image()
			_restore_control_ink(control, saved)
			await process_frame
			await RenderingServer.frame_post_draw
			if control is InputGlyph:
				var glyph: InputGlyph = control as InputGlyph
				# Removing the entire glyph exposes its parent button. On an
				# amber primary button that can match the glyph's own amber
				# accent, even when the accent is visibly drawn on dark fill.
				# Capture the same glyph with only its action token replaced
				# by its backing, preserving all other geometry and ink.
				var original_tokens: Dictionary = glyph.tokens
				var masked_tokens: Dictionary = original_tokens.duplicate(true)
				masked_tokens["colors"]["action"] = original_tokens["colors"]["elevated"]
				glyph.tokens = masked_tokens
				glyph.queue_redraw()
				await process_frame
				await RenderingServer.frame_post_draw
				var action_off: Image = root.get_texture().get_image()
				glyph.tokens = original_tokens
				glyph.queue_redraw()
				await process_frame
				await RenderingServer.frame_post_draw
				results = _score_glyph(glyph, p["rect"], normal, bare, action_off)
			else:
				results.append(score_text(p, normal, bare))
		else:
			results.append(_score(p, shown, behind))
		for r: Dictionary in results:
			r["view"] = label
			_report.append(r)
			worst = minf(worst, float(r["worst"]) / float(r["min"]))
			if not r["pass"]:
				_failed += 1
				print("  BELOW AA / MISSING INK %s %s %s: %.2f / %.1f %s" %
					[label, r["kind"], r["what"], r["worst"], r["min"], str(r.get("reason", ""))])
	print("  %s: %d probes, worst margin x%.2f of the AA minimum" % [label, probes.size(), worst])


## Text and icon probes: what is drawn, its rect on screen, its intended color and the AA minimum for its kind.
func _probes(view: Control) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for c: Control in Fixture.controls(view):
		if not c.is_visible_in_tree():
			continue
		var rect: Rect2 = _visible_rect(c)
		var mandatory_hint: bool = c is Label and c.get_parent() is InputPrompt and str(c.get_parent().name).begins_with("Hint_")
		if (rect.size.x < 1.0 or rect.size.y < 1.0) and not mandatory_hint:
			continue  # intentionally scrolled out of view; the field hints may never disappear
		if c is Label and (c as Label).text.strip_edges() != "":
			var l: Label = c
			var px: int = l.get_theme_font_size("font_size")
			var large: bool = px >= int(_tokens["large_text_px"])
			out.append({"what": l.text.left(40), "kind": "large_text" if large else "body_text", "rect": rect, "fg": l.get_theme_color("font_color"),
				"min": LARGE_MIN if large else BODY_MIN, "px": px, "control": l,
				"fit": _prompt_caption_fits(l, rect)})
		elif c is Button and (c as Button).text != "":
			var b: Button = c
			var box: StyleBox = b.get_theme_stylebox("normal")
			var inner: Rect2 = rect.grow_individual(-box.get_margin(SIDE_LEFT), -box.get_margin(SIDE_TOP), -box.get_margin(SIDE_RIGHT),
				-box.get_margin(SIDE_BOTTOM))
			var bpx: int = b.get_theme_font_size("font_size")
			var blarge: bool = bpx >= int(_tokens["large_text_px"])
			out.append({"what": b.text.left(40), "kind": "large_text" if blarge else "body_text", "rect": inner,
				"fg": b.get_theme_color(_button_font_key(b)), "min": LARGE_MIN if blarge else BODY_MIN, "px": bpx,
				"control": b, "fit": _button_caption_fits(b, inner)})
		elif c is InputGlyph:
			out.append({"control": c, "rect": rect})
		elif c is TextureRect and (c as TextureRect).texture != null:
			out.append({"what": str(c.get_meta("icon", (c as TextureRect).texture.resource_path.get_file())), "kind": "icon", "rect": rect,
				"fg": c.self_modulate, "min": ICON_MIN})
		elif c.get_script() == preload("res://scripts/ui/reticle.gd"):
			out.append({"what": "reticle", "kind": "reticle", "rect": rect, "fg": c.get("ink"), "fg2": c.get("outline"), "min": ICON_MIN})
		elif c.get_script() == preload("res://scripts/ui/tablet_map.gd"):
			var nodes: Array[Rect2] = []
			for n: Node in c.get_children():
				nodes.append((n as Control).get_global_rect().grow(ThemeTokens.px(8, float(view.get("scale_percent")))))
			for token: String in ["restored", "action", "fault", "unknown"]:
				out.append({"what": "map edge " + token, "kind": "graphic", "rect": rect, "fg": ThemeTokens.color(_tokens, token), "min": ICON_MIN,
					"sample_only_bg": true, "exclude": nodes})  # edges run over the map background between the nodes
	return out


## The part of a control left on screen by every clipping ancestor (scroll panels, the map).
func _visible_rect(c: Control) -> Rect2:
	var rect: Rect2 = c.get_global_rect()
	var a: Node = c.get_parent()
	while a is Control:
		if (a as Control).clip_contents:
			rect = rect.intersection((a as Control).get_global_rect())
		a = a.get_parent()
	return rect


var _hidden_ink: Dictionary = {}


func _hide_ink(view: Control, hide: bool) -> void:
	# Preserve exact original overrides and alpha, including muted controls.
	if hide:
		for c: Control in Fixture.controls(view):
			if c is Label or c is Button or c is TextureRect or c.get_script() == preload("res://scripts/ui/reticle.gd") \
					or c.get_script() == preload("res://scripts/ui/tablet_map.gd"):
				_hidden_ink[c] = _suppress_control_ink(c)
	else:
		for c: Control in _hidden_ink:
			if is_instance_valid(c):
				_restore_control_ink(c, _hidden_ink[c])
		_hidden_ink.clear()


static func _suppress_control_ink(c: Control) -> Dictionary:
	var state: Dictionary = {"modulate": c.self_modulate, "overrides": {}}
	if c is Button:
		for key: String in FONT_COLOR_KEYS:
			if c.has_theme_color_override(key):
				state["overrides"][key] = c.get_theme_color(key)
			c.add_theme_color_override(key, Color(0, 0, 0, 0))
	else:
		var tint: Color = c.self_modulate
		tint.a = 0.0
		c.self_modulate = tint
	return state


static func _restore_control_ink(c: Control, state: Dictionary) -> void:
	c.self_modulate = state["modulate"]
	if c is Button:
		for key: String in FONT_COLOR_KEYS:
			if state["overrides"].has(key):
				c.add_theme_color_override(key, state["overrides"][key])
			else:
				c.remove_theme_color_override(key)


static func _button_font_key(b: Button) -> String:
	match b.get_draw_mode():
		BaseButton.DRAW_DISABLED: return "font_disabled_color"
		BaseButton.DRAW_PRESSED: return "font_pressed_color"
		BaseButton.DRAW_HOVER: return "font_hover_color"
		BaseButton.DRAW_HOVER_PRESSED: return "font_hover_pressed_color"
	return "font_focus_color" if b.has_focus() else "font_color"


static func _prompt_caption_fits(l: Label, rect: Rect2) -> bool:
	if not l.get_parent() is InputPrompt:
		return true
	var need: Vector2 = l.get_minimum_size()
	return rect.size.x + 0.75 >= need.x and rect.size.y + 0.75 >= need.y


static func _button_caption_fits(b: Button, inner: Rect2) -> bool:
	# Only overlay-glyph buttons have the special reservation contract.
	var g: InputGlyph = b.find_child("*Glyph", false, false) as InputGlyph
	if g == null:
		return true
	if b.icon == null:
		return false
	var reserve_end: float = inner.position.x + b.icon.get_width()
	var text_start: float = reserve_end + b.get_theme_constant("h_separation")
	var needed: float = b.get_theme_font("font").get_string_size(b.text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, b.get_theme_font_size("font_size")).x
	return g.get_global_rect().end.x <= reserve_end + 0.75 and inner.end.x - text_start + 0.75 >= needed


static func _pixel_difference(a: Color, b: Color) -> float:
	return maxf(absf(a.r - b.r), maxf(absf(a.g - b.g), absf(a.b - b.b)))


## Only actual ink pixels contribute. Empty, clipped and invisible captions
## fail explicitly instead of producing an infinite or unrelated contrast.
static func score_text(p: Dictionary, shown: Image, behind: Image) -> Dictionary:
	var r: Rect2i = Rect2i(Rect2(p["rect"])).intersection(Rect2i(0, 0, behind.get_width(), behind.get_height()))
	var fg: Color = p["fg"]
	var worst: float = INF
	var peak: float = 0.0
	var count: int = 0
	for y: int in range(r.position.y, r.end.y):
		for x: int in range(r.position.x, r.end.x):
			var bg: Color = behind.get_pixel(x, y)
			var ink: Color = shown.get_pixel(x, y)
			if _pixel_difference(ink, bg) <= PIXEL_EPSILON:
				continue
			count += 1
			worst = minf(worst, _contrast(fg, bg))
			peak = maxf(peak, _contrast(ink, bg))
	var fit: bool = p.get("fit", true)
	var present: bool = count >= MIN_INK_PIXELS
	var minimum: float = p["min"]
	var passed: bool = fit and present and worst >= minimum and peak >= minimum
	var reason: String = "" if passed else ("clipped caption" if not fit else ("missing ink" if not present else "insufficient contrast"))
	return {"what": p["what"], "kind": p["kind"], "rect": [r.position.x, r.position.y, r.size.x, r.size.y],
		"fg": "#" + fg.to_html(false), "min": minimum, "worst": snappedf(worst, 0.01) if present else 0.0,
		"rendered_peak": snappedf(peak, 0.01), "ink_pixels": count, "fit": fit, "reason": reason, "pass": passed,
		"px": p.get("px", 0)}


## InputGlyph draws multiple colors itself. Require the actual opaque ink
## pixels and nearby actual backing color for each semantic component, rather
## than assigning one text color to its entire rectangle. The isolated blank
## capture prevents a nearby control from supplying the expected ink.
func _score_glyph(g: InputGlyph, rect: Rect2, shown: Image, behind: Image, action_off: Image) -> Array[Dictionary]:
	var kind: String = str(g.glyph_info().get("kind", ""))
	var code: int = int(g.glyph_info().get("code", -1))
	var pairs: Array = [["text_muted", "elevated", ICON_MIN]]
	if kind in ["keyboard", "shoulder", "button", "unbound"]:
		pairs.append(["text", "elevated", BODY_MIN])
	if kind in ["button", "dpad", "stick"] or (kind == "mouse" and code in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT,
			MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]):
		pairs.append(["action", "elevated", ICON_MIN])
	if kind == "stick":
		pairs.append(["background", "action", BODY_MIN])
	var results: Array[Dictionary] = []
	for pair: Array in pairs:
		var foreground: Color = ThemeTokens.color(g.tokens, pair[0])
		var backing: Color = ThemeTokens.color(g.tokens, pair[1])
		var isolated: Image = action_off if pair[0] == "action" else behind
		var result: Dictionary = score_glyph_component(rect, shown, isolated, foreground, backing, float(pair[2]))
		result["what"] = "%s %s / %s" % [g.action, kind, pair[0]]
		results.append(result)
	return results


static func score_glyph_component(rect: Rect2, shown: Image, behind: Image, fg: Color, bg: Color, minimum: float) -> Dictionary:
	var r: Rect2i = Rect2i(rect).intersection(Rect2i(0, 0, shown.get_width(), shown.get_height()))
	var count: int = 0
	var worst: float = INF
	for y: int in range(r.position.y, r.end.y):
		for x: int in range(r.position.x, r.end.x):
			var ink: Color = shown.get_pixel(x, y)
			if _pixel_difference(ink, fg) > PIXEL_EPSILON or _pixel_difference(ink, behind.get_pixel(x, y)) <= PIXEL_EPSILON:
				continue
			# A core ink pixel must be near the component's actual backing.
			var found: bool = false
			var local_worst: float = INF
			for yy: int in range(maxi(r.position.y, y - 4), mini(r.end.y, y + 5)):
				for xx: int in range(maxi(r.position.x, x - 4), mini(r.end.x, x + 5)):
					var nearby: Color = shown.get_pixel(xx, yy)
					if _pixel_difference(nearby, bg) <= PIXEL_EPSILON:
						found = true
						local_worst = minf(local_worst, _contrast(ink, nearby))
			if found:
				count += 1
				worst = minf(worst, local_worst)
	var present: bool = count >= MIN_INK_PIXELS
	var passed: bool = present and worst >= minimum
	return {"kind": "glyph_component", "rect": [r.position.x, r.position.y, r.size.x, r.size.y],
		"fg": "#" + fg.to_html(false), "bg": "#" + bg.to_html(false), "min": minimum,
		"worst": snappedf(worst, 0.01) if present else 0.0, "rendered_peak": snappedf(worst, 0.01) if present else 0.0,
		"ink_pixels": count, "pass": passed, "reason": "" if passed else ("missing paired glyph ink" if not present else "insufficient glyph contrast")}


func _score(p: Dictionary, shown: Image, behind: Image) -> Dictionary:
	var r: Rect2i = Rect2i(Rect2(p["rect"])).intersection(Rect2i(0, 0, behind.get_width(), behind.get_height()))
	var fg: Color = p["fg"]
	var worst: float = INF
	var peak: float = 0.0
	var step: int = 2 if r.size.x * r.size.y > 40000 else 1
	for y: int in range(r.position.y, r.end.y, step):
		for x: int in range(r.position.x, r.end.x, step):
			if p.has("exclude") and (p["exclude"] as Array).any(func(e: Rect2) -> bool: return e.has_point(Vector2(x, y))):
				continue
			var bg: Color = behind.get_pixel(x, y)
			var c: float = _contrast(fg, bg)
			if p["kind"] == "reticle":
				c = maxf(c, _contrast(p["fg2"], bg))  # two-tone: either tone separates it from this pixel
			worst = minf(worst, c)
			if not p.get("sample_only_bg", false):
				peak = maxf(peak, _contrast(shown.get_pixel(x, y), bg))
	var out: Dictionary = {"what": p["what"], "kind": p["kind"], "rect": [r.position.x, r.position.y, r.size.x, r.size.y],
		"fg": "#" + fg.to_html(false), "min": p["min"], "worst": snappedf(worst, 0.01), "rendered_peak": snappedf(peak, 0.01),
		"pass": worst >= float(p["min"])}
	if p.has("px"):
		out["px"] = p["px"]
	return out


static func _contrast(a: Color, b: Color) -> float:
	var la: float = _luminance(a)
	var lb: float = _luminance(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


static func _luminance(c: Color) -> float:
	var ch: Array[float] = []
	for v: float in [c.r, c.g, c.b]:
		ch.append(v / 12.92 if v <= 0.04045 else pow((v + 0.055) / 1.055, 2.4))
	return 0.2126 * ch[0] + 0.7152 * ch[1] + 0.0722 * ch[2]


func _front_center(b: Dictionary) -> Vector3:
	var x: int = int(b["min_cm"][0]) + int(b["size_cm"][0]) / 2
	var z: int = int(b["min_cm"][1]) if b["front"] == "south" else int(b["min_cm"][1]) + int(b["size_cm"][1])
	return KitBuilder.cm([x, 250, z])
