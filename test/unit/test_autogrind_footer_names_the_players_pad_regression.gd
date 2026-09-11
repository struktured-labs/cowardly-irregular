extends GutTest

## The autogrind footer — the only control legend visible while a grind runs — named buttons that
## do not exist, on BOTH screens, for every player who is not holding a SNES pad:
##
##     "Select: Pause"   raw index 4 is Back (Xbox) / Share (PlayStation) / Minus (Nintendo)
##     "Start: Rules"    raw index 6 is Start / Options / Plus
##     "L+R: Tier"       raw 9+10 is LB+RB / L1+R1 / L+R
##     "B: Exit"         ui_cancel is the EAST face on Nintendo, SOUTH elsewhere
##
## And a keyboard player was told nothing at all: P, R and T are live in classify_event and appeared
## on neither screen. The dashboard is reachable (GameLoop._show_autogrind_dashboard, called from
## the headless-mode start and from the tier-change handler); the monitor is reachable through
## AutogrindUI. Both anchor to GameLoop.tscn, the main scene.
##
## The tokens are derived in AutogrindInputHelper, BESIDE classify_event, so the caption and the
## binding it describes cannot drift apart — that drift is the whole defect.

const HELPER := "res://src/ui/autogrind/AutogrindInputHelper.gd"
const DASHBOARD := "res://src/ui/autogrind/AutogrindDashboard.gd"
const MONITOR := "res://src/ui/autogrind/AutogrindMonitor.gd"

const XBOX := "Xbox Wireless Controller"
const PLAYSTATION := "DualSense Wireless Controller"
const NINTENDO := "8BitDo SN30 Pro"


## Both footers, named. A corpus that names ONE of two sibling screens goes green while the other
## ships the defect — this lane has shipped that hole three times, and cowir-autogrind and
## cowir-battle each hit it the same day in the grid editors.
func _footer_sources() -> Array:
	var paths: Array[String] = [DASHBOARD, MONITOR]
	assert_eq(paths.size(), 2, "PRECONDITION: the corpus is BOTH footer screens")
	assert_true(paths.has(DASHBOARD), "PRECONDITION: the dashboard must be in the corpus")
	assert_true(paths.has(MONITOR), "PRECONDITION: the monitor must be in the corpus")
	var out: Array = []
	for p in paths:
		var src := FileAccess.get_file_as_string(p)
		assert_gt(src.length(), 1000, "PRECONDITION: %s must be readable" % p)
		out.append([p, src])
	return out


## THE DEFECT, per family. Every row must name something on the pad in the player's hands.
func test_every_row_names_a_button_the_family_really_has() -> void:
	var expected := {
		NINTENDO: {"pause": "Minus", "adjust_rules": "Plus", "tier_cycle": "L+R", "exit": "Ⓑ"},
		XBOX: {"pause": "Back", "adjust_rules": "Start", "tier_cycle": "LB+RB", "exit": "Ⓐ"},
		PLAYSTATION: {"pause": "Share", "adjust_rules": "Options", "tier_cycle": "L1+R1", "exit": "✕"},
	}
	for device in expected:
		for action in expected[device]:
			assert_eq(AutogrindInputHelper.hint_for(action, device), expected[device][action],
				"%s on %s" % [action, device])


## THE HALF NOBODY SAW: with no pad attached the legend must name the KEYS classify_event accepts.
## It named pad buttons unconditionally, so a keyboard player had no way to learn P/R/T short of
## reading the source.
func test_with_no_pad_the_legend_names_the_keys_the_classifier_accepts() -> void:
	var helper := FileAccess.get_file_as_string(HELPER)
	for pair in [["pause", "KEY_P"], ["adjust_rules", "KEY_R"], ["tier_cycle", "KEY_T"]]:
		var token: String = AutogrindInputHelper.hint_for(pair[0])
		assert_eq(token.length(), 1,
			"with no pad connected, %s must fall back to a single key, not a pad button" % pair[0])
		assert_true(helper.contains("%s:\n\t\t\t\treturn \"%s\"" % [pair[1], pair[0]]),
			"and classify_event must really accept %s for %s — a legend may not name a key the " % [pair[1], pair[0]] +
			"dispatch table would ignore")
		assert_true(pair[1].ends_with(token),
			"the key printed (%s) must be the key bound (%s)" % [token, pair[1]])


## Exit is a face button, so it resolves through hint_for_action and reaches a KEY with no pad.
func test_exit_resolves_to_something_pressable_with_no_pad() -> void:
	var token: String = AutogrindInputHelper.hint_for("exit")
	assert_ne(token, "", "exit must always name something — it is the only way out of the screen")
	var keys := InputProfileManager.get_action_key_label("ui_cancel")
	assert_true(keys.contains(token),
		"with no pad, exit must name one of ui_cancel's real keys (%s), not a pad button: %s" % [keys, token])


## THE FROZEN VOCABULARY, gone from both footers. Bounded so "Backspace" cannot score as "Back"
## and a comment explaining the defect cannot keep it red.
func test_neither_footer_spells_a_frozen_button_name() -> void:
	for entry in _footer_sources():
		var path: String = entry[0]
		for line in entry[1].split("\n"):
			var code: String = line.strip_edges()
			if code.begins_with("#") or code.begins_with("##") or not code.contains("\"text\""):
				continue
			for banned in ["Select:", "Start:", "L+R:", "B:"]:
				assert_false(code.contains(banned),
					"%s still spells a frozen button in a footer row: %s" % [path, code])


## ...and both are really derived. The negative above passes on a file with NO rows at all.
func test_both_footers_derive_every_row() -> void:
	for entry in _footer_sources():
		var path: String = entry[0]
		var src: String = entry[1]
		for action in ["pause", "adjust_rules", "tier_cycle", "exit"]:
			assert_true(src.contains("AutogrindInputHelper.hint_for(\"%s\")" % action),
				"%s must derive its %s row from the dispatch table" % [path, action])


## CONTROL. Not a literal against itself: this pins that hint_for DISCRIMINATES — between families,
## between actions, and that it can report a miss. A resolver returning one constant for everything
## would satisfy every arm above.
func test_the_resolver_discriminates() -> void:
	assert_ne(AutogrindInputHelper.hint_for("pause", XBOX),
		AutogrindInputHelper.hint_for("pause", NINTENDO),
		"CONTROL: the same action must resolve differently on two families")
	assert_ne(AutogrindInputHelper.hint_for("pause", XBOX),
		AutogrindInputHelper.hint_for("adjust_rules", XBOX),
		"CONTROL: two actions must resolve differently on one family")
	assert_eq(AutogrindInputHelper.hint_for("no_such_action", XBOX), "",
		"CONTROL: an action the classifier does not have must resolve to nothing")


## The ladder's EXEMPTION question: if classify_event ever stops binding these, the derivation above
## is describing a screen that no longer works, and this file should be re-read rather than kept.
func test_the_bindings_the_legend_describes_still_exist() -> void:
	var helper := FileAccess.get_file_as_string(HELPER)
	for token in ["JOY_BUTTON_BACK", "JOY_BUTTON_START", "JOY_BUTTON_LEFT_SHOULDER",
			"JOY_BUTTON_RIGHT_SHOULDER", "ui_cancel"]:
		assert_true(helper.contains(token),
			"classify_event must still bind %s, or the legend describes a dead control" % token)
