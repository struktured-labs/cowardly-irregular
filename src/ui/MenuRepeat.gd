extends RefCounted
class_name MenuRepeat

## Hold-to-repeat for menu navigation: hold a direction, it starts stepping on its own
## and accelerates. struktured 2026-08-22.
##
## POLLED, not event-driven, and that is the whole design. A held gamepad d-pad emits ONE
## press event in Godot and never echoes, so `is_echo()` — which 35 files use to suppress
## keyboard rapid-fire — can never produce repeat on a pad. Polling Input.is_action_pressed
## treats keyboard and pad identically and leaves every existing `is_echo()` guard alone,
## so a TAP behaves exactly as it does today. This only ever adds repeats after a hold.

## Tuning. A literal "few seconds" before the first repeat reads as a dead menu, so the
## initial hold is deliberate-but-short; the ramp is what makes a long hold feel fast.
const INITIAL_DELAY := 0.40   ## hold this long before the first auto-step
const SLOW_INTERVAL := 0.16   ## gap between the first auto-steps
const FAST_INTERVAL := 0.05   ## gap once fully ramped
const RAMP_TIME := 0.90       ## seconds of holding over which SLOW -> FAST

var _action: String = ""
var _held: float = 0.0
var _since_step: float = 0.0

## ⛔ INJECTED SO THE UNFOCUSED BRANCH IS DRIVABLE. Headless reports the window as FOCUSED, so a
## test cannot reach that branch through the real query at all. The default IS the real query, and
## an arm pins that the two agree — driving an injected predicate while the shipped one is wired to
## something else tests a workaround's policy instead of the source.
var focused_check: Callable

## Directions this instance watches, in priority order. Vertical first: a diagonal on an
## analog-ish d-pad should not fire two axes in one frame.
var actions: PackedStringArray = ["ui_up", "ui_down", "ui_left", "ui_right"]


func _init(watch: PackedStringArray = PackedStringArray()) -> void:
	if not watch.is_empty():
		actions = watch
	focused_check = _window_focused


func _window_focused() -> bool:
	return DisplayServer.window_is_focused()


## Call once per frame. Returns the action to repeat THIS frame, or "" for nothing.
## Never returns on the frame the key goes down — the menu's own _input owns the first step.
func tick(delta: float) -> String:
	## ⛔ A HELD DIRECTION SURVIVES FOCUS LOSS, AND THIS IS POLLED, SO IT KEPT STEPPING WHILE THE
	## PLAYER WAS IN ANOTHER WINDOW — at FULL ramp, which is faster than while they were watching.
	## Measured before the fix: 21 steps across 2s of holding, then 40 in the next 2s unfocused.
	## `reset()`'s own docstring already asked for this — "call when the menu closes OR LOSES
	## FOCUS" — and no caller existed. Fixed HERE rather than in the twelve menus that own one:
	## a polled guard belongs beside the poll, and twelve call sites is the wrong layer.
	if not focused_check.call():
		reset()
		return ""
	var down := _first_held()
	if down == "":
		reset()
		return ""
	if down != _action:
		# Direction changed mid-hold: restart the delay rather than inheriting the old
		# ramp, or flicking left during a long down-hold would fire instantly.
		_action = down
		_held = 0.0
		_since_step = 0.0
		return ""
	_held += delta
	if _held < INITIAL_DELAY:
		return ""
	_since_step += delta
	if _since_step < _interval():
		return ""
	_since_step = 0.0
	return _action


## Current gap between steps, ramping SLOW -> FAST over RAMP_TIME after the initial delay.
func _interval() -> float:
	var ramped: float = clampf((_held - INITIAL_DELAY) / RAMP_TIME, 0.0, 1.0)
	return lerpf(SLOW_INTERVAL, FAST_INTERVAL, ramped)


func _first_held() -> String:
	for a in actions:
		if InputMap.has_action(a) and Input.is_action_pressed(a):
			return a
	return ""


## Drop the hold. Call when the menu closes or loses focus, so reopening it does not
## inherit a ramp from the last time it was used.
func reset() -> void:
	_action = ""
	_held = 0.0
	_since_step = 0.0


## Exposed for tests and for menus that want to show a ramp indicator.
func held_time() -> float:
	return _held


func current_action() -> String:
	return _action
