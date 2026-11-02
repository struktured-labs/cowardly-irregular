extends GutTest

## The autobattle grid editor deleted with no way back. On a pad the same button CYCLES the operator on a
## condition cell and DELETES one cell to the right, so a player cycling operators who steps right loses an
## action group (Attack x3 goes in one press) — and B, which saves and closes, then keeps the loss.
## Mirrors cowir-main's 2026-11-02 console ruling (21420/21426): one level of undo, Ctrl+Z on a keyboard,
## and the delete button where nothing can be deleted on a pad.
##
## ⛔ THE SNAPSHOT IS BOUND TO THE LIVE `rules` ARRAY. Five sites replace that array (three character loads,
## a profile switch, an import), so an undo taken on one grid must refuse on another rather than paste one
## character's rules over the next. Arm 5 is that refusal.

const ED := "res://src/ui/autobattle/AutobattleGridEditor.gd"
const ABProfiles := preload("res://test/unit/helpers/autobattle_profiles.gd")

## col 0 = the condition · col 1 = the empty AND slot · col 2 = the Attack group · col 3 = the Potion group
const FIXTURE := [
	{"conditions": [{"type": "hp_percent", "op": "<", "value": 50}],
		"actions": [{"type": "attack", "target": "lowest_hp_enemy"}, {"type": "item", "id": "potion", "target": "self"}],
		"enabled": true},
	{"conditions": [{"type": "always"}], "actions": [{"type": "attack", "target": "lowest_hp_enemy"}], "enabled": true},
]
const ATTACK_COL := 2
const EMPTY_COL := 1

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


func after_each() -> void:
	AutobattleSystem._test_disable_persistence = _saved_persist


func _pad_delete() -> void:
	var e := InputEventJoypadButton.new()
	e.button_index = JOY_BUTTON_Y
	e.pressed = true
	_ed._input(e)


func _key_z(ctrl: bool) -> void:
	var e := InputEventKey.new()
	e.keycode = KEY_Z
	e.ctrl_pressed = ctrl
	e.pressed = true
	_ed._input(e)


func test_the_floor_names_every_member_this_file_drives() -> void:
	for m in ["_undo_delete", "_on_empty_slot", "_delete_cell_now", "_undo_route", "_refresh_grid", "_is_on_condition_cell"]:
		assert_true(_ed.has_method(m), "AutobattleGridEditor.%s must exist" % m)
	assert_true("_undo_snapshot" in _ed, "AutobattleGridEditor._undo_snapshot must exist")


## The fixture must put the cursor where each arm claims, or the arms below are about nothing.
func test_control_the_fixture_has_an_action_cell_and_an_empty_slot() -> void:
	_ed.cursor_col = ATTACK_COL
	assert_false(_ed._is_on_condition_cell(), "CONTROL: col %d must be off the condition" % ATTACK_COL)
	assert_false(_ed._on_empty_slot(), "CONTROL: col %d must hold the Attack group" % ATTACK_COL)
	_ed.cursor_col = EMPTY_COL
	assert_true(_ed._on_empty_slot(), "CONTROL: col %d must be the empty AND slot" % EMPTY_COL)


func test_the_pad_deletes_then_restores_the_identical_grid() -> void:
	var before: Array = (_ed.rules as Array).duplicate(true)
	_ed.cursor_col = ATTACK_COL
	_pad_delete()
	assert_ne(_ed.rules, before, "the delete button on an action group must delete it")
	assert_string_contains(str(_ed._flash_label.text), "Undo", "the delete must say how to undo it")
	_ed.cursor_col = EMPTY_COL
	_pad_delete()
	assert_eq(_ed.rules, before, "the delete button on an empty slot must restore the grid exactly")
	assert_true(_ed.visible, "and the editor stays open")


## Plain Z is ui_cancel (save and close), and it matches with Ctrl held, so Ctrl+Z must be read FIRST.
func test_ctrl_z_restores_and_does_not_close_the_editor() -> void:
	var closed := [false]
	_ed.closed.connect(func(): closed[0] = true)
	var before: Array = (_ed.rules as Array).duplicate(true)
	_ed.cursor_col = ATTACK_COL
	_pad_delete()
	_key_z(true)
	assert_eq(_ed.rules, before, "Ctrl+Z must restore the deleted group")
	assert_false(closed[0], "Ctrl+Z must not reach the Z = Back arm and close the editor")


## CONTROL for the arm above: without Ctrl the same key DOES close, so that arm's green is the ordering.
func test_control_plain_z_still_backs_out() -> void:
	var closed := [false]
	_ed.closed.connect(func(): closed[0] = true)
	_key_z(false)
	assert_true(closed[0], "CONTROL: plain Z must still back out, or the Ctrl+Z arm proves nothing")


## A load swaps the `rules` array; an undo from the previous grid must not land on this one.
func test_an_undo_from_another_grid_refuses() -> void:
	_ed.cursor_col = ATTACK_COL
	_pad_delete()
	_ed.rules = (_ed.rules as Array).duplicate(true)   # what every character/profile/import load does
	var loaded: Array = (_ed.rules as Array).duplicate(true)
	_key_z(true)
	assert_eq(_ed.rules, loaded, "an undo taken on another grid must refuse, not paste it here")
	assert_true((_ed._undo_snapshot as Dictionary).is_empty(), "and the stale snapshot is dropped")


func test_with_nothing_to_undo_the_empty_slot_changes_nothing() -> void:
	var before: Array = (_ed.rules as Array).duplicate(true)
	_ed.cursor_col = EMPTY_COL
	_pad_delete()
	assert_eq(_ed.rules, before, "the delete button on an empty slot with nothing to undo must change nothing")
