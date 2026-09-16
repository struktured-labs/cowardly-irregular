extends GutTest

## Regression tests for input handling
## Ensures all UI files properly check for echo events to prevent rapid-fire navigation

## Files that should have echo checks for navigation


## ⛔ A FILE SATISFIES THIS EITHER WAY, and the second way is STRICTER. The original property is
## "a held key must not rapid-fire", expressed as an inline `and not event.is_echo()`. Routing
## navigation through MenuNav satisfies it one level up — that helper's FIRST line is
## `if event == null or event.is_echo(): return ""` — and it additionally latches the analog axes,
## which an inline echo check cannot do at all, because an axis carries no echo flag.
## So a converted file is not exempt; it has the property by a route that also covers the stick.
func _guards_navigation(path: String, action: String) -> bool:
	var content := FileAccess.get_file_as_string(path)
	if content.contains('is_action_pressed("%s") and not event.is_echo()' % action):
		return true
	# Converted: the file must route through MenuNav, and MenuNav must still refuse echoes.
	if not content.contains("MenuNav.step("):
		return false
	var nav := FileAccess.get_file_as_string("res://src/ui/MenuNav.gd")
	return nav.contains("event.is_echo()")


func test_win98_menu_has_echo_checks() -> void:
	"""Win98Menu should check echo for navigation actions"""
	var content = FileAccess.get_file_as_string("res://src/ui/Win98Menu.gd")

	# Check for echo checks on navigation
	assert_true(_guards_navigation("res://src/ui/Win98Menu.gd", "ui_up"),
		"Win98Menu must refuse echo for ui_up — inline, or by routing through MenuNav")
	assert_true(_guards_navigation("res://src/ui/Win98Menu.gd", "ui_down"),
		"Win98Menu must refuse echo for ui_down — inline, or by routing through MenuNav")


func test_overworld_menu_has_echo_checks() -> void:
	"""OverworldMenu should check echo for navigation actions"""
	var content = FileAccess.get_file_as_string("res://src/ui/OverworldMenu.gd")

	assert_true(_guards_navigation("res://src/ui/OverworldMenu.gd", "ui_up"),
		"OverworldMenu must refuse echo for ui_up — inline, or by routing through MenuNav")
	assert_true(_guards_navigation("res://src/ui/OverworldMenu.gd", "ui_down"),
		"OverworldMenu must refuse echo for ui_down — inline, or by routing through MenuNav")


func test_items_menu_has_echo_checks() -> void:
	"""ItemsMenu should check echo for navigation actions"""
	var content = FileAccess.get_file_as_string("res://src/ui/ItemsMenu.gd")

	assert_true(_guards_navigation("res://src/ui/ItemsMenu.gd", "ui_up"),
		"ItemsMenu must refuse echo for ui_up — inline, or by routing through MenuNav")
	assert_true(_guards_navigation("res://src/ui/ItemsMenu.gd", "ui_down"),
		"ItemsMenu must refuse echo for ui_down — inline, or by routing through MenuNav")


func test_save_screen_has_echo_checks() -> void:
	"""SaveScreen should check echo for navigation actions"""
	var content = FileAccess.get_file_as_string("res://src/ui/SaveScreen.gd")

	assert_true(_guards_navigation("res://src/ui/SaveScreen.gd", "ui_up"),
		"SaveScreen must refuse echo for ui_up — inline, or by routing through MenuNav")
	assert_true(_guards_navigation("res://src/ui/SaveScreen.gd", "ui_down"),
		"SaveScreen must refuse echo for ui_down — inline, or by routing through MenuNav")


func test_settings_menu_has_echo_checks() -> void:
	"""SettingsMenu should check echo for navigation actions"""
	var content = FileAccess.get_file_as_string("res://src/ui/SettingsMenu.gd")

	assert_true(_guards_navigation("res://src/ui/SettingsMenu.gd", "ui_up"),
		"SettingsMenu must refuse echo for ui_up — inline, or by routing through MenuNav")
	assert_true(_guards_navigation("res://src/ui/SettingsMenu.gd", "ui_down"),
		"SettingsMenu must refuse echo for ui_down — inline, or by routing through MenuNav")


func test_title_screen_has_echo_checks() -> void:
	"""TitleScreen should check echo for navigation actions"""
	var content = FileAccess.get_file_as_string("res://src/ui/TitleScreen.gd")

	assert_true(_guards_navigation("res://src/ui/TitleScreen.gd", "ui_up"),
		"TitleScreen must refuse echo for ui_up — inline, or by routing through MenuNav")
	assert_true(_guards_navigation("res://src/ui/TitleScreen.gd", "ui_down"),
		"TitleScreen must refuse echo for ui_down — inline, or by routing through MenuNav")


func test_equipment_menu_has_echo_checks() -> void:
	"""EquipmentMenu should check echo for navigation actions"""
	var content = FileAccess.get_file_as_string("res://src/ui/EquipmentMenu.gd")

	assert_true(_guards_navigation("res://src/ui/EquipmentMenu.gd", "ui_up"),
		"EquipmentMenu must refuse echo for ui_up — inline, or by routing through MenuNav")
	assert_true(_guards_navigation("res://src/ui/EquipmentMenu.gd", "ui_down"),
		"EquipmentMenu must refuse echo for ui_down — inline, or by routing through MenuNav")


