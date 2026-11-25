extends GutTest

## The console saved up to six custom presets and listed them as [4]..[9], but only keys 4-6 and three ring rows
## ("Custom Slot 1-3") loaded anything: a 4th-6th preset was stored, shown with a key that did nothing, and a pad
## could never reach it. Every saved slot now loads by its listed key and by a ring row.

const AutogrindState := preload("res://test/unit/helpers/autogrind_state.gd")

var _ag: Dictionary
var _vp: SubViewport
var _ui: Control
var _saved_presets: Array = []


func before_each() -> void:
	_ag = AutogrindState.snapshot()
	AutogrindSystem._test_disable_persistence = true
	AutobattleSystem._test_disable_persistence = true
	_vp = SubViewport.new()
	_vp.size = Vector2i(1280, 720)
	add_child_autofree(_vp)
	_ui = load("res://src/ui/autogrind/AutogrindUI.gd").new()
	_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vp.add_child(_ui)
	await get_tree().process_frame
	_saved_presets = _ui._custom_presets.duplicate(true)
	_ui._is_grinding = false


func after_each() -> void:
	if _ui and is_instance_valid(_ui):
		_ui._custom_presets = _saved_presets
		_ui.queue_free()
	AutogrindState.restore(_ag)


func _seed(n: int) -> void:
	var presets: Array = []
	for i in range(n):
		presets.append({"name": "Custom %d" % (i + 1), "rules": [{"enabled": true, "conditions": [{"type": "battles_done", "op": ">=", "value": 100 + i}], "actions": [{"type": "stop_grinding"}]}]})
	_ui._custom_presets = presets


func _loaded_value() -> int:
	if _ui.rules.is_empty():
		return -1
	return int(((_ui.rules[0] as Dictionary).get("conditions", [{}]) as Array)[0].get("value", -1))


func _key(code: int) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code
	e.pressed = true
	return e


func _ring_ids() -> Array:
	var out: Array = []
	for opt in (_ui._options_ring_spec().get("options", []) as Array):
		out.append(str(opt.get("id", "")))
	return out


func test_every_saved_preset_loads_by_the_key_it_is_listed_under() -> void:
	_seed(_ui.MAX_CUSTOM_PRESETS)
	assert_eq(_ui._custom_presets.size(), 6, "CONTROL: six presets saved, the console's own cap")
	for i in range(_ui.MAX_CUSTOM_PRESETS):
		_ui.rules = []
		_ui._input(_key(KEY_4 + i))
		assert_eq(_loaded_value(), 100 + i, "key %d (listed as [%d]) did not load saved preset %d" % [i + 4, i + 4, i + 1])


func test_every_saved_preset_has_a_ring_row_that_loads_it() -> void:
	_seed(_ui.MAX_CUSTOM_PRESETS)
	var ids := _ring_ids()
	for i in range(_ui.MAX_CUSTOM_PRESETS):
		var id := "custom_%d" % (i + 1)
		assert_has(ids, id, "the options ring has no row for saved preset %d, so a pad cannot load it" % (i + 1))
		_ui.rules = []
		_ui._commit_autogrind_option(id)
		assert_eq(_loaded_value(), 100 + i, "ring row %s did not load saved preset %d" % [id, i + 1])


func test_a_row_names_the_same_key_the_panel_lists() -> void:
	_seed(_ui.MAX_CUSTOM_PRESETS)
	for opt in (_ui._options_ring_spec().get("options", []) as Array):
		var id := str(opt.get("id", ""))
		if id.begins_with("custom_"):
			assert_string_ends_with(str(opt["label"]), "(%d)" % (int(id.substr(7)) + 3), "%s names a key that is not its slot's" % id)


## With few presets the ring is as before: slots 1-3, no rows for slots nobody saved.
func test_few_presets_keep_the_three_slot_ring() -> void:
	_seed(2)
	var customs: Array = _ring_ids().filter(func(x): return str(x).begins_with("custom_"))
	assert_eq(customs, ["custom_1", "custom_2", "custom_3"], "the ring's custom rows changed for a two-preset save")
