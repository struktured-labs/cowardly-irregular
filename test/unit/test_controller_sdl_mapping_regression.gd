extends GutTest

## Regression tests for the 2026-07-25 "8BitDo does nothing / wrong buttons" class.
##
## Root cause: Godot only normalizes a pad to the JoyButton/JoyAxis constants when SDL holds a
## mapping for its GUID. The 8BitDo Ultimate 2 Wireless Controller (2dc8:310b) is absent from the
## bundled DB, so Input.is_joy_known() was false and Godot reported RAW evdev indices — putting
## battle_defer on a stick click and letting a right-stick nudge fire a battle action. Measured on
## struktured's hardware, not inferred: is_joy_known flipped false -> true once the mapping was added.

const ULTIMATE_2_GUID := "03000000c82d00000b31000014010000"
## Same physical pad, D-input mode — a mode switch changes the product id, hence the GUID.
const ULTIMATE_2_DINPUT_GUID := "03000000c82d00001260000011010000"

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


## THE LESSON OF THIS WHOLE INVESTIGATION: one physical controller has SEVERAL identities. A mode
## switch changes the USB product id, which changes the GUID, which silently voids a mapping keyed
## to the other mode. Mapping one mode is not mapping the pad.
func test_both_ultimate_2_modes_are_mapped() -> void:
	assert_true(_mappings.has_mapping_for_guid(ULTIMATE_2_GUID),
		"Ultimate 2 (2dc8:310b) must be mapped")
	assert_true(_mappings.has_mapping_for_guid(ULTIMATE_2_DINPUT_GUID),
		"Ultimate 2 D-input mode (2dc8:6012) must ALSO be mapped — same pad, different product id, different layout")


## D-input mode inserts BTN_C and BTN_Z among the face buttons, shifting everything after them by
## two. Measured on the device 2026-07-25 (struktured pressing each control into /dev/input/event14).
## If someone re-derives this from the other mode's layout, or from convention, this fails.
func test_dinput_mode_matches_measured_hardware_layout() -> void:
	var mapping := ""
	for candidate in _mappings.MAPPINGS:
		if _mappings.guid_of(candidate) == ULTIMATE_2_DINPUT_GUID:
			mapping = candidate
			break
	assert_ne(mapping, "", "D-input mapping must exist")

	var expected := {
		"a": "b0", "b": "b1", "y": "b3", "x": "b4",   # BTN_C=b2 and BTN_Z=b5 are unused extras
		"leftshoulder": "b6", "rightshoulder": "b7",  # 0x136 / 0x137, measured
		"back": "b10", "start": "b11", "guide": "b12",
		"leftstick": "b13", "rightstick": "b14",
		"lefttrigger": "a5", "righttrigger": "a4",    # ABS_BRAKE / ABS_GAS, measured
		"leftx": "a0", "lefty": "a1",
		"rightx": "a2", "righty": "a3",               # ABS_Z / ABS_RZ are the STICK in this mode
	}
	for key in expected:
		assert_true(mapping.contains("%s:%s," % [key, expected[key]]),
			"%s must map to %s (measured on the device, not assumed)" % [key, expected[key]])


## The triggers were the near-miss: ABS_Z/ABS_RZ are the conventional trigger axes on many pads and
## are the RIGHT STICK on this one. Binding them as triggers would put Defer/Advance on a stick nudge.
func test_dinput_triggers_are_not_bound_to_the_right_stick_axes() -> void:
	for mapping in _mappings.MAPPINGS:
		if _mappings.guid_of(mapping) != ULTIMATE_2_DINPUT_GUID:
			continue
		assert_false(mapping.contains("lefttrigger:a2") or mapping.contains("righttrigger:a3"),
			"a2/a3 are the RIGHT STICK in D-input mode — binding them as triggers puts battle actions on a stick nudge")


