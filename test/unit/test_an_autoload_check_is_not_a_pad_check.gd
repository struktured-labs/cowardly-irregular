extends GutTest

## `ReadableProp.close_glyph()` read:
##
##     if InputProfileManager:
##         return InputProfileManager.glyph_for_action("ui_cancel", device_name)
##     return "B"
##
## ⛔ THAT `if` GUARDS THE AUTOLOAD, NOT A PAD. The autoload is always present in a shipped game, so
## the "B" fallback never fired — and `glyph_for_action` resolves the face family through
## `face_family_for_device("")`, which returns **"xbox"** for *no device*. Measured, no pad connected:
##
##     close_glyph()               ->  Ⓐ        what a KEYBOARD player was shown
##     ui_cancel keyboard bindings ->  X, Escape
##
## So the village notebook's footer read `[Ⓐ] Close` to someone holding no controller. The branch
## looked like a fallback and answered a different question than the one it appeared to answer.
##
## 🔑 WHAT THIS GUARD DEFENDS IS THE PAIR, not the spelling (@cowir-battle's framing): the defect is
## (unsafe helper) + (autoload-only guard). Either alone is fine — `hint_for_action` needs no pad
## branch because it falls back to the key itself, and an autoload check is harmless beside it. The
## file becomes defective again the moment someone swaps the helper, and the `if` will still be
## sitting there reading like protection. So the arm forbids the unsafe helpers in this file by name.
##
## ⚠️ SCOPE: this file only. The same pair exists across `src/ui/**` and is @cowir-controller's audit;
## a lane-wide ban belongs with that pass, not bolted on here.

const READABLE := "res://src/exploration/ReadableProp.gd"
## Returns the face family for an UNKNOWN pad, which is a real case — so it may not return "".
const UNSAFE := ["glyph_for_action", "face_glyph_for_index"]


## ⚠️ A `#` INSIDE A STRING IS NOT A COMMENT, and my window has one: IndustrialOverworld's
## `_create_npc("Worker #4471", ...)`. A naive `find("#")` truncates that line and deletes real code
## from the scan. Harmless for a PRESENCE assert (a lost symbol reds loudly); silent and wrong for a
## BAN assert, where a forbidden name after the cut simply stops being seen. @cowir-music flagged the
## shape and measured their own window clean; mine was not.
func _comment_start(line: String) -> int:
	var in_double := false
	var in_single := false
	var i := 0
	while i < line.length():
		var c := line[i]
		if c == "\\":
			i += 2
			continue
		if c == "\"" and not in_single:
			in_double = not in_double
		elif c == "'" and not in_double:
			in_single = not in_single
		elif c == "#" and not in_double and not in_single:
			return i
		i += 1
	return -1

## ⛔ CODE ONLY. The repair's own comment QUOTES `glyph_for_action` to explain what was wrong, so an
## unstripped scan reports the fix as the defect — it did, on this guard's first run. Ordinary quoted
## strings are deliberately KEPT: a helper name in one is a call, never a caption.
## ⚠️ DOCSTRINGS ARE THE EXCEPTION, added 2026-09-12 on @cowir-music's finding. `"""` blocks are
## string LITERALS, so a `#`-only strip leaves them and prose quoting a name satisfies a presence
## assert — `assert_true(src.contains("hint_for_action"))` below would pass with the real call gone.
## ReadableProp carries ZERO docstrings today; this guard exists for the version that does not.
func _code(path: String = READABLE) -> String:
	var raw := FileAccess.get_file_as_string(path)
	assert_gt(raw.length(), 500, "PRECONDITION: %s must be readable" % path)
	# ⚠️ ORDER IS LOAD-BEARING (@cowir-sprites 2026-09-12): a `"""` INSIDE a # comment flips the
	# parity for the rest of the file — real code leaves the code half AND prose enters it, from one
	# flip. Strip comments FIRST so such a delimiter is gone before the split ever sees it.
	# Measured 0 occurrences in this corpus today: latent, not live. Inert, not safe by design.
	var decommented := ""
	for line in raw.split("\n"):
		var l := str(line)
		var at := _comment_start(l)
		decommented += (l.substr(0, at) if at >= 0 else l) + "\n"
	var out := ""
	var chunks: PackedStringArray = decommented.split("\"\"\"")
	for i in range(chunks.size()):
		if i % 2 == 0:
			out += str(chunks[i])
	return out


