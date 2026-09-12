extends Node

## MouseCursorManager - Auto-show/hide mouse cursor based on input activity.
##
## Behavior (updated 2026-05-03 for kb+mouse hybrid users):
##   - Mouse motion / click  → show cursor immediately
##   - Gamepad input         → hide cursor immediately (gamepad-first)
##   - Keyboard input        → DOES NOT hide cursor any more. Users
##                             commonly use keyboard hotkeys (F2/F3/Esc)
##                             while mousing through menus; the prior
##                             "any kb event = hide" toggled the cursor
##                             on/off jankily during normal play.
##   - Idle 5s after non-mouse activity → optionally hide (off by default
##                             to avoid surprising mouse-first players).

const HIDE_AFTER_IDLE_SEC := 0.0  # 0 = never hide on idle; raise to e.g. 5.0 to enable

## Same value as GamepadFilter.STICK_DEADZONE, and deliberately the same NUMBER rather than an
## import: these are the only two raw-axis readers in src/input/ and they must not disagree.
const STICK_DEADZONE := 0.2

var _last_mouse_activity: float = 0.0


func _ready() -> void:
	# Start with cursor visible — accessible by default. Gamepad input
	# hides it once a controller is actually used.
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _process(_delta: float) -> void:
	if HIDE_AFTER_IDLE_SEC <= 0.0:
		return
	if Input.get_mouse_mode() != Input.MOUSE_MODE_VISIBLE:
		return
	if Time.get_ticks_msec() / 1000.0 - _last_mouse_activity > HIDE_AFTER_IDLE_SEC:
		Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion or event is InputEventMouseButton:
		if Input.get_mouse_mode() != Input.MOUSE_MODE_VISIBLE:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		_last_mouse_activity = Time.get_ticks_msec() / 1000.0
	elif event is InputEventJoypadButton:
		_hide_cursor()
	elif event is InputEventJoypadMotion:
		# ⛔ DEADZONE. This hid the cursor on ANY axis event, and a raw InputEventJoypadMotion is
		# not a deliberate push: resting sticks drift and triggers settle, so a plugged-in pad
		# nobody is touching could hide a mouse-first player's cursor, which every mouse motion
		# then restored. That is the "toggled the cursor on/off jankily during normal play"
		# behaviour this file's own docstring says was fixed for KEYBOARD in 2026-05-03 — the
		# same shape, left on the input that actually emits noise.
		# 0.2 is GamepadFilter.STICK_DEADZONE, reused rather than invented: one deadzone in
		# src/input/, not two that can drift apart.
		if absf((event as InputEventJoypadMotion).axis_value) > STICK_DEADZONE:
			_hide_cursor()


func _hide_cursor() -> void:
	if Input.get_mouse_mode() != Input.MOUSE_MODE_HIDDEN:
		Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
