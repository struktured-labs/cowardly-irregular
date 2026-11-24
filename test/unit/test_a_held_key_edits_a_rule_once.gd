extends GutTest

## Press map 2026-11-24 (main 27267, struktured: "I always seem to press some button by accident"):
## Tab (rule on/off), Shift+Tab (next profile) and C (cycle operator) had no echo guard in the grid
## editor, so HOLDING one repeated it every key repeat and left the rule wherever the hold ended.

const ED := "res://src/ui/autobattle/AutobattleGridEditor.gd"
const ABProfiles := preload("res://test/unit/helpers/autobattle_profiles.gd")
const CID := "heldkey_probe"

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
	_editor.rules = [{
		"conditions": [{"type": "hp_percent", "op": "<", "value": 50}],
		"actions": [{"type": "attack", "target": "lowest_hp_enemy"}],
		"enabled": true,
	}]
	_editor.cursor_row = 0
	_editor.cursor_col = 0
	_editor._portrait_focused = false
	_editor._refresh_grid()


func _key(code: Key, echo: bool, shift: bool = false) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code
	e.pressed = true
	e.echo = echo
	e.shift_pressed = shift
	return e


## A hold: the press, then the key repeats the OS sends while it is down.
func _hold(code: Key, repeats: int, shift: bool = false) -> void:
	_editor._input(_key(code, false, shift))
	for i in repeats:
		_editor._input(_key(code, true, shift))


func test_a_held_tab_turns_the_rule_off_once() -> void:
	_hold(KEY_TAB, 5)
	assert_false(bool(_editor.rules[0].get("enabled", true)), "the press turns the rule off, and 5 repeats must not turn it back on")


## CONTROL: two separate presses are two toggles, so the guard has not eaten the key itself.
func test_two_tab_presses_are_two_toggles() -> void:
	_editor._input(_key(KEY_TAB, false))
	assert_false(bool(_editor.rules[0].get("enabled", true)), "one press turns the rule off")
	_editor._input(_key(KEY_TAB, false))
	assert_true(bool(_editor.rules[0].get("enabled", false)), "a second press turns it back on")


func test_a_held_c_cycles_the_operator_once() -> void:
	var before := str(_editor.rules[0]["conditions"][0].get("op", ""))
	_editor._input(_key(KEY_C, false))
	var once := str(_editor.rules[0]["conditions"][0].get("op", ""))
	assert_ne(once, before, "CONTROL: one press of C cycles the operator")
	for i in 5:
		_editor._input(_key(KEY_C, true))
	assert_eq(str(_editor.rules[0]["conditions"][0].get("op", "")), once, "key repeats of a held C must not cycle it again")


func test_a_held_shift_tab_moves_one_profile() -> void:
	var count: int = _ab().get_character_profiles(CID).size()
	assert_gt(count, 2, "CONTROL: a fresh character has 3+ profiles, so extra steps would show")
	var start: int = _ab().get_active_profile_index(CID)
	_hold(KEY_TAB, 4, true)
	assert_eq(_ab().get_active_profile_index(CID), (start + 1) % count, "a held Shift+Tab moves exactly one profile")
