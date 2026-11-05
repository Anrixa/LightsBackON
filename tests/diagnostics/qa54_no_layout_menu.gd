extends "res://scripts/ui/main_menu.gd"
## QA54 diagnostic-only substitution: real menu _ready() and persistence run,
## but responsive theme rebuilding and resize overrides are omitted.
## Used only in isolated test processes; never installed in a game scene.


func _layout_for_size(_viewport_size: Vector2) -> void:
	pass
