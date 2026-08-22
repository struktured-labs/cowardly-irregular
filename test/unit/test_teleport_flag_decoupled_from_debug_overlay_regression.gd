extends GutTest

## Teleport used to be gated on `debug_log_enabled` — a flag whose name and comment
## advertise only a logging overlay ("Show debug log overlay"). Turning the overlay off
## before a demo silently removed the pause-menu Teleport row, which was the ONLY route to
## Glacius and Pyrroth while they sat in sealed walkable components of the W1 map.
## Found 2026-08-22. The fix is a separate flag; these pin BOTH directions.

# GameState is an AUTOLOAD: whatever this file leaves set survives into every later test
# file. Restore what was actually there, not a hardcoded true — forcing a value is itself
# a leak if the suite arrived with the flag off.
var _orig_debug: bool = true
var _orig_teleport: bool = true


func before_all() -> void:
	if GameState:
		_orig_debug = GameState.debug_log_enabled
		_orig_teleport = GameState.teleport_menu_enabled


func after_each() -> void:
	_restore()


func after_all() -> void:
	_restore()


func _restore() -> void:
	if GameState:
		GameState.debug_log_enabled = _orig_debug
		GameState.teleport_menu_enabled = _orig_teleport


func test_the_overlay_flag_no_longer_gates_teleport() -> void:
	var src: String = FileAccess.get_file_as_string("res://src/ui/OverworldMenu.gd")
	assert_ne(src, "", "OverworldMenu must be readable")
	var idx := src.find('"id": "teleport"')
	assert_gt(idx, -1, "the teleport row must still exist")
	# Read the guard ABOVE the append, not the whole file: debug_log_enabled may legitimately
	# appear elsewhere, and a file-wide search would pass on the wrong occurrence.
	var head: String = src.substr(maxi(0, idx - 200), 200)
	assert_false(head.contains("debug_log_enabled"),
		"the teleport row must NOT be gated on the debug-overlay flag")
	assert_true(head.contains("teleport_menu_enabled"),
		"the teleport row must be gated on its own flag")


func _teleport_row_present(debug_on: bool, teleport_on: bool) -> bool:
	# BUILDS the real option list instead of grepping source, so dead code cannot fake it.
	# setup() iterates the party; an empty array skips that loop and reaches the gate.
	GameState.debug_log_enabled = debug_on
	GameState.teleport_menu_enabled = teleport_on
	var menu = load("res://src/ui/OverworldMenu.gd").new()
	add_child_autofree(menu)
	menu.setup([])
	for opt in menu._menu_options:
		if opt.get("id", "") == "teleport":
			return true
	return false


func test_the_debug_overlay_can_be_turned_off_without_losing_teleport() -> void:
	# The demo case: hide the debug overlay before showing the game to people, keep the
	# only route to two W1 dragons. This is the whole reason the split exists.
	assert_true(_teleport_row_present(false, true),
		"overlay OFF + teleport ON must still offer Teleport")


func test_the_teleport_flag_actually_controls_the_row() -> void:
	# ARM- : the flag must discriminate, or the arm above passes on a row that is always there.
	assert_false(_teleport_row_present(true, false),
		"teleport OFF must remove the row even with the debug overlay ON")


func test_both_flags_exist() -> void:
	assert_true("debug_log_enabled" in GameState, "overlay flag must survive")
	assert_true("teleport_menu_enabled" in GameState, "teleport must have its own flag")


func test_turning_the_overlay_back_on_restores_teleport() -> void:
	# Without this, a save made before the split with debug already OFF inherits false and
	# can never recover the row — a one-way door the old single flag did not have.
	var src: String = FileAccess.get_file_as_string("res://src/ui/SettingsMenu.gd")
	var idx := src.find("func _save_debug_log_setting")
	assert_gt(idx, -1, "the debug-log save helper must exist")
	var body: String = src.substr(idx, 600)
	assert_true(body.contains("teleport_menu_enabled = true"),
		"re-enabling the debug overlay must restore the teleport flag")


func test_a_presplit_save_keeps_exactly_the_behaviour_it_had() -> void:
	# Migration: no teleport key in the save -> inherit whatever used to gate it.
	var src: String = FileAccess.get_file_as_string("res://src/save/SaveSystem.gd")
	var idx := src.find('settings.has("teleport_menu_enabled")')
	assert_gt(idx, -1, "load must look for the new key")
	var body: String = src.substr(idx, 400)
	assert_true(body.contains('elif settings.has("debug_log_enabled")'),
		"a save predating the split must inherit the old flag, not silently flip to default")
	assert_true(src.contains('settings["teleport_menu_enabled"] = GameState.teleport_menu_enabled'),
		"the new flag must be persisted, or it resets every load")
