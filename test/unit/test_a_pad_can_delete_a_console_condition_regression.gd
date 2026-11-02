extends GutTest

## cowir-main 21465 (.763): once the north button stepped a condition's operator, a pad had no way to delete a condition in
## the autogrind console. A on a condition now opens its type list with "Delete condition" last, the label the autobattle
## editor uses (cowir-controller 21511); choosing it is the ordinary delete, so it is undoable.

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


func _picker_ids(spec: Dictionary) -> Array:
	return (spec["options"] as Array).map(func(o): return str(o["id"]))


func test_a_on_a_condition_opens_the_type_list_with_delete_last() -> void:
	var ui := _console()
	assert_eq(_at(ui, 0, 0), "condition", "CONTROL: the cursor is on hp < 30")
	ui._edit_current_cell()
	assert_true(ui._options_ring != null and is_instance_valid(ui._options_ring), "A on a condition opens a picker")
	var spec: Dictionary = ui._condition_picker_spec()
	var ids := _picker_ids(spec)
	assert_eq(ids.back(), ui.DELETE_CONDITION_ID, "Delete rides last")
	assert_string_contains(str((spec["options"] as Array).back()["label"]), "Delete condition", "with the editor's label")
	assert_eq(ids[int(spec["selected"])], "member_hp", "and the current type is the selected row, so opening never lands on Delete")
	for t in ui.CONDITION_TYPES:
		assert_ne(str(t["id"]), ui.DELETE_CONDITION_ID, "the delete id is not a real condition type")


func test_choosing_delete_removes_exactly_that_condition_and_undo_restores_it() -> void:
	var ui := _console()
	var before: Array = ui.rules.duplicate(true)
	_at(ui, 0, 1)
	ui._commit_condition_choice(ui.DELETE_CONDITION_ID)
	assert_eq(ui.rules[0]["conditions"], [{"type": "member_hp", "op": "<", "value": 30}], "exactly Any Dead is gone")
	assert_eq(ui.rules[0]["actions"], before[0]["actions"], "and no action moved")
	_at(ui, ui.rules.size(), 0)
	ui._press_delete_button()
	assert_eq(ui.rules, before, "the north button off a cell undoes it exactly")


func test_a_rules_only_condition_says_the_rule_goes_with_it() -> void:
	var ui := _console()
	_at(ui, 1, 0)
	assert_string_contains(str((ui._condition_picker_spec()["options"] as Array).back()["label"]), "and its rule",
		"deleting a rule's only condition deletes the rule, which is what cost him his rules, so the label says so")


func test_choosing_a_type_still_changes_it() -> void:
	var ui := _console()
	_at(ui, 0, 0)
	ui._commit_condition_choice("party_mp_avg")
	var cond: Dictionary = ui.rules[0]["conditions"][0]
	assert_eq(str(cond["type"]), "party_mp_avg", "CONTROL: picking a type sets it")
	assert_eq(cond.get("op"), AutogrindSystem.condition_defaults_for("party_mp_avg").get("op"), "with the grammar's own default")
	assert_eq((ui.rules[0]["conditions"] as Array).size(), 2, "and deletes nothing")
