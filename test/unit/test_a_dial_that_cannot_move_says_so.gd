extends GutTest

## -/= or the stick on a condition with no number (Always, Ally Dead…), or on one already at its limit, changed nothing and still played menu_move in both rule editors.
## Each such press now plays menu_error and flashes why; a real change still plays menu_move. Read through cooldown stamps, whose own CONTROL is the first arm.

const AB_EDITOR := "res://src/ui/autobattle/AutobattleGridEditor.gd"
const AG_EDITOR := "res://src/ui/autogrind/AutogrindGridEditor.gd"
const AutogrindState := preload("res://test/unit/helpers/autogrind_state.gd")
const SfxState := preload("res://test/unit/helpers/sfx_state.gd")

## [editor, a dialable condition at its midpoint, the same condition at its top, a nullary one]
const CASES := [
	[AB_EDITOR, {"type": "hp_percent", "op": "<", "value": 50}, {"type": "hp_percent", "op": "<", "value": 100}, {"type": "always"}],
	[AG_EDITOR, {"type": "party_hp_avg", "op": "<", "value": 50}, {"type": "party_hp_avg", "op": "<", "value": 100}, {"type": "member_dead", "member": ""}],
]

var _abs
var _profiles_backup: Dictionary = {}
var _ag: Dictionary


func before_each() -> void:
	_ag = AutogrindState.snapshot()
	AutogrindSystem._test_disable_persistence = true
	AutobattleSystem._test_disable_persistence = true
	_abs = get_tree().root.get_node_or_null("AutobattleSystem")
	_profiles_backup = (_abs.character_profiles as Dictionary).duplicate(true)
	SoundManager._sfx_cooldowns.clear()


func after_each() -> void:
	var live: Dictionary = _abs.character_profiles
	live.clear()
	for k in _profiles_backup:
		live[k] = _profiles_backup[k]
	AutogrindState.restore(_ag)
	SoundManager._sfx_cooldowns.clear()
	SoundManager._sfx_suppressed_by_cooldown = false
	SfxState.release_streams()


func _stamped(key: String) -> bool:
	return SoundManager._sfx_cooldowns.has(key)


func _editor(path: String, cond: Dictionary) -> Node:
	var ed: Node = load(path).new()
	ed.size = Vector2(1280, 720)
	add_child_autofree(ed)
	await get_tree().process_frame
	var rules: Array = ed.get("rules") as Array
	rules.clear()
	rules.append({"conditions": [cond.duplicate(true)], "actions": [{"type": "attack"}], "enabled": true})
	ed.set("cursor_row", 0)
	ed.set("cursor_col", 0)
	ed._refresh_grid()
	assert_true(ed._is_on_condition_cell(), "CONTROL: the cursor is on the condition")
	SoundManager._sfx_cooldowns.clear()
	return ed


func _cond(ed: Node) -> Dictionary:
	return (((ed.get("rules") as Array)[0] as Dictionary)["conditions"] as Array)[0] as Dictionary


func _shown(ed: Node) -> String:
	var label: Label = ed.get("_flash_label") if ed.get("_flash_label") != null else ed.get("_status_label")
	return str(label.text) if label != null else ""


func _name(path: String) -> String:
	return path.get_file().get_basename()


func test_the_cue_oracle_can_see_a_cue() -> void:
	assert_false(_stamped("menu_error"), "FLOOR: the stamp table starts clean")
	SoundManager.play_ui("menu_error")
	assert_true(_stamped("menu_error"), "CONTROL: play_ui leaves a stamp, or every arm here measures nothing")


func test_a_dial_that_changes_the_value_still_moves() -> void:
	for c in CASES:
		var ed: Node = await _editor(c[0], c[1])
		assert_true(ed._dial_condition(1), "CONTROL %s: the value at 50 can rise" % _name(c[0]))
		assert_gt(int(_cond(ed)["value"]), 50, "CONTROL %s: the value rose" % _name(c[0]))
		assert_true(_stamped("menu_move"), "%s: a real change must still be heard as menu_move" % _name(c[0]))
		assert_false(_stamped("menu_error"), "%s: a real change must not play the refusal" % _name(c[0]))


func test_a_condition_with_no_number_is_refused_out_loud() -> void:
	for c in CASES:
		var ed: Node = await _editor(c[0], c[3])
		var before: Dictionary = _cond(ed).duplicate(true)
		assert_false(ed._dial_condition(1), "%s: %s has no number, so nothing can change" % [_name(c[0]), c[3]["type"]])
		assert_eq(_cond(ed), before, "%s: the condition is unchanged" % _name(c[0]))
		assert_true(_stamped("menu_error"), "%s: dialling %s changed nothing and was not refused" % [_name(c[0]), c[3]["type"]])
		assert_false(_stamped("menu_move"), "%s: a dial that changed nothing still played menu_move" % _name(c[0]))
		assert_string_contains(_shown(ed), "no value", "%s: the refusal must say why" % _name(c[0]))


func test_a_value_at_its_limit_is_refused_out_loud() -> void:
	for c in CASES:
		var ed: Node = await _editor(c[0], c[2])
		assert_false(ed._dial_condition(1), "%s: 100 cannot rise" % _name(c[0]))
		assert_eq(int(_cond(ed)["value"]), 100, "%s: the value is unchanged" % _name(c[0]))
		assert_true(_stamped("menu_error"), "%s: dialling past the top changed nothing and was not refused" % _name(c[0]))
		assert_false(_stamped("menu_move"), "%s: a dial that changed nothing still played menu_move" % _name(c[0]))
		assert_string_contains(_shown(ed), "any further", "%s: the refusal must say why" % _name(c[0]))


func test_the_keys_and_the_stick_go_through_the_dial() -> void:
	for c in CASES:
		var ed: Node = await _editor(c[0], c[3])
		var key := InputEventKey.new()
		key.keycode = KEY_EQUAL
		key.pressed = true
		ed._input(key)
		assert_true(_stamped("menu_error"), "%s: = on %s was not refused" % [_name(c[0]), c[3]["type"]])
		assert_false(_stamped("menu_move"), "%s: = still plays menu_move over a refusal" % _name(c[0]))
		SoundManager._sfx_cooldowns.clear()
		var ev := InputEventJoypadMotion.new()
		ev.axis = JOY_AXIS_RIGHT_Y
		ev.axis_value = 1.0
		ed._value_stick_latched = false
		assert_true(ed._handle_value_stick(ev), "CONTROL %s: the stick step was taken" % _name(c[0]))
		assert_true(_stamped("menu_error"), "%s: the stick on %s was not refused" % [_name(c[0]), c[3]["type"]])
		assert_false(_stamped("menu_move"), "%s: the stick still plays menu_move over a refusal" % _name(c[0]))
