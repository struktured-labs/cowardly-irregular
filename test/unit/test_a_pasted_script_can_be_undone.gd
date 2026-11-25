extends GutTest

## Press map 2026-11-24 (main 27267): Shift+I / "Paste share code" / an import replaced the character's whole
## grid in one press, and Ctrl+Z could not bring it back — the undo kept only cell deletes, and refused any
## snapshot from a replaced grid. Both routes reload through _reload_applied_script, which now leaves an undo.

const ED := "res://src/ui/autobattle/AutobattleGridEditor.gd"
const ABProfiles := preload("res://test/unit/helpers/autobattle_profiles.gd")
const CID := "paste_undo_probe"

var _editor: Node = null
var _ab_profiles_entry: Dictionary = {}
var _was_persisting_off: bool = false

const MINE := [{"conditions": [{"type": "hp_percent", "op": "<", "value": 40}],
	"actions": [{"type": "defend", "target": "self"}], "enabled": true}]
const PASTED := [{"conditions": [{"type": "always"}],
	"actions": [{"type": "attack", "target": "lowest_hp_enemy"}], "enabled": true}]


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
	_editor.rules = MINE.duplicate(true)
	_editor.cursor_row = 0
	_editor.cursor_col = 0
	_editor._refresh_grid()


## What an import or a paste does once its decode succeeds: the system holds the new script, the grid reloads.
func _apply_pasted() -> void:
	_ab().set_character_script(CID, {"rules": PASTED.duplicate(true)})
	_editor._reload_applied_script()


func _ctrl_z() -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = KEY_Z
	e.ctrl_pressed = true
	e.pressed = true
	return e


func test_ctrl_z_brings_back_the_grid_a_paste_replaced() -> void:
	_apply_pasted()
	assert_eq(_editor.rules, PASTED, "CONTROL: the paste replaced the grid")
	_editor._input(_ctrl_z())
	assert_eq(_editor.rules, MINE, "Ctrl+Z after a paste restores the grid the player had")


## CONTROL: the undo is one level and is spent, so a second Ctrl+Z does not flip back to the paste.
func test_a_second_ctrl_z_does_nothing() -> void:
	_apply_pasted()
	_editor._input(_ctrl_z())
	_editor._input(_ctrl_z())
	assert_eq(_editor.rules, MINE, "a spent undo leaves the restored grid alone")


## Both player routes must reach the reload that records the undo; a new route that rebuilds rules itself would not.
func test_paste_and_import_both_reload_through_the_undoable_path() -> void:
	var src := FileAccess.get_file_as_string(ED)
	for fn in ["func _paste_share_code", "func _import_script_file"]:
		var at := src.find(fn)
		assert_gt(at, -1, "%s exists" % fn)
		var body := src.substr(at, src.find("\nfunc ", at + 10) - at)
		assert_true(body.contains("_reload_applied_script()"), "%s reloads through _reload_applied_script" % fn)
