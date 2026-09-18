extends GutTest

## `FileAccess.open(path, WRITE)` TRUNCATES ON OPEN. `_write_save_file` opened the player's slot
## directly and only then ran `JSON.stringify` over the whole game state, so for the duration of
## serializing party + quests + inventory + bestiary + injuries + corruption the save on disk was
## 0 bytes. A crash in that window did not corrupt the save, it erased it.
##
## ⛔ THE WINDOW WAS NOT A RACE AGAINST ANOTHER WRITER — it is a race against your own process
## dying, which is why no lock or latch could have covered it (@cowir-controller's framing, found
## on the same shape in the input-mapping writer).
##
## 🔑 AND THE CAUSE WAS ALREADY DIAGNOSED IN THIS FILE: `load_settings`' own docstring says
## "Common cause: game crashed mid-write, leaving an empty / truncated settings.json" — somebody
## saw the truncated file, named the mechanism, and hardened the READER. The writer that creates
## the truncated file was left alone (@cowir-main).
##
## Repair: serialize first, write to `<slot>.new`, rename into place. The previous save is intact
## until the new one is complete on disk, and a failed rename reports false rather than lying.

const SLOT := 94
## The functions in this file that persist player data. The one hand-list in an otherwise derived
## arm, and it is deliberate: a derived corpus shrinks silently, a named one reds.
const PERSISTERS := ["_write_save_file", "save_settings"]
const SENTINEL := '{"sentinel":"PREVIOUS","keep":true}'
## The shared stripper. My private one skipped line-start `#` and had never heard of `"""`.
const GdSource := preload("res://test/unit/helpers/gd_source.gd")


func _save_system() -> Node:
	return get_node_or_null("/root/SaveSystem")


func _path() -> String:
	var ss := _save_system()
	return ss._get_save_path(SLOT) if ss else ""


