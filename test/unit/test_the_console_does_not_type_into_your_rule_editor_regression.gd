extends GutTest
## Open the rules editor mid-grind, then let the grind STOP while you are editing -- an HP interrupt,
## a max-battles stop, or your own stop_grinding rule. GameLoop's _on_grind_complete calls
## AutogrindUI.set_grinding(false), which sets `visible = true` to bring the console back. The editor
## is still up, and it is our SIBLING (parented to our parent, deliberately), so hiding never covered
## it. Both are _input, and set_input_as_handled gates _unhandled_input, so BOTH read every press:
## one Cancel closes the editor AND the console.
## The dashboard half of this was already closed at GameLoop:7771-7778, hidden first and commented;
## the console was the surface nobody had hidden because a grind had hidden it for them.
const AutogrindState := preload("res://test/unit/helpers/autogrind_state.gd")
const UI := "res://src/ui/autogrind/AutogrindUI.gd"

var _ag: Dictionary


func before_each() -> void:
	_ag = AutogrindState.snapshot()
	AutogrindSystem._test_disable_persistence = true
	AutobattleSystem._test_disable_persistence = true


func after_each() -> void:
	AutogrindState.restore(_ag)


func _console() -> Node:
	var ui: Node = load(UI).new()
	add_child_autofree(ui)
	ui.visible = true
	return ui


func _assert_gate_exists(ui: Node) -> void:
	assert_true("_rules_editor_open" in ui,
		"FLOOR: AutogrindUI._rules_editor_open must exist, or every arm here passes by absence")


func _set_editor(ui: Node, ed) -> bool:
	if not ("_rules_editor_open" in ui):
		return false
	ui._rules_editor_open = ed
	return true


func _an_editor(vis: bool = true) -> Control:
	var c := Control.new()
	add_child_autofree(c)
	c.visible = vis
	return c


func _cancel(ui: Node) -> void:
	var ev := InputEventAction.new()
	ev.action = "ui_cancel"
	ev.pressed = true
	ui._input(ev)


## THE DEFECT: with the editor up, the console must not act on the press that closes it.
func test_the_console_stands_down_while_the_rule_editor_is_open() -> void:
	var ui := _console()
	_assert_gate_exists(ui)
	if not _set_editor(ui, _an_editor()):
		return
	watch_signals(ui)
	_cancel(ui)
	assert_signal_not_emitted(ui, "closed",
		"the Cancel that closes the rule editor must not also close the console behind it")


## CONTROL: and it must still close normally, or this gate is a lockout rather than a fix.
func test_the_console_still_closes_when_no_editor_is_open() -> void:
	var ui := _console()
	_assert_gate_exists(ui)
	if not _set_editor(ui, null):
		return
	watch_signals(ui)
	_cancel(ui)
	assert_signal_emitted(ui, "closed",
		"CONTROL: with no editor up, Cancel must still close the console")


## CONTROL: a freed editor must not block forever -- is_instance_valid is load-bearing.
func test_a_freed_editor_does_not_wedge_the_console() -> void:
	var ui := _console()
	_assert_gate_exists(ui)
	var ed := Control.new()
	if not _set_editor(ui, ed):
		return
	ed.free()
	watch_signals(ui)
	_cancel(ui)
	assert_signal_emitted(ui, "closed",
		"CONTROL: a freed editor must not leave the console permanently deaf")


## CONTROL: a HIDDEN editor must not block either -- the gate reads visible, not mere existence.
func test_a_hidden_editor_does_not_block_the_console() -> void:
	var ui := _console()
	_assert_gate_exists(ui)
	if not _set_editor(ui, _an_editor(false)):
		return
	watch_signals(ui)
	_cancel(ui)
	assert_signal_emitted(ui, "closed",
		"CONTROL: an editor that is not on screen must not swallow the console's input")


## THE ARM THAT PINS THE GATE'S POSITION. Hidden + not grinding is the wedge-escape path: Cancel
## closes the console even while invisible. With the editor up that hatch must NOT fire, or the same
## Cancel closes both. A gate placed BELOW the hatch passes every other arm here and fails this one.
func test_the_hidden_console_escape_hatch_stands_down_for_the_editor() -> void:
	var ui := _console()
	_assert_gate_exists(ui)
	if not _set_editor(ui, _an_editor()):
		return
	ui.visible = false
	ui._is_grinding = false
	watch_signals(ui)
	_cancel(ui)
	assert_signal_not_emitted(ui, "closed",
		"the hidden console's Cancel hatch must stand down for the editor, or one press closes both")


## CONTROL: the hatch must still work with no editor up -- it exists because a hidden console with
## no grind was input-dead with no way out (struktured, 2026-09-06).
func test_the_hidden_console_escape_hatch_still_works_alone() -> void:
	var ui := _console()
	_assert_gate_exists(ui)
	if not _set_editor(ui, null):
		return
	ui.visible = false
	ui._is_grinding = false
	watch_signals(ui)
	_cancel(ui)
	assert_signal_emitted(ui, "closed",
		"CONTROL: with no editor, Cancel must still rescue a hidden console")


## THE WIRING, not the gate. Every arm above SETS the field by hand, so all of them pass even if
## open_rules_editor never records the editor -- the fix would be inert and the guard green, which
## is the exact shape of a sentence wired to a handler nothing calls.
func test_opening_the_editor_records_it() -> void:
	var ui := _console()
	_assert_gate_exists(ui)
	assert_true(ui.has_method("open_rules_editor"), "FLOOR: open_rules_editor must exist")
	if not ui.has_method("open_rules_editor"):
		return
	var ed = ui.open_rules_editor()
	assert_not_null(ed, "FLOOR: the editor must actually be created")
	if ed == null:
		return
	assert_eq(ui._rules_editor_open, ed,
		"opening the editor must RECORD it, or the gate above guards a field nobody fills")
	ed.queue_free()


## And releases it, or the console is deaf for the rest of the session.
func test_closing_the_editor_releases_the_console() -> void:
	var ui := _console()
	_assert_gate_exists(ui)
	if not ui.has_method("open_rules_editor"):
		return
	var ed = ui.open_rules_editor()
	if ed == null:
		return
	assert_eq(ui._rules_editor_open, ed, "FLOOR: it must be recorded before we can watch it clear")
	ed.closed.emit()
	assert_null(ui._rules_editor_open,
		"closing must release the console, or every later press is swallowed for the whole session")
