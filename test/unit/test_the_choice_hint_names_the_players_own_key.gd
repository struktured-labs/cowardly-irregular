extends GutTest

## A keyboard player was shown an Xbox glyph on every dialogue choice.
##
## `glyph_for_action` resolves an absent device by asking the family table, and
## `face_family_for_device("")` returns "xbox" — correct for an UNKNOWN pad, a
## silent lie for NO pad. One function answering two questions.
##
## The existing guard (test_choice_and_key_item_hint_glyph_regression) pins both
## pad families exactly and never asks what a player with no pad sees, so the
## defect sat inside a green test about the very string it appears in.
##
## TOKENISE, not SWAP. The naive repair is `hint_for_action`, which returns the
## KEYBOARD KEY with no pad — and this caption already prints `Enter`, so that
## renders "[Enter/Enter/Click]". The glyph here sits BESIDE a printed key, so
## the fix is to drop the token and its separator, not to substitute a sibling.

const XBOX := "Xbox Wireless Controller"
const NINTENDO := "8BitDo SN30 Pro"

## Every face glyph InputProfileManager can emit, across all four families.
const FACE_GLYPHS: Array[String] = ["Ⓐ", "Ⓑ", "Ⓧ", "Ⓨ", "✕", "○", "□", "△"]


# ── the premise ───────────────────────────────────────────────────────────────

func test_the_no_pad_case_is_actually_reachable_here() -> void:
	## CONTROL, and it is load-bearing: every assert below is vacuous if this
	## runner has a pad attached. A zero is worth nothing until the probe has
	## proven it can be non-zero.
	assert_true(Input.get_connected_joypads().is_empty(),
		"this suite asserts the NO-PAD render — with a pad attached the rest measures nothing")


# ── the defect ────────────────────────────────────────────────────────────────

func test_a_keyboard_player_is_never_shown_a_pad_glyph() -> void:
	var hint: String = DialogueChoiceMenu.hint_text(true, "")
	for g in FACE_GLYPHS:
		assert_eq(hint.find(g), -1,
			"no pad attached, yet the hint prints '%s' — a button this player does not have: %s" % [g, hint])


func test_the_story_choice_variant_is_clean_too() -> void:
	## `can_cancel = false` is its own return and had its own copy of the glyph.
	var hint: String = DialogueChoiceMenu.hint_text(false, "")
	for g in FACE_GLYPHS:
		assert_eq(hint.find(g), -1,
			"the story-choice hint prints '%s' with no pad attached: %s" % [g, hint])


func test_the_keyboard_player_is_still_told_what_to_press() -> void:
	## Dropping the glyph must not leave an empty bracket — the keys were always
	## there beside it, and they are what this player actually uses.
	var hint: String = DialogueChoiceMenu.hint_text(true, "")
	assert_true(hint.find("Enter") != -1, "confirm must still name Enter: %s" % hint)
	assert_true(hint.find("Esc") != -1, "cancel must still name Esc: %s" % hint)
	assert_eq(hint.find("[/"), -1, "a dropped token must take its separator with it, not leave '[/': %s" % hint)
	assert_eq(hint.find("//"), -1, "and must never double the separator: %s" % hint)


# ── the pad renders must not move ─────────────────────────────────────────────

func test_a_pad_player_still_sees_their_own_cap() -> void:
	## CONTROL: this fix drops a glyph for players who have no pad. It must not
	## drop it for players who do — that would be the opposite defect.
	for pad in [XBOX, NINTENDO]:
		var hint: String = DialogueChoiceMenu.hint_text(true, pad)
		var found: bool = false
		for g in FACE_GLYPHS:
			if hint.find(g) != -1:
				found = true
				break
		assert_true(found, "%s must still print a face cap: %s" % [pad, hint])


func test_the_two_families_still_disagree() -> void:
	## CONTROL on the control: if both families rendered the same cap, the test
	## above would pass on a build that had stopped resolving per device.
	assert_ne(DialogueChoiceMenu.hint_text(true, XBOX), DialogueChoiceMenu.hint_text(true, NINTENDO),
		"the two families print different confirm caps — equal means the resolver is dead")


func test_the_navigation_token_names_both_routes_throughout() -> void:
	## The one part of this caption that was already right, pinned so the glyph
	## repair cannot take it out. Every directional action binds arrow key AND
	## d-pad AND stick, so both routes are always live and neither branches.
	for dev in ["", XBOX, NINTENDO]:
		assert_true(DialogueChoiceMenu.hint_text(true, dev).find("(↑↓/D-pad)") != -1,
			"the nav token must name the keyboard and the pad route, device '%s'" % dev)
