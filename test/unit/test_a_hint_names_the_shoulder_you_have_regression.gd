extends GutTest

## THIRD pass over TutorialHints, and the two earlier ones were this lane's own. `{confirm}`,
## `{cancel}` and `{menu}` were derived per family (test_a_hint_names_a_button_you_have_regression);
## `{defer}`, `{advance}` and `{options}` were still frozen NINTENDO names, and one body printed the
## literal "Select". Measured per family 2026-09-16:
##
##   battle_defer         LB (xbox) · L (nintendo) · L1 (playstation)   the hint said "L shoulder"
##   battle_advance       RB · R · R1                                   the hint said "R shoulder"
##   battle_toggle_auto   Back · Minus · Share                          the hint said "Select" —
##                                                                      a name NO family prints
##
## ⛔ WHY TWO SWEEPS MISSED IT: the existing guard scans rendered tokens for FACE glyphs, and a
## shoulder name is not a face glyph. The arm that would have caught it reads the CATALOG BODIES for
## frozen family words, which is the arm below.

const Hints = preload("res://src/ui/TutorialHints.gd")

const XBOX := "Xbox 360 Controller"
const NINTENDO := "Nintendo Switch Pro Controller"
const PLAYSTATION := "PS5 Controller"

## Pad words that are NEVER ordinary English — scanned bare.
const PAD_ONLY_WORDS := ["LB", "RB", "L1", "R1", "L shoulder", "R shoulder", "L/R shoulder"]
## Pad words that ARE ordinary English (Back Row, Backstab, "Share the JSON…"), so they only count
## in an imperative BUTTON position. My first version scanned these bare and produced three false
## positives from prose — the instrument, not the corpus, was wrong.
const AMBIGUOUS_PAD_WORDS := ["Select", "Start", "Back", "Minus", "Plus", "Share"]
const BUTTON_POSITION := ["Press ", "press ", "Hold ", "hold ", "Tap ", "tap ", "with ", "or "]


func _ipm():
	return InputProfileManager


## THE PROPERTY: no authored hint body may print a family-specific button word. Tokens, not words.
func test_no_hint_body_freezes_a_family_name() -> void:
	var offenders: Array = []
	for id in Hints.HINTS.keys():
		var body: String = str(Hints.HINTS[id].get("body", ""))
		for w in PAD_ONLY_WORDS:
			if body.contains(w):
				offenders.append("%s: '%s'" % [id, w])
		for w in AMBIGUOUS_PAD_WORDS:
			for lead in BUTTON_POSITION:
				var at: int = body.find(lead + w)
				if at < 0:
					continue
				# `\b`-equivalent: the next character must not continue the word (Backstab, Shared).
				var after: int = at + lead.length() + w.length()
				var tail: String = body.substr(after, 1)
				if tail == "" or not (tail.to_lower() >= "a" and tail.to_lower() <= "z"):
					offenders.append("%s: '%s%s'" % [id, lead, w])
	assert_eq(offenders.size(), 0,
		"hint bodies must use a {token} the resolver derives, not a button word one family prints: %s" % str(offenders))


## CONTROL FOR THE INSTRUMENT, both directions — the scan above is only as good as this.
func test_control_the_scan_catches_a_button_word_and_spares_prose() -> void:
	var prose := "Front Line boosts ATK, Back Row boosts DEF. Backstab the unguarded turns. Share the JSON with other players."
	var offenders: Array = []
	for w in AMBIGUOUS_PAD_WORDS:
		for lead in BUTTON_POSITION:
			var at: int = prose.find(lead + w)
			if at >= 0:
				var after: int = at + lead.length() + w.length()
				var tail: String = prose.substr(after, 1)
				if tail == "" or not (tail.to_lower() >= "a" and tail.to_lower() <= "z"):
					offenders.append(lead + w)
	assert_eq(offenders.size(), 0, "prose must not trip the scan: %s" % str(offenders))
	var defect := "Press F6 or Select to toggle autobattle ON/OFF for all party members."
	var caught := false
	for w in AMBIGUOUS_PAD_WORDS:
		for lead in BUTTON_POSITION:
			if defect.contains(lead + w):
				caught = true
	assert_true(caught,
		"the pre-fix body — 'Press F6 or Select' — must trip the scan, or this file would not have found it")


