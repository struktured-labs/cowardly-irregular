extends GutTest

## Regression test for the 2026-07-25 "controller not working" playtest report.
##
## Bug: InputProfileManager.active_profile was HARDCODED to "8BitDo Ultimate Pro 2"
## and applied at _ready() to whatever pad was attached. struktured's pad is an
## "8BitDo Ultimate 2 Wireless Controller" — a DIFFERENT device, which xpad
## presents with a bog-standard layout (BTN_A/B/X/Y + BTN_TL/TR + ABS_HAT0), so
## Godot's JoyButton constants were already correct for it.
##
## The Ultimate Pro 2 profile carries a device-specific shoulder quirk
## (advance=9/L, defer=10/R, from a hardware measurement on that other pad).
## Applied to a standard device it INVERTED L/R against project.godot AND
## against the on-screen hint bar ("[L] Defer · [R] Advance"). It also collapsed
## ui_menu from project.godot's [6, 7] down to [6], silently dropping a binding.
##
## Player-visible consequence: tapping L did nothing (it was bound to Advance),
## so the queue-undo and hold-to-confirm affordances on battle_defer were
## unreachable — reported as "I can't find a button for cancel the last Advance".
##
## Fix: PROFILE_STANDARD mirrors project.godot, is the default, and is chosen by
## name-based autodetect for any pad that isn't a known-quirky device.
##
## These assertions are RELATIONSHIP-form on purpose: the standard profile is
## compared against project.godot as parsed at test time, not against copied
## literals. Change one without the other and this fails — which is precisely
## the divergence that shipped.

const ACTIONS := [
	"ui_accept", "ui_cancel", "battle_advance",
	"battle_defer", "battle_toggle_auto", "ui_menu",
]


## Parse project.godot's [input] section for an action's joypad button indices.
func _project_godot_buttons(action: String) -> Array:
	var f := FileAccess.open("res://project.godot", FileAccess.READ)
	assert_not_null(f, "project.godot must be readable")
	var src := f.get_as_text()
	f.close()

	var start := src.find("\n%s={" % action)
	assert_true(start != -1, "project.godot must define action '%s'" % action)
	# Action blocks end at the first line that is exactly "}".
	var end := src.find("\n}", start)
	var block := src.substr(start, end - start)

	var out: Array = []
	var re := RegEx.new()
	re.compile('InputEventJoypadButton[^)]*?"button_index":(\\d+)')
	for m in re.search_all(block):
		out.append(int(m.get_string(1)))
	out.sort()
	return out


func test_standard_profile_matches_project_godot_exactly() -> void:
	for action in ACTIONS:
		var baseline := _project_godot_buttons(action)
		assert_true(
			InputProfileManager.PROFILE_STANDARD.has(action),
			"PROFILE_STANDARD must cover '%s'" % action
		)
		var profile: Array = (InputProfileManager.PROFILE_STANDARD[action] as Array).duplicate()
		profile.sort()
		assert_eq(
			profile, baseline,
			"PROFILE_STANDARD['%s'] must equal project.godot's binding — a remap that " % action
			+ "disagrees with the baseline silently overrides correct bindings at runtime"
		)


## The specific inversion struktured hit: L must defer, R must advance.
func test_standard_profile_shoulders_match_the_hint_bar() -> void:
	# Godot 4 JoyButton: 9 = LEFT_SHOULDER, 10 = RIGHT_SHOULDER.
	assert_eq(
		InputProfileManager.PROFILE_STANDARD["battle_defer"], [9],
		"hint bar promises '[L] Defer' — battle_defer must be LEFT_SHOULDER (9)"
	)
	assert_eq(
		InputProfileManager.PROFILE_STANDARD["battle_advance"], [10],
		"hint bar promises '[R] Advance' — battle_advance must be RIGHT_SHOULDER (10)"
	)


func test_standard_profile_keeps_both_ui_menu_buttons() -> void:
	assert_eq(
		(InputProfileManager.PROFILE_STANDARD["ui_menu"] as Array).size(), 2,
		"_replace_joypad_buttons is destructive — a profile listing fewer buttons than "
		+ "project.godot silently DROPS the omitted ones (ui_menu lost button 7 this way)"
	)


func test_strukturers_actual_pad_autodetects_to_standard() -> void:
	# Verbatim string from Input.get_joy_name() in the 2026-07-25 boot log.
	assert_eq(
		InputProfileManager.detect_profile_for_device("8BitDo Ultimate 2 Wireless Controller"),
		"Standard",
		"'Ultimate 2' must NOT match the 'Ultimate Pro 2' profile — they are different devices"
	)


func test_known_quirky_devices_still_get_their_profiles() -> void:
	assert_eq(
		InputProfileManager.detect_profile_for_device("8BitDo Ultimate Pro 2"),
		"8BitDo Ultimate Pro 2",
		"the measured Ultimate Pro 2 shoulder quirk must survive for that actual device"
	)
	assert_eq(
		InputProfileManager.detect_profile_for_device("8BitDo SN30 Pro"),
		"8BitDo SN30", "SN30 must still autodetect"
	)


func test_unknown_devices_fall_back_to_standard() -> void:
	for name in ["Xbox 360 Controller", "Sony DualSense", "", "Generic USB Gamepad"]:
		assert_eq(
			InputProfileManager.detect_profile_for_device(name), "Standard",
			"unknown pad '%s' must get Standard, never a device-specific quirk profile" % name
		)


func test_every_profile_name_resolves_to_bindings() -> void:
	for profile_name in InputProfileManager.PROFILE_NAMES:
		var bindings: Dictionary = InputProfileManager.get_profile_bindings(profile_name)
		assert_false(
			bindings.is_empty(),
			"profile '%s' is offered in PROFILE_NAMES but resolves to no bindings" % profile_name
		)
