extends "res://tests/test_case.gd"

const Menu := preload("res://scenes/menu/main_menu.tscn")

func test_QA55_start_button_created_once() -> void:
	var source: String = FileAccess.get_file_as_string("res://scripts/ui/main_menu.gd")
	assert_eq(source.count("start_button = Button.new()"), 1, "Only one StartButton should be allocated")

func test_QA55_start_button_owned_by_menu() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var menu: Control = Menu.instantiate() as Control
	tree.root.add_child(menu)
	var start: Button = menu.get("start_button") as Button
	assert_true(start != null and start.get_parent() != null, "start action should be attached to scene")
	tree.root.remove_child(menu)
	menu.free()
