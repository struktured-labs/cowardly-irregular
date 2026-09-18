extends GutTest

## `test_gamepad_preferred_device_regression` pins `preference_rank` — that an 8BitDo outranks the
## backup, that ranking is case-insensitive, that an unlisted pad still ranks ahead of the sentinel.
## Every one of those is about the RANKING's arithmetic, and the ranking is a pure function.
##
## ⛔ NOTHING PINNED WHAT THE RANKING IS FOR, AND THAT IS WHERE IT WAS BROKEN. GamepadFilter's own
## header says it exists because "USB enumeration order must not decide which one steers the camera
## when both are attached" — and `_input`, which captures the right stick, read EVERY device:
##
##   _process   shoulder fallback    is_joy_button_pressed(preferred_device, …)   gated ✅
##   _input     the right stick      no device check at all                       ⛔
##
## So the fallback obeyed the ranking and the primary axis ignored it. A backup pad's stick steered
## whatever the ranking said. Both the source comment and the other guard's header called
## `right_stick_x` a consumer of `preferred_device`; it read the field nowhere.
##
## ⚠️ SCOPE, in this file's own words rather than inherited: Mode 7 rotation is disabled, so nothing
## reads `right_stick_x` today and no player can see this. It is a SEAM defect. GamepadFilter's
## header argues the ranking is worth keeping because "it will be right on the day the feature turns
## on" — that argument is the entire reason this is worth fixing, and it is the only claim made here.

const FilterScript := preload("res://src/input/GamepadFilter.gd")

const PRIMARY := 0
const BACKUP := 1


func _motion(device: int, axis: int, value: float) -> InputEventJoypadMotion:
	var ev := InputEventJoypadMotion.new()
	ev.device = device
	ev.axis = axis
	ev.axis_value = value
	return ev


## Built by hand rather than via _scan_controllers, which needs real hardware to enumerate.
func _filter_preferring(device: int) -> Node:
	var f: Node = FilterScript.new()
	f.preferred_device = device
	return f


func test_only_the_preferred_pad_steers() -> void:
	var f: Node = _filter_preferring(PRIMARY)
	autofree(f)

	## CONTROL FIRST: the preferred pad must move it, or every assert below passes on a filter
	## that simply ignores everything — which is the same green as a correct one.
	f._input(_motion(PRIMARY, f.RIGHT_STICK_X_AXIS, 0.9))
	assert_almost_eq(f.right_stick_x, 0.9, 0.001,
		"CONTROL: the preferred pad must steer, or the arms below measure a filter that drops all input")

	f.right_stick_x = 0.0
	f._input(_motion(BACKUP, f.RIGHT_STICK_X_AXIS, 0.9))
	assert_eq(f.right_stick_x, 0.0,
		"a NON-preferred pad must not steer the camera — that is the whole reason the ranking exists, "
		+ "and the ranking cannot enforce it if the primary axis never reads preferred_device")


func test_the_deadzone_still_applies_to_the_preferred_pad() -> void:
	var f: Node = _filter_preferring(PRIMARY)
	autofree(f)
	f._input(_motion(PRIMARY, f.RIGHT_STICK_X_AXIS, 0.9))
	assert_almost_eq(f.right_stick_x, 0.9, 0.001, "CONTROL: a real push registers")

	## ⛔ THE DEVICE GATE MUST NOT SWALLOW THE CENTRING EVENT. Returning early for a
	## below-deadzone value instead of writing 0.0 would leave the stick stuck at its last push.
	f._input(_motion(PRIMARY, f.RIGHT_STICK_X_AXIS, 0.05))
	assert_eq(f.right_stick_x, 0.0, "a drift-sized value from the preferred pad must CENTRE it, not be ignored")


func test_another_axis_on_the_preferred_pad_is_ignored() -> void:
	var f: Node = _filter_preferring(PRIMARY)
	autofree(f)
	f._input(_motion(PRIMARY, JOY_AXIS_RIGHT_Y, 0.9))
	assert_eq(f.right_stick_x, 0.0,
		"only the named right-stick X axis drives rotation — this line once accepted a 2-5 range "
		+ "and swept in the right stick Y and both triggers")


## With no pad selected there is nothing to prefer, and accepting input would mean the first pad to
## emit an event steers — the enumeration-order behaviour the ranking replaced.
func test_nothing_steers_when_no_pad_is_selected() -> void:
	var f: Node = _filter_preferring(-1)
	autofree(f)
	f._input(_motion(PRIMARY, f.RIGHT_STICK_X_AXIS, 0.9))
	assert_eq(f.right_stick_x, 0.0, "with preferred_device unset, no pad may steer")


## ⛔ AN UNPLUG DELIVERS NO CENTRING EVENT. `_input` only hears pads that are still attached, so a
## stick released by being unplugged mid-push would rotate the camera forever. A rescan is the one
## moment the filter knows the previous device's last word is no longer valid.
func test_a_rescan_forgets_the_previous_pads_last_push() -> void:
	var f: Node = _filter_preferring(PRIMARY)
	autofree(f)
	f._input(_motion(PRIMARY, f.RIGHT_STICK_X_AXIS, 0.9))
	assert_almost_eq(f.right_stick_x, 0.9, 0.001, "CONTROL: the push must land before the rescan clears it")

	f._scan_controllers()
	assert_eq(f.right_stick_x, 0.0,
		"a rescan must clear the axis: the pad that pushed it may be gone, and no centring event "
		+ "will ever arrive from a device that is no longer attached")
