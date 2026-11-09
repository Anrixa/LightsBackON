extends Node3D
## DS08 lookdev scene (ADR-016 decision 4.1, approved 9 Nov 2026). Shows the Stormglass look on Alder Street with a
## FAKE supply state chosen here, never from a host: every frame carries a "LOOKDEV - FAKE STATE" caption, and nothing
## in the shipping game references this scene (ADR-017 decision 2). The mission uses the same look with real host state.

const StreetLook := preload("res://scripts/world/street_look.gd")
const StreetDressing := preload("res://scripts/world/street_dressing.gd")
const RestorationPresentation := preload("res://scripts/world/restoration_presentation.gd")
const DistrictBuilder := preload("res://scripts/world/district_builder.gd")
const PowerGrid := preload("res://scripts/simulation/power_grid.gd")
const FAKE_STATES: Array[String] = ["dark", "temporary", "grid"]
## Long enough to finish any A04 fade in one step, so a captured frame shows the settled state.
const SETTLE_SECONDS: float = 30.0

@export_enum("dark", "temporary", "grid") var fake_state: String = "dark"

var world: Node3D
var camera: Camera3D
var fx: RestorationPresentation
var _caption: Label


func _ready() -> void:
	var look: Dictionary = StreetLook.load_look()
	StreetLook.apply_environment(self, look)
	var d: Dictionary = DistrictBuilder.load_district()
	world = (load(str(d["scene"])) as PackedScene).instantiate()
	world.name = "District"
	add_child(world)
	StreetLook.skin_world(world, look, d)
	StreetDressing.new().build(world, d, look, StreetDressing.load_dressing())
	StreetLook.add_rain(self, look)
	camera = Camera3D.new()
	camera.name = "LookdevCamera"
	add_child(camera)
	camera.current = true
	fx = RestorationPresentation.new()
	fx.setup(world, look["windows"])
	var layer: CanvasLayer = CanvasLayer.new()
	add_child(layer)
	_caption = Label.new()
	_caption.position = Vector2(24, 16)
	_caption.add_theme_font_size_override("font_size", 22)
	_caption.add_theme_color_override("font_color", Color("#FFC86B"))
	_caption.add_theme_color_override("font_outline_color", Color("#111B25"))
	_caption.add_theme_constant_override("outline_size", 6)
	layer.add_child(_caption)
	set_fake_state(fake_state)


## Applies a made-up grid snapshot in which every C01 service has the given supply. Lookdev only.
func set_fake_state(state: String) -> void:
	fake_state = state
	fx.apply(fake_snapshot(state), state != "dark")
	fx.advance(SETTLE_SECONDS)
	_caption.text = "LOOKDEV - FAKE STATE: %s (not host state)" % state.to_upper()


static func fake_snapshot(state: String) -> Dictionary:
	var nodes: Dictionary = {
		"GRID": {"kind": PowerGrid.KIND_SOURCE, "online": true},
		"GEN": {"kind": PowerGrid.KIND_SOURCE, "online": state == "temporary"},
	}
	var edges: Dictionary = {}
	for service: String in RestorationPresentation.SERVICES:
		nodes[service] = {"kind": PowerGrid.KIND_CONSUMER, "supplied": state != "dark"}
		edges["FAKE_" + service] = {"from": "GEN" if state == "temporary" else "GRID", "to": service,
			"energized": state != "dark"}
	return {"grid": {"nodes": nodes, "edges": edges}}
