extends GutTest

## GamepadFilter used to take the FIRST non-ignored pad, so USB enumeration order decided which pad
## became `preferred_device`. struktured has two attached at times — an 8BitDo Ultimate 2 (his stated
## PRIMARY, 2026-07-25) and a Hyperkin Cadet backup — and enumeration order is not a preference.
##
## ⚠️ CORRECTED 2026-07-29. This file previously said a backup pad "could silently take the camera
## away from the pad in his hands." THAT WAS FALSE and I retracted it in GamepadFilter.gd (c94783d2)
## without fixing it here. `preferred_device`'s only consumers are `right_stick_x` / `shoulder_rotate`,
## the input half of Mode 7 camera rotation, which Mode7Overlay.gd deliberately disables (search: "Camera rotation DISABLED"). Nothing
## is being taken, because there is no camera rotation to take.
##
## The ranking is still correct and still worth guarding — it is preparation that will be right the
## day rotation ships. It just does not fix a present-day symptom, and this file should not tell the
## next reader that it does. A guard has two audiences: the header, read while auditing, and the
## assert message, read by whoever just broke it. I corrected the source and left BOTH of this
## file's audiences carrying the retracted claim (cowir-sfx's find, msg 3374, within the hour).
##
## preference_rank is a pure function so this is testable with no hardware attached.

var _filter


func before_each() -> void:
	_filter = load("res://src/input/GamepadFilter.gd").new()


func after_each() -> void:
	if is_instance_valid(_filter):
		_filter.free()


func test_the_8bitdo_outranks_the_hyperkin() -> void:
	# The exact strings Godot reports for struktured's two pads, in both of the 8BitDo's modes.
	var ultimate_a: int = _filter.preference_rank("8BitDo Ultimate 2 Wireless Controller")
	var ultimate_b: int = _filter.preference_rank("8BitDo 8BitDo Ultimate 2 Wireless Controller for PC")
	var hyperkin: int = _filter.preference_rank("NEXT SNES Controller")
	assert_lt(ultimate_a, hyperkin, "the 8BitDo is the stated primary and must outrank the backup")
	assert_lt(ultimate_b, hyperkin, "BOTH 8BitDo modes must outrank it — a mode switch renames the pad")


func test_ranking_is_case_insensitive() -> void:
	assert_eq(_filter.preference_rank("8BITDO ULTIMATE 2"), _filter.preference_rank("8bitdo ultimate 2"),
		"device names are vendor-formatted and inconsistently cased; ranking must not depend on it")


## Preference must never become exclusion — an unknown pad has to stay fully usable, or a guest
## controller silently does nothing and reads as broken hardware.
func test_unknown_pads_rank_last_but_are_still_selectable() -> void:
	var unknown: int = _filter.preference_rank("Some Generic USB Gamepad")
	assert_eq(unknown, _filter.PREFERRED_NAMES.size(), "unlisted pads rank last")
	assert_true(unknown < _filter.PREFERRED_NAMES.size() + 1,
		"must still beat the 'nothing selected' sentinel, or a lone unknown pad would never be picked")


## The axis this file reads is only meaningful once SDL normalizes the pad. It was a bare `2`, and
## before that a `2-5` range that swept in the right stick Y and BOTH triggers.
func test_right_stick_axis_is_a_named_constant_not_a_magic_number() -> void:
	# States the INSTRUCTION (cannot rot) and POINTS at the header for the claim about external
	# state (can). My first version restated the header's claim here too — two copies of one rotting
	# fact, in a fix made specifically to solve the two-audiences problem. cowir-story's refinement:
	# two-audiences is not solved by writing both carefully, it is solved by having ONE copy.
	assert_eq(_filter.RIGHT_STICK_X_AXIS, JOY_AXIS_RIGHT_X,
		"the right-stick capture must read the NAMED axis constant, not a bare number — and see this file's header before assuming a wrong value here would be visible in play")
	var src: String = FileAccess.get_file_as_string("res://src/input/GamepadFilter.gd")
	assert_false(src.contains("e.axis == 2"),
		"no bare axis numbers — an axis index means nothing until SDL maps the device")


## Ignore still beats preference: IGNORED_NAME excludes, PREFERRED_NAMES only orders.
func test_ignore_and_preference_are_separate_concerns() -> void:
	assert_ne(_filter.IGNORED_NAME, "", "the ignore filter is expected to be configured")
	assert_false(_filter.PREFERRED_NAMES.has(_filter.IGNORED_NAME.to_lower()),
		"a name must not be both preferred and ignored")
