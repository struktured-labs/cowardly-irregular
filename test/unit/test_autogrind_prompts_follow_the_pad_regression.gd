extends GutTest

const GdSource = preload("res://test/unit/helpers/gd_source.gd")

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
## ⚠️ "LIVE" HERE MEANS ANCHORED, NOT PLAYTHROUGH-REACHABLE — @cowir-adhoc/@cowir-music's
## dispatchability-vs-reachability split, which lands on my own word. This arm computes
## `callers > 0 and not (the one caller is the dead hub)`: a static scan. The DEAD verdicts are the
## strong half (MenuScene is instantiated nowhere, so those screens genuinely cannot be opened); the
## LIVE ones say a chain reaches the main scene's script, NOT that a player arrives there. Whether
## anyone reaches the summary needs a progression trace, which no grep can answer.
##   AutogrindSummary         GameLoop loads it                          ANCHORED
##   AutogrindGridEditor      AutogrindUI.gd                              ANCHORED
##   AutobattleGridEditor     GameLoop + BattleScene                      ANCHORED
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

## ONE source of truth for the census pattern. It lived as two copies — the live one and the scope
## arm's — and I widened only the live one, so the tripwire whose whole job is "if someone widens
## the pattern, red and restate the claims" went on watching a string that could no longer change.
## A tripwire holding its own copy of the thing it watches cannot fire.
## ⚠️ IT WILL MATCH IN-WORLD PROSE, AND THAT IS THE DELIBERATE CHOICE. @cowir-story found
## "Form 1-A: the incident" in Rivet Row — correct prose that `[ABXY]:` adjacency matches — and
## @cowir-controller's conclusion for THEIR arm was to key on caption context instead, because an
## arm that reds on prose gets suppressed. Measured here before copying it: "Plan B: retreat",
## "Tier A: fast" and "Exhibit A: the ledger" all match; live instances in LANE_DIRS today: 0.
##
## Not narrowing, because the risk profiles differ and the symptom is shared while the cause is not.
## Their corpus is 197 prose JSON files; mine is two control-panel directories — 208 `.text`
## assignments, 15 `"text":` dict keys, no prose. A context key (`.text` / `"text":`) would cover
## both historical offenders AND lose a caption built into a local before assignment, i.e. it trades
## a LOUD false positive for a SILENT false negative. A red on "Tier A: fast" costs one
## conversation; the miss shipped "B: Exit" to players in .297.
##
## So if this ever reds on real prose: derive the caption or restructure the string. Do NOT add a
## DEFERRED entry — the key is the regex MATCH, so exempting "B: E" would exempt every B:E… caption
## in the lane, an exemption broader than its subject.
const CENSUS_PATTERN := "(Press [ABXY]\\b|\\b[ABXY]:\\s*[A-Za-z]|\\b[ABXY] or [ABXY]\\b|\\[[ABXY]\\])"

## ⚠️ SCOPE, MEASURED — and this corpus is named after a DIRECTORY while its subject is "captions an
## autogrind player reads". Those are not the same set, and the difference cost a real miss: GameLoop's
## autogrind overlay rendered "P: Pause   B: Exit" with a frozen Nintendo B, and @cowir-controller's
## whole-src sweep found it because mine structurally could not look there.
##
## Who covers what, so nobody assumes this file is the whole net:
##   THIS GUARD          src/ui/autogrind + src/ui/autobattle — captions AND derivation AND reachability
##   controller's net    face letters in caption strings across ALL of src/ (282 files), so
##                       GameLoop's and ControllerOverlay's caption forms are theirs, not a gap
##   NEITHER, today      letters DRAWN on a diagram: ControllerOverlay passes "A"/"B"/"X"/"Y" as
##                       draw_string ARGUMENTS, with no `.text =` and no bracketed form, so a
##                       caption-shaped pattern cannot match them. RadialPicker is the same shape.
##                       Reported to @cowir-controller (msg 10564) as an eighth surface; the fix is
##                       face_position_for_action, in their file and their vocabulary.
##
## ⛔ I deliberately did NOT widen LANE_DIRS to "fix" this. Measured why it would be theatre:
##   deriving the corpus from "files mentioning autogrind that render text" gives 24 files, 14 of them
##   mentions only (BestiaryMenu, CreditsSequence, JukeboxMenu…) — "autogrind" is a TOPIC term, so it
##   catches prose. And the two files that ARE autogrind-facing add nothing here: GameLoop's caption is
##   already in controller's net and their fix is in flight, and ControllerOverlay's letters are
##   invisible to this file's ASCII [ABXY] pattern by construction.
## A corpus widened to look thorough while catching nothing is worse than a narrow one that says so.
const LANE_DIRS := ["res://src/ui/autogrind", "res://src/ui/autobattle"]

