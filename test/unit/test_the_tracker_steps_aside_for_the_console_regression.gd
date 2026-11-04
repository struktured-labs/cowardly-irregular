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
	_console.visibility_changed.connect(_gl._field_hud_steps_aside_for_console.bind(_console))
	_console.tree_exited.connect(_gl._field_hud_steps_aside_for_console.bind(_console))


func after_each() -> void:
	# Off before autofree: freeing the console emits tree_exited into a GameLoop that may already be gone.
	for sig in [_console.visibility_changed, _console.tree_exited]:
		for c in sig.get_connections():
			sig.disconnect(c["callable"])
	_gl._autogrind_ui = null
	_gl._signalled_console = null
	for prop in ["_overworld_menu", "_autobattle_editor", "_field_settings_menu", "_party_chat_menu"]:
		_gl.set(prop, null)


func test_the_console_wires_its_visibility_to_the_hud() -> void:
	var src := FileAccess.get_file_as_string("res://src/GameLoop.gd")
	var open_fn := src.substr(src.find("func _open_autogrind_ui"), 3000)
	assert_true("visibility_changed.connect(_field_hud_steps_aside_for_console.bind(_autogrind_ui))" in open_fn,
		"_open_autogrind_ui must hand the console's visibility to the HUD hider, or the arms below test a wire nothing makes")
	assert_true("tree_exited.connect(_field_hud_steps_aside_for_console.bind(_autogrind_ui))" in open_fn,
		"and its leaving, so a console that goes away by any path gives the field its HUD back")


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


func test_an_untracked_console_still_hides_the_tracker_and_gives_it_back() -> void:
	# His drawn console was one GameLoop no longer tracked (the overworld menu opened under it).
	_gl._autogrind_ui = null
	_console.visible = false
	_console.visible = true
	assert_false(_field._quest_tracker.visible, "a console that shows hides the tracker even when GameLoop lost track of it")
	_console.visible = false
	assert_true(_field._quest_tracker.visible, "and when it goes away the tracker comes back, so the HUD is never stranded")


func test_a_console_leaving_gives_the_tracker_back() -> void:
	_gl._autogrind_ui = null
	_console.visible = false
	_console.visible = true
	assert_false(_field._quest_tracker.visible, "CONTROL: hidden under the console")
	remove_child(_console)
	assert_true(_field._quest_tracker.visible, "a console freed or removed by any path restores the tracker")
	add_child(_console)


func test_a_running_grind_keeps_what_start_restored() -> void:
	_gl._is_autogrinding = true
	_gl._set_field_hud_hidden(true)
	_console.visible = false
	assert_false(_field._quest_tracker.visible, "the hide-on-leave rule does not run mid-grind; _start_autogrind owns that restore")
	_gl._is_autogrinding = false


## adhoc, his 16:24 shots: the rule is any full-screen panel, derived from the states that already refuse the field-menu toggle.
const SCREENS := ["_overworld_menu", "_autobattle_editor", "_field_settings_menu", "_party_chat_menu"]


func _panel() -> Control:
	var c := Control.new()
	add_child_autofree(c)
	return c


func test_every_screen_that_owns_the_field_hides_the_tracker_and_gives_it_back() -> void:
	_console.visible = false
	_gl._signalled_console = null
	_gl._autogrind_ui = null
	for prop in SCREENS:
		_gl._process(0.0)
		assert_true(_field._quest_tracker.visible, "CONTROL: no screen open, the tracker is on the field (before %s)" % prop)
		var panel := _panel()
		_gl.set(prop, panel)
		_gl._process(0.0)
		assert_false(_field._quest_tracker.visible, "%s owns the screen: the tracker must step aside" % prop)
		assert_false(_field._objective_arrow.visible, "%s owns the screen: so must the objective arrow" % prop)
		_gl.set(prop, null)
		panel.queue_free()
		_gl._process(0.0)
		assert_true(_field._quest_tracker.visible, "%s closed: the tracker comes back" % prop)


func test_a_field_menu_hidden_behind_its_own_submenu_still_owns_the_screen() -> void:
	_console.visible = false
	_gl._signalled_console = null
	_gl._autogrind_ui = null
	var menu := _panel()
	_gl._overworld_menu = menu
	menu.visible = false
	_gl._process(0.0)
	assert_false(_field._quest_tracker.visible, "a submenu hides the field menu's own panel; the menu still owns the screen")
	_gl._overworld_menu = null


func test_ownership_is_derived_from_the_toggle_gate() -> void:
	var src := FileAccess.get_file_as_string("res://src/GameLoop.gd")
	var owns := src.substr(src.find("func _a_screen_owns_the_field"), 600)
	for pred in ["_field_editor_open()", "_field_modal_open()"]:
		assert_true(pred in owns, "screen ownership must reuse %s, the predicate the field-menu toggle refuses on" % pred)
	var toggle := src.substr(src.find("var x_pressed := OverworldMenu.is_toggle_event(event)"), 800)
	assert_true("_field_modal_open()" in toggle, "CONTROL: the toggle gate still refuses on _field_modal_open()")


func test_the_field_hud_is_left_alone_outside_exploration() -> void:
	_gl._set_field_hud_hidden(true)
	_gl.current_state = GL.LoopState.BATTLE
	_gl._process(0.0)
	assert_false(_field._quest_tracker.visible, "outside exploration the reconciler touches nothing")
	_gl.current_state = GL.LoopState.EXPLORATION
