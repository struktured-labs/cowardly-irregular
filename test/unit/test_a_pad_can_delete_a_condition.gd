extends GutTest

## cowir-main 2026-11-02 (21465): the north button cycles a condition's operator and never removes it, so until
## this a PAD player could not delete a condition in the autobattle grid at all; only keyboard Delete could.
## A on a condition opens the Condition Type picker, and that picker now ends with "Delete condition". The
## choice runs the ordinary delete, so it is undoable like every other delete and a rule's ONLY condition
## still goes through the rule menu rather than vanishing.

const ED := "res://src/ui/autobattle/AutobattleGridEditor.gd"
const ABProfiles := preload("res://test/unit/helpers/autobattle_profiles.gd")

## col 0 = hp_percent · col 1 = mp_percent: two conditions, so removing one is a plain delete.
const FIXTURE := [
	{"conditions": [{"type": "hp_percent", "op": "<", "value": 50}, {"type": "mp_percent", "op": "<", "value": 20}],
		"actions": [{"type": "attack", "target": "lowest_hp_enemy"}], "enabled": true},
]

var _ed: Node = null
var _saved_persist := false
var _ab_profiles_entry: Dictionary = {}


func before_all() -> void:
	_ab_profiles_entry = ABProfiles.snapshot(get_tree().root.get_node_or_null("AutobattleSystem"))


func after_all() -> void:
	ABProfiles.restore(get_tree().root.get_node_or_null("AutobattleSystem"), _ab_profiles_entry)


func before_each() -> void:
	_saved_persist = AutobattleSystem._test_disable_persistence
	AutobattleSystem._test_disable_persistence = true
	_ed = load(ED).new()
	add_child_autofree(_ed)
	_ed.setup("hero", "Hero")
	await get_tree().process_frame
	(_ed.rules as Array).assign(FIXTURE.duplicate(true))
	_ed._refresh_grid()
	_ed.cursor_row = 0
	_ed.cursor_col = 1


func after_each() -> void:
	AutobattleSystem._test_disable_persistence = _saved_persist


func _offered() -> Array:
	_ed._open_condition_editor()
	assert_true(_ed._option_picker != null and is_instance_valid(_ed._option_picker),
		"PRECONDITION: A on a condition must open the Condition Type picker")
	return (_ed._option_picker.get_meta("spec") as Dictionary).get("options", [])


func test_the_floor_names_every_member_this_file_drives() -> void:
	for m in ["_open_condition_editor", "_commit_option_choice", "_undo_delete", "_refresh_grid"]:
		assert_true(_ed.has_method(m), "AutobattleGridEditor.%s must exist" % m)
	assert_true("_option_picker" in _ed, "AutobattleGridEditor._option_picker must exist")
	assert_true(_ed.get_script().get_script_constant_map().has("DELETE_CONDITION_ID"), "the picker's Delete id must exist")


func test_the_condition_picker_offers_delete_last_and_keeps_the_type_selected() -> void:
	var options := _offered()
	assert_gt(options.size(), 1, "CONTROL: the picker must list condition types")
	assert_eq(str(options[-1].get("id", "")), _ed.DELETE_CONDITION_ID, "Delete must be the LAST row")
	assert_string_contains(str(options[-1].get("label", "")), "Delete", "and say what it does")
	var spec: Dictionary = _ed._option_picker.get_meta("spec")
	assert_eq(str(options[int(spec.get("selected", -1))].get("id", "")), "mp_percent",
		"the current type must still be the selected row, so opening the picker never moves the player onto Delete")
	assert_false(AutobattleSystem.CONDITION_TYPES.has(_ed.DELETE_CONDITION_ID),
		"the Delete id must not be a real condition type")


func test_choosing_delete_removes_exactly_that_condition_and_can_be_undone() -> void:
	var before: Array = (_ed.rules as Array).duplicate(true)
	_ed._commit_option_choice("condition_type", _ed.DELETE_CONDITION_ID, {})
	var conds: Array = _ed.rules[0].get("conditions", [])
	assert_eq(conds.size(), 1, "exactly one condition must go")
	assert_eq(str(conds[0].get("type", "")), "hp_percent", "and it must be the one under the cursor")
	assert_eq(_ed.rules[0].get("actions", []), before[0].get("actions", []), "the actions must be untouched")
	assert_true(_ed._undo_delete(), "the delete must be undoable like any other")
	assert_eq(_ed.rules, before, "and the undo must restore the grid exactly")


## CONTROL: choosing a real type still changes the type, so the Delete branch did not swallow the picker.
func test_choosing_a_type_still_changes_the_type() -> void:
	_ed._commit_option_choice("condition_type", "hp_percent", {})
	var conds: Array = _ed.rules[0].get("conditions", [])
	assert_eq(conds.size(), 2, "choosing a type must not delete anything")
	assert_eq(str(conds[1].get("type", "")), "hp_percent", "it must change the type under the cursor")