## THE RENDERED STRING. Not "does it call the right helper" — what a player with no pad actually sees.
func test_the_close_hint_names_something_a_keyboard_player_can_press() -> void:
	var RP = load(READABLE)
	assert_true(Input.get_connected_joypads().is_empty(),
		"PRECONDITION: this arm measures the NO-PAD case; a pad is connected, so it proves nothing")
	var glyph: String = RP.close_glyph()
	assert_gt(glyph.length(), 0, "the close hint must not be empty — the footer renders '[%s] Close'" % glyph)
	# The face glyphs are exactly what a keyboard player cannot press.
	for face in ["Ⓐ", "Ⓑ", "Ⓧ", "Ⓨ", "○", "✕", "□", "△"]:
		assert_false(glyph.contains(face),
			"with NO pad connected the close hint rendered '%s', which contains the face glyph %s — " % [glyph, face] +
			"a player holding no controller cannot press it")
	assert_eq(glyph, InputProfileManager.hint_for_action("ui_cancel"),
		"the hint must be whatever hint_for_action resolves, not a frozen or separately-derived value")


## THE PAIR. The `if InputProfileManager:` is harmless beside a safe helper and load-bearing-looking
## beside an unsafe one. Forbid the unsafe half so the combination cannot re-form.
func test_this_file_does_not_pair_an_autoload_check_with_an_unsafe_helper() -> void:
	var src := _code()
	var guards_autoload := src.contains("if InputProfileManager:")
	for helper in UNSAFE:
		assert_false(src.contains(helper),
			("%s resolves the face family through face_family_for_device(\"\"), which answers " % helper) +
			"\"xbox\" for NO DEVICE — so it hands a keyboard player a glyph. This file has an " +
			"autoload check (%s) that reads like a pad branch and is not one; the two together are " % str(guards_autoload) +
			"the defect. Use hint_for_action or button_name_for_index.")
	assert_true(src.contains("hint_for_action"),
		"close_glyph must derive through hint_for_action, which falls back to the KEY with no pad")


## CONTROL: the unsafe-helper scan must be able to report a name PRESENT, or the arm above is free.
func test_the_helper_scan_discriminates() -> void:
	var src := _code()
	assert_true(src.contains("InputProfileManager"),
		"CONTROL present: the scan can see the autoload's name in this file")
	assert_false(src.contains("face_glyph_for_index"),
		"CONTROL absent: a helper this file does not call must scan as absent")
	# THE STRIPPER, both directions: it must eat the comment that names the forbidden helper, and
	# must NOT eat the code that names the safe one. Over-stripping would make the arm above vacuous.
	var raw := FileAccess.get_file_as_string(READABLE)
	assert_true(raw.contains("glyph_for_action"),
		"CONTROL: the raw file DOES contain the forbidden name — in the comment explaining the fix")
	assert_false(src.contains("glyph_for_action"),
		"CONTROL: ...and the stripper removed it, which is the only reason the arm above can pass")
	assert_true(src.contains("hint_for_action"),
		"CONTROL: the stripper did not eat the real call")
	# And the live predicate both ways, so neither direction is assumed.
	assert_true("if InputProfileManager:\n\t\treturn InputProfileManager.glyph_for_action(".contains(UNSAFE[0]),
		"CONTROL: the forbidden spelling is detectable in the exact shape that shipped")


## ⛔ CONTROL FOR THE STRIPPER — and the version before it COULD NOT FAIL. @cowir-battle's third
## point, measured here rather than accepted: neutering the docstring half of `_code` left this file
## EC=0 · Passing 4. The old arm re-implemented the split INSIDE the test and never called `_code`,
## and its one real assert (no triple quote survives) was vacuous because ReadableProp carries ZERO
## docstrings — nothing to strip, so nothing to get wrong.
##
## Two changes, both @cowir-music's shape: point it at a file that HAS both constructs, and assert
## STRUCTURALLY (no `#`, no triple quote survives) instead of naming a phrase, so rewording the prose
## cannot red a correct tree. The anti-vacuity pair is what makes "it stripped everything" mean
## something: a window with nothing to strip passes that assert for free.
const STRIPPER_SUBJECT := "res://src/exploration/OverworldScene.gd"

