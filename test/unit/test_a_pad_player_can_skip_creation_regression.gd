extends GutTest

## The character-creation screen draws "[ SKIP - Use Defaults ]" and a pad player could not take it.
## Skip had exactly two routes — KEY_TAB and a MenuMouseHelper click overlay — in a game whose
## Controls section says "NO MOUSE/CLICKING required" and whose first design principle is that
## everything works on gamepad. This is the first screen of a new game.
##
## ⛔ AND IT IS NOT THE SAME AS CONFIRMING, which is why a missing route mattered rather than merely
## costing a shortcut:
##     _skip_creation    -> creation_skipped  -> GameLoop._create_party()
##     _confirm_creation -> creation_complete -> GameLoop._create_party_from_customizations(...)
## Two different party-construction paths. A pad player could reach only the second.
##
## The instruction bar had the caption half of the same defect: "[Z/A] Next Char  [X/B] Back
## [START] Confirm" — A and B are the EAST and SOUTH faces, right on Nintendo only, START is the
## Xbox name for Plus/Options, and skip was advertised nowhere at all.

const SCREEN := "res://src/ui/CharacterCreationScreen.gd"

const XBOX := "Xbox Wireless Controller"
const PLAYSTATION := "DualSense Wireless Controller"
const NINTENDO := "8BitDo SN30 Pro"


func _src() -> String:
	var s := FileAccess.get_file_as_string(SCREEN)
	assert_gt(s.length(), 1000, "PRECONDITION: the screen must be readable")
	return s


func _strip_comment(line: String) -> String:
	var esc := false
	var quote := ""
	for i in range(line.length()):
		var c := line[i]
		if esc:
			esc = false
			continue
		if c == "\\":
			esc = true
		elif quote != "":
			if c == quote:
				quote = ""
		elif c == "\"" or c == "'":
			quote = c
		elif c == "#":
			return line.substr(0, i)
	return line


## Comments stripped: this fix's own comments quote "[Z/A]" and "START" to explain what was wrong,
## and an unstripped scan reports the repair as the defect. Three lanes hit that today; I hit it in
## the guard I wrote an hour ago.
func _code() -> String:
	var out := ""
	for line in _src().split("\n"):
		out += _strip_comment(line) + "\n"
	return out


## THE DEFECT. Skip must be reachable from a pad.
func test_skip_has_a_pad_route() -> void:
	var code := _code()
	assert_true(code.contains("event.keycode == KEY_TAB"),
		"PRECONDITION: the keyboard route must still exist — this guard defends ADDING the pad one")
	assert_true(code.contains("event.button_index == JOY_BUTTON_Y"),
		"skip must have a PAD route. It had none: KEY_TAB and a mouse-click overlay were the only " +
		"two, on the first screen of a new game, next to a drawn [ SKIP - Use Defaults ] label")
	var at := code.find("event.button_index == JOY_BUTTON_Y")
	assert_gt(code.find("_skip_creation()", at), -1,
		"the pad branch must call _skip_creation, not merely name the button")


## WHY IT MATTERED. If skip ever becomes a synonym for confirm, a missing route costs nothing and
## this file should be re-read rather than left as a guard nobody dares touch.
func test_skip_and_confirm_are_different_outcomes() -> void:
	var code := _code()
	assert_true(code.contains("creation_skipped.emit()"), "skip must emit its own signal")
	assert_true(code.contains("creation_complete.emit("), "confirm must emit a different one")
	var loop := FileAccess.get_file_as_string("res://src/GameLoop.gd")
	assert_true(loop.contains("_create_party()"),
		"the skipped path must still build a DEFAULT party")
	assert_true(loop.contains("_create_party_from_customizations("),
		"and the confirmed path a CUSTOM one — two outcomes is what makes the missing route a defect")


## The instruction bar must name every route through a derivation, not a frozen family.
func test_the_instruction_bar_derives_and_names_skip() -> void:
	var code := _code()
	var at := code.find("instructions.text")
	assert_gt(at, -1, "PRECONDITION: the instruction bar must exist")
	# Bounded at the STATEMENT's end, not the line's: the bar is a multi-line format call, and
	# stopping at the first newline captured the %s placeholders while missing the _route() calls
	# that fill them — a green-looking read of half a statement.
	var end := code.find("]", code.find("% [", at))
	assert_gt(end, at, "PRECONDITION: the instruction-bar statement must close")
	var line := code.substr(at, end - at)
	assert_false(line.contains("[Z/A]"), "the Next Char token froze A — the EAST face, Nintendo only")
	assert_false(line.contains("[X/B]"), "the Back token froze B — the SOUTH face, Nintendo only")
	assert_false(line.contains("[START]"), "START is the XBOX name for Plus/Options")
	assert_true(line.contains("Skip"), "skip must be advertised — it was named nowhere at all")
	for fn in ["_route(", "_skip_route("]:
		assert_true(line.contains(fn), "the bar must build its tokens through %s" % fn)


## THE TOKENS, per family, measured through the same helper the screen calls.
func test_each_token_names_the_family_you_hold() -> void:
	var expected := {
		NINTENDO: ["Ⓐ", "Ⓑ", "Ⓧ"],
		XBOX: ["Ⓑ", "Ⓐ", "Ⓨ"],
		PLAYSTATION: ["○", "✕", "△"],
	}
	for device in expected:
		var row: Array = expected[device]
		assert_eq(InputProfileManager.hint_for_action("ui_accept", device), row[0],
			"Next Char on %s" % device)
		assert_eq(InputProfileManager.hint_for_action("ui_cancel", device), row[1],
			"Back on %s" % device)
		assert_eq(InputProfileManager.button_name_for_index(JOY_BUTTON_Y, device), row[2],
			"Skip on %s — the north face, free here because ui_accept/ui_cancel hold east/south" % device)


## CONTROL: the resolver must discriminate, or every arm above passes on a constant.
func test_the_resolver_discriminates() -> void:
	assert_ne(InputProfileManager.hint_for_action("ui_accept", XBOX),
		InputProfileManager.hint_for_action("ui_accept", NINTENDO),
		"CONTROL: one action, two families, two answers")
	assert_ne(InputProfileManager.button_name_for_index(JOY_BUTTON_Y, XBOX),
		InputProfileManager.hint_for_action("ui_accept", XBOX),
		"CONTROL: the skip face must differ from the confirm face on one family")
	assert_eq(InputProfileManager.button_name_for_index(JOY_BUTTON_Y), "",
		"CONTROL: with no pad the raw-index helper returns EMPTY, which is why the bar says Tab")
