extends GutTest

## The autogrind hints told players to "Press 1/2/3", "Press Start" and "Press I" — keyboard-only
## instructions for verbs that are now reachable on a pad through the OPTIONS ring. A pad player
## reading them was told to press keys they do not have, while the ring that would serve them went
## unmentioned. That is struktured's own report (2026-09-06: "I dont know how to enable ludicrous
## or permadeath with controller, wasn't obvious") arriving through the tutorial text.
##
## The console already carries a live, glyph-accurate control strip. Two sources describing one
## surface is the drift class this project tracks, so the hints now teach the CONCEPT and point at
## the strip for exact buttons, rather than restating buttons that will drift again.

const TH = preload("res://src/ui/TutorialHints.gd")

const AUTOGRIND_HINTS := ["autogrind", "autogrind_menu", "autogrind_presets", "autogrind_export", "autogrind_resume"]


func _body(hint_id: String) -> String:
	return str((TH.HINTS[hint_id] as Dictionary).get("body", ""))


func test_every_token_used_in_any_hint_actually_resolves() -> void:
	## An unrecognised token is not inert — it renders as a literal "{options}" on screen. This
	## covers EVERY hint, not just autogrind: adding a token to a body and forgetting the
	## replacement is the same mistake in any lane.
	var offenders: Array[String] = []
	for hint_id in TH.HINTS.keys():
		var resolved: String = TH.resolve_tokens(_body(str(hint_id)))
		if resolved.contains("{") or resolved.contains("}"):
			offenders.append(str(hint_id))
	assert_eq(offenders.size(), 0,
		"these hints render a literal brace token to the player: %s" % str(offenders))


func test_the_resolver_is_actually_substituting() -> void:
	# ARM+. Without this, a resolve_tokens that returned its input unchanged would pass the
	# assertion above for every hint that happens to contain no braces.
	var out: String = TH.resolve_tokens("{confirm}|{options}")
	assert_false(out.contains("{"), "control: known tokens must be substituted, not passed through")
	assert_true(out.length() > "{confirm}|{options}".length() - 8,
		"control: substitution must produce real text, not an empty string")


func test_the_options_ring_token_names_both_routes() -> void:
	## The ring is the pad's only route to 13 verbs. Naming just the key would recreate the bug.
	var out: String = TH.resolve_tokens("{options}")
	assert_true(out.to_lower().contains("shoulder"), "the pad route must be named: got '%s'" % out)
	assert_true(out.to_lower().contains("o key") or out.to_lower().contains("o "),
		"the keyboard route must be named too: got '%s'" % out)


func test_no_autogrind_hint_dictates_a_raw_key_for_a_ring_owned_verb() -> void:
	## Presets, permadeath and file sharing all live under the ring now. A hint naming a bare
	## keystroke for them is pad-exclusionary and goes stale the next time a binding moves.
	var re := RegEx.new()
	re.compile("[Pp]ress [A-Z0-9]")
	var offenders: Array[String] = []
	for hint_id in AUTOGRIND_HINTS:
		if re.search(_body(hint_id)) != null:
			offenders.append(hint_id)
	assert_eq(offenders.size(), 0,
		"autogrind hints must point at {options} or the on-screen strip, not a raw key: %s" % str(offenders))


## ⛔ THE SAME DETECTOR, OVER EVERY HINT -- because the arm above had the right pattern and a
## corpus of FIVE. `first_formation` read "Press F to cycle formations", shipped, and was never in
## `AUTOGRIND_HINTS`, so nothing here could see it. Formation cycling has NO InputMap action (raw
## `KEY_F` at BattleScene:5475) and a pad reaches it ONLY via the `cycle_formation` command-menu row
## -- whose own comment records that someone fixed the pad REACHABILITY and left the hint naming the
## key. Worse, the hint fires from inside `cycle_formation()` (BattleScene:3762), so the pad player
## who just cycled via the menu was then told to press a key their hardware does not have.
##
## ✅ THE EXEMPTION IS THE DELIVERABLE, NOT A SUPPRESSION: a body may name a key as long as it
## also names the route a pad player has. You cannot silence this green, only explain it green --
## and the explanation is the repair.
func test_no_hint_at_all_dictates_a_raw_key_without_a_pad_route() -> void:
	var re := RegEx.new()
	re.compile("[Pp]ress [A-Z][0-9]?\\b")
	var offenders: Array[String] = []
	for hint_id in TH.HINTS.keys():
		var body: String = _body(str(hint_id))
		if re.search(body) == null:
			continue
		var names_pad_route: bool = body.contains("{") or body.contains("command menu") \
			or body.contains("Menu \u2192") or body.contains("on a pad") or body.contains("shoulder")
		if not names_pad_route:
			offenders.append(str(hint_id))
	assert_eq(offenders.size(), 0,
		"a hint naming a bare key must also name the pad route (a {token}, the command menu, or the "
		+ "strip) -- a pad has no letter keys: %s" % str(offenders))
	## CONTROL: the corpus must be the whole catalog, not the five this file already covered.
	assert_gt(TH.HINTS.keys().size(), 20,
		"CONTROL: this arm's value IS its corpus; %d hints is not the catalog" % TH.HINTS.keys().size())


func test_the_raw_key_detector_can_actually_fire() -> void:
	# ARM+ for the scan above: a regex that matched nothing would pass it vacuously.
	var re := RegEx.new()
	re.compile("[Pp]ress [A-Z0-9]")
	assert_not_null(re.search("Press I to import shared scripts"),
		"control: the detector must catch the exact wording this test retired")
	assert_null(re.search("Choose Resume on the console"),
		"control: it must NOT flag prose that names an on-screen affordance")
