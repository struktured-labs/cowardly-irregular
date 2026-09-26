extends GutTest

## Talking to an NPC, the confirm key is also the settings key and the cancel key is also
## the field menu. The box only froze movement (set_can_move). GameLoop still opened Settings
## on Enter and the overworld menu on X, on top of the line the player was reading. A choice
## prompt had the same hole the moment the line closed. The box and the prompt hold the field
## lock while they are up, including across the press that dismisses them, and let go after.

const GameLoopScript := preload("res://src/GameLoop.gd")
const DialogueScript := preload("res://src/cutscene/CutsceneDialogue.gd")
const ChoiceScript := preload("res://src/llm/DialogueChoiceMenu.gd")

var _saved_locks: Array = []


func before_each() -> void:
	_saved_locks = InputLockManager.get_active_locks()
	InputLockManager.pop_all()
	Input.action_release("ui_accept")
	Input.action_release("ui_cancel")
	Input.action_release("ui_menu")


func after_each() -> void:
	Input.action_release("ui_accept")
	Input.action_release("ui_cancel")
	Input.action_release("ui_menu")
	InputLockManager.pop_all()
	for id in _saved_locks:
		InputLockManager.push_lock(str(id))


func _loop() -> Node:
	# In the tree so get_viewport() exists. _ready raises the title; the press under test is exploration.
	var gl: Node = add_child_autofree(GameLoopScript.new())
	gl.current_state = gl.LoopState.EXPLORATION
	gl._transition_in_progress = false
	return gl


func _key(code: Key) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = code
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


func _box() -> Node:
	var box: Node = add_child_autofree(DialogueScript.new())
	box.show_dialogue([
		{"speaker": "Elder Theron", "text": "The cave is to the northwest.", "theme": "elder", "portrait": "elder"},
		{"speaker": "Elder Theron", "text": "Do not go in alone.", "theme": "elder", "portrait": "elder"},
	])
	return box


func _lock_ids(prefix: String) -> Array:
	var out: Array = []
	for id in InputLockManager.get_active_locks():
		if str(id).begins_with(prefix):
			out.append(str(id))
	return out


func test_enter_opens_settings_when_nobody_is_talking() -> void:
	var gl := _loop()
	assert_false(InputLockManager.is_locked(), "CONTROL: the field starts unlocked")
	gl._input(_key(KEY_ENTER))
	assert_true(_settings_open(gl),
		"CONTROL: Enter must open Settings on the field, or the dialogue arms pass by never reaching that button")


func test_a_dialogue_box_keeps_enter_and_x_off_the_field_menus() -> void:
	var gl := _loop()
	var box := _box()
	assert_eq(_lock_ids("dialogue_box_").size(), 1,
		"the open box must hold the field lock — movement-only freeze lets the menus through")
	gl._input(_key(KEY_ENTER))
	assert_false(_settings_open(gl),
		"Enter advances the line and also opened Settings over it")
	gl._input(_key(KEY_X))
	assert_null(gl._overworld_menu,
		"X skips the line and also opened the field menu over it")
	var ids := _lock_ids("dialogue_box_")
	if ids.is_empty():
		return
	var held: String = str(ids[0])
	InputLockManager._locks[held] = Time.get_ticks_msec() - InputLockManager.STALE_TIMEOUT_MS - 1000
	box._process(0.016)
	assert_true(InputLockManager.has_lock(held),
		"a conversation longer than the stale-lock window must keep the field locked — reading is not a leak")


func test_the_press_that_closes_the_box_does_not_open_settings() -> void:
	var gl := _loop()
	var box := _box()
	box._finish_dialogue()
	gl._input(_key(KEY_ENTER))
	assert_false(_settings_open(gl),
		"the confirm that closes the box also opened Settings on that same press")
	# This frame's _process already ran, before the box closed. The next one releases the lock.
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(_lock_ids("dialogue_box_").size(), 0,
		"once the box is gone the field lock must release, or the player never walks again")
	gl._input(_key(KEY_ENTER))
	assert_true(_settings_open(gl),
		"after the box closes, Enter must open Settings again")


func test_a_choice_prompt_keeps_enter_off_settings() -> void:
	var gl := _loop()
	var menu: Node = add_child_autofree(ChoiceScript.new())
	var runner := func() -> void:
		await menu.present(["Accept the quest", "Not now"])
	runner.call()
	assert_true(menu._active, "PRECONDITION: the prompt is up")
	assert_eq(_lock_ids("dialogue_choice_").size(), 1,
		"the choice prompt must hold the field lock while it waits for an answer")
	gl._input(_key(KEY_ENTER))
	assert_false(_settings_open(gl),
		"Enter picked a choice and also opened Settings over the prompt")
	menu.queue_free()
	await get_tree().process_frame
	assert_eq(_lock_ids("dialogue_choice_").size(), 0,
		"dismissing the prompt must release the field lock")
