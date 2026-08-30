extends GutTest

## struktured's artist, 2026-08-30: "I tried a lot of keys. Everytime i hit Esc, the thing
## gets stuck in the pause menu."
##
## Escape binds BOTH ui_cancel and ui_menu. In battle, ui_menu opened the autobattle editor —
## a full-screen modal grid that reads as a pause menu to anyone who did not build it. Then
## ui_cancel, inside that grid, DELETED THE CELL under the cursor. So Escape opened it, Escape
## could not close it, and every further press silently destroyed a rule. Only F5 got out.
##
## struktured's ruling: "escape should back out of whatever menu ir in ... something natural."
## Escape is BACK, never OPEN.

const GL := "res://src/GameLoop.gd"
const ED := "res://src/ui/autobattle/AutobattleGridEditor.gd"

var _editor: Node = null


func before_each() -> void:
	_editor = load(ED).new()
	add_child_autofree(_editor)
	_editor.setup("hero", "Hero")
	await get_tree().process_frame


func _esc() -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = KEY_ESCAPE
	e.pressed = true
	return e


## The artist's second press. Behavioural, because a source pin passes on a handler that is
## present and dead — and this is the exact key she reported.
func test_escape_closes_the_editor_instead_of_deleting() -> void:
	var closed := [false]
	_editor.closed.connect(func(): closed[0] = true)
	_editor._input(_esc())
	assert_true(closed[0],
		"Escape must back out of the editor — she pressed it repeatedly and it deleted her rules instead")


## Delete has to survive the move, or the fix trades one broken thing for another.
func test_delete_is_still_reachable_on_keyboard_and_pad() -> void:
	var src := FileAccess.get_file_as_string(ED)
	assert_true(src.contains("KEY_DELETE, KEY_BACKSPACE"),
		"Delete/Backspace must delete a cell now that ui_cancel backs out")
	var y_at := src.find("JOY_BUTTON_Y")
	assert_gt(y_at, -1, "the pad's Y branch still exists")
	assert_true(src.substr(y_at, 320).contains("_delete_current_cell"),
		"a pad needs a delete too — Y off a condition cell was a dead end and now carries it")


## Escape must not OPEN the editor. This is the half that made her stuck rather than merely
## confused: the key she used to escape was the key that summoned it.
func test_escape_does_not_open_the_editor_in_battle() -> void:
	var src := FileAccess.get_file_as_string(GL)
	var branch := src.find("elif current_state == LoopState.BATTLE:", src.find('is_action_pressed("ui_menu")'))
	assert_gt(branch, -1, "the in-battle ui_menu branch exists")
	# Search from the branch to the end of the file rather than a fixed window — the opener
	# sits ~700 chars in, and a short window made this assert compare against -1.
	var guard := src.find("KEY_ESCAPE", branch)
	var opener := src.find("_toggle_autobattle_editor", branch)
	assert_gt(guard, -1, "the branch must reject Escape")
	assert_gt(opener, -1, "CONTROL: the opener is still in this branch, so the compare is real")
	assert_lt(guard, opener, "and reject it BEFORE the open, or Escape still summons the grid")


## The legend is what she would have read. It said "B:Delete", which was true and lethal.
func test_the_legend_tells_her_escape_goes_back() -> void:
	var src := FileAccess.get_file_as_string(ED)
	assert_true(src.contains("B/Esc:Back"), "the on-screen legend must say Escape backs out")
	assert_false(src.contains("B:Delete"),
		"and must no longer advertise B as delete — that is the mapping that trapped her")
