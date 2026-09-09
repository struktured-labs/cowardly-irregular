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


func test_the_raw_key_detector_can_actually_fire() -> void:
	# ARM+ for the scan above: a regex that matched nothing would pass it vacuously.
	var re := RegEx.new()
	re.compile("[Pp]ress [A-Z0-9]")
	assert_not_null(re.search("Press I to import shared scripts"),
		"control: the detector must catch the exact wording this test retired")
	assert_null(re.search("Choose Resume on the console"),
		"control: it must NOT flag prose that names an on-screen affordance")
