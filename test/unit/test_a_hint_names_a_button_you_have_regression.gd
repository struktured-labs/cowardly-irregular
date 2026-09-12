extends GutTest

## TutorialHints.resolve_tokens had two defects, found while scanning for what was LEFT after the
## .308/.311 caption sweep — not by looking at this file, which this lane had already declared
## clean earlier the same day.
##
## 1. {menu} was the literal "Start / Enter". ui_menu is [6, 7]; measured per family:
##      xbox Start  ·  nintendo Plus  ·  playstation Options
##    A Switch or PlayStation player was told to press a button NOT PRINTED ON THEIR PAD.
##
## 2. ⛔ BUCKET 4 — the unsafe helper behind an AUTOLOAD-only guard. The old code asked
##    `if ipm and ipm.has_method("glyph_for_action")`, which tests whether the autoload EXISTS and
##    never whether a pad is CONNECTED, then called glyph_for_action — which answers from the XBOX
##    table on an empty device name. With no pad a keyboard player was shown "Ⓑ / Z": a glyph for
##    hardware they do not have, in a family they may not own. The defect is the PAIR, and neither
##    half looks wrong alone.
##
## ⛔⛔ HOW THIS LANE MISSED IT, recorded because the miss repeated inside one session: earlier
## today I inspected this file, saw "Ⓑ / Z" rendered, and filed it clean. I checked that a glyph
## APPEARED and never asked whether it was right for the device — the identical blind spot I had
## named two hours earlier for my own footer classifier ("is a keyboard key named?" instead of "is
## the pad name right for this family?"), committed again while writing up the first instance.
##
## ⛔⛔⛔ AND AN EXISTING GUARD PINNED THE BUG. test_tutorial_hints_name_both_inputs_regression
## asserted a glyph was present UNCONDITIONALLY and went green under GUT, which attaches no pad —
## it passed *because* of the xbox fallback. A test can hold a defect in place by asserting the
## symptom; that file is corrected in the same commit rather than deleted, since the both-inputs
## claim it defends is real and only its unconditionality was wrong.

const Hints = preload("res://src/ui/TutorialHints.gd")

const XBOX := "Xbox 360 Controller"
const NINTENDO := "Nintendo Switch Pro Controller"
const PLAYSTATION := "PS5 Controller"


func _ipm():
	return InputProfileManager


func _all_face_glyphs() -> Array:
	var out := []
	for family in _ipm().FACE_GLYPHS:
		for idx in _ipm().FACE_GLYPHS[family]:
			var g: String = _ipm().FACE_GLYPHS[family][idx]
			if not out.has(g):
				out.append(g)
	return out


## DEFECT 1, behavioural: the rendered token, read as a player would.
func test_the_menu_token_is_not_a_frozen_xbox_name() -> void:
	var out := Hints.resolve_tokens("Open it with {menu}.")
	assert_false(out.contains("{"), "the token must resolve at all")
	assert_eq(out.find("Start"), -1,
		"'Start' is the Xbox name — Nintendo prints Plus and PlayStation prints Options")


## DEFECT 1, per family: the three names the caption must be able to produce are genuinely distinct,
## so freezing any one of them is wrong on the other two.
func test_ui_menu_is_named_differently_on_every_family() -> void:
	var seen := {}
	for dev in [XBOX, NINTENDO, PLAYSTATION]:
		var name_str: String = _ipm().hint_for_action("ui_menu", dev)
		assert_ne(name_str, "", "ui_menu must resolve on " + dev)
		seen[name_str] = true
	assert_eq(seen.size(), 3,
		"three families, three names — if they collapsed, the frozen literal would be harmless")
	assert_eq(_ipm().hint_for_action("ui_menu", XBOX), "Start", "the frozen literal was the Xbox one")
	assert_eq(_ipm().hint_for_action("ui_menu", NINTENDO), "Plus",
		"a Switch player was told to press a button their pad does not print")
	assert_eq(_ipm().hint_for_action("ui_menu", PLAYSTATION), "Options",
		"…and so was a PlayStation player")


## ⛔ DEFECT 2, the pin. With no pad NO token may render a family glyph. Keyed on the rendered
## text across every token the resolver knows, so a guess arriving through any of them is caught.
func test_with_no_pad_no_token_renders_a_family_glyph() -> void:
	assert_true(Input.get_connected_joypads().is_empty(),
		"precondition: this arm describes the no-pad case, which is what GUT runs as")
	var glyphs := _all_face_glyphs()
	assert_gt(glyphs.size(), 3, "precondition: FACE_GLYPHS must hold glyphs to scan for")
	for token in ["{confirm}", "{cancel}", "{menu}", "{move}", "{defer}", "{advance}", "{options}"]:
		var out := Hints.resolve_tokens(token)
		assert_false(out.contains("{"), "%s must resolve" % token)
		for g in glyphs:
			assert_eq(out.find(g), -1,
				"%s rendered '%s' with no pad attached — glyph_for_action answers from the XBOX " % [token, g] +
				"table on an empty device name, so that is a guess, not a neutral default")


## The measurement that makes defect 2 a defect rather than a style choice.
func test_an_empty_device_name_silently_answers_as_xbox() -> void:
	assert_eq(_ipm().glyph_for_action("ui_accept", ""), _ipm().glyph_for_action("ui_accept", XBOX),
		"no-pad and Xbox must be shown to agree — that agreement IS the hazard")
	assert_ne(_ipm().glyph_for_action("ui_accept", ""), _ipm().glyph_for_action("ui_accept", NINTENDO),
		"…and to disagree with Nintendo, or there would be nothing to get wrong")


## The guard must not over-correct: a keyboard player still needs to be told a KEY.
func test_the_keyboard_player_is_still_told_which_key() -> void:
	assert_string_contains(Hints.resolve_tokens("{confirm}"), "Z", "confirm names its key")
	assert_string_contains(Hints.resolve_tokens("{cancel}"), "X", "cancel names its key")
	assert_string_contains(Hints.resolve_tokens("{menu}"), "Enter", "menu names its key")


## THE CONTROL. Without it "no glyph appeared" is satisfied by a resolver that returns "" for
## everything, and the family table is satisfied by a glyph set that is empty.
func test_the_probe_would_notice_a_frozen_or_empty_resolver() -> void:
	var planted := Hints.resolve_tokens("Open it with Start / Enter.")
	assert_true(planted.find("Start") > -1,
		"the reader must SEE a frozen 'Start' when one is present — resolve_tokens leaves " +
		"non-token text alone, so this is the shape the defect had")
	assert_true(_all_face_glyphs().has("Ⓑ") and _all_face_glyphs().has("✕"),
		"the glyph set must span families, or the no-pad pin scans for nothing")
	assert_ne(Hints.resolve_tokens("{confirm}"), "",
		"a resolver returning empty would satisfy every no-glyph assert above")
