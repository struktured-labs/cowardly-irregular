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
	"Start:Save": "Start is not a face button; AutobattleGridEditor derives the Select half via hint_for_action (folded 2026-09-11) and Start is still owed the same treatment.",
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
## REACHABILITY AS A TRIPWIRE, not a paragraph. I wrote the live/dead split into this file's header
## and was about to leave it there -- the third time today I would have documented a limitation
## instead of encoding one, after being shown twice what that is worth. A comment does not notice
## when MenuScene is revived, replaced, or deleted, and it does not notice when a LIVE surface
## quietly loses its last caller.
##
## ⚓ WHY THOSE TWO ARE DEAD, named rather than left as an absence. "Unreachable" invites the next
## reader to wonder whether it was ever reachable and whether that was intended; the cause answers
## both, and @cowir-controller asked for the SHA to outlive their message:
##
##   78209230  2026-03-22  "chore: remove dead code from GameLoop — sync battle, menu, unused vars"
##             -const MenuSceneRes = preload("res://src/ui/MenuScene.tscn")
##             -	var menu_scene = MenuSceneRes.instantiate()
##             2 files, 76 deletions, and it touched NEITHER of the two screens it stranded.
##
## So the hub was orphaned by a deliberate dead-code cleanup that removed its only preload from the
## main scene's script, and nothing measured the blast radius at the time. Not rot — a decision with
## an unmeasured consequence, which is a different thing to hand whoever rules on these two screens.
## (Corroboration that this is a CLASS: @cowir-battle's `_rule_to_action` was orphaned the same way
## by `c9b57d6f "remove dead code, batch 4"`, which deleted the CALL and left the FUNCTION. A
## cleanup that removes one end of an edge manufactures the dead code the next cleanup finds.)
##
## Pins today's split so a change in EITHER direction is deliberate. @cowir-battle's point is why
## the dead half matters as much as the live: an unreachable screen whose captions are already
## correct is BETTER bait than a frozen one, because it reads as a file someone maintains.
const REACHABILITY := {
	"AutogrindSummary.gd": true,
	"AutogrindGridEditor.gd": true,
	"AutobattleGridEditor.gd": true,
	"AutogrindHistoryScreen.gd": false,
	"AutogrindTemplatePicker.gd": false,
	## Added when the set-difference arm below reded on its FIRST run and named it — AutogrindUI
	## derives glyphs (it gained hint_for_action in the .296 fold) and my hand-written table had
	## never classified it. Anchored via GameLoop, which is the main scene's script.
	"AutogrindUI.gd": true,
}

func test_the_live_dead_split_is_still_what_the_header_claims() -> void:
	var src_files := {}
	for d in ["res://src", "res://src/ui", "res://src/battle", "res://src/autogrind", "res://src/autobattle", "res://src/ui/autogrind", "res://src/ui/autobattle"]:
		var dir := DirAccess.open(d)
		if dir == null:
			continue
		for f in dir.get_files():
			if f.ends_with(".gd"):
				src_files[d + "/" + f] = true
	assert_gt(src_files.size(), 40, "CONTROL: the reachability sweep must read a real corpus")

	var drifted: Array = []
	for target in REACHABILITY.keys():
		## ⚠️ Match the bare STEM, not the ".gd" path, and strip comments first. This arm failed on its
		## first run claiming AutogrindGridEditor had one caller -- because MenuScene reaches it by
		## PATH, `load("res://.../AutogrindGridEditor.gd")`, while AutogrindUI reaches it by
		## CLASS_NAME, `AutogrindGridEditor.new()`. A path-only search sees the dead hub and misses
		## the live caller, i.e. declares a LIVE surface dead. My published measurement used the bare
		## name and was right; the tripwire I wrote to defend it used the path and was not.
		##
		## Comments stripped because the hunt is for a CODE reference: AutogrindUI's docstring names
		## this class twice without calling it, and for REACHABILITY an over-count is the dangerous
		## direction -- it makes a dead surface look live. (Opposite polarity to the census below,
		## which hunts a string literal and must not strip. Same file, both settings, per
		## @cowir-controller: the polarity follows what the scan is asking to FIND.)
		var stem: String = str(target).replace(".gd", "")
		var callers := 0
		for f in src_files.keys():
			if f.ends_with("/" + target):
				continue
			if _code_only(FileAccess.get_file_as_string(f)).contains(stem):
				callers += 1
		var reachable: bool = callers > 0 and not (callers == 1 and _only_caller_is_dead_hub(src_files, target))
		if reachable != REACHABILITY[target]:
			drifted.append("%s: pinned reachable=%s, measured %d caller(s)" % [target, REACHABILITY[target], callers])
	assert_eq(drifted, [],
		"a prompt surface changed reachability -- if MenuScene was revived or a live screen lost its last caller, update REACHABILITY and say which")

	## ⛔ DRAINING MUST BE THE VIOLATION. Measured: `REACHABILITY := {}` scored Passing 7 with the
	## assert count unmoved — the loop above runs zero times and its one verdict passes vacuously.
	## The identical shape I fixed in DEFERRED this afternoon, in the table I wrote WHILE fixing it.
	## @cowir-adhoc's form: make the exemption a SUBTRAHEND so an empty table is maximal exposure
	## rather than zero work. Every file in the corpus that asks the authority for a glyph is a
	## prompt surface and must be classified here.
	var derives: Array = []
	for f in _gd_files():
		var src := _code_only(FileAccess.get_file_as_string(f))
		if src.contains("InputProfileManager.glyph_for_action(") \
				or src.contains("InputProfileManager.face_glyph_for_index(") \
				or src.contains("InputProfileManager.hint_for_action("):
			derives.append(f.get_file())
	assert_gt(derives.size(), 0, "CONTROL: the corpus must contain at least one deriving surface")
	var unclassified: Array = []
	for name in derives:
		if not REACHABILITY.has(name):
			unclassified.append(name)
	unclassified.sort()
	assert_eq(unclassified, [],
		"a surface derives its glyphs but is not classified in REACHABILITY -- add it as live or dead and say which, or this arm covers nothing")

	## ⚠️ WHAT THIS ARM IS AND IS NOT. It pins TODAY'S SPLIT and reds when a surface drifts across
	## it. It is NOT a reachability engine: it counts referrers and knows one dead hub by name,
	## which is @cowir-controller's weaker standard -- "two levels is still edge-counting; only
	## reaching an ANCHOR terminates the recursion". If a DIFFERENT hub dies tomorrow this arm will
	## not notice, and it should not be cited as proof a surface is reachable.
	##
	## The SPLIT it pins was derived by anchoring, read rather than assumed:
	##   project.godot  run/main_scene = "res://src/GameLoop.tscn"   the anchor · 31 autoloads
	##   MenuScene      appears in NEITHER -> not the main scene, not an autoload
	##   MenuScene.tscn referenced by nothing -> the chain terminates in an orphan
	##   the three live ones chain to GameLoop.gd, which IS the main scene's script
	## So the values are anchor-grade; the DETECTOR is drift-grade. Those are different claims and
	## conflating them is how a referrer count gets published as a reachability proof.


