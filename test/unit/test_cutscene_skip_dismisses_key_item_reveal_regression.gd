extends GutTest

## grant_item awaited the KeyItemPopup's `dismissed` signal raw. The popup dismisses only on a
## fresh A/B PRESS after its 0.3s intro, so a B held from before the reveal raised no event, the
## Director's hold-B skip fired at 1.5s with the popup still up, and the scene sat parked on a
## reveal the player had asked to skip. A freed popup (scene torn down under it) parked the step
## forever. _trigger_skip now dismisses a reveal in flight; the await is polled so a freed popup
## releases the step; KeyItemPopup.dismiss() is public, pre-intro-safe and idempotent.

const DirectorScript = preload("res://src/cutscene/CutsceneDirector.gd")

var _d: Node


func before_each() -> void:
	Input.action_release("ui_cancel")
	Input.action_release("ui_accept")
	_d = DirectorScript.new()
	add_child_autofree(_d)
	_d._skipping = false


func after_each() -> void:
	Input.action_release("ui_cancel")
	Input.action_release("ui_accept")
	if _d and is_instance_valid(_d):
		_d._active = false
		if _d._key_item_popup and is_instance_valid(_d._key_item_popup):
			_d._key_item_popup.dismiss()
			for i in 20:
				await get_tree().process_frame


func _start() -> Array:
	var done := [false]
	var runner := func() -> void:
		await _d._execute_step({"type": "grant_item", "item": "fool_card", "name": "The Fool", "description": "A card with no number."})
		done[0] = true
	runner.call()
	return done


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _until(done: Array, budget_frames: int) -> int:
	var n := 0
	while not done[0] and n < budget_frames:
		await get_tree().process_frame
		n += 1
	return n


func test_skip_dismisses_a_reveal_in_flight_and_releases_the_step() -> void:
	var done := _start()
	await _frames(2)
	var popup: Node = _d._key_item_popup
	assert_not_null(popup, "control: the reveal is up two frames in")
	assert_false(done[0], "control: the step is parked on the reveal")
	_d._trigger_skip()
	await _until(done, 40)
	assert_true(done[0], "a skip must release grant_item within the popup's 0.2s fade")
	assert_null(_d._key_item_popup, "the handle clears once the reveal is gone")
	await _frames(2)
	assert_false(is_instance_valid(popup), "the popup frees itself after the fade")


func test_without_a_skip_the_reveal_waits_for_a_press() -> void:
	# ARM+: a step that never waited would pass the test above.
	var done := _start()
	await _frames(12)
	assert_false(done[0], "control: no press, no skip — still parked after 12 frames")
	var popup: Node = _d._key_item_popup
	popup._dismissable = true  # past the intro
	var ev := InputEventAction.new()
	ev.action = "ui_accept"
	ev.pressed = true
	popup._input(ev)
	await _until(done, 40)
	assert_true(done[0], "a fresh confirm press still dismisses the reveal")


func test_a_freed_popup_releases_the_step_instead_of_parking_it_forever() -> void:
	var done := _start()
	await _frames(2)
	var popup: Node = _d._key_item_popup
	assert_not_null(popup, "control: reveal up")
	popup.free()
	await _until(done, 6)
	assert_true(done[0], "a popup torn down under the step must release it — the raw signal await never returned")
	assert_null(_d._key_item_popup)


func test_a_held_b_from_before_the_reveal_skips_through_it() -> void:
	# End to end: the hold accumulates in _process, the skip fires, the reveal fades, the step returns.
	_d._active = true
	Input.action_press("ui_cancel")
	var done := _start()
	await _frames(2)
	assert_not_null(_d._key_item_popup, "control: reveal up while B is held")
	_d._process(1.0)
	_d._process(1.0)
	assert_true(_d._skipping, "control: 2.0s of held B skips")
	await _until(done, 40)
	assert_true(done[0], "the held B that raised no press event still gets the player past the reveal")


func test_popup_dismiss_is_public_pre_intro_safe_and_idempotent() -> void:
	var host := Node.new()
	add_child_autofree(host)
	var popup := KeyItemPopup.show_item(host, {"name": "X", "description": "y"})
	var emissions := [0]
	popup.dismissed.connect(func() -> void: emissions[0] += 1)
	assert_false(popup._dismissable, "control: not yet dismissable right after show — a press would be ignored here")
	popup.dismiss()
	popup.dismiss()
	await _frames(40)
	assert_eq(emissions[0], 1, "two dismiss() calls fade once and emit once")
	assert_false(is_instance_valid(popup), "and the popup is gone")
