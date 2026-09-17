extends GutTest

## `battle_defer` / `battle_advance` each carry a BUTTON and an analog TRIGGER axis — L2 is axis 4,
## R2 is axis 5. An analog ramp emits one event per value change, and every one of them reads as
## PRESSED, because an axis carries no echo flag. So one trigger pull paged repeatedly.
##
## MEASURED before the fix, a 6-step pull past the 0.5 deadzone:
##     is_action_pressed true 5 times · page_delta non-zero 5 times
## At PAGE_ROWS = 10 that is 50 rows on one pull — a third of the Jukebox's 161 tracks.
##
## ⛔ THE PROJECT ALREADY KNEW. Win98Menu gates `_defer_axis_held` / `_advance_axis_held` with the
## comment "an L2 analog ramp emits a BURST of pressed events (no echo flag on axes) — only the
## first counts until a genuine release", and EquipmentMenu carries the same gate for character
## cycling. Both are per-menu. MenuPaging — the shared helper TEN menus page through — had none.
##
## The gate is static because page_delta is static; what keeps that safe is the self-heal at the
## top of the function, which is why these arms hold the action down rather than only feeding
## events: with nothing actually held, the self-heal correctly clears the latch on the next event.

const DEADZONE_RAMP := [0.55, 0.7, 0.85, 0.95, 1.0]


## The latch is cleared through the PUBLIC path — a release event — rather than by touching the
## private static. Reaching into it would make this file fail to COMPILE against the version being
## defended against, so the "does it red on the old code" check could not be run at all. Measured:
## the first draft did exactly that and the whole script was dropped, EC=3, nothing ran.
func _clear_latch() -> void:
	Input.action_release("battle_defer")
	Input.action_release("battle_advance")
	var rel := InputEventJoypadButton.new()
	rel.button_index = _bound_button("battle_defer")
	rel.pressed = false
	MenuPaging.page_delta(rel)


func before_each() -> void:
	_clear_latch()


func after_each() -> void:
	_clear_latch()


func _motion(axis: int, value: float) -> InputEventJoypadMotion:
	var ev := InputEventJoypadMotion.new()
	ev.axis = axis
	ev.axis_value = value
	return ev


func _button(index: int, pressed: bool) -> InputEventJoypadButton:
	var ev := InputEventJoypadButton.new()
	ev.button_index = index
	ev.pressed = pressed
	return ev


## ⛔ THE BOUND INDEX IS READ FROM THE InputMap, NEVER HARDCODED. Eight test files apply controller
## profiles, and InputProfileManager._replace_joypad_buttons ERASES an action's joypad events and
## re-adds them at the profile's indices. battle_defer and battle_advance are both in
## REMAPPABLE_ACTIONS, so in a batch run the default index is NOT a fact about the tree.
## Measured: after a profile moves battle_defer from the left shoulder to the right, an event
## carrying the old index stops reading as that action and every button arm here returns 0. That
## is what redded gate 222, and this file passed ALONE because nothing had remapped anything.
func _bound_button(action: String) -> int:
	for e in InputMap.action_get_events(action):
		if e is InputEventJoypadButton:
			return (e as InputEventJoypadButton).button_index
	return -1


func _key(code: int) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.pressed = true
	return ev


## ANTI-VACUITY, and it must come first: if the synthetic ramp does not read as pressed at all,
## every "exactly once" assert below would pass over nothing.
func test_the_ramp_really_does_read_as_a_burst_of_presses() -> void:
	var pressed := 0
	for v in DEADZONE_RAMP:
		if _motion(JOY_AXIS_TRIGGER_LEFT, v).is_action_pressed("battle_defer"):
			pressed += 1
	assert_gt(pressed, 1,
		"the fixture must reproduce the burst — %d of %d ramp steps read as pressed"
			% [pressed, DEADZONE_RAMP.size()])


## ⛔ THE DEFECT.
func test_one_trigger_pull_pages_exactly_once() -> void:
	Input.action_press("battle_defer")
	var jumps := 0
	for v in DEADZONE_RAMP:
		if MenuPaging.page_delta(_motion(JOY_AXIS_TRIGGER_LEFT, v)) != 0:
			jumps += 1
	assert_eq(jumps, 1,
		"a single pull must page once; every ramp step past the deadzone used to count")


func test_the_other_trigger_pages_exactly_once_too() -> void:
	Input.action_press("battle_advance")
	var jumps := 0
	for v in DEADZONE_RAMP:
		if MenuPaging.page_delta(_motion(JOY_AXIS_TRIGGER_RIGHT, v)) != 0:
			jumps += 1
	assert_eq(jumps, 1, "the advance trigger is gated the same way")


