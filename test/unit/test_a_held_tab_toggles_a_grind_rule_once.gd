extends GutTest

## Sibling of cowir-controller's dc0cdc4f3 (autobattle editor): the autogrind console's Tab arm had no
## echo guard, so HOLDING Tab flipped the rule under the cursor on every key repeat.

const UI := "res://src/ui/autogrind/AutogrindUI.gd"

var _vp: SubViewport = null
var _ui: Control = null


func before_each() -> void:
	AutogrindSystem._test_disable_persistence = true
	_vp = SubViewport.new()
	_vp.size = Vector2i(1280, 720)
	add_child_autofree(_vp)
	var layer := CanvasLayer.new()
	_vp.add_child(layer)
	_ui = load(UI).new()
	_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(_ui)
	await get_tree().process_frame
	_ui.rules = [
		{"conditions": [], "actions": [{"type": "attack", "target": "lowest_hp_enemy"}], "enabled": true},
	]
	_ui.cursor_row = 0
	_ui.cursor_col = 0
	_ui._refresh_grid()


func after_each() -> void:
	AutogrindSystem._test_disable_persistence = false
	_ui = null


func _tab(echo: bool) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = KEY_TAB
	e.pressed = true
	e.echo = echo
	return e


func _enabled() -> bool:
	return bool(_ui.rules[0].get("enabled", true))


## 5 repeats: an odd count, so a guard that lets echoes through cannot land back on the right answer.
func test_a_held_tab_turns_the_rule_off_once() -> void:
	assert_true(_enabled(), "CONTROL: the rule starts on")
	_ui._input(_tab(false))
	for i in 5:
		_ui._input(_tab(true))
	assert_false(_enabled(), "the press turns the rule off, and 5 key repeats must not turn it back on")


## CONTROL: two separate presses are two toggles, so the guard has not eaten the key itself.
func test_two_tab_presses_are_two_toggles() -> void:
	_ui._input(_tab(false))
	assert_false(_enabled(), "one press turns the rule off")
	_ui._input(_tab(false))
	assert_true(_enabled(), "a second press turns it back on")


## A swallowed echo must not fall through to GUI focus navigation, where Tab is ui_focus_next.
func test_a_tab_repeat_is_consumed() -> void:
	_vp.push_input(_tab(false))
	var e := _tab(true)
	_vp.push_input(e)
	assert_true(_vp.is_input_handled(), "a Tab key repeat was left unhandled for the focus system")
