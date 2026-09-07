extends GutTest

## AutogrindUI and AutogrindGridEditor were the only two _input consumers in src/ not gating on
## TutorialHint.is_any_active() — 19 other files do. They were protected only by tree ordering
## (a hint parented to the console is a child, and children consume first), which is incidental,
## not asserted: the bare "autogrind" hint is parented to GameLoop, making it a SIBLING of the
## menu layers rather than an ancestor. struktured 2026-09-06: "the autogrind explanation drives
## the menu forward".

var _ui
var _editor
var _saved_count: int = 0


func before_each() -> void:
	_saved_count = TutorialHint._active_count
	TutorialHint._active_count = 0
	_ui = preload("res://src/ui/autogrind/AutogrindUI.gd").new()
	add_child_autofree(_ui)
	_ui.visible = true
	_editor = preload("res://src/ui/autogrind/AutogrindGridEditor.gd").new()
	add_child_autofree(_editor)
	_editor.visible = true


func after_each() -> void:
	## Static — a leaked non-zero count silently gates every later test's input.
	TutorialHint._active_count = _saved_count


func _press(action: String) -> InputEvent:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	return ev


func test_console_moves_the_cursor_with_no_hint_active() -> void:
	# ARM+. Without this, "cursor did not move" below passes even if the event never arrives.
	_ui.cursor_row = 2
	_ui._input(_press("ui_up"))
	assert_eq(int(_ui.cursor_row), 1,
		"control: with no hint active the console must consume ui_up, else the gate test is vacuous")


func test_console_ignores_input_while_a_hint_is_active() -> void:
	_ui.cursor_row = 2
	TutorialHint._active_count = 1
	_ui._input(_press("ui_up"))
	assert_eq(int(_ui.cursor_row), 2,
		"a live tutorial hint owns the press — the console must not also act on it")


func test_grid_editor_moves_its_cursor_with_no_hint_active() -> void:
	# ARM+ for the editor. cursor_row defaults to 0 where ui_up is max(0,-1) — a no-op — so
	# starting there made the gate arm below pass with the guard DELETED (mutation, 2026-09-06).
	_editor.cursor_row = 2
	_editor._input(_press("ui_up"))
	assert_eq(int(_editor.cursor_row), 1,
		"control: the editor must consume ui_up from a non-zero row, else its gate arm is vacuous")


func test_grid_editor_is_gated_too() -> void:
	# The editor is a separate consumer; the gate is per-consumer, so it needs its own arm.
	_editor.cursor_row = 2
	TutorialHint._active_count = 1
	_editor._input(_press("ui_up"))
	assert_eq(int(_editor.cursor_row), 2,
		"the grid editor must ignore input while a hint is active")


func test_the_gate_reads_the_shared_counter_not_a_local_flag() -> void:
	# Pins the mechanism: clearing the counter must re-enable input, so the guard cannot be
	# a one-way latch that leaves the console dead after the first hint of a session.
	_ui.cursor_row = 2
	TutorialHint._active_count = 1
	_ui._input(_press("ui_up"))
	TutorialHint._active_count = 0
	_ui._input(_press("ui_up"))
	assert_eq(int(_ui.cursor_row), 1,
		"once the hint clears, the console must accept input again")
