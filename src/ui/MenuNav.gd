class_name MenuNav
extends RefCounted

## Shared cursor-step reader for menus, with the analog latch `MenuPaging` needed for the triggers.
##
## ui_up/ui_down bind the LEFT STICK'S Y axis and ui_left/ui_right its X axis, alongside the d-pad
## buttons. An axis carries no echo flag, so a stick push emits one event per value change and EVERY
## one of them reads as pressed. Measured on a six-step ramp past the 0.5 deadzone: `is_action_pressed`
## true 5 times, and a menu's usual `is_action_pressed(...) and not event.is_echo()` guard takes all
## five — five cursor rows on one nudge.
##
## The project already latches a stick for this reason: AutogrindGridEditor._handle_value_stick
## carries `_value_stick_latched` at a 0.6 deadzone for the RIGHT stick. The left stick, which every
## menu navigates with, had no latch anywhere.
##
## Buttons are NOT latched, and that is measured rather than tidy: a d-pad press emits exactly one
## pressed event. Latching them would let a stale latch swallow a real press — the mistake
## MenuPaging's stranded-latch arm caught.

## Directions this reads, in the order a diagonal resolves.
const DIRECTIONS := ["ui_up", "ui_down", "ui_left", "ui_right"]

## One latch per axis pair, so a vertical hold cannot swallow a horizontal step.
static var _v_axis_held: bool = false
static var _h_axis_held: bool = false


## ⛔ step() CONSUMES. It looks like a pure query and is not: on an analog event it SETS the latch
## as a side effect, so calling it TWICE for one event returns "" the second time and that step is
## silently dropped. Call it ONCE per event, per handler.
##
## FOUR menus have two call sites, and each is safe for a reason that lives in THAT file, not here:
## JobMenu, ItemsMenu and EquipmentMenu have one per mode handler; SettingsMenu dispatches to the
## quit-confirm's own handler and RETURNS before its main chain. All four are mutually exclusive, so
## exactly one runs per event — but that is a property of where their early returns sit.
##
## ⛔ THIS SAID "Five menus … and DialogueChoiceMenu", A FILE THAT NO LONGER EXISTS IN THE TREE. The
## count and the membership both went stale the ordinary way: a sibling change moved the world under
## a sentence nobody re-reads because it reads as settled. "A menu that reads a direction in two
## places on ONE path loses the second, and no guard would see it" — that part was TRUE, and it is
## why `test_a_second_step_on_one_path_is_lost` now derives this set instead of asserting it here.
##
## The direction this event steps, or "" for nothing. Buttons and keys pass straight through;
## an analog push steps ONCE until it returns past the deadzone.
static func step(event: InputEvent) -> String:
	if event == null or event.is_echo():
		return ""

	# Self-heal: a menu closing mid-push must not strand a latch and swallow the next menu's
	# first step. Same shape as MenuPaging's and EquipmentMenu's.
	if _v_axis_held and not Input.is_action_pressed("ui_up") and not Input.is_action_pressed("ui_down"):
		_v_axis_held = false
	if _h_axis_held and not Input.is_action_pressed("ui_left") and not Input.is_action_pressed("ui_right"):
		_h_axis_held = false

	# ⛔ NO is_action_released BRANCH HERE, and the reason is measured: ui_up and ui_down share ONE
	# axis, so a positive-Y event reads as RELEASING ui_up while it presses ui_down. A release
	# branch therefore cleared the latch on every ramp step and the gate did nothing — 5 steps, not
	# 1. The state poll above is the correct clear: it asks what is actually held rather than what
	# one event claims to have released.

	var motion := event is InputEventJoypadMotion
	for dir in DIRECTIONS:
		if not event.is_action_pressed(dir):
			continue
		var vertical: bool = (dir == "ui_up" or dir == "ui_down")
		if motion:
			if vertical:
				if _v_axis_held:
					return ""
				_v_axis_held = true
			else:
				if _h_axis_held:
					return ""
				_h_axis_held = true
		return dir
	return ""
