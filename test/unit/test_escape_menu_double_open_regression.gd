extends GutTest

## Regression (web-smoke stage-3 find 2026-07-11): in exploration, Escape
## matched BOTH the ui_menu handler (→ Settings, no return) AND the
## x_pressed block below it (KEY_ESCAPE → OverworldMenu) — one press
## stacked Settings over the overworld menu. Escape must reach ONLY the
## overworld-menu path; Start/Select/Enter keep the quick-Settings path.

const GL_PATH := "res://src/GameLoop.gd"


func _exploration_ui_menu_branch() -> String:
	var src := FileAccess.get_file_as_string(GL_PATH)
	var start := src.find("if event.is_action_pressed(\"ui_menu\"):")
	assert_gt(start, -1, "ui_menu handler must exist")
	var end := src.find("var x_pressed", start)
	assert_gt(end, start, "x_pressed block must follow the ui_menu handler")
	return src.substr(start, end - start)


func test_escape_is_excluded_from_the_settings_branch() -> void:
	var branch := _exploration_ui_menu_branch()
	var esc := branch.find("KEY_ESCAPE")
	var open_settings := branch.find("_open_settings_menu()")
	assert_gt(esc, -1, "the exploration branch must special-case KEY_ESCAPE")
	assert_gt(open_settings, esc,
		"the KEY_ESCAPE guard must come BEFORE _open_settings_menu — else Escape double-opens")


## Behavioural, not a text search. This used to grep for "KEY_ESCAPE" between `var x_pressed`
## and the opener call — which went red when the check moved into OverworldMenu.is_toggle_event
## while Escape kept opening the menu. It measured where a word sat, not what a key does.
func test_escape_still_reaches_the_overworld_menu() -> void:
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	assert_true(OverworldMenu.is_toggle_event(esc),
		"Escape must still count as the overworld-menu toggle so the menu opens on it")
	var src := FileAccess.get_file_as_string(GL_PATH)
	assert_true(src.contains("OverworldMenu.is_toggle_event(event)"),
		"GameLoop's opener must ask the predicate — else this arm proves a function nothing calls")