func test_abilities_menu_has_echo_checks() -> void:
	"""AbilitiesMenu should check echo for navigation actions"""
	var content = FileAccess.get_file_as_string("res://src/ui/AbilitiesMenu.gd")

	assert_true(_guards_navigation("res://src/ui/AbilitiesMenu.gd", "ui_up"),
		"AbilitiesMenu must refuse echo for ui_up — inline, or by routing through MenuNav")
	assert_true(_guards_navigation("res://src/ui/AbilitiesMenu.gd", "ui_down"),
		"AbilitiesMenu must refuse echo for ui_down — inline, or by routing through MenuNav")


func test_character_creation_has_echo_checks() -> void:
	"""CharacterCreationScreen should check echo for navigation actions"""
	var content = FileAccess.get_file_as_string("res://src/ui/CharacterCreationScreen.gd")

	assert_true(_guards_navigation("res://src/ui/CharacterCreationScreen.gd", "ui_up"),
		"CharacterCreationScreen must refuse echo for ui_up — inline, or by routing through MenuNav")
	assert_true(_guards_navigation("res://src/ui/CharacterCreationScreen.gd", "ui_down"),
		"CharacterCreationScreen must refuse echo for ui_down — inline, or by routing through MenuNav")


func test_virtual_keyboard_has_echo_checks() -> void:
	"""VirtualKeyboard should check echo for navigation actions"""
	var content = FileAccess.get_file_as_string("res://src/ui/VirtualKeyboard.gd")

	assert_true(_guards_navigation("res://src/ui/VirtualKeyboard.gd", "ui_up"),
		"VirtualKeyboard must refuse echo for ui_up — inline, or by routing through MenuNav")
	assert_true(_guards_navigation("res://src/ui/VirtualKeyboard.gd", "ui_down"),
		"VirtualKeyboard must refuse echo for ui_down — inline, or by routing through MenuNav")


func test_autobattle_grid_editor_has_echo_checks() -> void:
	"""AutobattleGridEditor should check echo for navigation actions"""
	var content = FileAccess.get_file_as_string("res://src/ui/autobattle/AutobattleGridEditor.gd")

	assert_true(_guards_navigation("res://src/ui/autobattle/AutobattleGridEditor.gd", "ui_up"),
		"AutobattleGridEditor must refuse echo for ui_up — inline, or by routing through MenuNav")
	assert_true(_guards_navigation("res://src/ui/autobattle/AutobattleGridEditor.gd", "ui_down"),
		"AutobattleGridEditor must refuse echo for ui_down — inline, or by routing through MenuNav")


func test_autogrind_grid_editor_has_echo_checks() -> void:
	"""AutogrindGridEditor should check echo for navigation actions"""
	var content = FileAccess.get_file_as_string("res://src/ui/autogrind/AutogrindGridEditor.gd")

	assert_true(_guards_navigation("res://src/ui/autogrind/AutogrindGridEditor.gd", "ui_up"),
		"AutogrindGridEditor must refuse echo for ui_up — inline, or by routing through MenuNav")
	assert_true(_guards_navigation("res://src/ui/autogrind/AutogrindGridEditor.gd", "ui_down"),
		"AutogrindGridEditor must refuse echo for ui_down — inline, or by routing through MenuNav")


func test_autogrind_ui_has_echo_checks() -> void:
	"""AutogrindUI should check echo for navigation actions"""
	var content = FileAccess.get_file_as_string("res://src/ui/autogrind/AutogrindUI.gd")

	assert_true(_guards_navigation("res://src/ui/autogrind/AutogrindUI.gd", "ui_up"),
		"AutogrindUI must refuse echo for ui_up — inline, or by routing through MenuNav")
	assert_true(_guards_navigation("res://src/ui/autogrind/AutogrindUI.gd", "ui_down"),
		"AutogrindUI must refuse echo for ui_down — inline, or by routing through MenuNav")


## Signal cleanup tests


func test_scene_transition_has_signal_cleanup() -> void:
	"""SceneTransition should disconnect signals in _exit_tree"""
	var content = FileAccess.get_file_as_string("res://src/transitions/SceneTransition.gd")

	assert_true(content.contains("func _exit_tree()"),
		"SceneTransition should have _exit_tree for cleanup")
	# Derived, not a hand-list. This used to name EncounterSystem.encounter_triggered, but
	# that connection was REMOVED — its handler took 1 arg on a 2-arg signal, so it never ran
	# and only logged an error per encounter. Naming a signal here pins a connection that may
	# legitimately go away; requiring every connect to have a disconnect does not.
	var connect_re := RegEx.new()
	connect_re.compile("([A-Za-z_][A-Za-z0-9_.]*)\\.connect\\(")
	var connected: Array = []
	var unmatched: Array = []
	for m in connect_re.search_all(content):
		var sig_path: String = m.get_string(1)
		if not connected.has(sig_path):
			connected.append(sig_path)
		if not content.contains("%s.disconnect(" % sig_path) and not unmatched.has(sig_path):
			unmatched.append(sig_path)
	assert_gt(connected.size(), 0,
		"CONTROL: the sweep must find at least one connect in SceneTransition, else it proves nothing")
	assert_eq(unmatched, [],
		"every signal SceneTransition connects must be disconnected in _exit_tree, or it leaks: %s" % str(unmatched))
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
		# Same property, either route — inline, or through MenuNav, which refuses echoes AND
		# latches the analog axes an inline check structurally cannot see.
		if not _guards_navigation(file_path, "ui_up"):
			issues.append(file_path)

	assert_true(issues.is_empty(),
		"All UI files should have echo checks. Missing in: %s" % str(issues))
