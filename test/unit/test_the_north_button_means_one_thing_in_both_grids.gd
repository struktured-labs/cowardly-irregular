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
	var ui := _console()
	for m in ["_refresh_grid", "_update_cursor", "_input", "_cell_type_at_cursor"]:
		assert_true(ui.has_method(m), "AutogrindUI.%s must exist" % m)
	for n in ["rules", "cursor_row", "cursor_col"]:
		assert_true(n in ed and n in ui, "both screens must expose %s" % n)


## CONTROL: the console's cell map must contain every kind the arms below aim at, or they press nothing.
func test_control_the_console_fixture_has_every_cell_kind() -> void:
	var ui := _console()
	for kind in ["condition", "action"]:
		assert_gt(_console_col(ui, kind), -1, "CONTROL: the console fixture must have a %s cell" % kind)
	assert_true(_console_col(ui, "empty_condition") > -1 or _console_col(ui, "empty_action") > -1,
		"CONTROL: the console fixture must have an empty slot")


func test_a_condition_with_an_operator_cycles_in_both() -> void:
	var e := _press_at(_editor(), 0)
	var ui := _console()
	var c := _press_at(ui, _console_col(ui, "condition", 0))
	assert_eq(c, e, "both screens must do the same to a condition with an operator")
	assert_eq(e, "cycle", "and that is CYCLE: the north button tunes a condition, it never removes one")


func test_a_nullary_condition_does_nothing_in_both() -> void:
	var e := _press_at(_editor(), 1)
	var ui := _console()
	var c := _press_at(ui, _console_col(ui, "condition", 1))
	assert_eq(c, e, "both screens must do the same to a condition with no operator")
	assert_eq(e, "nothing", "and that is NOTHING")


func test_an_action_is_deleted_in_both() -> void:
	var e := _press_at(_editor(), 3)
	var ui := _console()
	var c := _press_at(ui, _console_col(ui, "action", 0))
	assert_eq(c, e, "both screens must do the same to an action")
	assert_eq(e, "delete", "and that is DELETE, exactly one")


func test_an_empty_slot_undoes_the_last_delete_in_both() -> void:
	var e := _undo_at(_editor(), 3, 2)
	var ui := _console()
	var empty := _console_col(ui, "empty_condition")
	if empty == -1:
		empty = _console_col(ui, "empty_action")
	var c := _undo_at(ui, _console_col(ui, "action", 0), empty)
	assert_eq(c, e, "both screens must do the same on an empty slot after a delete")
	assert_eq(e, "undo", "and that is UNDO: the grid as it was before the delete")


func test_an_empty_slot_with_nothing_to_undo_does_nothing_in_both() -> void:
	var e := _press_at(_editor(), 2)
	var ui := _console()
	var empty := _console_col(ui, "empty_condition")
	if empty == -1:
		empty = _console_col(ui, "empty_action")
	var c := _press_at(ui, empty)
	assert_eq(c, e, "both screens must do the same on an empty slot with no delete to undo")
	assert_eq(e, "nothing", "and that is NOTHING")