## Frozen captions that are NOT fixed, each with the reason -- the value is required non-empty, so
## an entry can be explained green but never silenced green.
## EMPTY, and that is the goal state. "Start:Save" was retired 2026-09-11 by cowir-controller —
## ui_menu now resolves through hint_for_action in BOTH grid editors (Plus / Start / Options).
## @cowir-autogrind pre-authorised the removal when they declared this pin.
const DEFERRED := {}


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
##
## Multi-line `"""` blocks are stripped too — the last of three boundaries this file NAMED and did not
## close. Measured BEFORE changing it: 18 such blocks in the corpus, ZERO body lines the census
## pattern would match, and ZERO change to any reachability caller count. So it closes a hole with no
## live instance, by the same standard as the escape handling above: a named boundary that defends
## nothing reads as diligence, which this file's own header calls out.
##
## 🔬 BRANCH SEPARABILITY, measured — so the next person to mutate this does not repeat the two runs
## that taught nothing. @cowir-overworld's finding: an assert like `assert_false(contains(TRIPLE))` is
## a TAUTOLOGY when the stripper SPLITS on the triple quote, because split() eats its delimiter.
## Not the case here: this drops whole LINES, so a neutered docstring branch leaves the delimiter in
## the output and the assert fires on the keep-logic. Confirmed by isolating each half:
##
##   docstring branch removed, # cut kept    Failing 1   the docstring case, alone
##   # cut removed, docstring branch kept    Failing 2   the 5 stripper cases AND the reachability
##                                                       arm — without the strip, COMMENTS naming
##                                                       AutogrindHistoryScreen count as callers, so
##                                                       `measured 2` flips the dead-hub verdict.
##                                                       Fails toward ALARM, not a false clean.
##   whole function -> `return src`          Failing 2   IDENTICAL signature to removing only the
##                                                       # cut, so the sledgehammer cannot tell one
##                                                       half from both. It is the run to skip.
func _code_only(path: String, must_survive: String) -> String:
	## PATH-taking so the blank-control floor below is safe by construction; a literal cannot reach it.
	assert_gt(must_survive.length(), 0,
		"CONTROL: must_survive must name a real code site — an empty control asserts nothing")
	var raw: String = FileAccess.get_file_as_string(path)
	assert_gt(raw.length(), 0, "CONTROL: %s must be readable" % path)
	var stripped: String = str(GdSource.split(raw)["code"])
	assert_true(stripped.contains(must_survive),
		"CONTROL: the stripper removed load-bearing code (%s) — every arm below it is vacuous" % must_survive)
	return stripped


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
			if _code_only(f, "func ").contains(stem):
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
		var src := _code_only(f, "func ")
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
		if _code_only(f, "func ").contains(target.replace(".gd", "")):
			return f.ends_with("/MenuScene.gd")
	return false


