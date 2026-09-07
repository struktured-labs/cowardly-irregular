extends GutTest

## Tutorial hints hardcoded gamepad-only button names: "press A to save", "Use D-pad or left
## stick to move", "Confirm with A/Z".
##
## Two defects in one string. A keyboard player was never told a key for movement at all, and
## "A" names the button that CANCELS on any pad whose east face is printed B — which is every
## Xbox pad, i.e. the Windows demo audience. Nothing crashed; the text simply lied.
##
## Hints now carry tokens resolved at display time to BOTH the printed glyph and the key.

const Hints = preload("res://src/ui/TutorialHints.gd")


func test_no_hint_body_hardcodes_a_face_button_letter() -> void:
	# The regression itself: a bare "press A" / "with A/Z" in an authored body.
	var offenders: Array[String] = []
	for id in Hints.HINTS:
		var body: String = str(Hints.HINTS[id].get("body", ""))
		for bad in ["press A ", "Press A ", "with A/Z", "with B/X", "D-pad or left stick"]:
			if body.contains(bad):
				offenders.append("%s: '%s'" % [id, bad])
	assert_eq(offenders, [] as Array[String],
		"hint bodies naming a fixed face-button letter (wrong on pads whose east face isn't A)")


func test_movement_hint_mentions_a_keyboard_input() -> void:
	var body: String = Hints.resolve_tokens(str(Hints.HINTS["movement"]["body"]))
	assert_string_contains(body.to_lower(), "arrow keys",
		"a keyboard player must be told how to walk — the original said only D-pad/stick")


func test_tokens_resolve_to_both_a_glyph_and_a_key() -> void:
	var out := Hints.resolve_tokens("Save with {confirm}, back out with {cancel}.")
	assert_false(out.contains("{"), "every token substituted — a leftover brace ships to the player")
	assert_string_contains(out, "/ Z", "confirm names the keyboard key")
	assert_string_contains(out, "/ X", "cancel names the keyboard key")
	# The glyph half: one of the three families' east-face glyphs must be present.
	var has_glyph := out.contains("Ⓐ") or out.contains("Ⓑ") or out.contains("○")
	assert_true(has_glyph, "confirm names the button printed on the pad as well as the key")


func test_unknown_tokens_are_left_alone_not_blanked() -> void:
	# A typo'd token should be visible in review, not silently deleted into a gap.
	var out := Hints.resolve_tokens("Press {nonexistent} now.")
	assert_string_contains(out, "{nonexistent}", "unrecognised tokens survive rather than vanishing")


func test_every_token_used_in_a_hint_body_actually_resolves() -> void:
	# Guards the other direction: a body using {jump} would ship a literal brace to the player.
	var unresolved: Array[String] = []
	for id in Hints.HINTS:
		var out: String = Hints.resolve_tokens(str(Hints.HINTS[id].get("body", "")))
		if out.contains("{"):
			unresolved.append(id)
	assert_eq(unresolved, [] as Array[String],
		"hint bodies containing a token the resolver does not know")
