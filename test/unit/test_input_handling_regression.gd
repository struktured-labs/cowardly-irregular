extends GutTest

## Regression tests for input handling
## Ensures all UI files properly check for echo events to prevent rapid-fire navigation

## Files that should have echo checks for navigation


func test_win98_menu_has_echo_checks() -> void:
	"""Win98Menu should check echo for navigation actions"""
	var content = FileAccess.get_file_as_string("res://src/ui/Win98Menu.gd")

	# Check for echo checks on navigation
	assert_true(content.contains('is_action_pressed("ui_up") and not event.is_echo()'),
		"Win98Menu should check echo for ui_up")
	assert_true(content.contains('is_action_pressed("ui_down") and not event.is_echo()'),
		"Win98Menu should check echo for ui_down")


func test_overworld_menu_has_echo_checks() -> void:
	"""OverworldMenu should check echo for navigation actions"""
	var content = FileAccess.get_file_as_string("res://src/ui/OverworldMenu.gd")

	assert_true(content.contains('is_action_pressed("ui_up") and not event.is_echo()'),
		"OverworldMenu should check echo for ui_up")
	assert_true(content.contains('is_action_pressed("ui_down") and not event.is_echo()'),
		"OverworldMenu should check echo for ui_down")


func test_items_menu_has_echo_checks() -> void:
	"""ItemsMenu should check echo for navigation actions"""
	var content = FileAccess.get_file_as_string("res://src/ui/ItemsMenu.gd")

	assert_true(content.contains('is_action_pressed("ui_up") and not event.is_echo()'),
		"ItemsMenu should check echo for ui_up")
	assert_true(content.contains('is_action_pressed("ui_down") and not event.is_echo()'),
		"ItemsMenu should check echo for ui_down")


func test_save_screen_has_echo_checks() -> void:
	"""SaveScreen should check echo for navigation actions"""
	var content = FileAccess.get_file_as_string("res://src/ui/SaveScreen.gd")

	assert_true(content.contains('is_action_pressed("ui_up") and not event.is_echo()'),
		"SaveScreen should check echo for ui_up")
	assert_true(content.contains('is_action_pressed("ui_down") and not event.is_echo()'),
		"SaveScreen should check echo for ui_down")


func test_settings_menu_has_echo_checks() -> void:
	"""SettingsMenu should check echo for navigation actions"""
	var content = FileAccess.get_file_as_string("res://src/ui/SettingsMenu.gd")

	assert_true(content.contains('is_action_pressed("ui_up") and not event.is_echo()'),
		"SettingsMenu should check echo for ui_up")
	assert_true(content.contains('is_action_pressed("ui_down") and not event.is_echo()'),
		"SettingsMenu should check echo for ui_down")


func test_title_screen_has_echo_checks() -> void:
	"""TitleScreen should check echo for navigation actions"""
	var content = FileAccess.get_file_as_string("res://src/ui/TitleScreen.gd")

	assert_true(content.contains('is_action_pressed("ui_up") and not event.is_echo()'),
		"TitleScreen should check echo for ui_up")
	assert_true(content.contains('is_action_pressed("ui_down") and not event.is_echo()'),
		"TitleScreen should check echo for ui_down")


func test_equipment_menu_has_echo_checks() -> void:
	"""EquipmentMenu should check echo for navigation actions"""
	var content = FileAccess.get_file_as_string("res://src/ui/EquipmentMenu.gd")

	assert_true(content.contains('is_action_pressed("ui_up") and not event.is_echo()'),
		"EquipmentMenu should check echo for ui_up")
	assert_true(content.contains('is_action_pressed("ui_down") and not event.is_echo()'),
		"EquipmentMenu should check echo for ui_down")


func test_abilities_menu_has_echo_checks() -> void:
	"""AbilitiesMenu should check echo for navigation actions"""
	var content = FileAccess.get_file_as_string("res://src/ui/AbilitiesMenu.gd")

	assert_true(content.contains('is_action_pressed("ui_up") and not event.is_echo()'),
		"AbilitiesMenu should check echo for ui_up")
	assert_true(content.contains('is_action_pressed("ui_down") and not event.is_echo()'),
		"AbilitiesMenu should check echo for ui_down")


func test_character_creation_has_echo_checks() -> void:
	"""CharacterCreationScreen should check echo for navigation actions"""
	var content = FileAccess.get_file_as_string("res://src/ui/CharacterCreationScreen.gd")

	assert_true(content.contains('is_action_pressed("ui_up") and not event.is_echo()'),
		"CharacterCreationScreen should check echo for ui_up")
	assert_true(content.contains('is_action_pressed("ui_down") and not event.is_echo()'),
		"CharacterCreationScreen should check echo for ui_down")


func test_virtual_keyboard_has_echo_checks() -> void:
	"""VirtualKeyboard should check echo for navigation actions"""
	var content = FileAccess.get_file_as_string("res://src/ui/VirtualKeyboard.gd")

	assert_true(content.contains('is_action_pressed("ui_up") and not event.is_echo()'),
		"VirtualKeyboard should check echo for ui_up")
	assert_true(content.contains('is_action_pressed("ui_down") and not event.is_echo()'),
		"VirtualKeyboard should check echo for ui_down")


