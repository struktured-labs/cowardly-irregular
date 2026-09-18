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
##
## ⛔ ONE LATCH PER TRIGGER, AND IT WAS ONE SHARED LATCH UNTIL NOW. The triggers are on SEPARATE
## axes, so holding one must not gate the other — with a single flag, pulling R2 while L2 was held
## returned 0 and that page was lost outright (measured, not inferred). MenuNav carries two latches
## for exactly this reason ("so a vertical hold cannot swallow a horizontal step") and Win98Menu
## gates the same two actions with `_defer_axis_held` / `_advance_axis_held`. This helper — the one
## ten menus page through — collapsed both into one.
static var _defer_axis_held: bool = false
static var _advance_axis_held: bool = false


## -1 = page up, +1 = page down, 0 = not a paging input. PageUp/PageDown, Home/End's neighbours on
## keyboard; L1/R1 or the triggers on gamepad — one page per pull, not one per ramp step.
static func page_delta(event: InputEvent) -> int:
	if event == null or event.is_echo():
		return 0

	# Self-heal: a release that lands while a menu rebuilds, or a menu closing mid-hold, must not
	# strand the latch and swallow the next menu's first page. Same shape as EquipmentMenu's.
	if _defer_axis_held and not Input.is_action_pressed("battle_defer"):
		_defer_axis_held = false
	if _advance_axis_held and not Input.is_action_pressed("battle_advance"):
		_advance_axis_held = false

	## A release branch is safe HERE and is not in MenuNav: ui_up/ui_down share one axis, so a
	## positive-Y event reads as releasing one while pressing the other. These two are axis 4 and
	## axis 5, so a release event means only what it says.
	if event.is_action_released("battle_defer"):
		_defer_axis_held = false
		return 0
	if event.is_action_released("battle_advance"):
		_advance_axis_held = false
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
			if _defer_axis_held:
				return 0
			_defer_axis_held = true
		return -1
	if event.is_action_pressed("battle_advance"):
		if motion:
			if _advance_axis_held:
				return 0
			_advance_axis_held = true
		return 1
	return 0