## The 9-row comment/docstring case table that lived here moved to
## test_gd_source_is_the_shared_stripper.gd when this file adopted the shared stripper.
## Seven rows were already covered there; the two that were not — an inline """x"""
## (two fences on one line) and an escaped BACKSLASH at a string end — were carried in.
func test_the_census_reads_a_real_corpus() -> void:
	var files := _gd_files()
	assert_gt(files.size(), 5, "CONTROL: the lane dirs must yield real files, or every assert below is vacuous")
	var total := 0
	for f in files:
		total += FileAccess.get_file_as_string(f).length()
	assert_gt(total, 20000, "CONTROL: and real content, not empty reads")

	## ⛔ LANE_DIRS is AUTHORED-FIXED — a list this guard OWNS — so it needs an `== LITERAL` pin,
	## not just a per-member loop. @cowir-ai's split: a floor or a per-member check is right for a
	## corpus the guard DISCOVERS (it may legitimately grow or shrink), and wrong for a set the
	## guard owns, where shrinking should be a deliberate edit. Measured: dropping
	## "res://src/ui/autobattle" from the array scored EC=0 Passing 7 Risky — GRADE A, because the
	## loop below iterates the list and a removed entry takes its own check with it.
	## Widening the lane's corpus is welcome; doing it silently is not.
	## FLOOR, not equality. @cowir-sfx: the discriminator is whether the set MAY GROW on correct work,
	## not who authored it — and a lane adding a prompt directory is ordinary work, not an event.
	## Measured: a real third dir with a classified surface reds under `== 2` and passes under `>= 2`,
	## while the same dir with its surface UNclassified still reds by name through the arm below.
	assert_gte(LANE_DIRS.size(), 2,
		"LANE_DIRS holds %d, below the 2 prompt directories this lane has — a directory was dropped from the census, which silently un-guards every caption in it" % LANE_DIRS.size())

	## Every declared directory must CONTRIBUTE, and the failure names the one that went quiet.
	for d in LANE_DIRS:
		var from_dir := 0
		for f in files:
			if f.begins_with(d + "/"):
				from_dir += 1
		assert_gt(from_dir, 0,
			"%s contributed ZERO files — the census silently covered only the other lane dir, and a green below would be half a result reported as a whole one" % d)


func test_no_face_button_letter_is_frozen_into_a_caption() -> void:
	# The defect in any spelling: "Press A", "A:Confirm", "A: Confirm", "A or B", "[A]".
	## ⛔ `[ABXY]:[A-Za-z]` REQUIRED THE LETTER TO FOLLOW THE COLON IMMEDIATELY, so "B: Exit" — one
	## space — walked through. It shipped in v3.33.297-alpha at AutogrindDashboard:576 and
	## AutogrindMonitor, BOTH inside LANE_DIRS, i.e. inside the corpus this census claims to cover.
	## @cowir-controller found it by writing their own footer guard; mine was sitting on it.
	## Fifth time in this file that the pattern was narrower than the defect, and the header already
	## records their words for the fourth. `\s*` closes it.
	var re := RegEx.create_from_string(CENSUS_PATTERN)
	var frozen: Array = []
	for f in _gd_files():
		## strip_comments, NOT split: this census REPORTS LINE NUMBERS, and strip_comments emits one
		## output line per input line by construction where the docstring split can shift them.
		var lines := GdSource.strip_comments(FileAccess.get_file_as_string(f)).split("\n")
		for i in lines.size():
			var l: String = lines[i]
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
		var src := _code_only(f, "func ")
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
	var re := RegEx.create_from_string(CENSUS_PATTERN)
	assert_not_null(re, "CONTROL: the census pattern must compile")
	## "B: Exit" is in this list because it is the variant that shipped in .297 while the pattern
	## required the letter to follow the colon immediately. It documents the widened scope.
	for face in ["Press A", "B:Cancel", "B: Exit", "A or B", "[X]"]:
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


## ⛔ THE SCOPE NOTE ABOVE MAKES A CLAIM; THIS CHECKS IT. It says a letter DRAWN on a diagram is
## invisible to this file's caption pattern "by construction" — and a claim in a comment is a claim
## nobody verifies. Measured: 0 matches in both diagram surfaces, so the note is accurate and the gap
## is real rather than an excuse for a narrow corpus.
##
## 🔑 If someone later adds a caption-FORM letter to either file ("B: Exit" rather than
## draw_string(..., "B", ...)), this reds — which is the right moment to revisit the note, because the
## surface would then be reachable by this pattern and arguably belongs in LANE_DIRS after all.
func test_the_diagram_surfaces_really_are_out_of_this_patterns_reach() -> void:
	var rx := RegEx.new()
	assert_eq(rx.compile(CENSUS_PATTERN), OK, "CONTROL: the census pattern must compile or this proves nothing")
	var diagram_files := ["res://src/ui/ControllerOverlay.gd", "res://src/ui/RadialPicker.gd"]
	var reachable: Array = []
	for f in diagram_files:
		var raw: String = FileAccess.get_file_as_string(f)
		assert_ne(raw, "", "CONTROL: %s must be readable — a missing file would pass this vacuously" % f)
		for line in _code_only(f, "func ").split("\n"):
			if rx.search(line) != null:
				reachable.append("%s: %s" % [f.get_file(), line.strip_edges().substr(0, 60)])
	assert_eq(reachable, [],
		("a diagram surface now carries a CAPTION-form face letter, so this pattern CAN see it and the " +
		"scope note above is stale — decide whether it joins LANE_DIRS: %s") % [reachable])

	## And the positive control: the same pattern must still match a caption form, or "0 matches"
	## above means the pattern is broken rather than the surfaces being out of reach.
	assert_true(rx.search("  B: Exit") != null,
		"CONTROL: the census pattern no longer matches a plain caption form, so every zero it reports is meaningless")