func _only_caller_is_dead_hub(src_files: Dictionary, target: String) -> bool:
	for f in src_files.keys():
		if f.ends_with("/" + target):
			continue
		if _code_only(FileAccess.get_file_as_string(f)).contains(target.replace(".gd", "")):
			return f.ends_with("/MenuScene.gd")
	return false


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


## ⚠️ NAMED MEMBERSHIP, not a floor. @cowir-adhoc: "a floor protects against total vacuity and is
## blind to partial loss", learned from a red where `gates >= 4` stayed green after one gate was
## commented out. @cowir-controller hit it the same hour. Measured here before changing anything:
##
##   both LANE_DIRS lost   EC=1  Failing 2   the floor CAUGHT it
##   ONE lane dir lost     EC=0  Failing —   SILENT. Half the corpus gone, green, Asserts unmoved.
##
## And partial is the likelier failure by a distance — a rename or a move touches one directory,
## not both. The case a floor catches is the one least likely to happen. @cowir-overworld's
## assert-count detector is blind here too: these asserts aggregate, so the number never moves.
func test_the_census_reads_a_real_corpus() -> void:
	var files := _gd_files()
	assert_gt(files.size(), 5, "CONTROL: the lane dirs must yield real files, or every assert below is vacuous")
	var total := 0
	for f in files:
		total += FileAccess.get_file_as_string(f).length()
	assert_gt(total, 20000, "CONTROL: and real content, not empty reads")

	## Every declared directory must CONTRIBUTE, and the failure names the one that went quiet.
	for d in LANE_DIRS:
		var from_dir := 0
		for f in files:
			if f.begins_with(d + "/"):
				from_dir += 1
		assert_gt(from_dir, 0,
			"%s contributed ZERO files — the census silently covered only the other lane dir, and a green below would be half a result reported as a whole one" % d)


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
		assert_true(src.contains("InputProfileManager.glyph_for_action(") or src.contains("InputProfileManager.face_glyph_for_index(") or src.contains("InputProfileManager.hint_for_action("),
			"%s must ask the authority for its button glyph -- a COMMENT naming it does not count" % f.get_file())


## ⛔ THE CENSUS PATTERN IS FACE-LETTERS-ONLY, asserted here rather than described in a comment.
##
## Both DEFERRED entries I shipped ("Sel:Auto", "Start:Save") were INERT SUPPRESSIONS: I found them
## by eye while reading a line, wrote reasons, and published them as guarded pins — but the census
## matches `[ABXY]` and can never emit a non-face name. Measured by deleting the entry: the census
## stayed green. An allowlist line for what the detector cannot emit reads as coverage from BOTH
## sides, and neither side is doing the work the other appears to delegate.
##
## ⚠️ AND THE ARM BELOW GOES VACUOUS WHEN THE TABLE DRAINS. @cowir-sprites shipped that exact
## failure: a loop over an emptied list asserts nothing, and GUT cannot flag it because one assert
## elsewhere in the call graph clears [Risky]. Measured here — DEFERRED := {} scores Passing 6.
## So this arm lives OUTSIDE any loop and holds whatever the table's size: it pins the SCOPE of the
## detector, so widening the pattern forces the claim to be restated.
func test_the_census_scope_is_what_this_file_claims() -> void:
	var re := RegEx.create_from_string("(Press [ABXY]\\b|\\b[ABXY]:[A-Za-z]|\\b[ABXY] or [ABXY]\\b|\\[[ABXY]\\])")
	assert_not_null(re, "CONTROL: the census pattern must compile")
	for face in ["Press A", "B:Cancel", "A or B", "[X]"]:
		assert_not_null(re.search(face), "the census MUST emit a face-button caption: %s" % face)
	## The limitation, encoded. @cowir-controller derives the banned set from BUTTON_NAMES, which
	## covers every family's spelling of every NON-face button; this census does not, and a reader
	## must not take its green as covering them. If someone widens the pattern, these red and the
	## file's claims (and any now-real DEFERRED entry) have to be rewritten deliberately.
	for non_face in ["Sel:Auto", "Start:Save", "L:+AND", "R:+Action"]:
		assert_null(re.search(non_face),
			"census scope changed: it now emits '%s'. Widening is GOOD -- update this arm, the header, and any DEFERRED entry that was previously inert" % non_face)


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