## A pad mode that yields no input device at all must be documented, so "my controller is dead"
## has an answer instead of costing another full session.
func test_silent_dock_mode_is_documented() -> void:
	assert_true(_mappings.KNOWN_SILENT_MODES.has("2dc8:6013"),
		"the docked/asleep identity must be recorded — it enumerates on USB but builds no input device")


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


## Hardcoded joypad index LISTS are the "in case action mapping fails" reflex that predates having
## correct mappings. They are unreadable (is 9 a shoulder or a stick click? depends on the pad's
## mode), they bypass profiles, and they silently change meaning the moment a mapping is added or
## removed. Both grid editors carried `button_index in [6, 7, 9, 11]` commented as "common Start
## indices" — Start, L3, L1 and D-pad Up under Godot 4. Use named JOY_BUTTON_* or an action.
func test_no_hardcoded_joypad_index_lists() -> void:
	var offenders: Array[String] = []
	for path in _gd_files_under("res://src"):
		var src: String = FileAccess.get_file_as_string(path)
		for line in src.split("\n"):
			var stripped := line.strip_edges()
			if stripped.begins_with("#"):
				continue
			if stripped.contains("button_index in [") and not stripped.contains("MOUSE_BUTTON") \
					and not stripped.contains("JOY_BUTTON"):
				offenders.append("%s: %s" % [path, stripped])
	assert_eq(offenders, [] as Array[String],
		"use named JOY_BUTTON_* constants or an input action, never raw index lists:\n%s" % "\n".join(offenders))


func _gd_files_under(root: String) -> Array[String]:
	var found: Array[String] = []
	var dirs: Array[String] = [root]
	while not dirs.is_empty():
		var current: String = dirs.pop_back()
		var dir := DirAccess.open(current)
		if dir == null:
			continue
		dir.list_dir_begin()
		var entry := dir.get_next()
		while entry != "":
			var full := "%s/%s" % [current, entry]
			if dir.current_is_dir():
				dirs.append(full)
			elif entry.ends_with(".gd"):
				found.append(full)
			entry = dir.get_next()
		dir.list_dir_end()
	return found


## Documents, executably, that the Ultimate Pro 2 quirk profile INVERTS L/R relative to Standard on
## a mapped pad. Not asserting it is wrong — struktured measured it on his own hardware before
## ControllerMappings existed, when an index genuinely did not mean what the constant said. Asserting
## that the relationship is what it is, so "retire it / keep it" stays a decision someone makes on
## evidence rather than a surprise they hit in Settings.
func test_quirk_profile_is_documented_as_inverting_against_standard() -> void:
	var ipm = load("res://src/input/InputProfileManager.gd").new()
	var quirk: Dictionary = ipm.PROFILE_ULTIMATE_PRO_2
	var standard: Dictionary = ipm.PROFILE_STANDARD
	# IF THIS IS RED, READ THIS BEFORE REVERTING ANYTHING. Retire-vs-keep on this profile is an OPEN
	# ruling with struktured (see the note in InputProfileManager). A failure here most likely means
	# that ruling landed — the quirk was aligned with Standard, or the profile was retired — in which
	# case this test is the stale artifact and should be updated or deleted, NOT the change reverted.
	# It exists to stop the inversion changing SILENTLY and unratified, not to defend the inversion.
	var ruling_hint := " — if the retire/align ruling has landed, update THIS TEST, do not revert the change"
	assert_eq(quirk["battle_advance"], standard["battle_defer"],
		"the quirk profile puts Advance on Standard's Defer button — an inversion that was correct for an UNMAPPED pad" + ruling_hint)
	assert_eq(quirk["battle_defer"], standard["battle_advance"],
		"and Defer on Standard's Advance button" + ruling_hint)
	var src: String = FileAccess.get_file_as_string("res://src/input/InputProfileManager.gd")
	assert_true(src.contains("predates ControllerMappings"),
		"the inversion must carry a note explaining WHY it disagrees with the hint bar, or the next reader re-measures it from scratch")
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
