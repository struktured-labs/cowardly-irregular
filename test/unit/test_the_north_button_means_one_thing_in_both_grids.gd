extends GutTest

## cowir-main 2026-11-02 (21462/21465): the north face button does the SAME thing in the autobattle grid
## editor and the autogrind console, cell for cell: a condition with an operator CYCLES it, a nullary
## condition does NOTHING, an action is DELETED, and an empty slot UNDOES the last delete (else nothing).
## The console used to delete conditions on that button while the editor cycled them, so one muscle
## memory removed a rule in one screen and tuned it in the other.
##
## ⛔ BEHAVIOURAL, NOT A REPORTED VERB. A real press goes through each screen's `_input` and the verb is read
## off the RULE DATA before and after. A `y_verb()` getter would be a second copy of the branch and could
## agree with itself while the handler did something else.
##
## Each arm asserts the two screens agree AND that they give the ruled verb, so both drifting the same way
## still reds.

const ED := "res://src/ui/autobattle/AutobattleGridEditor.gd"
const UI := "res://src/ui/autogrind/AutogrindUI.gd"
const ABProfiles := preload("res://test/unit/helpers/autobattle_profiles.gd")
const AutogrindState := preload("res://test/unit/helpers/autogrind_state.gd")

## Editor columns: 0 = hp_percent (has an operator) · 1 = ally_dead (nullary) · 2 = the empty AND slot
## · 3 = Attack · 4 = Potion. Two actions, so deleting one is a plain delete.
const EDITOR_RULES := [
	{"conditions": [{"type": "hp_percent", "op": "<", "value": 50}, {"type": "ally_dead"}],
		"actions": [{"type": "attack", "target": "lowest_hp_enemy"}, {"type": "item", "id": "potion", "target": "self"}],
		"enabled": true},
]
const CONSOLE_RULES := [
	{"conditions": [{"type": "member_hp", "op": "<", "value": 30}, {"type": "member_dead"}],
		"actions": [{"type": "heal_party"}, {"type": "stop_grinding"}], "enabled": true},
]

var _saved_ab_persist := false
var _ab_profiles_entry: Dictionary = {}
var _ag: Dictionary = {}


func before_all() -> void:
	_ab_profiles_entry = ABProfiles.snapshot(get_tree().root.get_node_or_null("AutobattleSystem"))


func after_all() -> void:
	ABProfiles.restore(get_tree().root.get_node_or_null("AutobattleSystem"), _ab_profiles_entry)


func before_each() -> void:
	_ag = AutogrindState.snapshot()
	_saved_ab_persist = AutobattleSystem._test_disable_persistence
	AutobattleSystem._test_disable_persistence = true
	AutogrindSystem._test_disable_persistence = true


func after_each() -> void:
	AutobattleSystem._test_disable_persistence = _saved_ab_persist
	AutogrindState.restore(_ag)


func _editor() -> Node:
	var ed: Node = load(ED).new()
	add_child_autofree(ed)
	ed.setup("hero", "Hero")
	(ed.rules as Array).assign(EDITOR_RULES.duplicate(true))
	ed._refresh_grid()
	ed.cursor_row = 0
	return ed


func _console() -> Node:
	var ui: Node = load(UI).new()
	add_child_autofree(ui)
	ui.visible = true
	await wait_frames(2)   # _ready defers _build_ui, so a same-frame fixture has no grid
	assert_true(ui._grid_container != null and is_instance_valid(ui._grid_container), "PRECONDITION: the console built its grid")
	ui.rules = CONSOLE_RULES.duplicate(true)
	ui._refresh_grid()
	ui.cursor_row = 0
	return ui


## The console's own cell map, so its columns are found rather than assumed.
func _console_col(ui: Node, kind: String, nth: int = 0) -> int:
	var seen := 0
	for col in 12:
		ui.cursor_col = col
		ui._update_cursor()
		if ui._cell_type_at_cursor() == kind:
			if seen == nth:
				return col
			seen += 1
	return -1


