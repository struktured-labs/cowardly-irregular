extends GutTest

## Press map 2026-11-24 (main 27267): with the grid editor's portrait focused, the cursor frames the
## portrait and no cell, yet Delete, the north face, L, Tab, C, -/=, T and the right stick fell through
## and edited the cell under the hidden grid cursor — a rule could be deleted with nothing on screen saying which.

const ED := "res://src/ui/autobattle/AutobattleGridEditor.gd"
const ABProfiles := preload("res://test/unit/helpers/autobattle_profiles.gd")
const CID := "portrait_probe"

var _editor: Node = null
var _ab_profiles_entry: Dictionary = {}
var _was_persisting_off: bool = false


func _ab() -> Node:
	return get_tree().root.get_node_or_null("AutobattleSystem")


func before_all() -> void:
	_ab_profiles_entry = ABProfiles.snapshot(_ab())
	_was_persisting_off = _ab()._test_disable_persistence
	_ab()._test_disable_persistence = true


func after_all() -> void:
	_ab()._test_disable_persistence = _was_persisting_off
	ABProfiles.restore(_ab(), _ab_profiles_entry)


func before_each() -> void:
	_editor = load(ED).new()
	add_child_autofree(_editor)
	_editor.setup(CID, "Probe")
	await get_tree().process_frame
	_editor.rules = [
		{"conditions": [{"type": "hp_percent", "op": "<", "value": 50}, {"type": "hp_percent", "op": ">", "value": 10}],
			"actions": [{"type": "attack", "target": "lowest_hp_enemy"}, {"type": "attack", "target": "lowest_hp_enemy"}], "enabled": true},
		{"conditions": [{"type": "always"}], "actions": [{"type": "defend", "target": "self"}], "enabled": true},
	]
	_editor.cursor_row = 0
	_editor.cursor_col = 0
	_editor._portrait_focused = false
	_editor._refresh_grid()


func _key(code: Key, shift: bool = false) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code
	e.pressed = true
	e.shift_pressed = shift
	return e


func _north() -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.button_index = JOY_BUTTON_Y
	e.pressed = true
	return e


func _action(name: String) -> InputEventAction:
	var e := InputEventAction.new()
	e.action = name
	e.pressed = true
	return e


func _stick(v: float) -> InputEventJoypadMotion:
	var e := InputEventJoypadMotion.new()
	e.axis = JOY_AXIS_RIGHT_X
	e.axis_value = v
	return e


## Every cell-editing press, from the portrait, on a condition cell (the T picker is judged apart: it opens, it does not edit).
func test_no_cell_edit_reaches_the_hidden_cell_from_the_portrait() -> void:
	var before: Array = _editor.rules.duplicate(true)
	var presses: Array = [_north(), _key(KEY_DELETE), _key(KEY_BACKSPACE), _action("battle_defer"), _key(KEY_TAB),
		_key(KEY_C), _key(KEY_EQUAL), _key(KEY_MINUS), _stick(1.0)]
	for p in presses:
		_editor._portrait_focused = true
		_editor._input(p)
	assert_eq(_editor.rules, before, "nine cell-editing presses from the portrait must leave every rule as it was")
	assert_true(_editor._portrait_focused, "and the portrait keeps focus")


## Column 3 is the action group: 2 conditions + 1 empty AND slot (MAX_CONDITIONS 3) come first.
func test_t_opens_no_target_picker_from_the_portrait() -> void:
	_editor.cursor_col = 3
	_editor._portrait_focused = true
	_editor._input(_key(KEY_T))
	assert_null(_editor._option_picker, "T from the portrait opens nothing for a cell the player cannot see")


func test_in_the_grid_t_opens_the_target_picker() -> void:
	_editor.cursor_col = 3
	_editor._input(_key(KEY_T))
	assert_not_null(_editor._option_picker, "CONTROL: T on that action cell in the grid opens its target picker")


## CONTROLS: the same presses in the GRID still edit, so the refusal is scoped to the portrait.
func test_in_the_grid_the_north_face_still_edits() -> void:
	_editor._input(_north())
	assert_ne(str(_editor.rules[0]["conditions"][0].get("op", "")), "<", "north on a condition cell cycles its operator")


func test_in_the_grid_delete_still_deletes() -> void:
	_editor._input(_key(KEY_DELETE))
	assert_eq((_editor.rules[0]["conditions"] as Array).size(), 1, "Delete on a condition cell removes it")


## CONTROL: a character-level verb is not a cell edit and still works from the portrait.
func test_from_the_portrait_shift_tab_still_changes_profile() -> void:
	var count: int = _ab().get_character_profiles(CID).size()
	assert_gt(count, 1, "precondition: a fresh character has more than one profile")
	var start: int = _ab().get_active_profile_index(CID)
	_editor._portrait_focused = true
	_editor._input(_key(KEY_TAB, true))
	assert_eq(_ab().get_active_profile_index(CID), (start + 1) % count, "Shift+Tab from the portrait moves one profile")
