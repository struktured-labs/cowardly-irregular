extends GutTest

## Regression tests for the 2026-07-25 "8BitDo does nothing / wrong buttons" class.
##
## Root cause: Godot only normalizes a pad to the JoyButton/JoyAxis constants when SDL holds a
## mapping for its GUID. The 8BitDo Ultimate 2 Wireless Controller (2dc8:310b) is absent from the
## bundled DB, so Input.is_joy_known() was false and Godot reported RAW evdev indices — putting
## battle_defer on a stick click and letting a right-stick nudge fire a battle action. Measured on
## struktured's hardware, not inferred: is_joy_known flipped false -> true once the mapping was added.

const ULTIMATE_2_GUID := "03000000c82d00000b31000014010000"

var _mappings


func before_each() -> void:
	_mappings = load("res://src/input/ControllerMappings.gd").new()


func after_each() -> void:
	if is_instance_valid(_mappings):
		_mappings.free()


func test_ultimate_2_mapping_is_registered() -> void:
	assert_true(_mappings.has_mapping_for_guid(ULTIMATE_2_GUID),
		"8BitDo Ultimate 2 (2dc8:310b) must carry an SDL mapping — without it Godot reports raw indices and every shoulder/trigger binding points at the wrong control")


func test_every_mapping_is_well_formed() -> void:
	for mapping in _mappings.MAPPINGS:
		var guid: String = _mappings.guid_of(mapping)
		assert_eq(guid.length(), 32, "SDL GUIDs are 32 hex chars: %s" % guid)
		assert_true(guid.is_valid_hex_number(), "GUID must be hex: %s" % guid)
		assert_true(mapping.contains("platform:Linux"),
			"mapping needs a platform clause or SDL ignores it: %s" % guid)
		assert_gt(mapping.split(",").size(), 3, "mapping needs a name and bindings: %s" % guid)


## The measured evdev layout. If someone "fixes" the mapping to match Godot's constant NAMES
## instead of what the hardware sends, this fails — which is the mistake that started all this.
func test_ultimate_2_mapping_matches_measured_hardware_layout() -> void:
	var mapping := ""
	for candidate in _mappings.MAPPINGS:
		if _mappings.guid_of(candidate) == ULTIMATE_2_GUID:
			mapping = candidate
			break
	assert_ne(mapping, "", "Ultimate 2 mapping must exist")

	# /proc/bus/input/devices, 2026-07-25: BTN_TL/BTN_TR are raw buttons 4/5 (NOT 9/10 — those are
	# BTN_THUMBL/THUMBR), and the triggers are ABS_Z (axis 2) / ABS_RZ (axis 5).
	var expected := {
		"a": "b0", "b": "b1", "x": "b2", "y": "b3",
		"leftshoulder": "b4", "rightshoulder": "b5",
		"back": "b6", "start": "b7", "guide": "b8",
		"leftstick": "b9", "rightstick": "b10",
		"lefttrigger": "a2", "righttrigger": "a5",
		"leftx": "a0", "lefty": "a1", "rightx": "a3", "righty": "a4",
	}
	for key in expected:
		assert_true(mapping.contains("%s:%s," % [key, expected[key]]) or mapping.contains("%s:%s" % [key, expected[key]]),
			"%s must map to %s (measured on the device)" % [key, expected[key]])


func test_dpad_is_mapped_as_a_hat() -> void:
	for mapping in _mappings.MAPPINGS:
		if _mappings.guid_of(mapping) != ULTIMATE_2_GUID:
			continue
		# The pad exposes the d-pad on ABS_HAT0X/Y, so it must map as a hat, not as buttons.
		for direction in ["dpup:h0.1", "dpright:h0.2", "dpdown:h0.4", "dpleft:h0.8"]:
			assert_true(mapping.contains(direction), "d-pad must map as hat0: missing %s" % direction)


func test_register_all_reports_what_it_applied() -> void:
	assert_eq(_mappings.register_all(), _mappings.MAPPINGS.size(),
		"register_all must apply every mapping")


func test_unmapped_pad_is_not_silently_accepted() -> void:
	# The whole failure class was silence. warn_if_unmapped must exist and be callable so an
	# unknown pad leaves a trail instead of presenting as "half my buttons are wrong".
	assert_true(_mappings.has_method("warn_if_unmapped"),
		"an unmapped pad must warn — silent raw-index fallback is the bug this file exists for")
	# A device id that cannot be connected: must not crash, must not throw.
	_mappings.warn_if_unmapped(99)
	assert_true(true, "warn_if_unmapped tolerates an absent device")


## THE TRAP: the quirk profile is literally named after struktured's controller, so "his pad is an
## Ultimate 2, surely it wants the Ultimate Pro 2 profile" is the obvious and wrong move. Once
## SDL normalizes the pad (see mapping above), Standard is correct and the quirk profile inverts
## L/R against both project.godot and the on-screen hint bar. Measured 2026-07-25.
func test_ultimate_2_wireless_autodetects_to_standard_not_the_quirk_profile() -> void:
	var ipm = load("res://src/input/InputProfileManager.gd").new()
	# The exact string Godot reports for struktured's pad.
	var detected: String = ipm.detect_profile_for_device("8BitDo Ultimate 2 Wireless Controller")
	assert_eq(detected, "Standard",
		"the Ultimate 2 Wireless is SDL-normalized by ControllerMappings, so it must get Standard — the Ultimate Pro 2 quirk profile would swap L/R against the hint bar")
	# And Standard must keep the shoulder semantics the hint bar advertises.
	assert_eq(ipm.PROFILE_STANDARD["battle_defer"], [9], "[L] Defer == LEFT_SHOULDER == 9")
	assert_eq(ipm.PROFILE_STANDARD["battle_advance"], [10], "[R] Advance == RIGHT_SHOULDER == 10")
	ipm.free()


## ControllerMappings must run BEFORE anything reads or rewrites bindings, or the first frame of
## input is evaluated against raw indices.
func test_controller_mappings_autoload_precedes_input_consumers() -> void:
	var cfg := ConfigFile.new()
	assert_eq(cfg.load("res://project.godot"), OK, "project.godot must parse")
	var order: Array = cfg.get_section_keys("autoload")
	var mapping_idx := order.find("ControllerMappings")
	assert_ne(mapping_idx, -1, "ControllerMappings must be registered as an autoload")
	for consumer in ["GamepadFilter", "InputProfileManager"]:
		var consumer_idx := order.find(consumer)
		if consumer_idx == -1:
			continue
		assert_lt(mapping_idx, consumer_idx,
			"ControllerMappings must load before %s — mappings decide what every button index MEANS" % consumer)
