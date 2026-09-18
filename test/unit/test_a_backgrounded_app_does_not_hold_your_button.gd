extends GutTest

## The virtual gamepad releases an action ONLY on a touch-UP event. Backgrounding a tab or an app
## with a finger down delivers no touch-up at all — so the action stayed pressed for the rest of the
## session, with nothing left able to lift it.
##
## ⛔ MEASURED BEFORE THE FIX, on a real pad instance:
##     touch-down                  pressed true   _touch_map { 0: "ui_accept" }
##     APPLICATION_FOCUS_OUT       pressed TRUE   _touch_map { 0: "ui_accept" }
##     WM_WINDOW_FOCUS_OUT         pressed TRUE
## The player returns to a character walking into a wall, or a menu repeating. `_teardown` already
## lifted held fingers for the ROTATION case and had exactly one caller — the resize path — so the
## release logic existed and the app going away simply never reached it.
##
## ⚠️ THIS IS THE WEB AND TOUCH TARGET. The pad builds only where `DisplayServer.is_touchscreen_
## available()` or a real ScreenTouch says so, and backgrounding is far more ordinary there than a
## rotation: every notification shade, call and tab switch is one.
##
## 📌 The arms drive `propagate_notification` from the tree root rather than calling `_notification`
## on the node, because the engine delivers these by propagation — a handler that exists but is
## never reached would pass a direct call and fail a player.

const VG := preload("res://src/ui/VirtualGamepad.gd")

const SIZE := Vector2i(800, 480)


## Same three-step build the sibling rotation guard uses: `_ready` does not build headless, because
## `_is_touch_device()` is false, and these three calls exist in every version of the source.
func _pad_in(size: Vector2i) -> Array:
	var sv := SubViewport.new()
	sv.size = size
	add_child_autofree(sv)
	var pad = VG.new()
	sv.add_child(pad)
	await get_tree().process_frame
	pad._visible = true
	pad._compute_scale()
	pad._create_buttons()
	pad._draw_dpad()
	await get_tree().process_frame
	return [sv, pad]


## Puts a finger down the way `_input` does, and proves it landed before anything is asserted about
## lifting it — a release arm over an action that was never pressed is satisfied by nothing happening.
func _finger_down(pad, action: String) -> void:
	pad._press_action(action)
	pad._touch_map[0] = action
	Input.flush_buffered_events()
	assert_true(Input.is_action_pressed(action),
		"CONTROL: the press must actually land, or the release below has nothing to undo")
	assert_false(pad._touch_map.is_empty(), "CONTROL: …and the pad must be tracking that finger")


func _background(what: int) -> void:
	get_tree().root.propagate_notification(what)
	await get_tree().process_frame
	Input.flush_buffered_events()


## ⛔ THE DEFECT, on the notification a phone raises.
func test_backgrounding_the_app_lifts_a_held_finger() -> void:
	var r = await _pad_in(SIZE)
	var pad = r[1]
	_finger_down(pad, "ui_accept")

	await _background(NOTIFICATION_APPLICATION_FOCUS_OUT)

	assert_false(Input.is_action_pressed("ui_accept"),
		"the app went away with a finger down and no touch-up will ever arrive — the action stayed "
		+ "pressed for the rest of the session, with no button left able to lift it")
	assert_true(pad._touch_map.is_empty(),
		"…and the touch map must be dropped: index 0 names a hold that can no longer be released")


## The same hazard on desktop and web, where the window blurs rather than the app pausing. A fix
## wired to only one of these covers one target and reads as covering all three.
func test_blurring_the_window_lifts_a_held_finger() -> void:
	var r = await _pad_in(SIZE)
	var pad = r[1]
	_finger_down(pad, "ui_accept")

	await _background(NOTIFICATION_WM_WINDOW_FOCUS_OUT)

	assert_false(Input.is_action_pressed("ui_accept"),
		"a tab switch blurs the window without delivering a touch-up")
	assert_true(pad._touch_map.is_empty(), "…and the touch map goes with it")


## …and the mobile pause, which is the one that arrives when a call comes in.
func test_pausing_the_app_lifts_a_held_finger() -> void:
	var r = await _pad_in(SIZE)
	var pad = r[1]
	_finger_down(pad, "ui_accept")

	await _background(NOTIFICATION_APPLICATION_PAUSED)

	assert_false(Input.is_action_pressed("ui_accept"), "an incoming call must not leave the button held")
	assert_true(pad._touch_map.is_empty(), "…and the touch map goes with it")


## ⛔ THE WRONG FIX, AND NOTHING ELSE HERE CATCHES IT. `_teardown()` already lifts held fingers, so
## calling it from the notification handler makes every arm above pass — while FREEING every button.
## Nothing rebuilds on focus RETURN: `_build` is reached from `_ready` and the resize path, neither
## of which fires when focus comes back. The player would return to a pad with no buttons on it,
## which is a worse bug than the one being fixed and is invisible to a release-only assertion.
func test_the_buttons_survive_the_app_going_away() -> void:
	var r = await _pad_in(SIZE)
	var pad = r[1]
	var before: int = pad._buttons.size()
	var kids: int = pad.get_child_count()
	assert_gt(before, 6, "CONTROL: a real pad has a d-pad, a diamond, shoulders and a centre row")
	_finger_down(pad, "ui_accept")

	await _background(NOTIFICATION_APPLICATION_FOCUS_OUT)

	assert_eq(pad._buttons.size(), before,
		"releasing a held finger must not tear the pad down — nothing rebuilds it on focus return, "
		+ "so the player would come back to a screen with no buttons")
	assert_eq(pad.get_child_count(), kids, "…and its nodes must still be parented")


## A finger down at the moment of backgrounding is the interesting case; no finger down is the
## ordinary one, and a handler that fired regardless would release actions the pad never pressed.
func test_backgrounding_with_no_finger_down_touches_nothing() -> void:
	var r = await _pad_in(SIZE)
	var pad = r[1]
	assert_true(pad._touch_map.is_empty(), "CONTROL: no finger is down to begin with")
	var before: int = pad._buttons.size()

	await _background(NOTIFICATION_APPLICATION_FOCUS_OUT)

	assert_true(pad._touch_map.is_empty(), "nothing to lift, nothing lifted")
	assert_eq(pad._buttons.size(), before, "…and the pad is untouched")


## ⛔ DERIVED, NOT LISTED — the sibling rotation guard's teardown, for the same reason: a hand-list
## of today's actions silently stops covering the eleventh button somebody adds. Releasing an action
## nobody pressed costs nothing.
func after_each() -> void:
	for a in InputMap.get_actions():
		Input.action_release(a)
	Input.flush_buffered_events()
