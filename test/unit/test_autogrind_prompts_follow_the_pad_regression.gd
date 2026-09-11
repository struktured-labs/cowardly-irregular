extends GutTest

## Four player-facing prompts in this lane named buttons that do not exist on the pad in the
## player's hands. A PlayStation player reading "Press A or B to continue" on the autogrind summary
## has neither button; on a DualSense those are Cross and Circle.
##
##   AutogrindSummary       "Press A or B to continue"     accepts ui_accept OR ui_cancel
##   AutogrindHistoryScreen "Press B or Esc to return"     accepts ui_cancel
##   AutogrindTemplatePicker"Press B or Esc to close"      accepts ui_cancel
##   AutobattleGridEditor   "D-Pad:Select A:Confirm B:Cancel"
##
## @cowir-controller found these while correcting the reach of their own ratchet, which matches
## `"[A]` and glyphs and is structurally blind to the UNBRACKETED spelling. Their words: the
## pattern is narrower than the defect, for the fourth time in one file. So this census patterns on
## the DEFECT -- a face-button letter used as a caption, in any spelling -- not on one form of it.
##
## Esc and D-Pad stay literal on purpose: a keyboard key does not change with the pad, and every
## pad has a d-pad. The thing that varies is the FACE letter, and only that is derived.
##
## ⚠️ REACHABILITY, checked AFTER the fix and not before — @cowir-controller found a caption they
## had fixed that morning on a screen no player can open, and @cowir-story shipped 58 lines into a
## dead branch the same afternoon. Their shared diagnosis: every verification was about their own
## change and none asked WHO CALLS THIS. Mine were the same — labels vs accepted actions, glyph
## derivation, neighbours, six mutation arms — and not one asked whether a player can reach the
## screen. Measured only once they published it:
##
##   AutogrindSummary         GameLoop:6016 loads it                      LIVE
##   AutogrindGridEditor      AutogrindUI.gd                              LIVE
##   AutobattleGridEditor     GameLoop + BattleScene                      LIVE
##   AutogrindHistoryScreen   MenuScene.gd ONLY                           ⛔ DEAD HUB
##   AutogrindTemplatePicker  MenuScene.gd ONLY                           ⛔ DEAD HUB
##
## MenuScene.tscn is referenced by NOTHING and MenuScene.gd is instantiated nowhere in src/
## (verified independently of @cowir-controller's report). So two of these captions are correct on
## screens that cannot currently be opened. NOT reverted: unreachable is not the same as worth
## removing (@cowir-story's rule), the captions are right whenever that hub is revived or replaced,
## and the census would otherwise re-flag them forever. But this guard is NOT evidence that five
## player-visible surfaces were repaired — it is three, plus two held correct against a revival.
##
## ⛔ I FIRST EXEMPTED THREE OF THESE ON REASONS THAT WERE FALSE, and @cowir-controller measured
## them rather than reading them. I wrote that "Y:CycleOp" was the keyboard row — KEY_Y is bound to
## NOTHING in that file and the keyboard key is C (:1836); that Y is JOY_BUTTON_Y, Ⓧ on Nintendo and
## △ on PlayStation. I wrote that "Del/Y:Delete" named a pad button for a keyboard-only action —
## :1842-1847 deletes on JOY_BUTTON_Y whenever the cursor is off a condition cell. Both are now
## DERIVED through face_glyph_for_index, which is the right helper for a RAW button index (no
## action to look up), where glyph_for_action takes an action name.
##
## An exemption carrying a false reason is worse than no exemption: it reads as verified and stops
## the next sweep from looking. The reason field is the deliverable, so a wrong one is the one
## defect this design cannot absorb.

const LANE_DIRS := ["res://src/ui/autogrind", "res://src/ui/autobattle"]

## Frozen captions that are NOT fixed, each with the reason -- the value is required non-empty, so
## an entry can be explained green but never silenced green.
const DEFERRED := {
	"Sel:Auto": "Select is not a FACE button, so neither glyph_for_action nor face_glyph_for_index names it; @cowir-controller's non-face derivation is on an unfolded branch and duplicating it would create a second authority.",
	"Start:Save": "Start is not a face button; same reason as Sel:Auto.",
}


