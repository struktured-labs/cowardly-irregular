extends GutTest

## Playtest 2026-07-13 (struktured's artist): "when you select a menu item
## in the overworld menu it has brief moment where the overworld is live
## again ur char can move, then it locks once more."
##
## Root: menu-action handlers (autobattle, autogrind) called
## _on_overworld_menu_closed() which RESUMED exploration before the submenu
## re-paused it. Player could move for one frame in the gap.
##
## Fix: split widget teardown from exploration-resume. Handlers that
## immediately open a submenu use _teardown_overworld_menu_widget()
## (no resume). Only the true-close path (back from menu → field) resumes.


func test_teardown_helper_exists_and_does_not_resume() -> void:
	var src := FileAccess.get_file_as_string("res://src/GameLoop.gd")
	var i := src.find("func _teardown_overworld_menu_widget")
	assert_gt(i, -1, "widget-only teardown helper must exist to break the resume-then-repause artifact")
	# Body must NOT resume exploration or unhide field HUD.
	var next: int = src.find("\nfunc ", i + 1)
	var body := src.substr(i, (next - i) if next > -1 else 500)
	assert_false("_exploration_scene.resume" in body,
		"widget-only teardown must NOT resume exploration — that's the artifact this fix removes")
	assert_false("_set_field_hud_hidden(false)" in body,
		"widget-only teardown must NOT unhide field HUD — submenu is about to open on top")
	assert_true("_overworld_menu.queue_free" in body,
		"widget-only teardown must still free the menu widget")


func test_menu_action_handlers_use_teardown_not_close() -> void:
	# The action-side handlers (autobattle, autogrind) must NOT call
	# _on_overworld_menu_closed — that resumes exploration, causing the
	# one-frame movable gap the artist noticed. They must call the widget-
	# only teardown instead.
	var src := FileAccess.get_file_as_string("res://src/GameLoop.gd")
	var i := src.find("func _on_overworld_menu_action")
	assert_gt(i, -1)
	var next: int = src.find("\nfunc ", i + 1)
	var body := src.substr(i, (next - i) if next > -1 else 1500)
	# Must reference the teardown helper (both autobattle + autogrind branches).
	var teardown_count: int = body.count("_teardown_overworld_menu_widget()")
	assert_gte(teardown_count, 2,
		"both autobattle + autogrind menu-action branches must call _teardown_overworld_menu_widget (not _on_overworld_menu_closed) to prevent the transient resume")
	assert_false("_on_overworld_menu_closed()" in body,
		"menu-action handlers must NOT call _on_overworld_menu_closed — that resumes exploration between the menu-close and submenu-open, letting the player move for one frame")


func test_close_path_still_resumes_when_actually_backing_to_field() -> void:
	# The true close path (back button → field) MUST still resume exploration
	# and unhide the field HUD. Regression against the "we only teardown, never
	# resume" mistake going the other direction.
	var src := FileAccess.get_file_as_string("res://src/GameLoop.gd")
	var i := src.find("func _on_overworld_menu_closed")
	assert_gt(i, -1)
	var next: int = src.find("\nfunc ", i + 1)
	var body := src.substr(i, (next - i) if next > -1 else 500)
	assert_true("_teardown_overworld_menu_widget" in body,
		"true-close path must call the widget teardown helper (no duplicate cleanup)")
	assert_true("_exploration_scene.resume" in body,
		"true-close path must resume exploration — user is going back to the field")
	assert_true("_set_field_hud_hidden(false)" in body,
		"true-close path must unhide the field HUD")
