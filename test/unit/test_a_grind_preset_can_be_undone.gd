extends GutTest

## A grind preset (1/2/3, or a saved custom slot) replaced the player's whole rule grid in one press, and nothing brought it back.
## It now arms the same one-level undo a delete or a paste does, and the preset line says so. Sibling of controller's
## autobattle paste-undo (f5ec735c6) and the console's paste adoption (3212c5339).

const AutogrindState := preload("res://test/unit/helpers/autogrind_state.gd")

const MINE := [{"enabled": true, "conditions": [{"type": "battles_done", "op": ">=", "value": 7}], "actions": [{"type": "stop_grinding"}]}]

var _ag: Dictionary
var _ui: Node


func before_each() -> void:
	_ag = AutogrindState.snapshot()
	AutogrindSystem._test_disable_persistence = true
	AutobattleSystem._test_disable_persistence = true
	AutogrindSystem.set_autogrind_rules(MINE.duplicate(true))
	_ui = load("res://src/ui/autogrind/AutogrindUI.gd").new()
	add_child_autofree(_ui)
	await get_tree().process_frame
	_ui._load_rules()


func after_each() -> void:
	AutogrindState.restore(_ag)


func _first_type(rules: Array) -> String:
	return str(((rules[0] as Dictionary).get("conditions", [{}]) as Array)[0].get("type", "")) if not rules.is_empty() else ""


func _a_preset_id() -> String:
	var ids: Array = _ui.GRIND_PRESETS.keys()
	return str(ids[0]) if not ids.is_empty() else ""


func test_a_built_in_preset_can_be_undone() -> void:
	var pid := _a_preset_id()
	assert_ne(pid, "", "CONTROL: the console ships at least one preset")
	assert_eq(_first_type(_ui.rules), "battles_done", "CONTROL: the console starts on the player's own rules")
	_ui._apply_preset(pid)
	assert_ne(_ui.rules, MINE, "CONTROL: the preset replaced the grid")
	assert_true(_ui._undo_is_live(), "a preset left no way back to the rules it replaced")
	_ui._undo_delete()
	assert_eq(_first_type(_ui.rules), "battles_done", "undo brings back the player's own rules")
	_ui._persist_rules_on_close()
	assert_eq(_first_type(AutogrindSystem.get_autogrind_rules()), "battles_done", "and closing keeps them")


func test_a_saved_custom_preset_can_be_undone() -> void:
	var saved: Array = _ui._custom_presets.duplicate(true)
	_ui._custom_presets = [{"name": "Custom 1", "rules": [{"enabled": true, "conditions": [{"type": "always"}], "actions": [{"type": "stop_grinding"}]}]}]
	_ui._apply_custom_preset(0)
	assert_eq(_first_type(_ui.rules), "always", "CONTROL: the custom preset replaced the grid")
	assert_true(_ui._undo_is_live(), "a custom preset left no way back")
	_ui._undo_delete()
	assert_eq(_first_type(_ui.rules), "battles_done", "undo brings back the player's own rules")
	_ui._custom_presets = saved


## A second press of the same preset changes nothing, so it must not overwrite the snapshot with the preset itself.
func test_pressing_the_preset_again_keeps_the_way_back() -> void:
	var pid := _a_preset_id()
	_ui._apply_preset(pid)
	_ui._apply_preset(pid)
	assert_true(_ui._undo_is_live(), "CONTROL: an undo is still offered")
	_ui._undo_delete()
	assert_eq(_first_type(_ui.rules), "battles_done", "the second press replaced the way back with the preset")


func test_the_preset_line_names_the_undo() -> void:
	_ui._battle_log_lines.clear()
	_ui._apply_preset(_a_preset_id())
	var line := str(_ui._battle_log_lines.back()) if not _ui._battle_log_lines.is_empty() else ""
	assert_string_contains(line, "Ctrl+Z", "the preset line does not say how to undo it")
