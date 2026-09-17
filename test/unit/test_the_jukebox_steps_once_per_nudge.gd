extends GutTest

## One stick nudge moved the cursor five rows, on 161 tracks.
##
## `ui_up`/`ui_down` bind the left stick's Y axis, and an axis carries NO echo flag — so every step
## of a ramp reads as pressed and the menu's `is_action_pressed(...) and not event.is_echo()` guard
## took all of them. @cowir-controller measured 5 of 6 ramp steps passing that guard; on the Jukebox
## that is five of 161 rows per nudge, on the one screen whose entire purpose is browsing a long list.
##
## 🔑 THE ECHO CHECK GRANTS NOTHING HERE. It was written for a held KEY, and a key is the only input
## it can see. Routed through `MenuNav.step` (`.367`), which latches per axis pair and self-heals.
##
## ⛔ THE INTERACTION THIS FILE EXISTS FOR, beyond the conversion: the Jukebox RESTORES a remembered
## cursor on open (`_last_selected`, session-scoped). @cowir-controller stated plainly that their two
## conversion sites have no such restore, so the latch-plus-restore pair is measured for ZERO menus.
## It is measured here.

const JUKEBOX := preload("res://src/ui/JukeboxMenu.gd")


## ⛔ MenuNav's LATCH IS STATIC, so it outlives a test the way the Input singleton does —
## CLAUDE.md's leak class one layer over, in a helper rather than the engine. An arm that ends
## mid-push strands it and the NEXT arm's first nudge is swallowed. Measured: arm 2 read 0 steps
## because arm 1 left the stick held. Cleared through the PUBLIC seam (release, then one centring
## event, which is what the self-heal polls for) rather than by writing the private static.
func before_each() -> void:
	JUKEBOX._last_selected = 0
	_centre()


func _centre() -> void:
	Input.action_release("ui_up")
	Input.action_release("ui_down")
	var e := InputEventJoypadMotion.new()
	e.axis = JOY_AXIS_LEFT_Y
	e.axis_value = 0.0
	MenuNav.step(e)


func after_each() -> void:
	JUKEBOX._last_selected = 0
	_centre()
	SoundManager.stop_music()


func _open() -> Node:
	var jb: Node = JUKEBOX.new()
	add_child_autofree(jb)
	await get_tree().process_frame
	return jb


## ⛔ THE GLOBAL STATE IS PART OF THE SUBJECT, and my first harness left it out. `MenuNav`
## self-heals by POLLING `Input.is_action_pressed` — the correct clear for a shared axis — so an
## arm that only calls `_input()` leaves the poll reading "nothing held", the heal fires on every
## event, and the latch can never hold. Measured: 6 rows on a 6-step ramp, against a fix that works.
## The engine sets the action state from the axis and THEN delivers the event; the arm must too.
func _push(jb: Node, axis_value: float) -> void:
	var action: String = "ui_down" if axis_value > 0.0 else "ui_up"
	Input.action_press(action, absf(axis_value))
	var e := InputEventJoypadMotion.new()
	e.axis = JOY_AXIS_LEFT_Y
	e.axis_value = axis_value
	jb._input(e)


## Return past the deadzone: the engine releases the action, then delivers the centring event.
func _release(jb: Node) -> void:
	Input.action_release("ui_up")
	Input.action_release("ui_down")
	var e := InputEventJoypadMotion.new()
	e.axis = JOY_AXIS_LEFT_Y
	e.axis_value = 0.0
	jb._input(e)


func _dpad(pressed: bool = true) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.button_index = JOY_BUTTON_DPAD_DOWN
	e.pressed = pressed
	return e


func test_one_stick_nudge_moves_one_row() -> void:
	var jb: Node = await _open()
	assert_gt(jb.TRACKS.size(), 20, "CONTROL: %d rows, so five is a visible overshoot" % jb.TRACKS.size())
	jb.selected_index = 0

	## A six-step ramp past the deadzone — the shape @cowir-controller measured.
	for v in [0.55, 0.7, 0.8, 0.9, 0.95, 1.0]:
		_push(jb, v)
	assert_eq(jb.selected_index, 1,
		"one stick nudge moved %d rows — an axis emits one event per value change and every one reads as pressed" % jb.selected_index)


func test_the_latch_releases_and_the_next_nudge_steps() -> void:
	var jb: Node = await _open()
	jb.selected_index = 0
	for v in [0.6, 0.8, 1.0]:
		_push(jb, v)
	assert_eq(jb.selected_index, 1, "CONTROL: the first nudge stepped")

	## Return past the deadzone, then push again. Without the self-heal the second push is swallowed.
	_release(jb)
	for v in [0.6, 0.9]:
		_push(jb, v)
	assert_eq(jb.selected_index, 2,
		"the second nudge did not step — the latch stranded at %d" % jb.selected_index)


func test_a_dpad_press_is_not_latched() -> void:
	## ⛔ THE DANGEROUS DIRECTION. A button emits exactly one pressed event, so latching it would let
	## a stale latch swallow a real press — the stranded-latch shape MenuPaging's own arm caught.
	var jb: Node = await _open()
	jb.selected_index = 0
	jb._input(_dpad())
	jb._input(_dpad(false))
	jb._input(_dpad())
	assert_eq(jb.selected_index, 2, "two d-pad presses must move two rows; the cursor is at %d" % jb.selected_index)


func test_a_restored_cursor_still_accepts_its_first_nudge() -> void:
	## @cowir-controller's unmeasured pair: their conversion sites have no remembered cursor, so a
	## latch surviving a reopen has never met a restore. It does here on every open.
	var first: Node = await _open()
	## Strand the latch FIRST — the push itself steps, which is correct and would otherwise make the
	## restored cursor 41 and the control below assert its own side effect.
	_push(first, 0.9)
	first.selected_index = 40
	first._close_menu()
	await get_tree().process_frame

	var second: Node = await _open()
	assert_eq(second.selected_index, 40, "CONTROL: the cursor was restored, so the nudge below has a subject")
	## NOTE: no _release() here. The stick is still held from before the close — which is the case
	## @cowir-controller named as the one where a swallow is CORRECT. The self-heal fires on the
	## next event that arrives with nothing held, so release first, as a player's hand does.
	_release(second)
	for v in [0.6, 0.9]:
		_push(second, v)
	assert_eq(second.selected_index, 41,
		"the first nudge after a reopen did not step — a stranded latch swallowed it at %d" % second.selected_index)


func test_paging_is_untouched_by_the_conversion() -> void:
	## The shoulders are SEPARATE axes (4 and 5) and route through MenuPaging, not MenuNav.
	var jb: Node = await _open()
	jb.selected_index = 0
	var e := InputEventKey.new()
	e.keycode = KEY_PAGEDOWN
	e.pressed = true
	jb._input(e)
	assert_eq(jb.selected_index, MenuPaging.PAGE_ROWS,
		"a page jump must still move %d rows; it is at %d" % [MenuPaging.PAGE_ROWS, jb.selected_index])


func test_the_step_clamps_at_both_ends() -> void:
	var jb: Node = await _open()
	jb.selected_index = 0
	_push(jb, -0.9)
	assert_eq(jb.selected_index, 0, "the head must not go negative")

	jb.selected_index = jb.TRACKS.size() - 1
	_release(jb)
	_push(jb, 0.9)
	assert_eq(jb.selected_index, jb.TRACKS.size() - 1, "and the tail must not run past the end")
