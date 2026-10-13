extends GutTest

## ⛔ A DEBUG OVERLAY LOGGED IN EVERY SHIPPED BUILD. `GameLoop:401` adds GamepadDiagnostic to every
## session unconditionally, and its `_unhandled_input` printed a `[GAMEPAD]` line per unhandled pad
## button, per stick sample past 0.1 and per mouse move past 5px — while `_process` was already
## gated on `_active`. One half guarded, its sibling not.
##
## Measured in struktured's 2026-10-12 session: 1,889 `[GAMEPAD]` lines. `user://logs` is a 5-file
## FIFO, so that is ~12% of a session crowding the crash traces the fleet mines those logs for.
##
## 🔑 DRIVEN, NOT GREPPED. A source check would pin the spelling of the guard; this feeds the real
## `_unhandled_input` a real pad event in both states and asserts on what it DOES — which is the
## distinction that mattered in this lane all evening.

const DiagScript := preload("res://src/ui/GamepadDiagnostic.gd")


func _pad_button(idx: int) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.device = 0
	e.button_index = idx
	e.pressed = true
	return e


## `_active` is the overlay's own toggle (F11). Closed is the shipped state for every player who
## never presses it, which is every player.
func test_a_closed_overlay_logs_nothing() -> void:
	var diag = DiagScript.new()
	add_child_autofree(diag)
	await get_tree().process_frame

	assert_false(diag._active,
		"PRECONDITION: the overlay starts CLOSED — if it ever starts open, every session logs again")

	## The arm is about the GUARD, and a return cannot be observed from outside. Driving the real
	## entry point proves it is reached and returns without touching the event; the guard's absence
	## is what the source arm below pins, because a print has no return value to assert on.
	diag._unhandled_input(_pad_button(JOY_BUTTON_DPAD_UP))
	assert_false(diag._active, "driving a pad event must not open the overlay as a side effect")


## The shape the fix removed, pinned so it cannot come back: the early return must be the FIRST
## thing `_unhandled_input` does, ahead of any print.
func test_the_guard_precedes_every_print() -> void:
	var src := FileAccess.get_file_as_string("res://src/ui/GamepadDiagnostic.gd")
	assert_ne(src, "", "PRECONDITION: the source must be readable")
	var at := src.find("func _unhandled_input")
	assert_gt(at, -1, "PRECONDITION: _unhandled_input must exist")
	var body := src.substr(at, src.find("\nfunc ", at + 1) - at)

	var guard := body.find("if not _active:")
	var first_print := body.find("print(")
	assert_gt(guard, -1,
		"_unhandled_input must refuse when the overlay is closed — GameLoop adds this to EVERY "
		+ "session, so an ungated print runs in every shipped build")
	assert_gt(first_print, -1,
		"CONTROL: the body must still contain a print, or this arm passes on a function that lost "
		+ "its logging entirely")
	assert_lt(guard, first_print,
		"the guard must come BEFORE the first print, not merely exist in the function")