## Comments stripped QUOTE-AWARE, line count preserved so any positional reasoning stays valid.
## @cowir-controller's question, which found this: what does the file look like after a REAL person
## removes the thing you are defending? They do not delete the branch and leave no trace -- they
## leave the comment that explained it. Measured: reverting the derivation while leaving
## `## was InputProfileManager.glyph_for_action(...)` and hardcoding g_ok = "A" scored Passing 4 --
## GREEN with the prompt frozen back to A/B for every player.
##
## ⚠️ I FIRST BLANKED WHOLE COMMENT LINES ONLY, wrote the trailing-comment hole into my own commit
## as a known boundary, and shipped it. @cowir-controller then measured that hole in their file --
## `keycode in [KEY_ESCAPE]:  # KEY_ENTER dropped for now` walks straight through -- and made the
## strip quote-aware. Naming a boundary is not closing it: the note reads as diligence and defends
## nothing. Third costume of one hollowness in this lane today (bare find() -> full-line comment ->
## trailing comment), each fix blind to the next.
##
## Cuts at the first `#` OUTSIDE a string literal, so a `#` in quoted text cannot truncate real code
## -- 25 such lines exist in the two scanned dirs, the bulk hazard @cowir-sfx measured in theirs.
## Backslash escapes are skipped: without that, `"a \" b"` leaves an ODD quote count, the parser
## thinks it is still inside a string, and a trailing comment survives the strip. Even counts
## happen to work by luck, which is why the probe that "passes" is not evidence. Zero escaped-quote
## lines in this corpus today -- closed anyway, because I shipped a NAMED boundary two commits ago
## and @cowir-controller had to measure it for me.
func _code_only(src: String) -> String:
	var out := PackedStringArray()
	for l in src.split("\n"):
		var in_str := false
		var esc := false
		var cut := -1
		for i in l.length():
			var c := l[i]
			if esc:
				esc = false
				continue
			if c == "\\":
				esc = true
			elif c == "\"":
				in_str = not in_str
			elif c == "#" and not in_str:
				cut = i
				break
		out.append(l if cut == -1 else l.substr(0, cut))
	return "\n".join(out)


func _gd_files() -> Array:
	var out: Array = []
	for d in LANE_DIRS:
		var dir := DirAccess.open(d)
		if dir == null:
			continue
		for f in dir.get_files():
			if f.ends_with(".gd"):
				out.append(d + "/" + f)
	return out


## THE INSTRUMENT ITSELF, pinned directly rather than only through mutation arms — @cowir-overworld's
## move after four fixes in one file, each blind to the next. Mutation arms prove the stripper works
## on the one file I mutated; these prove the FUNCTION does, permanently, and a future reader does
## not have to re-run six arms to trust it.
##
## ⚠️ POLARITY, per @cowir-controller's correction of the table now circulating: it follows what the
## scan is asking to FIND, not which lane you are in — and THIS FILE NEEDS BOTH.
##   authority arm  hunts CODE (`glyph_for_action(`)  -> strips comments, ignores strings
##   census arm     hunts a STRING ("Press A")        -> uses NO stripper; the caption IS the defect
## Running _code_only over the census would report every frozen prompt clean. That is the silent,
## total false-clean @cowir-music warned about, one function away in the same file.
func test_the_comment_stripper_cuts_only_what_it_should() -> void:
	var cases := [
		# [input, expected, why]
		["\tg = f(\"ui_accept\")  # was derived", "\tg = f(\"ui_accept\")  ", "trailing comment cut"],
		## Cut-at-# leaves the leading whitespace, so this is "\t" and not "". Inert either way -- no
		## code survives -- but I wrote "" from my own earlier BLANK-the-line description, and the
		## direct pin caught the doc/behaviour drift in seconds where six mutation arms never would.
		["\t## whole line", "\t", "full-line comment: only the indent survives"],
		["\tvar c := \"#ff0000\"", "\tvar c := \"#ff0000\"", "a # INSIDE a string is not a comment"],
		["\tvar c := \"#ff0000\"  # note", "\tvar c := \"#ff0000\"  ", "quoted # then a real comment: cut at the comment only"],
		["\tvar s := \"odd \\\" quote\"  # note", "\tvar s := \"odd \\\" quote\"  ", "an ESCAPED quote must not flip the parser into a string"],
		## @cowir-controller's SIXTH costume: an escaped BACKSLASH at a string's end. A look-behind
		## check (`c == quote and line[i-1] != "\\\\"`) reads the preceding backslash and decides the
		## quote is escaped -- but that backslash was itself escaped, so the string really ends, and a
		## comment survives into the scan. This stripper is immune BY CONSTRUCTION rather than by
		## corpus: it SKIPS the char after a backslash instead of looking behind at one, so `\\\\` is
		## consumed as a pair and the closing quote is seen. Verified against both shapes side by side.
		["\tvar q := \"a\\\\\"  # note", "\tvar q := \"a\\\\\"  ", "escaped BACKSLASH at string end still closes the string"],
		["\tvar plain := 1", "\tvar plain := 1", "no # at all: untouched"],
	]
	for c in cases:
		assert_eq(_code_only(c[0]), c[1], c[2])