func test_a_genuine_release_arms_the_next_pull() -> void:
	Input.action_press("battle_defer")
	assert_eq(MenuPaging.page_delta(_motion(JOY_AXIS_TRIGGER_LEFT, 0.9)), -1, "first pull pages")
	assert_eq(MenuPaging.page_delta(_motion(JOY_AXIS_TRIGGER_LEFT, 1.0)), 0, "…and the ramp does not")

	Input.action_release("battle_defer")
	MenuPaging.page_delta(_motion(JOY_AXIS_TRIGGER_LEFT, 0.0))
	Input.action_press("battle_defer")
	assert_eq(MenuPaging.page_delta(_motion(JOY_AXIS_TRIGGER_LEFT, 0.9)), -1,
		"after a real release the next pull pages again — the gate must not be a one-shot")


func test_the_shoulder_button_still_pages() -> void:
	var defer_btn := _bound_button("battle_defer")
	var advance_btn := _bound_button("battle_advance")
	assert_gt(defer_btn, -1, "precondition: battle_defer must be bound to SOME joypad button")
	assert_gt(advance_btn, -1, "precondition: battle_advance must be bound to SOME joypad button")

	Input.action_press("battle_defer")
	assert_eq(MenuPaging.page_delta(_button(defer_btn, true)), -1,
		"the bound shoulder is the documented control and must still page")
	Input.action_release("battle_defer")
	MenuPaging.page_delta(_button(defer_btn, false))
	Input.action_press("battle_advance")
	assert_eq(MenuPaging.page_delta(_button(advance_btn, true)), 1, "…and the other one pages forward")


## Keyboard paging is NOT gated, and must not be: keys carry an echo flag, so a hold is already
## suppressed, and two deliberate presses are two pages.
func test_two_keyboard_presses_are_two_pages() -> void:
	assert_eq(MenuPaging.page_delta(_key(KEY_PAGEDOWN)), 1, "PageDown pages")
	assert_eq(MenuPaging.page_delta(_key(KEY_PAGEDOWN)), 1,
		"a second deliberate press pages again — the axis gate must not catch the keyboard")


## What makes a STATIC latch safe. A menu that closes mid-hold leaves it set; the next event must
## clear it rather than swallowing the next menu's first page.
## The self-heal, which the stranded-latch arm above does NOT cover: that one recovers because the
## gate is axis-only and a button is never gated. This one pins the heal itself — a stale latch
## must not swallow a later TRIGGER pull either. Added after a mutation removing the self-heal
## came back fully green.
func test_a_stranded_latch_does_not_swallow_a_later_trigger_pull() -> void:
	Input.action_press("battle_defer")
	assert_eq(MenuPaging.page_delta(_motion(JOY_AXIS_TRIGGER_LEFT, 0.9)), -1, "precondition: the pull paged")
	Input.action_release("battle_defer")          # released with NO menu listening for the release

	# An UNRELATED event arrives while nothing is held — this is the moment the heal exists for.
	# ⚠️ Not a zero-value motion: that IS an is_action_released event (measured), so it would clear
	# the latch through the release branch and this arm would pass with the heal deleted.
	var unrelated := InputEventKey.new()
	unrelated.keycode = KEY_DOWN
	unrelated.pressed = true
	assert_eq(MenuPaging.page_delta(unrelated), 0, "an unrelated key pages nothing")

	Input.action_press("battle_defer")
	assert_eq(MenuPaging.page_delta(_motion(JOY_AXIS_TRIGGER_LEFT, 0.9)), -1,
		"the next genuine pull must page — a stale latch would have eaten it")


func test_a_stranded_latch_heals_itself() -> void:
	# Strand it the way a menu actually does: pull the trigger, then have the menu go away before
	# the release event is delivered. No private state is touched.
	Input.action_press("battle_defer")
	assert_eq(MenuPaging.page_delta(_motion(JOY_AXIS_TRIGGER_LEFT, 0.9)), -1, "precondition: the pull paged")
	Input.action_release("battle_defer")          # the player let go; the release event went nowhere

	assert_false(Input.is_action_pressed("battle_defer"), "precondition: nothing is actually held")
	Input.action_press("battle_defer")
	assert_eq(MenuPaging.page_delta(_button(_bound_button("battle_defer"), true)), -1,
		"a stale latch must not eat the first page of the next menu")