func test_the_stripper_actually_strips() -> void:
	var path := STRIPPER_SUBJECT
	var raw := FileAccess.get_file_as_string(path)
	# DERIVED from the file, not a phrase: chunk 1 of a split on the triple quote IS the first
	# docstring's body. Naming a phrase reds on a reword; asserting "no triple quote survives" is
	# WORSE — split() consumes its delimiter, so that holds for a BROKEN stripper too. Measured.
	var parts: PackedStringArray = raw.split("\"\"\"")
	assert_gte(parts.size(), 3,
		"ANTI-VACUITY: the scanned file holds no docstring, so nothing below is evidence")
	var body: String = str(parts[1])
	assert_gt(body.strip_edges().length(), 20,
		"ANTI-VACUITY: the first docstring is too short to tell a strip from a no-op")
	assert_true(raw.contains("#"),
		"ANTI-VACUITY: the scanned file holds no # comment, so the comment arm is free")

	var code := _code(path)
	assert_false(code.contains(body),
		"the first docstring's BODY survived _code() — prose is reaching the source arms as code")
	# NOT `code.contains("#")`: a `#` inside a string LEGITIMATELY survives now, so that assert would
	# red on a correct tree the moment a scanned file gains a "Worker #4471". Ask the property instead.
	var surviving_comments := 0
	for line in code.split("\n"):
		if _comment_start(str(line)) >= 0:
			surviving_comments += 1
	assert_eq(surviving_comments, 0,
		"%d line(s) still carry a comment after _code() — comments are reaching the source arms as code" % surviving_comments)
	assert_true(code.contains("func _place_readables"),
		"CONTROL the other way: an over-strip would eat real declarations and make every arm vacuous")


## THE STRING-AWARE HALF, which is new logic and therefore owes its own arm. IndustrialOverworld is
## the live instance: `_create_npc("Worker #4471", ...)`. A naive strip cuts that line and silently
## deletes the rest of it from the scan.
func test_a_hash_inside_a_string_is_not_a_comment() -> void:
	assert_eq(_comment_start("var a = 1  # real comment"), 11, "a bare # starts a comment")
	assert_eq(_comment_start("_create_npc(\"Worker #4471\", \"villager\")"), -1,
		"a # inside a string is NOT a comment — cutting there deletes live code from the scan")
	assert_eq(_comment_start("var s = \"a\"  # after a closed string"), 13,
		"...and a # after the string closes still is one")
	var code := _code("res://src/exploration/IndustrialOverworld.gd")
	assert_true(code.contains("Worker #4471"),
		"the live instance must survive the strip intact")
	assert_true(code.contains("villager") and code.contains("MAP_SCALE"),
		"CONTROL: the code AFTER that # survives — the whole point of the string-aware scan")

## Every file this guard's stripper is pointed at — the subject plus the control's subject.
func _stripper_corpus() -> Array:
	return [READABLE, STRIPPER_SUBJECT]


## ⛔ `"""` MEANS DOCUMENTATION ONLY UNTIL SOMEBODY ASSIGNS IT (@cowir-ai, via @cowir-music,
## 2026-09-12). In `DialoguePrompts` the triple-quoted regions are `AUTOBATTLE_GRAMMAR_DESCRIPTION`
## and friends — SHIPPING PROMPT TEXT. A blanket stripper there would delete the subject, and a guard
## reading it would be reading the product, not prose. My stripper is safe because every scanned file
## has ZERO assigned regions; that is a per-file property that can change in one commit, so it is
## asserted here rather than relied on.
func test_no_scanned_file_keeps_content_in_a_triple_quote() -> void:
	var offenders: Array = []
	var scanned := 0
	for path in _stripper_corpus():
		var raw := FileAccess.get_file_as_string(path)
		assert_gt(raw.length(), 200, "CONTROL: %s is readable" % str(path).get_file())
		scanned += 1
		for line in raw.split("\n"):
			var l := str(line)
			var q := l.find("\"\"\"")
			if q < 0:
				continue
			var before := l.substr(0, q).strip_edges()
			if (before.begins_with("const ") or before.begins_with("var ")) and before.ends_with("="):
				offenders.append("%s: %s" % [str(path).get_file(), l.strip_edges().substr(0, 60)])
	offenders.sort()
	assert_gt(scanned, 0, "CONTROL: the corpus is non-empty, or the zero below is free")
	assert_eq(offenders, [],
		"a scanned file ASSIGNS a triple-quoted region to a name — that is CONTENT, not a docstring, " +
		"and this file's stripper would delete the very thing a source arm is looking for: %s" % str(offenders))
