extends GutTest

## struktured, 2026-11-01: B "doesn't close" the autogrind console, and his profile went from three rules (hp<30, mp<20,
## member_dead) to one. B on a rule cell was the console's DELETE, and deleting a rule's last condition deletes the rule, while
## the strip said "B Close". Ruling (cowir-main 21420/21422/21426/21462): B never deletes; the north button does what the
## autobattle editor's does (operator on a condition, delete on an action, undo off a cell); one level of undo.

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
	ui.rules = [
		{"conditions": [{"type": "member_hp", "op": "<", "value": 30}, {"type": "member_dead"}],
			"actions": [{"type": "heal_party"}, {"type": "stop_grinding"}], "enabled": true},
		{"conditions": [{"type": "member_mp", "op": "<", "value": 20}], "actions": [{"type": "stop_grinding"}], "enabled": true},
	]
	ui._refresh_grid()
	return ui


func _at(ui: Node, row: int, col: int) -> String:
	ui.cursor_row = row
	ui.cursor_col = col
	ui._update_cursor()
	return ui._cell_type_at_cursor()


## The first column on `row` holding a cell of `kind`, so the fixture does not hardcode the grid's slot arithmetic.
func _find(ui: Node, row: int, kind: String) -> int:
	for col in 12:
		if _at(ui, row, col) == kind:
			return col
	return -1


func _press(ui: Node, ev: InputEvent) -> void:
	ui._input(ev)


func _pad(idx: int) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.button_index = idx
	e.pressed = true
	return e


func _key(code: Key, ctrl := false) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code
	e.ctrl_pressed = ctrl
	e.pressed = true
	return e


func test_b_deletes_nothing_on_any_cell_and_closes() -> void:
	for spot in [[0, 0], [0, 1], [1, 0], [2, 0]]:
		var ui := _console()
		var kind := _at(ui, spot[0], spot[1])
		var before: Array = ui.rules.duplicate(true)
		watch_signals(ui)
		ui._handle_cancel()
		assert_eq(ui.rules, before, "B on a %s cell must delete nothing" % kind)
		assert_signal_emitted(ui, "closed", "B on a %s cell must close the console" % kind)


func test_the_north_button_cycles_an_operator_and_deletes_no_condition() -> void:
	var ui := _console()
	assert_eq(_at(ui, 0, 0), "condition", "CONTROL: the cursor is on rule 1's hp < 30")
	_press(ui, _pad(ui.DELETE_BUTTON))
	assert_eq((ui.rules[0]["conditions"] as Array).size(), 2, "the north button on a condition deletes nothing")
	assert_eq(str(ui.rules[0]["conditions"][0]["op"]), "<=", "it steps hp < 30 to the next operator")
	assert_eq(ui._delete_button_word(), "Operator", "and the strip names the operator")


func test_a_condition_without_an_operator_is_left_alone() -> void:
	var ui := _console()
	assert_eq(_at(ui, 0, 1), "condition", "CONTROL: the cursor is on Any Dead")
	var before: Array = ui.rules.duplicate(true)
	_press(ui, _pad(ui.DELETE_BUTTON))
	assert_eq(ui.rules, before, "Any Dead has no operator, so the north button changes nothing")
	assert_eq(ui._delete_button_word(), "", "and the strip names no verb there")


func test_the_north_button_deletes_exactly_one_action_and_undo_restores_it() -> void:
	var ui := _console()
	var before: Array = ui.rules.duplicate(true)
	var col := _find(ui, 0, "action")
	assert_gt(col, -1, "CONTROL: rule 1 shows an action cell")
	_press(ui, _pad(ui.DELETE_BUTTON))
	assert_eq((ui.rules[0]["actions"] as Array).size(), 1, "one press deletes one action")
	assert_eq((ui.rules[0]["conditions"] as Array).size(), 2, "and touches no condition")
	_at(ui, ui.rules.size(), 0)
	assert_eq(ui._delete_button_word(), "Undo", "off a cell after a delete, the strip names Undo")
	_press(ui, _pad(ui.DELETE_BUTTON))
	assert_eq(ui.rules, before, "the north button off a cell undoes the last delete, exactly")