func test_the_census_reads_a_real_corpus() -> void:
	var files := _gd_files()
	assert_gt(files.size(), 5, "CONTROL: the lane dirs must yield real files, or every assert below is vacuous")
	var total := 0
	for f in files:
		total += FileAccess.get_file_as_string(f).length()
	assert_gt(total, 20000, "CONTROL: and real content, not empty reads")


func test_no_face_button_letter_is_frozen_into_a_caption() -> void:
	# The defect in any spelling: "Press A", "A:Confirm", "A or B", "[A]".
	var re := RegEx.create_from_string("(Press [ABXY]\\b|\\b[ABXY]:[A-Za-z]|\\b[ABXY] or [ABXY]\\b|\\[[ABXY]\\])")
	var frozen: Array = []
	for f in _gd_files():
		var lines := FileAccess.get_file_as_string(f).split("\n")
		for i in lines.size():
			var l: String = lines[i]
			if l.strip_edges().begins_with("#"):
				continue
			if not l.contains("\""):
				continue
			var m := re.search(l)
			if m == null:
				continue
			var hit: String = m.get_string(1)
			if DEFERRED.has(hit):
				continue
			frozen.append("%s:%d  %s" % [f.get_file(), i + 1, hit])
	assert_eq(frozen.size(), 0,
		"a face-button letter is frozen into a caption -- derive it via InputProfileManager.glyph_for_action, or add it to DEFERRED with a reason:\n  %s"
		% "\n  ".join(frozen))


func test_the_four_repaired_surfaces_actually_ask_the_authority() -> void:
	# The census above proves no frozen letter remains; this proves the replacement DERIVES rather
	# than having simply deleted the caption.
	for f in ["res://src/ui/autogrind/AutogrindSummary.gd",
			  "res://src/ui/autogrind/AutogrindHistoryScreen.gd",
			  "res://src/ui/autogrind/AutogrindTemplatePicker.gd",
			  "res://src/ui/autobattle/AutobattleGridEditor.gd"]:
		var raw := FileAccess.get_file_as_string(f)
		assert_gt(raw.length(), 500, "CONTROL: %s was read" % f.get_file())
		var src := _code_only(raw)
		assert_true(src.contains("InputProfileManager.glyph_for_action(") or src.contains("InputProfileManager.face_glyph_for_index("),
			"%s must ask the authority for its button glyph -- a COMMENT naming it does not count" % f.get_file())


func test_deferred_entries_carry_a_reason_and_are_still_present() -> void:
	var all := ""
	for f in _gd_files():
		all += FileAccess.get_file_as_string(f)
	var stale: Array = []
	for k in DEFERRED.keys():
		if str(DEFERRED[k]).strip_edges().is_empty():
			stale.append("%s has an empty reason" % k)
		if not all.contains(k):
			stale.append("%s is no longer in the corpus -- remove the exemption" % k)
	assert_eq(stale, [], "DEFERRED entry is unexplained or stale")
