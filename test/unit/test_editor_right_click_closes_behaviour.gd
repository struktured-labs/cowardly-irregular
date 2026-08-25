extends GutTest

## Behavioural companion to test_editor_legend_promises_are_implemented_regression.
##
## That file's source pins pass on DEAD WIRING — measured: adding "and false" to the
## right-click condition left every assertion green, because the string and the
## save_and_close call are both still present. Same hollow shape as the settings-menu
## _nav_repeat pin. This drives a real editor with a real event instead.

var _editor: Node = null
var _closed_fired: bool = false


func before_each() -> void:
	_closed_fired = false
	_editor = load("res://src/ui/autobattle/AutobattleGridEditor.gd").new()
	add_child_autofree(_editor)
	_editor.setup("hero", "Hero")
	await get_tree().process_frame
	_editor.closed.connect(func(): _closed_fired = true)


func _right_click() -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_RIGHT
	e.pressed = true
	return e


func _left_click() -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	return e


func test_a_real_right_click_closes_the_editor() -> void:
	assert_true(_editor.visible, "precondition: the editor is up")
	assert_false(_closed_fired, "precondition: it has not closed yet")
	_editor._input(_right_click())
	assert_true(_closed_fired,
		"right-click must emit closed — the legend has promised RClick:Close since this shipped, and dead wiring reads identically in the source")


## CONTROL. Without it, "closed fired" could pass on an editor that closes on ANY event —
## which would be a different and worse bug.
func test_a_left_click_does_not_close_the_editor() -> void:
	_editor._input(_left_click())
	assert_false(_closed_fired, "only RIGHT click closes; left-click is the edit button")