func after_each() -> void:
	## Both the slot and any staging litter, so a failed arm cannot seed the next one.
	var p := _path()
	if p == "":
		return
	for f in [p, p + ".new"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(f)


func test_a_save_round_trips_through_the_staged_write() -> void:
	var ss := _save_system()
	assert_not_null(ss, "SaveSystem autoload unavailable — a skip here reports GREEN having tested nothing")
	if ss == null:
		return
	var ok: bool = ss._write_save_file(SLOT, {"sentinel": "NEW", "n": 7})
	assert_true(ok, "CONTROL: the staged write must report success, or the arms below are about a write that never happened")
	assert_true(FileAccess.file_exists(_path()), "the rename must put the payload at the real slot path")
	var f := FileAccess.open(_path(), FileAccess.READ)
	assert_not_null(f, "the written slot must be readable")
	if f == null:
		return
	var body := f.get_as_text()
	f.close()
	assert_true(body.contains("\"sentinel\""), "the slot must hold the new payload, got: %s" % body.substr(0, 80))
	assert_false(FileAccess.file_exists(_path() + ".new"),
		"the staging file must not survive a successful write — a leftover .new is litter in the player's save dir")


func test_the_previous_save_is_never_truncated_by_starting_a_new_one() -> void:
	## The defect's shape directly: plant a prior save, write over it, and require that at no
	## point is the destination the file being filled. Observable end state — the slot is either
	## the old bytes or the new bytes, never 0.
	var ss := _save_system()
	assert_not_null(ss, "SaveSystem autoload unavailable")
	if ss == null:
		return
	var pre := FileAccess.open(_path(), FileAccess.WRITE)
	assert_not_null(pre, "CONTROL: could not plant a baseline save")
	if pre == null:
		return
	pre.store_string(SENTINEL)
	pre.close()
	assert_eq(FileAccess.get_file_as_string(_path()).length(), SENTINEL.length(),
		"CONTROL: the baseline must be on disk at full length before the overwrite")

	var ok: bool = ss._write_save_file(SLOT, {"sentinel": "NEW"})
	assert_true(ok, "the write must succeed")
	var after := FileAccess.get_file_as_string(_path())
	assert_gt(after.length(), 0,
		"the slot is 0 bytes after a write — this is the erase, not a corruption: the player's save is gone")


func test_the_destination_is_never_opened_for_write() -> void:
	## A SOURCE ratchet, because the defect is the ORDER and the failure cannot be staged: making
	## the process die mid-serialize is not something a test can arrange. Same technique as the
	## jukebox latch guard — pin the two relationships the repair consists of.
	var f := FileAccess.open("res://src/save/SaveSystem.gd", FileAccess.READ)
	assert_not_null(f, "could not read SaveSystem.gd")
	if f == null:
		return
	var src := f.get_as_text()
	f.close()

	## ⚠️ THE WINDOW IS CUT FROM THE CODE HALF. `find`+`substr` on ONE string is index-safe whatever
	## the strip does to line counts, and nothing below prints a line number — the case where
	## delegating is free. On RAW source a `"""` region carrying a column-0 `func ` moves the START
	## or truncates the END, and then the CONTROLS red with a message about the wrong thing.
	var code := str(GdSource.split(src)["code"])
	assert_true(code.contains("DirAccess.rename_absolute"),
		"CONTROL: the strip ate a known code site — the window below would be cut from an emptied corpus")
	var start := code.find("func _write_save_file")
	assert_gt(start, -1, "func _write_save_file not found — renamed? this ratchet is now about nothing")
	if start == -1:
		return
	var end := code.find("\nfunc ", start + 1)
	var body := code.substr(start, (end - start) if end > start else -1)

	var opened_dest: bool = body.contains("FileAccess.open(file_path, FileAccess.WRITE)")
	assert_false(opened_dest,
		"_write_save_file opens the DESTINATION with WRITE, which truncates the player's existing save before the replacement exists")

	var i_stringify := body.find("JSON.stringify")
	var i_open := body.find("FileAccess.open")
	assert_gt(i_stringify, -1, "CONTROL: _write_save_file must still serialize, or this ratchet guards nothing")
	assert_gt(i_open, -1, "CONTROL: _write_save_file must still open a file")
	assert_lt(i_stringify, i_open,
		"JSON.stringify runs AFTER the open (stringify at %d, open at %d) — the whole game state is serialized while the target file is already truncated" % [i_stringify, i_open])

	assert_true(body.contains("rename_absolute"),
		"the staged file must be renamed into place — without it the write is not atomic and a dead process leaves no save")


## Derived rather than hand-listed: EVERY writer in this file, so a third one added later is
## covered without anybody remembering to extend this arm. `_write_save_file` was fixed first and
## `save_settings` sat 170 lines below it with the identical shape — a per-function ratchet would
## have passed the whole time.
func test_no_writer_in_this_file_opens_its_destination() -> void:
	var f := FileAccess.open("res://src/save/SaveSystem.gd", FileAccess.READ)
	assert_not_null(f, "could not read SaveSystem.gd")
	if f == null:
		return
	var src := f.get_as_text()
	f.close()

	var offenders: Array = []
	var staged_writes := 0
	for line in src.split("\n"):
		var t := line.strip_edges()
		if not t.contains("FileAccess.open(") or not t.contains("FileAccess.WRITE"):
			continue
		if t.contains("staged"):
			staged_writes += 1
		else:
			offenders.append(t)

	## ⛔ A COUNT FLOOR IS SATISFIED BY A SURVIVOR. This was `staged_writes > 0`, and it passed with
	## BOTH writers gone: planting the .434 refactor — hoist each open into a shared `_write_staged`
	## helper — left one staged write (the helper's) above the floor, offenders empty, arm GREEN.
	## Every subject had left the derivation and the only thing that red was the per-function arm.
	## So the floor is MEMBERSHIP, by name: each persister must carry its own staged write.
	## (cowir-controller's rule, cowir-sfx's second instance, this is the third.)
	assert_gt(staged_writes, 0,
		"CONTROL: no staged write found in SaveSystem.gd — either the repair is gone or this arm stopped matching it")
	## ⛔ THE PAREN IS LOAD-BEARING AND I LEARNED THAT IN THIS FILE TONIGHT, FOR `FileAccess.open(`,
	## AND DID NOT CARRY IT HERE. `find("func " + fn)` is bounded LEFT by "func " and UNBOUNDED
	## RIGHT, so `func save_settingsX()` satisfies a floor whose subject is gone — measured: a
	## suffix rename left this arm silent while the real function was absent from the file.
	## (cowir-battle's shape: a floor built on a substring accepts a SURVIVOR; one built on an
	## exact or delimited match does not.)
	## ⛔ AND THE PINS READ THE CODE HALF, NOT `src`. A `"""` DOCSTRING IS NOT A COMMENT, AND MY
	## line-start `#` skip had never heard of one — SaveSystem.gd carries 36 docstring lines.
	## Measured here (cowir-battle's 2c, in my file): delegate the write to a helper AND name
	## FileAccess.WRITE in _write_save_file's docstring -> the delegation pin stays GREEN; the same
	## delegation with the docstring untouched -> it reds. One line of prose was the whole
	## difference. Both pins are assert-PRESENT, so a docstring SATISFIES them — the harmful
	## polarity; the two SCANS above are assert-EMPTY, where the same prose is a false RED instead.
	## 📌 AND THE STRIP IS LOAD-BEARING, NOT HYGIENE: delegate the write and leave the old call as a
	## TRAILING comment, and every raw-source arm in this file goes green on the surviving text —
	## this pin is the only one that reds. Failing 1, and it is this assert.
	var halves := GdSource.split(src)
	var code := str(halves["code"])
	## GdSource's own header puts this obligation on every caller: over-stripping and a correct
	## strip are the same green, and an empty doc half passes by construction.
	assert_true(code.contains("DirAccess.rename_absolute"),
		"CONTROL: the strip ate a known code site — the rename that makes the write atomic is gone from the code half, so every pin below is asserting over a corpus the stripper emptied")
	assert_gt(str(halves["doc"]).length(), 0,
		"CONTROL: the doc half is empty, so the split did nothing and these pins are back on raw source — which is the bug they were converted to fix")
	for fn in PERSISTERS:
		assert_eq(_declares(code, fn), 1,
			"PERSISTER %s is not DECLARED exactly once in SaveSystem.gd — renamed, deleted, or surviving only as a comment; this list exists so a disappearance is LOUD rather than a silently smaller corpus" % fn)
		var body := _code_body(code, fn)
		## ⛔ NOT `contains("staged")` — MY FIRST ATTEMPT AT THIS FLOOR, AND IT DID NOT FIRE.
		## Hoisting the open into a helper leaves `var staged := path + ".new"` in place, so the
		## token survives while the write leaves. A name satisfied for a reason unrelated to the
		## property, committed inside the fix for exactly that. The arm's corpus is
		## `FileAccess...WRITE` lines, so the floor must assert what the corpus can SEE.
		assert_true(body.contains("FileAccess.WRITE"),
			"%s no longer performs its own write — it may be correct (a helper can stage and rename just as well), but this arm derives its corpus from FileAccess...WRITE lines and can no longer see it, so a file with every writer delegated would report ZERO offenders and a clean bill. Inline it, or extend this arm to follow the delegate." % fn)
	assert_eq(offenders, [],
		"a writer in SaveSystem.gd opens its real destination with WRITE, which truncates the player's file before the replacement exists: %s" % str(offenders))


func test_the_settings_writer_reports_a_failure_it_used_to_swallow() -> void:
	## `save_settings` returns void and had a bare `if file:` with no else, so a settings save
	## that could not open was indistinguishable from one that worked — at all six call sites.
	var f := FileAccess.open("res://src/save/SaveSystem.gd", FileAccess.READ)
	assert_not_null(f, "could not read SaveSystem.gd")
	if f == null:
		return
	var src := f.get_as_text()
	f.close()
	## Same reasoning as the window above: code half, find+substr, no line numbers.
	var code := str(GdSource.split(src)["code"])
	assert_true(code.contains("DirAccess.rename_absolute"),
		"CONTROL: the strip ate a known code site — the window below would be cut from an emptied corpus")
	var start := code.find("func save_settings(")
	assert_gt(start, -1, "func save_settings not found — renamed? this ratchet is now about nothing")
	if start == -1:
		return
	var end := code.find("\nfunc ", start + 1)
	var body := code.substr(start, (end - start) if end > start else -1)

	assert_true(body.contains("push_warning"),
		"save_settings can fail to open its file and say nothing — the player keeps playing with settings that were never written")
	assert_true(body.contains("rename_absolute"),
		"save_settings must stage and rename: load_settings' own docstring records a crash mid-write already emptying settings.json in the wild")
	## The cleanup is load-bearing for THIS writer only — settings.json holds the BYOK key, and a
	## player who configures it once may never trigger the next save that would truncate an orphan.
	assert_true(body.contains("push_error"),
		"a failed remove of the staging file leaves the player's API key in plaintext at settings.json.new and says nothing — it needs its own loud branch naming the path")


## ⛔ EVERY ARM ABOVE KEYS ON `FileAccess.open(…, WRITE)`. A write by ANY OTHER MECHANISM is not an
## offender and not a missing member — it is INVISIBLE (cowir-sfx's fourth-form lens, via
## cowir-autogrind). This file persists the save slot and the settings, so a future writer using
## another form would bypass both the staging requirement and every check above it.
##
## Zero today, and ALL EIGHT PATTERNS ARE MUTATION-PROVEN rather than asserted: planting one
## function that uses every form makes this arm name every one of them
## (ResourceSaver.save · store_var · store_buffer · store_line · save_png · save_to_file ·
## open_encrypted · open_compressed). cowir-autogrind closed the same caveat on their file by
## planting each in turn; this is the combined version, and it works because the arm appends one
## offender per (line, form) so each pattern must name itself.
##
## ⚠️ THE COMBINED PLANT ALSO TRIPS SIBLING ARMS — it opens a non-staged path — so it proves the
## patterns MATCH and is NOT evidence of "siblings silent". The per-form mutation that showed
## coverage rather than duplication was the single ResourceSaver.save plant.
##
## ⛔ AND THE LIMIT THAT CANNOT BE CLOSED: THE LIST IS HAND-WRITTEN, SO A NINTH FORM IS UNBOUNDED.
## This arm is not "no exotic write can exist"; it is "none of these eight, and nobody has taught
## it a ninth". A hand-written list cannot SHRINK with its subject the way a self-referential floor
## can (cowir-sfx's `elements.keys()` case) — it can only be SHORT, which is the failure this file
## can live with.
const OTHER_WRITE_FORMS := [
	"ResourceSaver.save", "store_var", "store_buffer", "store_line",
	"save_png", "save_to_file", "open_encrypted", "open_compressed",
]


func test_no_write_reaches_disk_by_a_form_these_arms_cannot_see() -> void:
	var f := FileAccess.open("res://src/save/SaveSystem.gd", FileAccess.READ)
	assert_not_null(f, "could not read SaveSystem.gd")
	if f == null:
		return
	var src := f.get_as_text()
	f.close()

	## ⛔ A LIST-DRIVEN ARM IS VACUOUS WHEN THE LIST IS EMPTY, AND MINE WAS: emptying
	## OTHER_WRITE_FORMS left this file at 7 passing, EC=0. The GameLoop control below proves the
	## READ works, not that the list has members — two different things, and only one was checked.
	## (cowir-sprites' case: their protection derivation returns an empty set for `bard` and reports
	## "nothing is artist work", the one answer that destroys everything while looking green.)
	##
	## ⚠️ MEMBERSHIP, NOT A COUNT — a size floor is satisfied by a survivor, which is the hole this
	## whole file spent the evening closing. Named forms, so removing one is loud.
	for required in ["ResourceSaver.save", "store_var", "save_png", "open_encrypted"]:
		assert_true(OTHER_WRITE_FORMS.has(required),
			"OTHER_WRITE_FORMS no longer lists %s — this arm reports a clean file by not looking for it, and an emptied list passes with nothing checked" % required)

	## ⚠️ LINE-PRESERVING STRIP, NOT `split()["code"]` — this arm PRINTS `SaveSystem.gd:%d`, and the
	## code half DELETES doc regions, so every number below it would shift. `strip_comments` emits
	## one line per input line (quote-aware, so a `#` inside a string is not a comment), which also
	## closes the trailing-comment false RED `begins_with("#")` could never see.
	## 📌 THE `"""` HALF IS STILL RAW HERE AND THAT IS STATED RATHER THAN FIXED: measured, SaveSystem.gd
	## carries 78 doc lines and ZERO naming a write form, and the direction is a false RED (prose
	## ACCUSES an assert-EMPTY scan, it cannot hide a real write from it). The index-safe repair is a
	## skip-in-place `code_lines()` on GdSource, which is not mine to add mid-fold.
	var scan_src := GdSource.strip_comments(src)
	var offenders: Array = []
	var line_no := 0
	for line in scan_src.split("\n"):
		line_no += 1
		var t := line.strip_edges()
		for form in OTHER_WRITE_FORMS:
			if t.contains(form):
				offenders.append("%s:%d %s" % ["SaveSystem.gd", line_no, form])
	assert_eq(offenders, [],
		"a write reaches disk by a form the staging arms above cannot see, so it is neither staged nor flagged: %s" % str(offenders))

	## POSITIVE CONTROL — the patterns must find the forms that DO exist in src/, or this zero is
	## a dead matcher reporting health. save_png is the live one; the other seven are absent
	## fleet-wide today, which is why only this one can prove the instrument.
	var probe := FileAccess.open("res://src/GameLoop.gd", FileAccess.READ)
	assert_not_null(probe, "CONTROL: could not read GameLoop.gd")
	if probe == null:
		return
	var gl := probe.get_as_text()
	probe.close()
	assert_true(gl.contains("save_png"),
		"CONTROL: the form patterns find nothing in GameLoop.gd, which is known to call save_png — the matcher is dead and the zero above means nothing")


## ⛔ THE BURDEN IS INVERTED HERE ON PURPOSE: AN OPEN MUST PROVE IT IS READ-ONLY.
## Every other arm asks "is this line a write?" and so requires `FileAccess.WRITE` on the open
## line. A hoisted mode defeats all of them — `var mode := FileAccess.WRITE` then
## `FileAccess.open(path, mode)` — and I verified it: planting that in this file left the whole
## guard at 6 passing, EC=0, with a live truncating write to a user path (cowir-autogrind, who
## planted the same form and found two guards blind at once). So a mode this scan cannot read as
## read-only is a write CANDIDATE, not a pass.
##
## ⚠️ ORDER IS LOAD-BEARING: `READ_WRITE` CONTAINS `READ`, so the write forms are tested FIRST or
## the widest mode reads as the safest.
## ⚠️ AND THE PAREN IS LOAD-BEARING: `:1091` says "FileAccess.open failed" inside a push_warning
## STRING. Requiring `FileAccess.open(` keeps prose out of a source scan.
func test_every_open_here_proves_it_is_read_only_or_is_staged() -> void:
	var f := FileAccess.open("res://src/save/SaveSystem.gd", FileAccess.READ)
	assert_not_null(f, "could not read SaveSystem.gd")
	if f == null:
		return
	var src := f.get_as_text()
	f.close()

	## ⚠️ LINE-PRESERVING STRIP, NOT `split()["code"]` — this arm PRINTS `SaveSystem.gd:%d`, and the
	## code half DELETES doc regions, so every number below it would shift. `strip_comments` emits
	## one line per input line (quote-aware, so a `#` inside a string is not a comment), which also
	## closes the trailing-comment false RED `begins_with("#")` could never see.
	## 📌 THE `"""` HALF IS STILL RAW HERE AND THAT IS STATED RATHER THAN FIXED: measured, SaveSystem.gd
	## carries 78 doc lines and ZERO naming a write form, and the direction is a false RED (prose
	## ACCUSES an assert-EMPTY scan, it cannot hide a real write from it). The index-safe repair is a
	## skip-in-place `code_lines()` on GdSource, which is not mine to add mid-fold.
	var scan_src := GdSource.strip_comments(src)
	var candidates: Array = []
	var read_only := 0
	var line_no := 0
	for line in scan_src.split("\n"):
		line_no += 1
		var t := line.strip_edges()
		if not t.contains("FileAccess.open("):
			continue
		if _classify_open(t) == "read_only":
			read_only += 1
			continue
		## a write, or a mode this scan cannot read: it must be opening the staging path
		if not t.contains("staged"):
			candidates.append("SaveSystem.gd:%d %s" % [line_no, t])

	assert_gt(read_only, 0,
		"CONTROL: no read-only open found in SaveSystem.gd — this file demonstrably reads its own save and settings, so the classifier is not reading modes at all and every pass below is vacuous")
	assert_eq(candidates, [],
		"an open here neither proves it is read-only nor targets the staging path, so it may truncate the player's file where nothing can see it: %s" % str(candidates))

## Extracted so the classifier can be exercised on CONSTRUCTED input, which is the only place both
## answers exist: this file holds no open with an unreadable mode, so the corpus cannot test the
## OVER-MATCH direction. cowir-controller measured that their equivalent control passed while
## matching EVERYTHING — `READABLE_MODES = ["FileAccess."]` classified every open as safe and the
## arm went permanently silent with its control still green.
##
## ⛔ THE VERDICTS NAME WHAT WAS MEASURED, NOT "WRITE-NESS" — I had two mechanism claims wrong here
## and both are corrected from an in-engine probe (write 10 bytes, reopen in each mode, re-read):
##     FileAccess.WRITE        10 -> 0    TRUNCATES
##     FileAccess.WRITE_READ   10 -> 0    TRUNCATES
##     FileAccess.READ_WRITE   10 -> 10   PRESERVES      <- I had pinned this as a truncating write
## (cowir-autogrind measured it first and corrected their own comment; I re-ran it rather than
## relaying, and cowir-controller's rule is why it mattered: a wrong "this truncates" is a claim
## about the MECHANISM, not just the site.)
##
## ⛔ AND "ORDER IS LOAD-BEARING" WAS ALSO WRONG. `"FileAccess.READ_WRITE".contains("FileAccess.WRITE")`
## is FALSE — measured — so READ_WRITE reaches the READ test on its own. The `FileAccess.` PREFIX is
## what prevents the collision; a bare `"WRITE"` test would mis-sort it. Order is incidental.
##
## ⚠️ READ_WRITE IS STILL A CANDIDATE, AND THAT IS DELIBERATE: it does not truncate, and it is not
## read-only either. An in-place byte overwrite of a save slot is its own hazard, so the arm demands
## staging for anything that can write at all — the message just must not say "truncates".
func _classify_open(line: String) -> String:
	if line.contains("FileAccess.WRITE"):
		return "truncating"
	if line.contains("FileAccess.READ_WRITE"):
		return "writable"
	if line.contains("FileAccess.READ"):
		return "read_only"
	return "unprovable"


func test_the_open_classifier_answers_both_ways_on_constructed_input() -> void:
	## A count over the SAFE class cannot see a classifier that calls everything safe — the failure
	## mode of an inverted-burden arm is silence, not noise. So both answers are pinned here.
	assert_eq(_classify_open('var f = FileAccess.open(p, FileAccess.READ)'), "read_only",
		"a literal READ open must classify read-only, or the arm flags every legitimate read in the file")
	assert_eq(_classify_open('var f = FileAccess.open(p, FileAccess.WRITE)'), "truncating",
		"a literal WRITE open must classify truncating — measured 10 bytes -> 0")
	assert_eq(_classify_open('var f = FileAccess.open(p, FileAccess.WRITE_READ)'), "truncating",
		"WRITE_READ also truncates — measured 10 -> 0 — and it is caught by the same FileAccess.WRITE prefix")
	assert_eq(_classify_open('var f = FileAccess.open(p, FileAccess.READ_WRITE)'), "writable",
		"READ_WRITE PRESERVES (measured 10 -> 10) so it must not be labelled truncating, and it is not read-only either — it stays a candidate for the in-place-overwrite hazard, under its own name")
	assert_eq(_classify_open('var w := FileAccess.open(path, mode)'), "unprovable",
		"a HOISTED mode must be unprovable, not read_only — this is the form that left the whole guard at 6 passing with a live truncating write in the file")


## A declaration line, not a substring anywhere in the file. ⛔ THIS IS A PIN (assert-PRESENT), so a
## comment SATISFIES it and the failure is a FALSE GREEN — the harmful polarity (cowir-autogrind).
## Measured: deleting `save_settings` and leaving `# was: func save_settings() -> void:` left the
## floor SILENT while the function was absent. The two SCANS in this file skip `#` lines already, so
## comment-awareness was applied to the scans and not to the pin, in the same file.
##
## ⚠️ A LINE-START REQUIREMENT AND A STRIPPED CORPUS, NOT ONE OR THE OTHER. The left bound alone
## defeats a `#` comment — the `#` occupies column 0 itself, the one case where cowir-sprites'
## "a comment carries your right bound too" cannot reach. It does NOT defeat a `"""` region, whose
## lines keep their own indentation, so callers pass the code half and the bound covers the rest.
func _declares(src: String, fn: String) -> int:
	var n := 0
	for line in src.split("\n"):
		if line.begins_with("func " + fn + "(") or line.begins_with("static func " + fn + "("):
			n += 1
	return n


## One function's lines. ⚠️ PASS THE CODE HALF — this no longer strips anything itself. It used to
## skip line-start `#`, which is a private stripper that cannot inherit a fix and never saw a
## docstring; GdSource.split() does both halves and is the sixteenth copy's replacement, not its peer.
## Index-safe by construction: every assertion over this body is a `contains`, never a line number.
func _code_body(src: String, fn: String) -> String:
	var out: Array = []
	var inside := false
	for line in src.split("\n"):
		if line.begins_with("func ") or line.begins_with("static func "):
			inside = line.begins_with("func " + fn + "(") or line.begins_with("static func " + fn + "(")
		if inside:
			out.append(line)
	return "\n".join(out)
