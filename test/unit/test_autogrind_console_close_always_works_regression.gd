extends GutTest

## struktured 2026-09-06, LIVE WEDGE: "I somehow entered a village while in autogrind menu... I
## cant seem to exit autogrind rn, its busted." An AreaTransition fired UNDER the open console,
## he grinded from the new scene, the HP-threshold stop fired, and the console would not close.
##
## MECHANISM: _input's first line is `if not visible: return`, and a grind sets visible=false.
## So while hidden the console accepts NO input at all — including cancel. Every route back runs
## through GameLoop calling set_grinding(false). If any of them is missed — and _toggle_grinding
## sets visible=false BEFORE `await process_frame`, so an interruption there emits no
## grind_requested at all — the console is invisible, input-dead, and unrecoverable.
##
## The invariant: A CONSOLE THAT IS NOT GRINDING MUST ALWAYS BE CLOSEABLE, whatever its
## visibility. Closing is the escape hatch; it must not depend on the state that broke.

var _ui
var _closed_count: int = 0


func before_each() -> void:
	_closed_count = 0
	_ui = preload("res://src/ui/autogrind/AutogrindUI.gd").new()
	add_child_autofree(_ui)
	_ui.closed.connect(func() -> void: _closed_count += 1)


func _cancel() -> InputEvent:
	var ev := InputEventAction.new()
	ev.action = "ui_cancel"
	ev.pressed = true
	return ev


func test_cancel_closes_a_visible_idle_console() -> void:
	# ARM+: the ordinary path must work, else every assertion below is vacuous.
	_ui.visible = true
	_ui._is_grinding = false
	_ui._input(_cancel())
	assert_eq(_closed_count, 1, "control: cancel must close a normal, visible console")


func test_cancel_closes_a_HIDDEN_console_that_is_not_grinding() -> void:
	## THE WEDGE. visible=false with no grind running is exactly the state the interrupted
	## start-path and a missed set_grinding(false) both leave behind. Pre-fix this emitted
	## nothing and the player had no way out.
	_ui.visible = false
	_ui._is_grinding = false
	_ui._input(_cancel())
	assert_eq(_closed_count, 1,
		"a hidden, non-grinding console MUST still close — this is the only escape hatch")


func test_cancel_is_still_ignored_while_actually_grinding() -> void:
	## Scope guard: the fix must not let a stray cancel tear down a live grind. The monitor
	## owns the screen then, and stopping is its job.
	_ui.visible = false
	_ui._is_grinding = true
	_ui._input(_cancel())
	assert_eq(_closed_count, 0,
		"a running grind must not be closed by a stray cancel — the monitor owns that state")


func test_set_grinding_false_restores_visibility() -> void:
	# The documented recovery path still has to work; the fix is a backstop, not a replacement.
	_ui.visible = false
	_ui._is_grinding = true
	_ui.set_grinding(false)
	assert_true(_ui.visible, "set_grinding(false) must show the config UI again")
	assert_false(_ui._is_grinding, "and must clear the grinding flag")