func _north(screen: Node) -> void:
	var e := InputEventJoypadButton.new()
	e.button_index = JOY_BUTTON_Y
	e.pressed = true
	screen._input(e)


func _actions(rules: Array) -> int:
	var n := 0
	for r in rules:
		n += (r.get("actions", []) as Array).size()
	return n


func _conditions(rules: Array) -> Array:
	var out: Array = []
	for r in rules:
		for c in r.get("conditions", []):
			var bare: Dictionary = (c as Dictionary).duplicate()
			bare.erase("op")
			out.append(bare)
	return out


## The verb, read off the data: what one press did to the rules.
func _verb(before: Array, after: Array, undo_target = null) -> String:
	if after == before:
		return "nothing"
	if undo_target != null and after == undo_target:
		return "undo"
	if _actions(after) == _actions(before) - 1 and _conditions(after) == _conditions(before):
		return "delete"
	if _actions(after) == _actions(before) and _conditions(after) == _conditions(before):
		return "cycle"
	return "other: %s -> %s" % [before, after]


## Presses north on `col` of a fresh screen and returns the verb.
func _press_at(screen: Node, col: int) -> String:
	screen.cursor_col = col
	if screen.has_method("_update_cursor"):
		screen._update_cursor()
	var before: Array = (screen.rules as Array).duplicate(true)
	_north(screen)
	return _verb(before, (screen.rules as Array).duplicate(true))


## Deletes the first action, then presses north on the empty slot: the verb relative to the pre-delete grid.
func _undo_at(screen: Node, action_col: int, empty_col: int) -> String:
	var original: Array = (screen.rules as Array).duplicate(true)
	screen.cursor_col = action_col
	if screen.has_method("_update_cursor"):
		screen._update_cursor()
	_north(screen)
	var after_delete: Array = (screen.rules as Array).duplicate(true)
	if after_delete == original:
		return "PRECONDITION: the delete did not delete"
	screen.cursor_col = empty_col
	if screen.has_method("_update_cursor"):
		screen._update_cursor()
	_north(screen)
	return _verb(after_delete, (screen.rules as Array).duplicate(true), original)


func test_the_floor_names_every_member_this_file_drives() -> void:
	var ed := _editor()
	for m in ["setup", "_refresh_grid", "_update_cursor", "_input"]:
		assert_true(ed.has_method(m), "AutobattleGridEditor.%s must exist" % m)
	var ui := await _console()
	for m in ["_refresh_grid", "_update_cursor", "_input", "_cell_type_at_cursor"]:
		assert_true(ui.has_method(m), "AutogrindUI.%s must exist" % m)
	for n in ["rules", "cursor_row", "cursor_col"]:
		assert_true(n in ed and n in ui, "both screens must expose %s" % n)


## CONTROL: the console's cell map must contain every kind the arms below aim at, or they press nothing.
func test_control_the_console_fixture_has_every_cell_kind() -> void:
	var ui := await _console()
	for kind in ["condition", "action"]:
		assert_gt(_console_col(ui, kind), -1, "CONTROL: the console fixture must have a %s cell" % kind)
	assert_true(_console_col(ui, "empty_condition") > -1 or _console_col(ui, "empty_action") > -1,
		"CONTROL: the console fixture must have an empty slot")


func test_a_condition_with_an_operator_cycles_in_both() -> void:
	var e := _press_at(_editor(), 0)
	var ui := await _console()
	var c := _press_at(ui, _console_col(ui, "condition", 0))
	assert_eq(c, e, "both screens must do the same to a condition with an operator")
	assert_eq(e, "cycle", "and that is CYCLE: the north button tunes a condition, it never removes one")


func test_a_nullary_condition_does_nothing_in_both() -> void:
	var e := _press_at(_editor(), 1)
	var ui := await _console()
	var c := _press_at(ui, _console_col(ui, "condition", 1))
	assert_eq(c, e, "both screens must do the same to a condition with no operator")
	assert_eq(e, "nothing", "and that is NOTHING")


