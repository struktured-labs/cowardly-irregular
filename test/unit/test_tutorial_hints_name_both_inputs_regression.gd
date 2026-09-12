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


## ⛔ CORRECTED 2026-09-12. This test used to REQUIRE a glyph unconditionally and passed under GUT,
## which attaches no pad — it passed *because* glyph_for_action falls back to the xbox table on an
## empty device name. So it was pinning the defect: a keyboard player was shown "Ⓑ / Z", a glyph
## for hardware they do not have. Three of its asserts ("/ Z", "/ X", has_glyph) each encoded the
## unexamined assumption that a pad is always attached. The both-inputs claim it was written to
## defend is real and still pinned below — it is conditional on a pad, which nobody had checked.
func test_tokens_name_the_key_and_no_glyph_when_no_pad_is_attached() -> void:
	assert_true(Input.get_connected_joypads().is_empty(),
		"precondition: this arm describes the no-pad case, which is what GUT runs as")
	var out := Hints.resolve_tokens("Save with {confirm}, back out with {cancel}.")
	assert_false(out.contains("{"), "every token substituted — a leftover brace ships to the player")
	assert_string_contains(out, "Z", "confirm must still name the keyboard key")
	assert_string_contains(out, "X", "cancel must still name the keyboard key")
	for g in ["Ⓐ", "Ⓑ", "Ⓧ", "Ⓨ", "○", "✕", "□", "△"]:
		assert_false(out.contains(g),
			"'%s' is one family's glyph and no pad is attached — showing it is a guess" % g)


## The both-inputs claim, kept and made conditional: WITH a pad the token names the glyph too.
## Asserted through the resolver's own source since no pad can be attached headless.
func test_with_a_pad_the_token_would_name_the_glyph_beside_the_key() -> void:
	var src := FileAccess.get_file_as_string("res://src/ui/TutorialHints.gd")
	var at := src.find("static func _control_name")
	assert_gt(at, -1, "the resolver must route tokens through the pad-aware helper")
	var stop := src.find("\nstatic func ", at + 10)
	var body := src.substr(at, stop - at) if stop > at else src.substr(at)
	assert_true(body.find("Input.get_connected_joypads().is_empty()") > -1,
		"the helper must branch on a PAD check, not on whether the autoload exists")
	assert_true(body.find("hint_for_action") > -1,
		"and must derive the pad half through hint_for_action, which is pad-guarded internally")


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