## ⛔ THE BLANKET DOCSTRING STRIP IS SAFE ONLY WHILE NO SCANNED FILE ASSIGNS A TRIPLE-QUOTED REGION.
## @cowir-ai's inversion: `"""` means DOCUMENTATION only until someone assigns it to a name. In
## src/llm/DialoguePrompts.gd the regions are `const AUTOGRIND_GRAMMAR_DESCRIPTION := """…` — shipping
## prompt CONTENT. Stripping there would delete the subject, so the fix inverts. **That is a per-file
## measurement, not a language fact**, and _code_only above strips blindly.
##
## Measured when this arm was written: 0 assigned regions across 41 openers in the 4 scanned files that
## have any. The day someone writes `const SOMETHING := """…"""` into one of them, this reds — which is
## the moment the strip stops being safe and starts deleting the thing a census should read.
func test_no_scanned_file_assigns_a_triple_quoted_region() -> void:
	## The test is "is there CODE BEFORE THE QUOTE", not "does an assignment operator precede it".
	## My first version enumerated operators — `(:=|=|:|\(|,|\[)\s*"""` — and MISSED 2 of the 6 real
	## cases in src/: `return """…` (TitleScreen:519) and a triple quote after a call argument
	## (HowToPlayOverlay:27). Wrong in the REASSURING direction: it reports a clean zero on a file
	## that holds content. The prefix test needs no operator list and reproduces all 6.
	var assigned: Array = []
	var openers := 0
	for d in LANE_DIRS:
		var da := DirAccess.open(d)
		if da == null:
			continue
		for f in da.get_files():
			if not f.ends_with(".gd"):
				continue
			var in_block := false
			var line_no := 0
			for line in FileAccess.get_file_as_string("%s/%s" % [d, f]).split("\n"):
				line_no += 1
				var fences: int = line.count("\"\"\"")
				## `fences >= 1`, not `== 1`: a ONE-LINE `const X := """caption"""` has two fences and an
				## `== 1` gate skips it entirely — the same reassuring-direction miss one layer down.
				if not in_block and fences >= 1:
					openers += 1
					if not _prefix_before_quote(line).is_empty():
						assigned.append("%s:%d %s" % [f, line_no, line.strip_edges().substr(0, 48)])
					in_block = fences % 2 == 1
					continue
				if in_block and fences >= 1:
					in_block = false

	## ✅ VALIDATE BEFORE TRUSTING THE ZERO — @cowir-music's rule. Every form below is a form that
	## EXISTS in src/ today, so this control fails if the classifier stops seeing a real case.
	for known in ['const FOO := """x"""', '\treturn """x"""', '\t\tvar shader_code = """',
			'\t_face_cell("ui_accept", "East")) + """', '\t"key": """x"""']:
		assert_false(_prefix_before_quote(known).is_empty(),
			"classifier cannot see a real assigned form, so its zero is worthless: %s" % known)
	for doc in ['"""Play transition when leaving battle"""', '\t"""Iris-close centered on party"""']:
		assert_true(_prefix_before_quote(doc).is_empty(),
			"classifier called a free docstring assigned — it would red every documented function: %s" % doc)

	gut.p("  scanned openers: %d, assigned (content) regions: %d" % [openers, assigned.size()])
	assert_gt(openers, 10,
		"CONTROL: only %d triple-quote openers found — with none in range this arm cannot fail" % openers)
	assert_eq(assigned, [],
		("a scanned file now ASSIGNS a triple-quoted region, so it is CONTENT and _code_only is " +
		"deleting it — a caption living in that const would be invisible to the census: %s") % [assigned])


## Whatever precedes the first triple quote on a line, trimmed. Empty = a free docstring.
func _prefix_before_quote(line: String) -> String:
	var at: int = line.find("\"\"\"")
	return "" if at < 0 else line.substr(0, at).strip_edges()
