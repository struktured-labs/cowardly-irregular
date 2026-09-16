class_name MenuPaging
extends RefCounted

## Shared page-jump input for long scrolling menus (struktured 2026-07-25: "should be a fast scroll
## down feature in menus. settings menu is already huge... or page up/down buttons").
##
## Deliberately NOT a new InputMap action: the controller lane is actively rewriting bindings, and
## L1/R1 already exist as battle_defer/battle_advance. Menus that page are never live during battle,
## so reusing the shoulder actions costs nothing and adds no binding to keep in sync.

## Rows a page jump moves. Roughly a screenful in the menus that use it.
const PAGE_ROWS := 10


## Release-edge gate. battle_defer/battle_advance each carry a BUTTON and an analog TRIGGER axis
## (L2 = axis 4, R2 = axis 5), and an analog ramp emits one event per value change — every one of
## which reads as pressed, because an axis has no echo flag. Measured: a 6-step pull past the
## deadzone returned a page jump FIVE times, i.e. one pull moved 50 rows instead of 10.
## Static because page_delta is static; kept honest by the self-heal at the top of the function.
static var _axis_held: bool = false


## -1 = page up, +1 = page down, 0 = not a paging input. PageUp/PageDown, Home/End's neighbours on
## keyboard; L1/R1 or the triggers on gamepad — one page per pull, not one per ramp step.
static func page_delta(event: InputEvent) -> int:
	if event == null or event.is_echo():
		return 0

	# Self-heal: a release that lands while a menu rebuilds, or a menu closing mid-hold, must not
	# strand the latch and swallow the next menu's first page. Same shape as EquipmentMenu's.
	if _axis_held and not Input.is_action_pressed("battle_defer") \
			and not Input.is_action_pressed("battle_advance"):
		_axis_held = false

	if event.is_action_released("battle_defer") or event.is_action_released("battle_advance"):
		_axis_held = false
		return 0

	# Keyboard paging is not gated: keys carry an echo flag, which the early return above handles.
	if event is InputEventKey and (event as InputEventKey).pressed:
		match (event as InputEventKey).keycode:
			KEY_PAGEUP:
				return -1
			KEY_PAGEDOWN:
				return 1

	# ⛔ THE GATE IS AXIS-ONLY, and that is the measurement rather than a simplification. A BUTTON
	# press emits exactly one pressed event; only an analog ramp emits many. Gating buttons too
	# would leave a stranded latch able to swallow a real press — which is what an earlier draft
	# did, and what the stranded-latch arm caught.
	var motion := event is InputEventJoypadMotion
	if event.is_action_pressed("battle_defer"):
		if motion:
			if _axis_held:
				return 0
			_axis_held = true
		return -1
	if event.is_action_pressed("battle_advance"):
		if motion:
			if _axis_held:
				return 0
			_axis_held = true
		return 1
	return 0
