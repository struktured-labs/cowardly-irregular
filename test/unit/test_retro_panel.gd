extends GutTest

## Tests for RetroPanel utility and overworld menu styling
## Ensures beveled 3D borders render correctly across all menus

## ---- RetroPanel Utility ----

func test_retro_panel_class_exists() -> void:
	var script = load("res://src/ui/RetroPanel.gd")
	assert_not_null(script, "RetroPanel.gd should load")


func test_retro_panel_has_create_panel_method() -> void:
	var rp = RetroPanel.new()
	assert_true(rp.has_method("create_panel"),
		"RetroPanel should have static create_panel method")


func test_retro_panel_has_add_border_method() -> void:
	var rp = RetroPanel.new()
	assert_true(rp.has_method("add_border"),
		"RetroPanel should have static add_border method")


func test_retro_panel_tile_size() -> void:
	assert_eq(RetroPanel.TILE_SIZE, 4, "RetroPanel tile size should be 4")


func test_create_panel_returns_control() -> void:
	var panel = RetroPanel.create_panel(100, 50,
		Color(0.1, 0.1, 0.15),
		Color(0.7, 0.7, 0.85),
		Color(0.25, 0.25, 0.4))
	assert_not_null(panel, "create_panel should return a Control")
	assert_true(panel is Control, "Result should be a Control node")
	panel.queue_free()


func test_create_panel_has_children() -> void:
	var panel = RetroPanel.create_panel(200, 100,
		Color(0.1, 0.1, 0.15),
		Color(0.7, 0.7, 0.85),
		Color(0.25, 0.25, 0.4))
	assert_gt(panel.get_child_count(), 0,
		"Panel should have children (background + borders)")
	panel.queue_free()


func test_add_border_adds_children() -> void:
	var parent = Control.new()
	parent.size = Vector2(200, 100)
	add_child_autofree(parent)

	var initial_children = parent.get_child_count()
	RetroPanel.add_border(parent, parent.size,
		Color(0.7, 0.7, 0.85),
		Color(0.25, 0.25, 0.4))

	assert_gt(parent.get_child_count(), initial_children,
		"add_border should add border children to parent")


func test_add_border_with_zero_size() -> void:
	"""Should not crash with zero-size parent"""
	var parent = Control.new()
	parent.size = Vector2.ZERO
	add_child_autofree(parent)

	RetroPanel.add_border(parent, parent.size,
		Color(0.7, 0.7, 0.85),
		Color(0.25, 0.25, 0.4))
	assert_true(true, "Should not crash with zero size")


## ---- All Menus Use RetroPanel ----

func test_overworld_menu_uses_retro_panel() -> void:
	var content = FileAccess.get_file_as_string("res://src/ui/OverworldMenu.gd")
	assert_true(content.contains("RetroPanel"),
		"OverworldMenu should reference RetroPanel")


func test_items_menu_uses_retro_panel() -> void:
	var content = FileAccess.get_file_as_string("res://src/ui/ItemsMenu.gd")
	assert_true(content.contains("RetroPanel"),
		"ItemsMenu should reference RetroPanel")


func test_equipment_menu_uses_retro_panel() -> void:
	var content = FileAccess.get_file_as_string("res://src/ui/EquipmentMenu.gd")
	assert_true(content.contains("RetroPanel"),
		"EquipmentMenu should reference RetroPanel")


func test_job_menu_uses_retro_panel() -> void:
	var content = FileAccess.get_file_as_string("res://src/ui/JobMenu.gd")
	assert_true(content.contains("RetroPanel"),
		"JobMenu should reference RetroPanel")


func test_abilities_menu_uses_retro_panel() -> void:
	var content = FileAccess.get_file_as_string("res://src/ui/AbilitiesMenu.gd")
	assert_true(content.contains("RetroPanel"),
		"AbilitiesMenu should reference RetroPanel")


func test_status_menu_uses_retro_panel() -> void:
	var content = FileAccess.get_file_as_string("res://src/ui/StatusMenu.gd")
	assert_true(content.contains("RetroPanel"),
		"StatusMenu should reference RetroPanel")


func test_settings_menu_uses_retro_panel() -> void:
	var content = FileAccess.get_file_as_string("res://src/ui/SettingsMenu.gd")
	assert_true(content.contains("RetroPanel"),
		"SettingsMenu should reference RetroPanel")


## ---- All Menus Have Correct Border Colors ----

func test_overworld_menu_has_border_light_and_shadow() -> void:
	var content = FileAccess.get_file_as_string("res://src/ui/OverworldMenu.gd")
	assert_true(content.contains("BORDER_LIGHT"),
		"OverworldMenu should define BORDER_LIGHT")
	assert_true(content.contains("BORDER_SHADOW"),
		"OverworldMenu should define BORDER_SHADOW")


func test_no_menu_uses_old_border_color() -> void:
	"""Regression: old flat BORDER_COLOR should be replaced in all menus"""
	var menu_files = [
		"res://src/ui/OverworldMenu.gd",
		"res://src/ui/ItemsMenu.gd",
		"res://src/ui/EquipmentMenu.gd",
		"res://src/ui/JobMenu.gd",
		"res://src/ui/AbilitiesMenu.gd",
		"res://src/ui/StatusMenu.gd",
	]

	var found_old = false
	for file_path in menu_files:
		var content = FileAccess.get_file_as_string(file_path)
		# Check that BORDER_COLOR constant is NOT defined (replaced by BORDER_LIGHT/SHADOW)
		var lines = content.split("\n")
		for i in range(lines.size()):
			var line = lines[i].strip_edges()
			if line.begins_with("const BORDER_COLOR"):
				found_old = true
				assert_true(false,
					"%s still has old 'const BORDER_COLOR' at line %d" % [file_path, i + 1])
	if not found_old:
		assert_true(true, "No menu uses old BORDER_COLOR constant")


## ---- Menu Script Loading ----

func test_all_menu_scripts_load() -> void:
	var scripts = [
		"res://src/ui/OverworldMenu.gd",
		"res://src/ui/ItemsMenu.gd",
		"res://src/ui/EquipmentMenu.gd",
		"res://src/ui/JobMenu.gd",
		"res://src/ui/AbilitiesMenu.gd",
		"res://src/ui/StatusMenu.gd",
		"res://src/ui/SettingsMenu.gd",
		"res://src/ui/RetroPanel.gd",
	]

	for script_path in scripts:
		var script = load(script_path)
		assert_not_null(script, "%s should load without errors" % script_path)