func test_an_action_is_deleted_in_both() -> void:
	var e := _press_at(_editor(), 3)
	var ui := await _console()
	var c := _press_at(ui, _console_col(ui, "action", 0))
	assert_eq(c, e, "both screens must do the same to an action")
	assert_eq(e, "delete", "and that is DELETE, exactly one")


func test_an_empty_slot_undoes_the_last_delete_in_both() -> void:
	var e := _undo_at(_editor(), 3, 2)
	var ui := await _console()
	var empty := _console_col(ui, "empty_condition")
	if empty == -1:
		empty = _console_col(ui, "empty_action")
	var c := _undo_at(ui, _console_col(ui, "action", 0), empty)
	assert_eq(c, e, "both screens must do the same on an empty slot after a delete")
	assert_eq(e, "undo", "and that is UNDO: the grid as it was before the delete")


func test_an_empty_slot_with_nothing_to_undo_does_nothing_in_both() -> void:
	var e := _press_at(_editor(), 2)
	var ui := await _console()
	var empty := _console_col(ui, "empty_condition")
	if empty == -1:
		empty = _console_col(ui, "empty_action")
	var c := _press_at(ui, empty)
	assert_eq(c, e, "both screens must do the same on an empty slot with no delete to undo")
	assert_eq(e, "nothing", "and that is NOTHING")


## ── .763 (cowir-main 21465): A on a condition opens the type list, and both end with the same Delete. ──

## The last row each screen offers on a condition, read off its own picker spec.
func _editor_delete_row(ed: Node) -> Dictionary:
	ed.cursor_col = 0
	ed._open_condition_editor()
	var options: Array = (ed._option_picker.get_meta("spec") as Dictionary).get("options", [])
	return options[-1] if not options.is_empty() else {}


func _console_delete_row(ui: Node) -> Dictionary:
	ui.cursor_col = _console_col(ui, "condition", 0)
	ui._update_cursor()
	var options: Array = (ui._condition_picker_spec() as Dictionary).get("options", [])
	return options[-1] if not options.is_empty() else {}


func test_both_condition_pickers_end_with_the_same_delete() -> void:
	var e := _editor_delete_row(_editor())
	var c := _console_delete_row(await _console())
	assert_eq(str(c.get("label", "")), str(e.get("label", "")), "both screens must name the Delete row the same")
	assert_eq(str(e.get("label", "")), "Delete condition", "and that name is the ruled one")


## Choosing Delete in each screen removes exactly one condition, and the north button on an empty slot brings it back.
func test_choosing_delete_removes_one_condition_and_undoes_in_both() -> void:
	var ed := _editor()
	ed.cursor_col = 0
	var e_before: Array = (ed.rules as Array).duplicate(true)
	ed._commit_option_choice("condition_type", ed.DELETE_CONDITION_ID, {})
	var ui := await _console()
	ui.cursor_col = _console_col(ui, "condition", 0)
	ui._update_cursor()
	var c_before: Array = (ui.rules as Array).duplicate(true)
	ui._commit_condition_choice(ui.DELETE_CONDITION_ID)
	for pair in [[ed, e_before, "editor"], [ui, c_before, "console"]]:
		var after: Array = pair[0].rules
		assert_eq(_conditions(after).size(), _conditions(pair[1]).size() - 1, "%s: exactly one condition must go" % pair[2])
		assert_eq(_actions(after), _actions(pair[1]), "%s: the actions must be untouched" % pair[2])
	var e_empty := 2 - 1   # one condition fewer: the editor's empty AND slot moved one column left
	ed.cursor_col = e_empty
	_north(ed)
	var c_empty := _console_col(ui, "empty_condition")
	if c_empty == -1:
		c_empty = _console_col(ui, "empty_action")
	ui.cursor_col = c_empty
	ui._update_cursor()
	_north(ui)
	assert_eq(ed.rules, e_before, "editor: the north button on an empty slot must restore the deleted condition")
	assert_eq(ui.rules, c_before, "console: the north button on an empty slot must restore the deleted condition")