func test_autobattle_grid_editor_has_echo_checks() -> void:
	"""AutobattleGridEditor should check echo for navigation actions"""
	var content = FileAccess.get_file_as_string("res://src/ui/autobattle/AutobattleGridEditor.gd")

	assert_true(content.contains('is_action_pressed("ui_up") and not event.is_echo()'),
		"AutobattleGridEditor should check echo for ui_up")
	assert_true(content.contains('is_action_pressed("ui_down") and not event.is_echo()'),
		"AutobattleGridEditor should check echo for ui_down")


func test_autogrind_grid_editor_has_echo_checks() -> void:
	"""AutogrindGridEditor should check echo for navigation actions"""
	var content = FileAccess.get_file_as_string("res://src/ui/autogrind/AutogrindGridEditor.gd")

	assert_true(content.contains('is_action_pressed("ui_up") and not event.is_echo()'),
		"AutogrindGridEditor should check echo for ui_up")
	assert_true(content.contains('is_action_pressed("ui_down") and not event.is_echo()'),
		"AutogrindGridEditor should check echo for ui_down")


func test_autogrind_ui_has_echo_checks() -> void:
	"""AutogrindUI should check echo for navigation actions"""
	var content = FileAccess.get_file_as_string("res://src/ui/autogrind/AutogrindUI.gd")

	assert_true(content.contains('is_action_pressed("ui_up") and not event.is_echo()'),
		"AutogrindUI should check echo for ui_up")
	assert_true(content.contains('is_action_pressed("ui_down") and not event.is_echo()'),
		"AutogrindUI should check echo for ui_down")


## Signal cleanup tests


func test_scene_transition_has_signal_cleanup() -> void:
	"""SceneTransition should disconnect signals in _exit_tree"""
	var content = FileAccess.get_file_as_string("res://src/transitions/SceneTransition.gd")

	assert_true(content.contains("func _exit_tree()"),
		"SceneTransition should have _exit_tree for cleanup")
	assert_true(content.contains("EncounterSystem.encounter_triggered.disconnect"),
		"SceneTransition should disconnect EncounterSystem signal")
	assert_true(content.contains("BattleManager.battle_ended.disconnect"),
		"SceneTransition should disconnect BattleManager signal")


func test_battle_scene_has_signal_cleanup() -> void:
	"""BattleScene should disconnect BattleManager signals in _exit_tree"""
	var content = FileAccess.get_file_as_string("res://src/battle/BattleScene.gd")

	assert_true(content.contains("func _exit_tree()"),
		"BattleScene should have _exit_tree for cleanup")
	assert_true(content.contains("BattleManager.battle_started.disconnect"),
		"BattleScene should disconnect battle_started signal")
	assert_true(content.contains("BattleManager.battle_ended.disconnect"),
		"BattleScene should disconnect battle_ended signal")


func test_win98_menu_timer_cleanup() -> void:
	"""Win98Menu should stop timers in _exit_tree"""
	var content = FileAccess.get_file_as_string("res://src/ui/Win98Menu.gd")

	assert_true(content.contains("func _exit_tree()"),
		"Win98Menu should have _exit_tree for cleanup")
	assert_true(content.contains("_submenu_timer") and content.contains(".stop()"),
		"Win98Menu should stop submenu timer")
	assert_true(content.contains("_cursor_blink_timer") and content.contains(".stop()"),
		"Win98Menu should stop cursor blink timer")


## Shop scene input fix


func test_shop_scene_extends_control() -> void:
	"""ShopScene should extend Control (not CanvasLayer) for proper input handling"""
	var content = FileAccess.get_file_as_string("res://src/exploration/ShopScene.gd")

	assert_true(content.begins_with("extends Control"),
		"ShopScene should extend Control for proper input propagation to Win98Menu")
	assert_false(content.contains("extends CanvasLayer"),
		"ShopScene should NOT extend CanvasLayer")


## Summary test


func test_all_ui_files_follow_input_patterns() -> void:
	"""Summary: All UI files should follow consistent input handling patterns"""
	var critical_files = [
		"res://src/ui/Win98Menu.gd",
		"res://src/ui/OverworldMenu.gd",
		"res://src/ui/ItemsMenu.gd",
		"res://src/ui/SaveScreen.gd",
		"res://src/ui/SettingsMenu.gd",
		"res://src/ui/TitleScreen.gd",
		"res://src/ui/EquipmentMenu.gd",
		"res://src/ui/AbilitiesMenu.gd",
		"res://src/ui/CharacterCreationScreen.gd",
		"res://src/ui/VirtualKeyboard.gd",
		"res://src/ui/autobattle/AutobattleGridEditor.gd",
		"res://src/ui/autogrind/AutogrindGridEditor.gd",
		"res://src/ui/autogrind/AutogrindUI.gd",
	]

	var issues = []

	for file_path in critical_files:
		var content = FileAccess.get_file_as_string(file_path)
		if not content.contains('is_action_pressed("ui_up") and not event.is_echo()'):
			issues.append(file_path)

	assert_true(issues.is_empty(),
		"All UI files should have echo checks. Missing in: %s" % str(issues))
