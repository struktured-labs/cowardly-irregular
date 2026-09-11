extends GutTest

## The Advance-queue hint bar rendered "Ⓑ Add+Commit · HOLD L Commit · tap L/Ⓐ Undo" to a player
## with NO PAD — two xbox glyphs for a device they do not have, and inverted besides: ui_accept is
## the EAST face, which xbox calls B, so the "confirm" glyph was a B and the "undo" glyph an A.
##
## ⛔ THE GUARD THAT LOOKED LIKE PROTECTION. The literals were `var g_ok := "A"` behind
## `if InputProfileManager:` — which tests whether the AUTOLOAD is up, NOT whether a pad exists.
## The autoload is always up, so those literals never fired once. glyph_for_action with no pad
## resolves face_family_for_device("") to "xbox" and returns a real glyph, so nothing was empty and
## nothing looked wrong. The pair (unsafe helper + autoload-only guard) is the defect; either alone
## is fine, which is why hint_for_action needs no such branch — it falls back to the KEY itself.
##
## This row exists because struktured asked for it on 2026-09-10 ("there should be one button to
## commit your choices") and it named buttons a keyboard player does not have.

const MENU := "res://src/ui/Win98Menu.gd"

const XBOX := "Xbox Wireless Controller"
const PLAYSTATION := "DualSense Wireless Controller"
const NINTENDO := "8BitDo SN30 Pro"


func _src() -> String:
	var s := FileAccess.get_file_as_string(MENU)
	assert_gt(s.length(), 1000, "PRECONDITION: Win98Menu must be readable")
	return s


## Quote-aware comment stripping, because THE FIX'S OWN COMMENT NAMES THE DEFECT. I wrote the
## explanation "WAS glyph_for_action …" directly above the repair and the first version of this
## guard redded on it — reporting the repair as the defect. @cowir-overworld and @cowir-autogrind
## each hit this within an hour today (glyph_for_action, str(item_id)); I described it and then did
## it in the next guard I wrote. A scan whose subject is a SYMBOL must never read prose.
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
		elif c == "\"" or c == "\'":
			quote = c
		elif c == "#":
			return line.substr(0, i)
	return line


func _bar_body() -> String:
	var src := _src()
	var at := src.find("func _update_hint_bar")
	assert_gt(at, -1, "PRECONDITION: _update_hint_bar must exist")
	var stop := src.find("\nfunc ", at + 10)
	var raw := src.substr(at, (stop - at) if stop > at else 900)
	var out := ""
	for line in raw.split("\n"):
		out += _strip_comment(line) + "\n"
	return out


## THE DEFECT, per family. Each token must name something on the pad in the player's hands.
func test_each_token_names_the_family_you_hold() -> void:
	var expected := {
		NINTENDO: ["Ⓐ", "Ⓑ", "L"],
		XBOX: ["Ⓑ", "Ⓐ", "LB"],
		PLAYSTATION: ["○", "✕", "L1"],
	}
	for device in expected:
		var row: Array = expected[device]
		assert_eq(InputProfileManager.hint_for_action("ui_accept", device), row[0],
			"Add+Commit token on %s" % device)
		assert_eq(InputProfileManager.hint_for_action("ui_cancel", device), row[1],
			"Undo token on %s" % device)
		assert_eq(InputProfileManager.hint_for_action("battle_defer", device), row[2],
			"HOLD/tap token on %s" % device)


## THE HALF THAT SHIPPED WRONG: with no pad the bar must name KEYS, not glyphs.
func test_with_no_pad_the_bar_names_keys() -> void:
	assert_true(Input.get_connected_joypads().is_empty(),
		"PRECONDITION: the runner has no pad — that is the live path this defect took")
	for action in ["ui_accept", "ui_cancel", "battle_defer"]:
		var tok: String = InputProfileManager.hint_for_action(action)
		assert_false(tok.is_empty(), "%s must resolve to something pressable" % action)
		var keys: String = InputProfileManager.get_action_key_label(action)
		assert_true(keys.contains(tok),
			"with no pad, %s must name one of its real KEYS (%s), not a pad glyph: got '%s'" %
			[action, keys, tok])


## THE PAIR, forbidden by name. Evading this is the correction, so it cannot be gamed.
func test_the_bar_does_not_use_the_xbox_falling_back_helpers() -> void:
	var body := _bar_body()
	assert_false(body.contains("glyph_for_action"),
		"_update_hint_bar must not call glyph_for_action — with no pad it resolves to the XBOX " +
		"family and hands a keyboard player a glyph. Use hint_for_action, which falls back to the key")
	assert_false(body.contains("face_glyph_for_index"),
		"same for face_glyph_for_index — same xbox fallback")
	# NAMED MEMBERSHIP, not presence. `contains("hint_for_action")` passes with ONE of three tokens
	# derived and two frozen — the partial-loss blindness that has bitten this lane before.
	for action in ["ui_accept", "ui_cancel", "battle_defer"]:
		assert_true(body.contains("hint_for_action(\"%s\")" % action),
			"the %s token must derive — a bar with two derived tokens and one frozen still reads " % action +
			"as \"uses the safe helper\" to a presence check")


## The bindings the caption describes. If HOLD/tap stops being battle_defer, the row is naming a
## control nobody has and this file should be re-read rather than re-blessed.
func test_the_bindings_the_row_describes_still_exist() -> void:
	assert_true(InputMap.has_action("battle_defer"), "battle_defer must exist — HOLD/tap name it")
	assert_true(InputMap.has_action("ui_accept"), "ui_accept must exist")
	assert_true(InputMap.has_action("ui_cancel"), "ui_cancel must exist")
	var body := _bar_body()
	assert_true(body.contains("queued %d/%d"), "the row must still report the queue depth")


## CONTROL. Pins that the resolver DISCRIMINATES — a helper returning one constant would satisfy
## every arm above. Not a literal against itself.
func test_the_resolver_discriminates() -> void:
	assert_ne(InputProfileManager.hint_for_action("ui_accept", XBOX),
		InputProfileManager.hint_for_action("ui_accept", NINTENDO),
		"CONTROL: one action must resolve differently across families")
	assert_ne(InputProfileManager.hint_for_action("ui_accept", XBOX),
		InputProfileManager.hint_for_action("ui_cancel", XBOX),
		"CONTROL: two actions must resolve differently on one family")
	assert_ne(InputProfileManager.hint_for_action("ui_accept", XBOX),
		InputProfileManager.hint_for_action("ui_accept"),
		"CONTROL: pad and no-pad must differ — the no-pad case is the one that shipped wrong")


## THE STRIPPER, pinned both directions — it is what stands between this guard and reporting its
## own subject's explanation as the defect.
func test_the_comment_stripper_cuts_prose_and_keeps_code() -> void:
	var bs := "\\"
	assert_eq(_strip_comment("\t\t# WAS glyph_for_action, the xbox fallback"), "\t\t",
		"a full-line comment naming the forbidden symbol must go")
	assert_eq(_strip_comment("\tvar g := ipm.hint_for_action(\"ui_accept\")  # was glyph_for_action"),
		"\tvar g := ipm.hint_for_action(\"ui_accept\")  ",
		"a TRAILING comment must go and the call must stay")
	assert_eq(_strip_comment("\tvar s := \"#ff0000\""), "\tvar s := \"#ff0000\"",
		"a # inside a string is data, not a comment")
	assert_eq(_strip_comment("\tvar q := \"a" + bs + bs + "\"  # tail"), "\tvar q := \"a" + bs + bs + "\"  ",
		"a string ending in an escaped backslash still closes, so the real comment is cut")
