extends GutTest

## A grind preset (1/2/3, or a saved custom slot) replaced the player's whole rule grid in one press, and nothing brought it back.
## It now arms the same one-level undo a delete or a paste does, and the preset line says so. Sibling of controller's
## autobattle paste-undo (f5ec735c6) and the console's paste adoption (3212c5339).

const AutogrindState := preload("res://test/unit/helpers/autogrind_state.gd")

const MINE := [{"enabled": true, "conditions": [{"type": "battles_done", "op": ">=", "value": 7}], "actions": [{"type": "stop_grinding"}]}]

var _ag: Dictionary
var _ui: Node
var _scale_was := -1.0


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
	if _scale_was >= 0.0:
		GameState.text_size_scale = _scale_was
		_scale_was = -1.0
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


## The preset line grew the undo hint; at Text Size 2.0 the real line (longest description) must wrap inside the log, not run past it.
func test_the_preset_line_wraps_inside_the_log_at_text_size_two() -> void:
	_scale_was = float(GameState.text_size_scale)
	GameState.text_size_scale = 2.0
	var ui: Node = load("res://src/ui/autogrind/AutogrindUI.gd").new()
	add_child_autofree(ui)
	await get_tree().process_frame
	ui._load_rules()
	var longest := ""
	for pid in ui.GRIND_PRESETS.keys():
		if str(ui.GRIND_PRESETS[pid]["description"]).length() > str(ui.GRIND_PRESETS.get(longest, {}).get("description", "")).length():
			longest = str(pid)
	ui._apply_preset(longest)
	await get_tree().process_frame
	var console_log: RichTextLabel = ui._battle_log
	assert_not_null(console_log, "CONTROL: the console rebuilt its log")
	if console_log == null:
		return
	var line: String = str(ui._battle_log_lines.back()) if not ui._battle_log_lines.is_empty() else ""
	assert_string_contains(line, "to undo the rules", "CONTROL: the logged line is the preset line with its undo")
	var plain := RegEx.create_from_string("\\[/?[a-z]+[^\\]]*\\]").sub(line, "", true)
	var px: int = console_log.get_theme_font_size("normal_font_size")
	var one_line: float = console_log.get_theme_font("normal_font").get_string_size(plain, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	assert_gt(one_line, console_log.size.x, "CONTROL: at 2.0 the preset line is wider than the log, or this arm proves nothing")
	assert_ne(console_log.autowrap_mode, TextServer.AUTOWRAP_OFF, "the console's log does not wrap")
	var before: int = console_log.get_line_count()
	ui._log_message(line)
	await get_tree().process_frame
	assert_gt(console_log.get_line_count() - before, 1, "the preset line ran past the log's edge instead of wrapping")
