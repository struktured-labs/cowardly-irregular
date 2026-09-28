extends GutTest

## Regression: How to Play opened from the Controls menu handles only Back and up/down, so a
## confirm fell through to ControlsMenu._input, which re-ran the selected row — How to Play — and
## stacked another copy on top. Each copy then needed its own Back. struktured's play log of
## 2026-09-24 carries it: 15 confirms in a row, each opening a fresh overlay (its
## "This control can't grab focus" warning), none closing. TitleScreen and GameLoop's F1 already
## stand aside while their overlay is up; the Controls menu was the one opener that did not.

const ControlsMenuScript := preload("res://src/ui/ControlsMenu.gd")
const OverlayScript := preload("res://src/ui/HowToPlayOverlay.gd")

var _vp: SubViewport
var _menu: Control


func before_each() -> void:
	_vp = SubViewport.new()
	_vp.size = Vector2i(1280, 720)
	add_child_autofree(_vp)
	_menu = ControlsMenuScript.new()
	_menu.size = Vector2(1280, 720)
	_vp.add_child(_menu)
	await get_tree().process_frame
	_menu.selected_index = _menu.ROW_HELP


func _press(action: String) -> void:
	var down := InputEventAction.new()
	down.action = action
	down.pressed = true
	_vp.push_input(down)
	var up := InputEventAction.new()
	up.action = action
	up.pressed = false
	_vp.push_input(up)
	await get_tree().process_frame


func _overlays() -> int:
	var n := 0
	for c in _menu.find_children("*", "Control", true, false):
		if c.get_script() == OverlayScript and not c.is_queued_for_deletion():
			n += 1
	return n


func test_confirm_while_reading_does_not_stack_a_second_copy() -> void:
	await _press("ui_accept")
	assert_eq(_overlays(), 1, "CONTROL: confirm on the How to Play row opened it")
	await _press("ui_accept")
	await _press("ui_accept")
	assert_eq(_overlays(), 1, "confirm while reading How to Play stacked more copies on top")


func test_one_back_returns_to_a_live_controls_menu() -> void:
	await _press("ui_accept")
	await _press("ui_accept")
	await _press("ui_cancel")
	assert_eq(_overlays(), 0, "one Back must close How to Play")
	await _press("ui_accept")
	assert_eq(_overlays(), 1, "the Controls menu must answer again once How to Play is closed")
