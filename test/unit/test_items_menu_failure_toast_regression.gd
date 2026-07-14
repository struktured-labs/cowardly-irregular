extends GutTest

## Trying to use Phoenix Down on a living party member fired a
## menu_error SFX with no other feedback — the menu stayed open, the
## item stayed selected, the targets stayed unhighlighted. The player
## couldn't tell whether the click registered or what they did wrong.
##
## Same shape for the generic 'use_item returned false' branch (heal
## at full HP, status-clear with no matching status, etc).
##
## Fix: Toast.show_warning on both paths with a reason. Audio cue
## preserved alongside the visible message.

const ITEMS_MENU := "res://src/ui/ItemsMenu.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


func test_revive_on_alive_target_toasts() -> void:
	var src := _read(ITEMS_MENU)
	assert_true(src.contains("Cannot revive — no KO'd target"),
		"Phoenix Down on a living target must Toast a 'no KO'd target' message")


func test_use_item_failure_toasts() -> void:
	var src := _read(ITEMS_MENU)
	assert_true(src.contains("Item had no effect"),
		"use_item returning false must Toast a 'no effect' message (target already healthy, etc)")
