extends GutTest

## Regression tests for mouse-accessible UI paths.
##
## Bug history (2026-04-30):
##   User asked "can you use the mouse exclusively?" — audit found three
##   mouse-blind gaps that this commit closes:
##     1. WorldMapMenu had no right-click-cancel; no scroll wheel.
##     2. QuestLog had no right-click-cancel; no scroll wheel.
##     3. In-battle command menu had "Auto" (toggle on) but no entry
##        to open the autobattle rule editor — only F5/Start/L+R could.
##
## We verify the three fixes by source-level grep rather than runtime
## simulation, since these UIs require full battle/GameLoop context that
## GUT can't easily set up. Source-level checks are good enough — they'd
## have caught the original gap and they'll catch a regression that
## removes the wiring.


func _read_file(path: String) -> String:
	var f = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var text = f.get_as_text()
	f.close()
	return text


func test_world_map_has_right_click_cancel() -> void:
	var src = _read_file("res://src/ui/WorldMapMenu.gd")
	assert_string_contains(src, "MenuMouseHelper.add_right_click_cancel",
		"WorldMapMenu must wire right-click-to-close via MenuMouseHelper")
	assert_string_contains(src, "_close",
		"WorldMapMenu right-click-cancel should call _close()")


func test_world_map_has_scroll_wheel() -> void:
	var src = _read_file("res://src/ui/WorldMapMenu.gd")
	assert_string_contains(src, "MenuMouseHelper.handle_scroll_wheel",
		"WorldMapMenu must handle scroll wheel for navigation")


func test_world_map_cards_are_clickable() -> void:
	var src = _read_file("res://src/ui/WorldMapMenu.gd")
	assert_string_contains(src, "MenuMouseHelper.make_clickable(card",
		"WorldMapMenu cards must be click-and-hover wired")
	assert_string_contains(src, "_on_card_hovered",
		"WorldMapMenu cards must select on hover")


func test_quest_log_has_right_click_cancel() -> void:
	var src = _read_file("res://src/ui/QuestLog.gd")
	assert_string_contains(src, "MenuMouseHelper.add_right_click_cancel",
		"QuestLog must wire right-click-to-close")


func test_quest_log_has_scroll_wheel() -> void:
	var src = _read_file("res://src/ui/QuestLog.gd")
	assert_string_contains(src, "MOUSE_BUTTON_WHEEL_UP",
		"QuestLog must handle wheel-up for scrolling")
	assert_string_contains(src, "MOUSE_BUTTON_WHEEL_DOWN",
		"QuestLog must handle wheel-down for scrolling")


func test_battle_command_menu_has_autobattle_edit_entry() -> void:
	var src = _read_file("res://src/battle/BattleCommandMenu.gd")
	# Entry must exist in the command builder
	assert_string_contains(src, "autobattle_edit",
		"BattleCommandMenu must offer 'autobattle_edit' so mouse users can " +
		"open the rule editor without F5/Start/L+R hotkeys")
	assert_string_contains(src, "Auto Rules",
		"BattleCommandMenu's autobattle_edit entry should be labeled 'Auto Rules'")


func test_battle_command_menu_autobattle_edit_invokes_editor() -> void:
	var src = _read_file("res://src/battle/BattleCommandMenu.gd")
	# Handler must call into GameLoop's editor toggle
	assert_string_contains(src, "_toggle_autobattle_editor",
		"BattleCommandMenu's autobattle_edit handler must call " +
		"GameLoop._toggle_autobattle_editor() so the existing entry/exit " +
		"wiring (pause exploration, hide menu, etc.) is reused")


func test_overworld_menu_already_has_autobattle_entry() -> void:
	# Sanity: this was already wired before today's work, but we verify it
	# still exists so no regression silently removes the only path mouse
	# users have to open the editor in exploration mode.
	var src = _read_file("res://src/ui/OverworldMenu.gd")
	assert_string_contains(src, "\"id\": \"autobattle\"",
		"OverworldMenu must keep 'autobattle' entry for mouse-only path " +
		"in exploration mode")
