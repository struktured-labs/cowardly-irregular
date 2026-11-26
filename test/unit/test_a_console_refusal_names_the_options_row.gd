extends GutTest

## The autogrind console refused two verbs by naming only a keyboard key: "Export first with [E]" and "Delete one first
## ([D] key)". A pad has neither key; its route to both verbs is the options ring. Each refusal now names the key AND the
## ring row, read from the ring itself, so a renamed row cannot leave the message pointing at a row that is not there.
## Arms: CONTROL (the ring offers both rows) · the row name drops the "(D)" suffix and is a ring label's start · a full
## preset list's refusal names the key and the row · an import with no export files names the key and the export row.

const AutogrindState := preload("res://test/unit/helpers/autogrind_state.gd")
const UI := "res://src/ui/autogrind/AutogrindUI.gd"

var _ag: Dictionary
var _vp: SubViewport
var _ui: Control
var _saved_presets: Array = []
var _export_dir_was: String = ""


func before_each() -> void:
	_ag = AutogrindState.snapshot()
	AutogrindSystem._test_disable_persistence = true
	AutobattleSystem._test_disable_persistence = true
	_vp = SubViewport.new()
	_vp.size = Vector2i(1280, 720)
	add_child_autofree(_vp)
	_ui = load(UI).new()
	_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vp.add_child(_ui)
	await get_tree().process_frame
	_saved_presets = _ui._custom_presets.duplicate(true)
	_export_dir_was = ScriptShareManager.EXPORT_DIR
	_ui._is_grinding = false


func after_each() -> void:
	ScriptShareManager.EXPORT_DIR = _export_dir_was
	if _ui and is_instance_valid(_ui):
		_ui._custom_presets = _saved_presets
		_ui.queue_free()
	AutogrindState.restore(_ag)


func _ring_labels() -> Dictionary:
	var out := {}
	for opt in (_ui._options_ring_spec().get("options", []) as Array):
		out[str(opt.get("id", ""))] = str(opt.get("label", ""))
	return out


func test_the_ring_offers_both_rows() -> void:
	var labels := _ring_labels()
	assert_has(labels, "export", "CONTROL: the options ring offers Export, the pad's route to it")
	assert_has(labels, "delete_preset", "CONTROL: the options ring offers Delete Last Preset")


func test_a_row_name_is_the_label_without_its_key() -> void:
	var labels := _ring_labels()
	for id in ["export", "delete_preset"]:
		var row: String = _ui._options_row_name(id)
		assert_ne(row, "", "%s has a row name" % id)
		assert_false(row.contains("("), "%s's row name '%s' drops the key suffix" % [id, row])
		assert_true(str(labels.get(id, "")).begins_with(row), "'%s' is how the ring's %s row reads: %s" % [row, id, labels.get(id, "")])
	assert_eq(_ui._options_row_name("zz_not_a_row"), "", "CONTROL: an id the ring does not offer names no row")


func test_a_full_preset_list_names_the_key_and_the_row() -> void:
	var presets: Array = []
	for i in range(_ui.MAX_CUSTOM_PRESETS):
		presets.append({"name": "Custom %d" % (i + 1), "rules": []})
	_ui._custom_presets = presets
	_ui.rules = [{"enabled": true, "conditions": [{"type": "battles_done", "op": ">=", "value": 5}], "actions": [{"type": "stop_grinding"}]}]
	var before: int = _ui._battle_log_lines.size()
	_ui._save_current_as_preset()
	assert_eq(_ui._custom_presets.size(), _ui.MAX_CUSTOM_PRESETS, "CONTROL: a full list refused the save")
	assert_gt(_ui._battle_log_lines.size(), before, "CONTROL: the refusal was logged")
	var line: String = str(_ui._battle_log_lines[-1])
	assert_true(line.contains("[D]"), "the refusal still names the key: %s" % line)
	assert_true(line.contains("OPTIONS ▸ %s" % _ui._options_row_name("delete_preset")), "and the ring row a pad can take: %s" % line)


func test_an_import_with_no_exports_names_the_key_and_the_row() -> void:
	## A directory no run creates, so the refusal is reached whatever an earlier file exported.
	ScriptShareManager.EXPORT_DIR = "user://zz_no_exports_%d/" % Time.get_ticks_usec()
	assert_eq(ScriptShareManager.list_exports().size(), 0, "CONTROL: there is nothing to import, so this reads the refusal")
	var before: int = _ui._battle_log_lines.size()
	_ui._import_scripts()
	assert_gt(_ui._battle_log_lines.size(), before, "CONTROL: the import logged a line")
	var line: String = str(_ui._battle_log_lines[-1])
	assert_true(line.contains("No export files found"), "CONTROL: that line is the empty-list refusal: %s" % line)
	assert_true(line.contains("[E]"), "the refusal still names the key: %s" % line)
	assert_true(line.contains("OPTIONS ▸ %s" % _ui._options_row_name("export")), "and the export row a pad can take: %s" % line)