## CONTROL: the words really are family-specific, or the arm above is scanning for nothing.
func test_control_those_words_are_each_wrong_on_two_families() -> void:
	var defer_names := {}
	var auto_names := {}
	for dev in [XBOX, NINTENDO, PLAYSTATION]:
		defer_names[_ipm().hint_for_action("battle_defer", dev)] = true
		auto_names[_ipm().hint_for_action("battle_toggle_auto", dev)] = true
	assert_eq(defer_names.size(), 3,
		"three families, three names for Defer (%s) — freezing any one is wrong on the other two" % str(defer_names.keys()))
	assert_eq(auto_names.size(), 3,
		"and three for the autobattle toggle (%s)" % str(auto_names.keys()))
	assert_false(auto_names.has("Select"),
		"'Select' is printed by NO family here — it was wrong on all three, not merely two")


## The tokens resolve, and none of them renders a name from the wrong family with no pad attached.
func test_the_new_tokens_resolve_without_a_pad() -> void:
	assert_true(Input.get_connected_joypads().is_empty(),
		"precondition: GUT attaches no pad, which is the case this arm describes")
	for token in ["{defer}", "{advance}", "{auto}", "{options}"]:
		var out: String = Hints.resolve_tokens(token)
		assert_false(out.contains("{"), "%s must resolve" % token)
		# The frozen NINTENDO forms are in PAD_ONLY_WORDS, so a revert to "L shoulder / L key" trips
		# this arm as well as the body scan. Scanning only face-family words is what let them survive.
		for w in PAD_ONLY_WORDS + AMBIGUOUS_PAD_WORDS:
			assert_eq(out.find(w), -1,
				"%s rendered the pad word '%s' with no pad attached — that is a guess about hardware the player may not own" % [token, w])


## With no pad the tokens must still name a KEY, or a keyboard player is told nothing.
func test_the_new_tokens_still_name_a_key() -> void:
	assert_ne(Hints.resolve_tokens("{defer}").strip_edges(), "", "Defer must name its key")
	assert_ne(Hints.resolve_tokens("{advance}").strip_edges(), "", "Advance must name its key")
	assert_true(Hints.resolve_tokens("{options}").contains("O"),
		"the console's options ring is on the O key when no pad is attached")
	assert_ne(Hints.resolve_tokens("{auto}").strip_edges(), "", "the autobattle toggle must name its key")


## The catalog must actually USE the derived token where the frozen word was — a resolver that can
## render {auto} while no body says {auto} fixes nothing.
func test_the_toggle_hint_uses_the_derived_token() -> void:
	var body: String = str(Hints.HINTS["autobattle_toggle"].get("body", ""))
	assert_true(body.contains("{auto}"),
		"the autobattle toggle hint must ask the resolver for its button, not print one")
	var rendered: String = Hints.resolve_tokens(body)
	assert_false(rendered.contains("{"), "and it must resolve")
	assert_true(rendered.contains("F6"),
		"F6 is a real global hotkey and stays — it is the PAD name that was wrong, not the key")


## `{options}` is composed from raw shoulder indices, the way the console's own footer composes it,
## because the console reads JOY_BUTTON_*_SHOULDER rather than an action.
func test_options_is_composed_from_the_shoulders_like_the_console() -> void:
	var src := FileAccess.get_file_as_string("res://src/ui/TutorialHints.gd")
	assert_true("button_name_for_index(JOY_BUTTON_LEFT_SHOULDER" in src,
		"the options token must read the same button index the console reads")
	var console := FileAccess.get_file_as_string("res://src/ui/autogrind/AutogrindUI.gd")
	assert_true("button_name_for_index(JOY_BUTTON_LEFT_SHOULDER" in console,
		"PRECONDITION: the console composes it that way — if it stops, this hint is describing the wrong control")
