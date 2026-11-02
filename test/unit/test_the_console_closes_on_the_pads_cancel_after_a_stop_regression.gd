extends GutTest

## struktured, .758: "in autogrind mode, it stopped, tried to exit after and its stuck again where b doesnt close it" / "escape worked tho".
## The grind stopped (Healing items depleted), the console came back, and the pad's cancel never closed it. Driven here through the
## REAL path: GameLoop opens the console, a grind hides it, _on_grind_complete brings it back with its summary, and the pad's own
## cancel button goes through Input.parse_input_event, the remap and the viewport, never a direct _input call.

const AutogrindState := preload("res://test/unit/helpers/autogrind_state.gd")
const GL_SRC := "res://src/GameLoop.gd"

var _ag: Dictionary
var _gl: Node


func before_each() -> void:
	_ag = AutogrindState.snapshot()
	AutogrindSystem._test_disable_persistence = true
	AutobattleSystem._test_disable_persistence = true
	_gl = load(GL_SRC).new()
	add_child_autofree(_gl)
	var explore := Node.new()
	add_child_autofree(explore)
	_gl._exploration_scene = explore
	_gl._current_map_id = "overworld"
	var members: Array[Combatant] = []
	for n in ["Fighter", "Cleric"]:
		var c := Combatant.new()
		c.combatant_name = n
		c.max_hp = 50
		c.current_hp = 50
		c.is_alive = true
		_gl.add_child(c)
		members.append(c)
	_gl.party = members


func after_each() -> void:
	InputLockManager.pop_all()
	Engine.time_scale = 1.0
	AutogrindState.restore(_ag)
	SoundManager.stop_music()


## The pad button the player's profile binds to ui_cancel, so the press is the one the hint names.
func _pad_cancel_button() -> int:
	for ev in InputMap.action_get_events("ui_cancel"):
		if ev is InputEventJoypadButton:
			return (ev as InputEventJoypadButton).button_index
	return -1


func _press_pad(button: int) -> void:
	for pressed in [true, false]:
		var ev := InputEventJoypadButton.new()
		ev.device = 0
		ev.button_index = button
		ev.pressed = pressed
		Input.parse_input_event(ev)
		Input.flush_buffered_events()
		await wait_frames(2)


func _stopped_console() -> Node:
	_gl._open_autogrind_ui()
	var ui: Node = _gl._autogrind_ui
	ui.set_grinding(true)
	ui.visible = false
	_gl._is_autogrinding = true
	_gl.current_state = _gl.LoopState.AUTOGRIND
	_gl._on_grind_complete("Healing items depleted")
	await wait_frames(3)
	return ui


## Found by this file's first run: the console came back with the cursor on rule 1's first cell, and B there DELETES the cell
## rather than closing (_handle_cancel). Pressed twice, it ate a condition and left the console up.
func test_a_stopped_console_comes_back_where_b_closes_it_and_deletes_nothing() -> void:
	var ui: Node = await _stopped_console()
	var rules_before: int = ui.rules.size()
	var cell = ui._get_cell_at_cursor()
	assert_false(cell != null and cell.has_meta("cell_type") and str(cell.get_meta("cell_type")) in ["condition", "action"],
		"a stop must not bring the console back with the cursor on a rule cell, where B deletes")
	var button := _pad_cancel_button()
	for i in 2:
		if _gl._autogrind_ui_open():
			await _press_pad(button)
	assert_eq(AutogrindSystem.get_autogrind_rules().size() if is_instance_valid(ui) else rules_before, rules_before, "pressing B to leave must delete no rule")


func test_the_pads_cancel_closes_a_console_brought_back_by_a_stop() -> void:
	var button := _pad_cancel_button()
	assert_gt(button, -1, "CONTROL: ui_cancel must carry a pad button, or this press is not the one the hint names")
	var ui: Node = await _stopped_console()
	assert_true(is_instance_valid(ui) and ui.visible, "CONTROL: the stop must bring the console back")
	assert_true(_gl._autogrind_ui_open(), "CONTROL: GameLoop must still track the console it brought back")
	## The summary sits above the console; its own cancel dismisses it first. Two presses is the most a player should need.
	for i in 2:
		if _gl._autogrind_ui_open():
			await _press_pad(button)
	assert_false(_gl._autogrind_ui_open(), "two presses of the pad's cancel did not close the stopped console")
	assert_true(_gl._autogrind_summary == null or not is_instance_valid(_gl._autogrind_summary),
		"and the summary above it is gone too")


## struktured, preview: "also I can't hit B again to close autogrind after 2 runs". Whatever is left behind is per-run, so
## the same stop-then-close cycle is driven three times on ONE GameLoop, reopening the console each time as the player does.
func test_the_pads_cancel_still_closes_it_after_three_runs() -> void:
	var button := _pad_cancel_button()
	assert_gt(button, -1, "CONTROL: ui_cancel must carry a pad button")
	for run in 3:
		var ui: Node = await _stopped_console()
		assert_true(is_instance_valid(ui) and _gl._autogrind_ui_open(), "CONTROL: run %d brought the console back" % (run + 1))
		for i in 2:
			if _gl._autogrind_ui_open():
				await _press_pad(button)
		assert_false(_gl._autogrind_ui_open(), "after run %d, two presses of the pad's cancel did not close the console" % (run + 1))
		if _gl._autogrind_ui_open():
			return
