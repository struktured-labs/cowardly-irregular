extends GutTest

## struktured .758: a grind STOPPED (healing items depleted), the autogrind console came back on the field, and the quest
## tracker drew over its "AUTOGRIND RULES" header with a stray "< Objective" arrow in the rules. Starting a grind brings
## the field HUD back, and nothing hid it again when the console showed itself on stop. Drives the real GameLoop handlers.

const GL := preload("res://src/GameLoop.gd")


class StubField extends Node:
	var _quest_tracker: CanvasLayer
	var _objective_arrow: CanvasLayer

	func pause() -> void:
		pass

	func resume() -> void:
		pass


var _gl: Node
var _field: StubField
var _console: Control


func _stub_field() -> StubField:
	var f := StubField.new()
	f._quest_tracker = CanvasLayer.new()
	f._objective_arrow = CanvasLayer.new()
	f.add_child(f._quest_tracker)
	f.add_child(f._objective_arrow)
	add_child_autofree(f)
	return f


func before_each() -> void:
	_gl = GL.new()
	autofree(_gl)
	_field = _stub_field()
	_gl._exploration_scene = _field
	_console = Control.new()
	add_child_autofree(_console)
	_gl._autogrind_ui = _console
	_console.visibility_changed.connect(_gl._field_hud_steps_aside_for_console)


func after_each() -> void:
	_gl._autogrind_ui = null


func test_the_console_wires_its_visibility_to_the_hud() -> void:
	var src := FileAccess.get_file_as_string("res://src/GameLoop.gd")
	var open_fn := src.substr(src.find("func _open_autogrind_ui"), 3000)
	assert_true("visibility_changed.connect(_field_hud_steps_aside_for_console)" in open_fn,
		"_open_autogrind_ui must hand the console's visibility to the HUD hider, or the arms below test a wire nothing makes")


func test_the_tracker_steps_aside_when_the_console_comes_back_after_a_grind() -> void:
	_gl._set_field_hud_hidden(true)
	assert_false(_field._quest_tracker.visible, "CONTROL: opening the console hides the tracker")
	# The grind starts: the console hides and _start_autogrind brings the field HUD back.
	_console.visible = false
	_gl._set_field_hud_hidden(false)
	assert_true(_field._quest_tracker.visible, "CONTROL: the tracker is back while the grind runs")
	# The grind stops: the console shows itself again (set_grinding(false)).
	_console.visible = true
	assert_false(_field._quest_tracker.visible, "the quest tracker must not draw over the console that came back")
	assert_false(_field._objective_arrow.visible, "nor the objective arrow inside its rules")


func test_closing_the_console_brings_the_tracker_back() -> void:
	_console.visible = false
	_console.visible = true
	assert_false(_field._quest_tracker.visible, "CONTROL: hidden under the console")
	_gl._on_autogrind_ui_closed()
	assert_true(_field._quest_tracker.visible, "closing the console returns the tracker to the field")


func test_a_field_scene_built_by_the_stop_is_covered_too() -> void:
	# The stop path may return to a NEW field scene whose HUD was never hidden, with the console already showing.
	var fresh := _stub_field()
	_gl._exploration_scene = fresh
	assert_true(fresh._quest_tracker.visible, "CONTROL: a freshly built field shows its tracker")
	_gl._field_hud_steps_aside_for_console()
	assert_false(fresh._quest_tracker.visible, "the console over a fresh field still hides its tracker")
	var src := FileAccess.get_file_as_string("res://src/GameLoop.gd")
	var stop_fn := src.substr(src.find("func _stop_autogrind"), src.find("\nfunc ", src.find("func _stop_autogrind") + 1) - src.find("func _stop_autogrind"))
	var ret := stop_fn.find("_return_to_exploration()")
	var aside := stop_fn.find("_field_hud_steps_aside_for_console()")
	assert_gt(ret, -1, "CONTROL: the stop path still returns to exploration")
	assert_gt(aside, ret, "_stop_autogrind must hide the HUD AFTER its return to exploration builds the field")


func test_a_hidden_console_hides_nothing() -> void:
	_console.visible = false
	_gl._field_hud_steps_aside_for_console()
	assert_true(_field._quest_tracker.visible, "while the grind runs (console hidden) the tracker stays on the field")
