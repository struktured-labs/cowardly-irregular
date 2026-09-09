extends GutTest

## Every input test in this lane calls `_input(event)` BY HAND. That proves the handler EXECUTES;
## it says nothing about whether a real press REACHES it.
##
## @cowir-battle, 2026-09-09, after retracting the day's most-cited find: "a test that calls the
## repaired function directly cannot tell either — reachability is not a property you can observe
## from inside the thing you are reaching." Pyrroth's fire breath was correct, wired, guarded and
## unselectable; seven behavioural tests invoked the entry point by hand and all seven passed.
##
## This drives the REAL path: push the event at the viewport and let Godot route it. Verified
## headless — SubViewport.push_input reaches both _input and _unhandled_input.

const UI := "res://src/ui/autogrind/AutogrindUI.gd"

var _vp: SubViewport = null
var _layer: CanvasLayer = null
var _ui: Control = null


func before_each() -> void:
	_vp = SubViewport.new()
	_vp.size = Vector2i(1280, 720)
	add_child_autofree(_vp)
	_layer = CanvasLayer.new()
	_vp.add_child(_layer)
	_ui = load(UI).new()
	_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	_layer.add_child(_ui)
	await get_tree().process_frame
	await get_tree().process_frame


func after_each() -> void:
	if _ui and is_instance_valid(_ui):
		_ui.queue_free()
	_ui = null


func _shoulder() -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.button_index = JOY_BUTTON_LEFT_SHOULDER
	e.pressed = true
	return e


## THE REAL PATH. Not _ui._input(e) — the viewport routes it, so this also exercises the console
## being in the tree, visible, and nothing upstream consuming the press first.
func test_a_real_shoulder_press_opens_the_options_ring() -> void:
	assert_null(_ui._options_ring, "precondition: no ring open")
	_vp.push_input(_shoulder())
	await get_tree().process_frame
	assert_not_null(_ui._options_ring,
		"a press DELIVERED BY THE ENGINE must open the ring — calling _input() by hand cannot show this")


## THE DEMONSTRATION, and the reason this file exists. Detach the console from the tree: a direct
## call still reports success because the handler is fine. Real routing correctly sees nothing.
## That gap is exactly what hid Pyrroth's unselectable fire breath behind seven green tests.
func test_a_direct_call_cannot_tell_that_nothing_reaches_it() -> void:
	_layer.remove_child(_ui)
	await get_tree().process_frame

	# the handler still works when invoked by hand — this is the reassuring, useless result
	_ui._input(_shoulder())
	assert_not_null(_ui._options_ring,
		"CONTROL: called directly the handler still runs, which is what makes the weak test green")
	_ui._close_options_ring()

	# but the engine reaches nothing, because the node is not in the tree
	_vp.push_input(_shoulder())
	await get_tree().process_frame
	assert_null(_ui._options_ring,
		"an unreachable console must stay closed under REAL routing — if this opens, the test is not routing")

	_layer.add_child(_ui)


## A press must not open the ring when the console is hidden — the guard the real path exercises
## and a hand-call also honours, pinned so the routing arm is not the only thing standing.
func test_a_hidden_console_ignores_a_real_press() -> void:
	_ui.visible = false
	_vp.push_input(_shoulder())
	await get_tree().process_frame
	assert_null(_ui._options_ring, "a hidden console must not react to a press")
	_ui.visible = true
