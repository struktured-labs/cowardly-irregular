extends GutTest

## Third and last editor with Leo's wedge (2026-08-30: "Everytime i hit Esc, the thing gets
## stuck in the pause menu"). AutobattleGridEditor was fixed then; AutogrindGridEditor was not.
##
## MEASURED before the fix: Escape binds BOTH ui_cancel and ui_menu. In this file's elif chain
## ui_cancel sits at :1029 and ui_menu at :1105, and ui_cancel calls set_input_as_handled() —
## so Escape DELETED the cell under the cursor and could never reach save-and-close. The later
## `keycode == KEY_ESCAPE or KEY_ENTER` branch was unreachable for both keys (ui_accept binds
## Enter), i.e. an exit that reads as present in source and cannot fire.

const ED := "res://src/ui/autogrind/AutogrindGridEditor.gd"

var _vp: SubViewport = null
var _ed: Node = null


## Own viewport per test: the shared one latches is_input_handled(), which silently disarms
## every _input arm after the first handled press.
func before_each() -> void:
	_vp = SubViewport.new()
	_vp.size = Vector2i(1280, 720)
	add_child_autofree(_vp)
	_ed = load(ED).new()
	_vp.add_child(_ed)
	await get_tree().process_frame
	await get_tree().process_frame


func after_each() -> void:
	if _ed and is_instance_valid(_ed):
		_ed.queue_free()
	_ed = null


func _action(name: String) -> InputEventAction:
	var e := InputEventAction.new()
	e.action = name
	e.pressed = true
	return e


## Behavioural: the press he actually made. A source pin passes on a handler that is present
## and dead — which is exactly what the old KEY_ESCAPE branch was.
func test_cancel_backs_out_instead_of_deleting() -> void:
	var closed := [false]
	_ed.closed.connect(func(): closed[0] = true)
	_ed._input(_action("ui_cancel"))
	assert_true(closed[0],
		"Escape/B must leave the editor — it deleted the cell under the cursor instead")


## Delete has to survive the move, or the fix trades one broken thing for another.
func test_delete_is_still_reachable_on_both_devices() -> void:
	var src := FileAccess.get_file_as_string(ED)
	assert_true(src.contains("KEY_DELETE, KEY_BACKSPACE"),
		"a keyboard needs a delete now that ui_cancel backs out")
	var x_at := src.find("JOY_BUTTON_X")
	assert_gt(x_at, -1, "a pad needs one too — X was the only free button in this file")
	assert_true(src.substr(x_at, 200).contains("_delete_current_cell"),
		"and X must actually delete, not merely be bound")


## The dead exit must not be silently restored: it reads as a working Escape and is not one.
func test_the_unreachable_escape_branch_is_not_reinstated() -> void:
	var src := FileAccess.get_file_as_string(ED)
	assert_false(src.contains("event.keycode == KEY_ESCAPE or event.keycode == KEY_ENTER"),
		"that branch cannot fire — ui_cancel takes Escape and ui_accept takes Enter above it")


## The legend is what he would have read. It said B:Delete, which was true and lethal.
func test_the_legend_tells_him_escape_goes_back() -> void:
	var src := FileAccess.get_file_as_string(ED)
	assert_true(src.contains("/Esc:Back"),
		"the on-screen legend must say Escape backs out")
	## The face glyph is DERIVED now (InputProfileManager.glyph_for_action), so pinning the
	## literal "B/Esc:Back" pinned a spelling no PlayStation player ever sees. The intent --
	## Escape is named as the way back -- survives derivation; the letter never should have.
	assert_true(src.contains("glyph_for_action("),
		"and the face letter beside it must be derived, not frozen back in")
	assert_false(src.contains("B:Delete"),
		"and must stop advertising B as delete — that is the mapping that trapped him")


## CONTROL: ui_accept must still edit, so "cancel closed it" is not just "everything closes it".
func test_accept_still_edits_and_does_not_close() -> void:
	var closed := [false]
	_ed.closed.connect(func(): closed[0] = true)
	_ed._input(_action("ui_accept"))
	assert_false(closed[0], "A edits a cell; only cancel/Start leave")
