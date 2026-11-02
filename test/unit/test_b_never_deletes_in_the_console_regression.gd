extends GutTest

## struktured, 2026-11-01: B "doesn't close" the autogrind console, and his profile went from three rules (hp<30, mp<20,
## member_dead) to one. B on a rule cell was the console's DELETE, and deleting a rule's last condition deletes the rule, while
## the strip said "B Close". Ruling (cowir-main 21420/21422/21426): B never deletes; delete is the autobattle editor's own pad
## index; one level of undo; the strip names what each button does where the cursor stands.

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
		{"conditions": [{"type": "member_hp", "op": "<", "value": 30}, {"type": "member_dead"}], "actions": [{"type": "stop_grinding"}], "enabled": true},
		{"conditions": [{"type": "member_mp", "op": "<", "value": 20}], "actions": [{"type": "stop_grinding"}], "enabled": true},
	]
	ui._refresh_grid()
	return ui


func _at(ui: Node, row: int, col: int) -> String:
	ui.cursor_row = row
	ui.cursor_col = col
	ui._update_cursor()
	var cell = ui._get_cell_at_cursor()
	return str(cell.get_meta("cell_type", "?")) if cell != null and cell.has_meta("cell_type") else "none"


func test_b_deletes_nothing_on_any_cell_and_closes() -> void:
	for spot in [[0, 0], [0, 1], [1, 0], [2, 0]]:
		var ui := _console()
		var kind := _at(ui, spot[0], spot[1])
		var before: Array = ui.rules.duplicate(true)
		watch_signals(ui)
		ui._handle_cancel()
		assert_eq(ui.rules, before, "B on a %s cell must delete nothing" % kind)
		assert_signal_emitted(ui, "closed", "B on a %s cell must close the console" % kind)


func test_the_delete_button_deletes_exactly_one_condition() -> void:
	var ui := _console()
	assert_eq(_at(ui, 0, 0), "condition", "CONTROL: the cursor is on rule 1's first condition")
	ui._press_delete_button()
	assert_eq((ui.rules[0]["conditions"] as Array).size(), 1, "one press deletes one condition")
	assert_eq(ui.rules.size(), 2, "and no rule")


func test_a_delete_can_be_undone_to_the_identical_profile() -> void:
	var ui := _console()
	var before: Array = ui.rules.duplicate(true)
	_at(ui, 1, 0)
	ui._press_delete_button()
	assert_eq(ui.rules.size(), 1, "CONTROL: deleting a rule's only condition deletes the rule, which is what cost him his rules")
	_at(ui, ui.rules.size(), 0)
	ui._press_delete_button()
	assert_eq(ui.rules, before, "the delete button off a rule cell undoes the last delete, exactly")


func test_the_strip_names_what_the_delete_button_does_here() -> void:
	var ui := _console()
	_at(ui, 0, 0)
	assert_string_contains(ui._hint_strip_text(), "Delete", "on a rule cell the strip names Delete")
	assert_eq(ui._delete_button_word(), "Delete")
	_at(ui, ui.rules.size(), 0)
	assert_false(ui._hint_strip_text().contains("Delete") or ui._hint_strip_text().contains("Undo"), "off a cell, with nothing to undo, it names neither")
	_at(ui, 0, 0)
	ui._press_delete_button()
	_at(ui, ui.rules.size(), 0)
	assert_string_contains(ui._hint_strip_text(), "Undo", "after a delete, off a cell, it names Undo")


func test_no_two_console_commands_share_a_pad_button() -> void:
	var ui := _console()
	assert_eq(ui.DELETE_BUTTON, JOY_BUTTON_Y, "delete is the autobattle editor's own index")
	assert_true(FileAccess.get_file_as_string("res://src/ui/autobattle/AutobattleGridEditor.gd").contains("button_name_for_index(JOY_BUTTON_Y)"),
		"CONTROL: the autobattle editor still names its delete on JOY_BUTTON_Y")
	var owners := {}
	var add := func(name: String, idx: int) -> void:
		if not owners.has(idx):
			owners[idx] = []
		owners[idx].append(name)
	for action in ["ui_accept", "ui_cancel", "ui_menu"]:
		for idx in InputProfileManager.get_current_button_indices(action):
			add.call(action, int(idx))
	add.call("delete", ui.DELETE_BUTTON)
	add.call("ludicrous", JOY_BUTTON_X)
	add.call("options(L)", JOY_BUTTON_LEFT_SHOULDER)
	add.call("options(R)", JOY_BUTTON_RIGHT_SHOULDER)
	var shared: Array = []
	for idx in owners:
		if (owners[idx] as Array).size() > 1:
			shared.append("button %d: %s" % [idx, ", ".join(owners[idx])])
	assert_eq(shared, [], "two console commands on one pad button:\n  %s" % "\n  ".join(shared))


## Through _input, not the helpers: Ctrl+Z must undo and leave the console up (ui_cancel is plain Z, and an action match
## tolerates extra modifiers), and a real delete-button press must delete (cowir-controller 21436).
func test_the_routed_presses_delete_and_undo() -> void:
	var ui := _console()
	var before: Array = ui.rules.duplicate(true)
	_at(ui, 0, 0)
	var y := InputEventJoypadButton.new()
	y.button_index = ui.DELETE_BUTTON
	y.pressed = true
	ui._input(y)
	assert_ne(ui.rules, before, "CONTROL: the routed delete button deleted a condition")
	var z := InputEventKey.new()
	z.keycode = KEY_Z
	z.ctrl_pressed = true
	z.pressed = true
	ui._input(z)
	assert_eq(ui.rules, before, "Ctrl+Z through _input must undo the delete")
	assert_true(ui.visible, "and must not close the console the way Cancel does")