func test_the_keyboard_deletes_one_condition_and_ctrl_z_undoes_it_without_closing() -> void:
	var ui := _console()
	var before: Array = ui.rules.duplicate(true)
	_at(ui, 0, 0)
	_press(ui, _key(KEY_DELETE))
	assert_eq((ui.rules[0]["conditions"] as Array).size(), 1, "Delete removes one condition")
	_press(ui, _key(KEY_Z, true))
	assert_eq(ui.rules, before, "Ctrl+Z through _input restores it exactly")
	assert_true(ui.visible, "and does not close the console the way Cancel does")


## cowir-controller 21460: an undo taken before the rules were swapped must not paste the old list over the new one.
func test_an_undo_refuses_once_the_rules_changed_since_the_delete() -> void:
	var ui := _console()
	_find(ui, 0, "action")
	_press(ui, _pad(ui.DELETE_BUTTON))
	assert_true(ui._undo_is_live(), "CONTROL: right after the delete there is an undo")
	var swapped: Array = [{"conditions": [{"type": "always"}], "actions": [{"type": "stop_grinding"}], "enabled": true}]
	ui.rules = swapped.duplicate(true)
	ui._refresh_grid()
	_at(ui, ui.rules.size(), 0)
	assert_eq(ui._delete_button_word(), "", "a retired undo is not offered")
	_press(ui, _pad(ui.DELETE_BUTTON))
	_press(ui, _key(KEY_Z, true))
	assert_eq(ui.rules, swapped, "neither the button nor Ctrl+Z pastes the old rules over the new ones")


func test_no_two_console_commands_share_a_pad_button() -> void:
	var ui := _console()
	assert_eq(ui.DELETE_BUTTON, JOY_BUTTON_Y, "the north verb is the autobattle editor's own index")
	assert_true(FileAccess.get_file_as_string("res://src/ui/autobattle/AutobattleGridEditor.gd").contains("event.button_index == JOY_BUTTON_Y:"),
		"CONTROL: the autobattle editor still handles JOY_BUTTON_Y")
	var owners := {}
	var add := func(name: String, idx: int) -> void:
		if not owners.has(idx):
			owners[idx] = []
		owners[idx].append(name)
	for action in ["ui_accept", "ui_cancel", "ui_menu"]:
		for idx in InputProfileManager.get_current_button_indices(action):
			add.call(action, int(idx))
	add.call("north verb", ui.DELETE_BUTTON)
	add.call("ludicrous", JOY_BUTTON_X)
	add.call("options(L)", JOY_BUTTON_LEFT_SHOULDER)
	add.call("options(R)", JOY_BUTTON_RIGHT_SHOULDER)
	var shared: Array = []
	for idx in owners:
		if (owners[idx] as Array).size() > 1:
			shared.append("button %d: %s" % [idx, ", ".join(owners[idx])])
	assert_eq(shared, [], "two console commands on one pad button:\n  %s" % "\n  ".join(shared))


## With a pad attached "[R]" reads as the R shoulder, which opens the options ring; the keyboard strip keeps it.
func test_a_pad_strip_does_not_offer_r_for_resume() -> void:
	var ui := _console()
	assert_string_contains(ui._hint_strip_text(), "[R] Resume", "CONTROL: the keyboard strip still names R for Resume")
	for pad in ["Nintendo Switch Pro Controller", "Xbox Series Controller", "Sony DualSense Wireless Controller"]:
		var strip: String = ui._hint_strip_text(pad)
		assert_false(strip.contains("[R]"), "%s: '[R]' sits beside the R shoulder that opens options: %s" % [pad, strip])
		assert_string_contains(strip, "Resume", "%s: Resume is still named, in the options list" % pad)
