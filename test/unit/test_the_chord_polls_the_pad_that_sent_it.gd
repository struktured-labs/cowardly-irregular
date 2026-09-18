extends GutTest

## ⛔ THE L+R CHORD POLLED DEVICE 0 WHILE THE EVENT CAME FROM WHATEVER PAD PRESSED IT.
## `Input.is_joy_button_pressed(0, …)` in two places — `AutogrindInputHelper.classify_event` and
## GameLoop's live AUTOGRIND branch — so with the player's pad at any other index the chord's
## `button_index` check passes, the poll on device 0 comes back false, and the tier/dashboard
## toggle silently does nothing.
##
## 🔑 REACHABLE, AND THE CODEBASE RECORDS IT HAPPENING HERE: GamepadFilter's docstring describes a
## second pad ("NEXT SNES Controller") enumerating FIRST and winning `preferred_device`, and
## struktured runs an 8BitDo primary with a Hyperkin backup. Two pads attached is the ordinary case
## for this machine, not a hypothetical.
##
## 🔑 AND A CORRECT SIBLING ALREADY EXISTED: GamepadFilter polls this same L1/R1 pair with
## `preferred_device`, and RadialPicker reads its axes with `event.device`. Two of four device
## consumers resolved the pad; two hardcoded 0.
##
## ⚠️ HEADLESS HAS NO JOYPADS, so `is_joy_button_pressed` answers false for every index and the two
## versions are indistinguishable by their RETURN. These arms use Input.parse_input_event to put a
## synthetic device into the real Input state — the same seam the stick-latch suite needed — and a
## CONTROL proves that seam works before any arm relies on it.

const HELPER := preload("res://src/ui/autogrind/AutogrindInputHelper.gd")
const PAD := 1   ## deliberately NOT 0 — the whole point


func _btn(device: int, index: int, pressed: bool) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.device = device
	e.button_index = index
	e.pressed = pressed
	return e


func _hold_both(device: int) -> void:
	Input.parse_input_event(_btn(device, JOY_BUTTON_LEFT_SHOULDER, true))
	Input.parse_input_event(_btn(device, JOY_BUTTON_RIGHT_SHOULDER, true))
	Input.flush_buffered_events()


func after_each() -> void:
	for d in [0, PAD]:
		Input.parse_input_event(_btn(d, JOY_BUTTON_LEFT_SHOULDER, false))
		Input.parse_input_event(_btn(d, JOY_BUTTON_RIGHT_SHOULDER, false))
	Input.flush_buffered_events()


## ⛔ THE SEAM CONTROL. If parse_input_event does not reach is_joy_button_pressed for a synthetic
## device, every arm below passes for the wrong reason — a chord that never registers looks
## identical to a chord correctly refused.
func test_the_synthetic_device_reaches_the_input_state() -> void:
	_hold_both(PAD)
	assert_true(Input.is_joy_button_pressed(PAD, JOY_BUTTON_LEFT_SHOULDER),
		"parse_input_event does not reach is_joy_button_pressed for device %d — the arms below "
		% PAD + "cannot distinguish the fix from the bug")
	assert_true(Input.is_joy_button_pressed(PAD, JOY_BUTTON_RIGHT_SHOULDER),
		"the second shoulder did not register on device %d" % PAD)


## The defect, directly: both shoulders held on a NON-ZERO pad must read as the chord.
func test_the_chord_registers_on_a_pad_that_is_not_device_zero() -> void:
	_hold_both(PAD)
	var verdict: String = HELPER.classify_event(_btn(PAD, JOY_BUTTON_RIGHT_SHOULDER, true))
	assert_eq(verdict, "tier_cycle",
		"both shoulders are held on pad %d and the chord did not register — the poll is looking at "
		% PAD + "device 0, so a player whose pad is not index 0 cannot reach this control at all")


## ANTI-OVERCORRECTION: one shoulder is not the chord. A fix that always returned tier_cycle would
## pass the arm above and break every single-shoulder press.
func test_one_shoulder_is_not_the_chord() -> void:
	Input.parse_input_event(_btn(PAD, JOY_BUTTON_LEFT_SHOULDER, true))
	Input.flush_buffered_events()
	var verdict: String = HELPER.classify_event(_btn(PAD, JOY_BUTTON_LEFT_SHOULDER, true))
	assert_ne(verdict, "tier_cycle",
		"a single shoulder registered as the two-button chord")


## And the chord must not fire from a pad that is NOT holding it — polling the sending device is
## the claim, not polling any device that happens to be held.
func test_a_different_pad_holding_both_does_not_fire_the_chord() -> void:
	_hold_both(PAD)
	var verdict: String = HELPER.classify_event(_btn(0, JOY_BUTTON_RIGHT_SHOULDER, true))
	assert_ne(verdict, "tier_cycle",
		"device 0 sent the event while only pad %d holds the shoulders — the chord must follow the "
		% PAD + "pad that sent it, not any pad that happens to be held")


## ⛔ RATCHET: no joypad poll in src/ may hardcode a device index. Two of four consumers did.
func test_no_joypad_poll_hardcodes_a_device() -> void:
	var GdSource = load("res://test/unit/helpers/gd_source.gd")
	var offenders: Array = []
	var scanned := 0
	for path in _gd_files("res://src"):
		var code: String = GdSource.code_of(path)
		if code == "":
			continue
		scanned += 1
		for probe in ["is_joy_button_pressed(0", "get_joy_axis(0", "get_joy_name(0"]:
			if code.contains(probe):
				offenders.append("%s: %s" % [path.get_file(), probe])
	assert_gt(scanned, 100, "CONTROL: the scan must read the src tree, or this arm is vacuous")
	assert_true(offenders.is_empty(),
		"these poll a hardcoded joypad index — the player's pad is not always device 0, and "
		+ "GamepadFilter's docstring records a second pad enumerating first on this machine: %s"
			% [offenders])


func _gd_files(dir_path: String) -> Array:
	var out: Array = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		var full := dir_path.path_join(name)
		if dir.current_is_dir():
			out.append_array(_gd_files(full))
		elif name.ends_with(".gd"):
			out.append(full)
		name = dir.get_next()
	dir.list_dir_end()
	return out
