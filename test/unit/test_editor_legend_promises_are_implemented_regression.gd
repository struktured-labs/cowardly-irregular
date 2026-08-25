extends GutTest

## struktured 2026-08-23, shipped build 08e90acf: stuck in the autobattle editor with a mouse.
##
## The legend strip at the bottom of that screen has read "RClick:Close" since it shipped.
## Nothing implemented it — the file had zero MOUSE_BUTTON_RIGHT handlers. Meanwhile ui_cancel
## (X / Escape / gamepad B) DELETES A CELL rather than backing out, so F5 was the only exit
## and it is the one key a stuck player has no reason to try.
##
## A legend is a promise rendered on screen. This joins it to the handler set so the two
## cannot drift apart again — the failure mode is silent by construction, because the promise
## renders perfectly whether or not anything reads the input.

const ED := "res://src/ui/autobattle/AutobattleGridEditor.gd"


func _source() -> String:
	var s := FileAccess.get_file_as_string(ED)
	assert_gt(s.length(), 1000, "the editor source must load — an empty read passes every contains() below")
	return s


## The specific promise he was standing in front of.
func test_right_click_closes_the_editor_because_the_legend_says_it_does() -> void:
	var src := _source()
	assert_true(src.contains("RClick:Close"), "CONTROL: the legend still makes this promise")
	assert_true(src.contains("MOUSE_BUTTON_RIGHT"), "and something must implement it")
	var handler := src.find("MOUSE_BUTTON_RIGHT")
	var seg := src.substr(handler, 220)
	assert_true(seg.contains("save_and_close"),
		"right-click must SAVE and close — a bare close would discard the rules they just edited")


## The exit must be reachable ahead of the grid's own consumption. _input returns early for
## several submodes; a handler placed after them is unreachable exactly when a player is stuck.
func test_the_mouse_exit_is_not_behind_a_submode_early_return() -> void:
	var src := _source()
	var fn := src.find("func _input")
	assert_gt(fn, -1, "the editor handles _input")
	var right := src.find("MOUSE_BUTTON_RIGHT", fn)
	var keyboard_gate := src.find("_keyboard and is_instance_valid(_keyboard)", fn)
	var picker_gate := src.find("_share_picker and is_instance_valid(_share_picker)", fn)
	assert_gt(right, fn, "the right-click branch is inside _input")
	assert_lt(right, keyboard_gate, "and precedes the on-screen-keyboard early return")
	assert_lt(right, picker_gate, "and the share-picker early return")


## Why the trap was invisible: the universal back button is bound to something destructive here.
## Pinned so a future edit that reintroduces "cancel closes" has to notice this comment.
## ui_cancel binds FOUR times here and means "back" in three of them — leave portrait focus,
## close the option picker, close the share picker. In the main grid, the one you sit in, it
## deletes. find() lands on the portrait branch, so anchor on the grid one specifically.
func test_cancel_still_deletes_a_cell_which_is_why_a_mouse_exit_was_needed() -> void:
	var src := _source()
	var anchor := src.find("# B button - Delete current cell")
	assert_gt(anchor, -1, "the grid's cancel branch is still labelled")
	var seg := src.substr(anchor, 200)
	assert_true(seg.contains('is_action_pressed("ui_cancel")'), "and still bound to ui_cancel")
	assert_true(seg.contains("_delete_current_cell"),
		"ui_cancel deletes in the grid — if this ever becomes 'close', the mouse exit stops being the only back and this test should be revisited")
	var cancels := src.split('is_action_pressed("ui_cancel")').size() - 1
	assert_gt(cancels, 1, "CONTROL: ui_cancel binds in several contexts, so a bare find() would grab the wrong one")
