extends GutTest

## B on the W6 orrery choice used to cancel DialogueChoiceMenu, and _step_choice mapped the
## cancel sentinel to option 1 — with a menu_cancel sound, the game answered for the player.
## A story choice now swallows cancel (DialogueChoiceMenu.cancellable = false; opt-in, so the
## LLM / quest / tally / roamer consumers keep B = leave). Since B can no longer close it, the
## hold-B skip dismisses the menu in flight — a path that was unreachable before (B closed the
## menu long before the 1.5s hold) and that would otherwise hang the scene on an await.

const DirectorScript = preload("res://src/cutscene/CutsceneDirector.gd")
const MenuScript = preload("res://src/llm/DialogueChoiceMenu.gd")
const FLAG_A := "test_choice_backout_a"
const FLAG_B := "test_choice_backout_b"

var _d: Node


func before_each() -> void:
	Input.action_release("ui_cancel")
	Input.action_release("ui_accept")
	_d = DirectorScript.new()
	add_child_autofree(_d)
	_d._skipping = false
	_clear_flags()


func after_each() -> void:
	Input.action_release("ui_cancel")
	Input.action_release("ui_accept")
	# Release any coroutine still parked on a menu so a freed Director never hosts a live await.
	if _d and is_instance_valid(_d) and _d._choice_menu != null:
		_d._trigger_skip()
		for i in 4:
			await get_tree().process_frame
	_clear_flags()


func _gs() -> Node:
	return get_tree().root.get_node_or_null("GameState")


func _clear_flags() -> void:
	var gs := _gs()
	if gs == null:
		return
	for f in [FLAG_A, FLAG_B]:
		gs.game_constants.erase("cutscene_flag_" + f)
		if gs.has_method("set_story_flag"):
			gs.set_story_flag(f, false)


func _flag_set(f: String) -> bool:
	var gs := _gs()
	return gs != null and gs.game_constants.get("cutscene_flag_" + f, false) == true


func _step() -> Dictionary:
	return {"type": "choice", "prompt": "", "options": [
		{"text": "Yes", "flag": FLAG_A},
		{"text": "No", "flag": FLAG_B},
	]}


## Starts the choice step unawaited; the one-slot array flips when it releases.
func _start() -> Array:
	var done := [false]
	var runner := func() -> void:
		await _d._execute_step(_step())
		done[0] = true
	runner.call()
	return done


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _press(menu: Node, action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	menu._input(ev)


func test_cancel_no_longer_answers_a_story_choice() -> void:
	var done := _start()
	await _frames(2)
	var menu: Node = _d._choice_menu
	assert_not_null(menu, "control: the choice menu is up two frames in")
	if menu == null:
		return
	_press(menu, "ui_cancel")
	await _frames(3)
	assert_false(done[0], "B must not close a story choice — it used to, and option 1 got picked")
	assert_true(menu._active, "the menu stays up after a cancel press")
	assert_false(_flag_set(FLAG_A), "no option flag is written by a cancel press")
	assert_false(_flag_set(FLAG_B))


func test_confirm_still_picks_the_highlighted_option() -> void:
	var done := _start()
	await _frames(2)
	var menu: Node = _d._choice_menu
	assert_not_null(menu, "control: menu up")
	if menu == null:
		return
	_press(menu, "ui_down")
	_press(menu, "ui_accept")
	await _frames(3)
	assert_true(done[0], "confirm resolves the step")
	assert_true(_flag_set(FLAG_B), "the highlighted (second) option's flag is written")
	assert_false(_flag_set(FLAG_A))
	assert_null(_d._choice_menu, "the handle clears once the step resolves")


func test_hold_b_skip_dismisses_a_choice_in_flight() -> void:
	# The path the fix makes reachable: with B swallowed, the 1.5s hold is the only way out.
	var done := _start()
	await _frames(2)
	var menu: Node = _d._choice_menu
	assert_not_null(menu, "control: menu up")
	if menu == null:
		return
	_press(menu, "ui_cancel")
	await _frames(1)
	assert_false(done[0], "control: cancel did not resolve it")
	_d._trigger_skip()
	await _frames(4)
	assert_true(done[0], "a skip must release the choice step, not leave the scene parked on the menu")
	assert_true(_flag_set(FLAG_A), "a skipped choice answers option 1 — the same answer the pre-menu skip path gives")
	assert_null(_d._choice_menu)


func test_the_menu_default_still_cancels_for_its_other_consumers() -> void:
	# ARM+: the swallow is opt-in. DynamicConversation / QuestSystem / TallyWall / RoamingMonster rely on B = leave.
	var menu: Node = MenuScript.new()
	add_child_autofree(menu)
	assert_true(menu.cancellable, "cancellable defaults to true")
	var result := [null]
	var runner := func() -> void:
		result[0] = await menu.present(["Tell me more.", "Farewell."])
	runner.call()
	await _frames(2)
	_press(menu, "ui_cancel")
	await _frames(3)
	assert_eq(result[0], "", "a cancellable menu still resolves with the cancel sentinel on B")


func test_a_story_choice_hint_does_not_advertise_cancel() -> void:
	var menu: Node = MenuScript.new()
	add_child_autofree(menu)
	menu.cancellable = false
	var runner := func() -> void:
		await menu.present(["Yes", "No"])
	runner.call()
	await _frames(2)
	assert_not_null(menu._hint_label, "control: the hint row is built")
	if menu._hint_label:
		assert_false(menu._hint_label.text.contains("Cancel"), "a menu that swallows B must not print a Cancel hint: %s" % menu._hint_label.text)
		assert_true(menu._hint_label.text.contains("Confirm"), "control: the confirm hint survives")
	menu.dismiss()
	await _frames(2)
