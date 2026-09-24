extends GutTest

## Start opens Settings while a map fade-in is on screen.
##
## Area transitions set _transition_in_progress for the whole fade, but the
## area_transition_fade lock is pushed only after _start_exploration (which
## pop_all's first). Fade-in therefore holds no lock. The field menu and
## party chat already refuse in that window. Start only asked is_locked(),
## so Settings opened over the fade, paused the map about to be freed, and
## left the arriving map running under the menu.

const GameLoopScript := preload("res://src/GameLoop.gd")

var _saved_locks: Array = []


func before_each() -> void:
	_saved_locks = InputLockManager.get_active_locks()
	InputLockManager.pop_all()


func after_each() -> void:
	InputLockManager.pop_all()
	for id in _saved_locks:
		InputLockManager.push_lock(str(id))


func _loop() -> Node:
	var gl: Node = autofree(GameLoopScript.new())
	# _ready shows the title and flips the state; the press under test is exploration.
	gl.current_state = gl.LoopState.EXPLORATION
	gl._transition_in_progress = false
	return gl


func _start_press() -> InputEventJoypadButton:
	var ev := InputEventJoypadButton.new()
	ev.button_index = JOY_BUTTON_START
	ev.pressed = true
	return ev


func _settings_open(gl: Node) -> bool:
	for child in gl.get_children():
		if not (child is CanvasLayer):
			continue
		for grand in child.get_children():
			if grand is SettingsMenu:
				return true
	return false


func test_start_during_fade_in_does_not_open_settings() -> void:
	var gl := _loop()
	gl._transition_in_progress = true
	assert_false(InputLockManager.is_locked(),
		"CONTROL: fade-in holds no lock — a guard that only reads is_locked() cannot see this window")
	gl._input(_start_press())
	assert_false(_settings_open(gl),
		"Start during a map fade-in opened Settings. The arriving map then runs under the menu, because the pause landed on the map that was about to be freed.")


func test_start_still_opens_settings_when_nothing_is_in_flight() -> void:
	var gl := _loop()
	assert_false(InputLockManager.is_locked(), "CONTROL: no lock is held")
	assert_false(gl._transition_in_progress, "CONTROL: no fade is in flight")
	gl._input(_start_press())
	assert_true(_settings_open(gl),
		"CONTROL: Start must still open Settings in ordinary exploration, or the fade-in arm passes by never seeing the button")


func test_start_during_an_encounter_lock_still_refuses() -> void:
	var gl := _loop()
	InputLockManager.push_lock("encounter_transition")
	gl._input(_start_press())
	assert_false(_settings_open(gl),
		"Start during an encounter transition opened Settings under the battle that is about to load")
