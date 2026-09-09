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


## ── cowir-autogrind: the two guards whose SUBJECT is input arriving ──────────────────────────
## @cowir-controller planted this defect against MY console and it is worse for my suites than for
## theirs. Their planted break made a feature silently ABSENT. Mine makes guards that exist to
## CONTROL INPUT ARRIVAL pass BECAUSE nothing arrives:
##
##   the TutorialHint gate   "the console must not act on a hint's dismiss press"
##   the close escape hatch  "a hidden, non-grinding console must still be closeable"
##
## Both are satisfied perfectly by a console that receives nothing. A guard whose subject is input
## reaching the wrong place, verified by calling the handler by hand, is testing the one thing it
## cannot see. Verified: with set_process_input(false) my five console suites stay GREEN.


func _cancel() -> InputEventAction:
	var e := InputEventAction.new()
	e.action = "ui_cancel"
	e.pressed = true
	return e


func _up() -> InputEventAction:
	var e := InputEventAction.new()
	e.action = "ui_up"
	e.pressed = true
	return e


func test_a_real_press_MOVES_the_cursor_when_no_hint_is_active() -> void:
	## ARM+ for the gate arm below, and the whole reason it is not vacuous: the press must be shown
	## to ARRIVE before "the hint blocked it" means anything.
	var saved: int = TutorialHint._active_count
	TutorialHint._active_count = 0
	_ui.cursor_row = 2
	_vp.push_input(_up())
	await get_tree().process_frame
	TutorialHint._active_count = saved
	assert_eq(int(_ui.cursor_row), 1,
		"a real ui_up must move the cursor — if it does not, nothing below is testing the gate")


func test_a_live_hint_blocks_a_REAL_press_not_just_a_hand_called_one() -> void:
	## My hint gate, through the engine. Pre-routing this was verified by calling _input() by hand,
	## which cannot distinguish "the gate blocked it" from "it never arrived".
	var saved: int = TutorialHint._active_count
	TutorialHint._active_count = 1
	_ui.cursor_row = 2
	_vp.push_input(_up())
	await get_tree().process_frame
	TutorialHint._active_count = saved
	assert_eq(int(_ui.cursor_row), 2,
		"a live hint owns the press — the console must not also act on it")


func test_the_escape_hatch_works_under_REAL_routing() -> void:
	## struktured's console wedge: a grind hides the console, and every route back runs through
	## GameLoop calling set_grinding(false). Hidden + not grinding was input-dead with no exit.
	## The hatch is the only way out, so verifying it by hand-calling _input is the weakest possible
	## check of an escape route.
	var closed := [0]
	_ui.closed.connect(func() -> void: closed[0] += 1)
	_ui.visible = false
	_ui._is_grinding = false
	_vp.push_input(_cancel())
	await get_tree().process_frame
	assert_eq(closed[0], 1,
		"a hidden, non-grinding console must close on a press DELIVERED BY THE ENGINE")


func test_the_hatch_does_not_contradict_the_hidden_console_rule() -> void:
	## Scope pin against a future simplification. The arm above says a hidden console CLOSES on
	## cancel; test_a_hidden_console_ignores_a_real_press says a hidden console IGNORES a shoulder.
	## Both are correct and they are adjacent, so someone collapsing them would break the wedge fix.
	## A running grind must still ignore cancel — the monitor owns that state.
	var closed := [0]
	_ui.closed.connect(func() -> void: closed[0] += 1)
	_ui.visible = false
	_ui._is_grinding = true
	_vp.push_input(_cancel())
	await get_tree().process_frame
	assert_eq(closed[0], 0,
		"a RUNNING grind must not be closed by a stray cancel, even a real one")
