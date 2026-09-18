extends GutTest

const GdSource := preload("res://test/unit/helpers/gd_source.gd")

## The truncate-on-open family, for the three writers outside AutogrindSystem. `open(dest, WRITE)`
## truncates, so serializing after it puts the payload inside a window where a process death leaves
## 0 bytes and no previous copy. All three overwrite something the player owns:
##   AutobattleSystem  user://autobattle/profiles.json — 88 KB on struktured's disk, the largest
##   AutogrindUI       the player's authored custom presets
##   ScriptShareManager  export filenames are FIXED, so a re-export overwrites the previous one
## DERIVED per file rather than per function: a per-function ratchet is what let a second writer sit
## 170 lines below a fixed one with the identical shape (cowir-music, src/save).

const SOURCES := {
	"res://src/autobattle/AutobattleSystem.gd": "the largest player-data file in the game",
	"res://src/ui/autogrind/AutogrindUI.gd": "the player's authored autogrind presets",
	"res://src/autobattle/ScriptShareManager.gd": "an export the player hands to a friend",
}


## ✅ FIXED, AND MY REASON FOR NOT FIXING IT WAS FALSE. I recorded this as "deliberately left" on
## the grounds that the failure direction is conservative (a false RED puts a human on the line)
## AND that a quote-aware stripper is ~12 lines of machinery. The second half was wrong:
## GdSource.strip_comments already existed, 181 files use it, and adopting it cost one preload.
## ⛔ @cowir-controller re-derived that same helper privately this evening and caught it; a private
## copy does not inherit a fix, and theirs was quote-aware where GdSource is ALSO escape-aware.
## Four forms planted rather than argued, arm totals 9/9 on every run:
##   trailing comment carrying a write      was a FALSE POSITIVE -> now not flagged
##   whole line commented out                                    -> not flagged
##   real write + `#` inside a push_warning  the truncation hazard -> still FLAGGED
##   control: real write, no comment                              -> FLAGGED
func _write_opens(src: String) -> Array:
	var out: Array = []
	var n := 0
	for line in src.split("\n"):
		n += 1
		var t: String = line.strip_edges()
		if t.begins_with("#") or t.begins_with("##"):
			continue
		if line.contains("FileAccess.open(") and line.contains("WRITE"):
			out.append([n, t])
	return out


## ⛔ MEMBERSHIP, NOT A COUNT — AND THE AGGREGATE VERSION SHIPPED HERE THIS MORNING.
## A count floor is satisfied by a SURVIVOR (@cowir-controller, 2026-09-18). Measured on this very
## file: removing the staged open from TWO of these three writers left it GREEN at 3 passing, because
## the third still had one and the summed floor never noticed. A count answers "did the scan run at
## all"; only per-source membership answers "is EACH writer still being watched".
func test_every_named_writer_is_still_present() -> void:
	var missing: Array = []
	for path in SOURCES:
		var src: String = _code_of(path)
		if src == "":
			missing.append("%s (unreadable — its verdict below would be vacuous)" % path)
		elif _write_opens(src).is_empty():
			missing.append("%s (no WRITE open at all — %s)" % [path, SOURCES[path]])
	assert_eq(missing, [],
		"a writer this file exists to watch has no WRITE open left — it was moved, renamed or deleted, and the offender scan below is silently no longer about it: %s" % str(missing))


func test_no_writer_opens_its_destination() -> void:
	var offenders: Array = []
	for path in SOURCES:
		var src: String = _code_of(path)
		for entry in _write_opens(src):
			if not str(entry[1]).contains("FileAccess.open(staged,"):
				offenders.append("%s:%d — %s (%s)" % [path, entry[0], entry[1], SOURCES[path]])
	assert_eq(offenders, [],
		"These open a destination with WRITE, truncating it before anything is serialized. Stage a sibling and rename it into place: %s" % str(offenders))


func test_every_writer_verifies_its_bytes_before_renaming() -> void:
	## store_string returns nothing, so a short write is invisible — and staging does NOT cover it:
	## a rename carries a partial file into place just as happily. Checked before the rename.
	var missing: Array = []
	for path in SOURCES:
		var src: String = _code_of(path)
		var i_check: int = src.find("get_length()")
		var i_err: int = src.find("get_error()")
		var i_rename: int = src.find("rename_absolute")
		if i_err < 0 or i_check < 0 or i_rename < 0:
			missing.append("%s (get_error=%d get_length=%d rename=%d)" % [path, i_err, i_check, i_rename])
		elif i_check > i_rename:
			missing.append("%s (byte check runs AFTER the rename)" % path)
	assert_eq(missing, [],
		"each writer must consult get_error() AND read its bytes back BEFORE renaming: %s" % str(missing))


## ⛔ SOURCES IS A HAND-LIST OF THE WRITERS THAT EXIST TODAY, AND A CORPUS SCOPED TO WHERE THE
## SUBJECT IS FOUND TODAY CANNOT SEE IT ARRIVE SOMEWHERE NEW (@cowir-controller, 2026-09-18: their
## ratchet named the one src/ui file that writes, so three siblings were INVISIBLE, not clean).
## The arms above ask "did a known writer stop being watched"; this pair asks "did an unwatched
## writer appear". Derived from the lane's directories, so a new FILE is covered with no edit here.
const LANE_DIRS := ["res://src/autogrind", "res://src/ui/autogrind", "res://src/autobattle"]

## Covered by its own guard (test_a_writer_never_opens_its_destination_regression), NOT exempt —
## a second report here would be noise. Its absence from SOURCES is coverage, not a hole.
const COVERED_ELSEWHERE := "AutogrindSystem.gd"


func _lane_gd_files() -> Array:
	var out: Array = []
	var stack: Array = LANE_DIRS.duplicate()
	while not stack.is_empty():
		var d: String = str(stack.pop_back())
		for sub in DirAccess.get_directories_at(d):
			stack.append("%s/%s" % [d, sub])
		for f in DirAccess.get_files_at(d):
			if f.ends_with(".gd"):
				out.append("%s/%s" % [d, f])
	out.sort()
	return out


func test_the_lane_scan_can_actually_fire() -> void:
	## Control: a derived-empty file list makes the arm below vacuously green, which is the shape
	## that let a batch go red today — a green over a corpus that could not contain the defect.
	var files := _lane_gd_files()
	assert_gt(files.size(), 5, "derived implausibly few lane files — the directory walk is broken, not the code")
	assert_true("res://src/autobattle/ScriptShareManager.gd" in files,
		"control: a known writer must appear in the walk, else the arm below is scanning the wrong tree")


func test_no_unwatched_writer_has_appeared_in_the_lane() -> void:
	var unwatched: Array = []
	for path in _lane_gd_files():
		if path.ends_with(COVERED_ELSEWHERE) or SOURCES.has(path):
			continue
		var src: String = _code_of(path)
		if src == "":
			continue
		for entry in _write_opens(src):
			unwatched.append("%s:%d — %s" % [path, entry[0], entry[1]])
	assert_eq(unwatched, [],
		"a file in this lane writes to disk and NOTHING watches its shape — add it to SOURCES with what the player loses if it truncates, or route it through a staged writer: %s" % str(unwatched))


## ⛔ THE ARM ABOVE CATCHES A NEW FILE; THIS ONE CATCHES A NEW *FORM*, AND THE SAME MUTATION HABIT
## HIDES BOTH (@cowir-sfx, 2026-09-18). Every arm in this file keys on `FileAccess.open(…, WRITE)`,
## so a write through ResourceSaver, store_var/store_buffer or save_png reaches disk while every
## assertion here stays green — it is not an offender, it is not a missing member, it is invisible.
## Measured today: my lane uses NO such form, and the same patterns DO find the fleet's four
## (GameLoop ×2, BaseTileGenerator, FeedbackBundle), so the zero is over a working instrument.
## ✅ ALL SEVEN ARE MUTATION-PROVEN, not asserted: each was planted in turn and each reds THIS arm
## and only this arm. @cowir-music flagged the opposite state in their copy — "proven for one form
## and asserted for seven" — because only `save_png` has a live positive anywhere in `src/`, so the
## other six are absent fleet-wide and a pattern that never matches is a pattern never tested.
## ⚠️ WHAT REMAINS AND CANNOT BE CLOSED HERE: THE LIST IS HAND-WRITTEN, SO AN EIGHTH FORM IS
## UNBOUNDED. This arm is not "no exotic write can exist"; it is "none of these seven, and nobody
## has taught it an eighth". @cowir-music's framing of the asymmetry is the right one — this list
## cannot SHRINK with its subject the way a self-referential floor can, it can only be SHORT.
const OTHER_WRITE_FORMS := [
	"ResourceSaver.", "store_var(", "store_buffer(", "store_line(", "store_csv_line(",
	"save_png(", "save_to_file(",
]


## ⛔ AN EMPTY LIST MAKES THE FORM ARM PERMANENTLY GREEN, AND A SIZE FLOOR WOULD BE SATISFIED BY A
## SURVIVOR — the hole this whole file spent the evening closing, one level in (@cowir-music).
## MEASURED: emptying OTHER_WRITE_FORMS left 8 passing WITH A LIVE ResourceSaver WRITE in the lane.
## ⚠️ THE DUPLICATE LIST IS THE POINT, NOT AN OVERSIGHT: a floor whose reference IS the thing under
## test cannot see that thing shrink (@cowir-sfx's `elements.keys()`). Two independent copies means
## deleting a form from one is caught by the other; one copy would delete the witness with it.
func test_the_form_list_still_holds_every_proven_form() -> void:
	var proven := ["ResourceSaver.", "store_var(", "store_buffer(", "store_line(",
		"store_csv_line(", "save_png(", "save_to_file("]
	var missing: Array = []
	for f in proven:
		if not (f in OTHER_WRITE_FORMS):
			missing.append(f)
	assert_eq(missing, [],
		"a write form this file has MUTATION-PROVEN it can catch was removed from OTHER_WRITE_FORMS, so that form now reaches disk unwatched — restore it, or delete its proof from the header too: %s" % str(missing))


func test_no_write_reaches_disk_by_a_form_this_file_cannot_see() -> void:
	var exotic: Array = []
	for path in _lane_gd_files():
		var src: String = _code_of(path)
		if src == "":
			continue
		var n := 0
		for line in src.split("\n"):
			n += 1
			var t: String = line.strip_edges()
			if t.begins_with("#"):
				continue
			for form in OTHER_WRITE_FORMS:
				if line.contains(form):
					exotic.append("%s:%d — %s (%s)" % [path, n, t, form])
					break
	assert_eq(exotic, [],
		"this lane now reaches disk by a form none of the arms above can see, so its truncate-on-open exposure is unaudited — either route it through a staged writer or teach this file the form: %s" % str(exotic))


## ⛔ EVERY ARM ABOVE REQUIRES THE MODE TO BE ON THE OPEN LINE, SO A HOISTED MODE DEFEATS THEM ALL
## (@cowir-controller, 2026-09-18): `var mode := FileAccess.WRITE` then `FileAccess.open(p, mode)`
## carries no "WRITE" where the scan looks. MEASURED by planting exactly that in
## AutogrindAchievements: this file stayed GREEN at 6 passing AND the gate ratchet on main stayed
## GREEN at 5 — a live, ungated, truncating write to user://autogrind/ach.json, invisible to both.
##
## 🔑 SO THE BURDEN IS INVERTED HERE: an open must PROVE it is read-only. A mode this file cannot
## read is a write candidate, not a pass — the opposite default from the arms above, deliberately.
## The whole verdict, in one place, so a CONTROL can feed it a fabricated line rather than trusting
## that the branches below still discriminate.
##
## ⛔ THE VERDICTS NAME WHAT WAS MEASURED, NOT "WRITE-NESS" — @cowir-controller flagged a sibling
## guard calling READ_WRITE truncating, which is wrong about the MECHANISM and not just the site.
## Probed in-engine 2026-09-18 (write 10 bytes, reopen in each mode, re-read the length):
##   FileAccess.WRITE        10 -> 0   TRUNCATES
##   FileAccess.WRITE_READ   10 -> 0   TRUNCATES
##   FileAccess.READ_WRITE   10 -> 10  PRESERVES   <- groups with READ here, deliberately
## ⚠️ THE TWO COMPOUND BRANCHES ARE REDUNDANT TODAY AND I AM SAYING SO RATHER THAN CLAIMING THEY
## ARE LOAD-BEARING — I wrote "match order is load-bearing", then mutated it and both cases PASSED.
## The `FileAccess.` PREFIX is what actually decides it:
##   "FileAccess.READ_WRITE".contains("FileAccess.WRITE")  false -> falls through to the READ test
##   "FileAccess.WRITE_READ".contains("FileAccess.WRITE")  true  -> already caught
## So each compound branch restates an answer the fallthrough gives anyway. They are kept because
## they become load-bearing the moment anyone drops the prefix to match a bare "WRITE" — which is
## precisely the shape @cowir-controller shipped and had to correct. A redundant branch that is
## documented as redundant is cheap; one documented as essential is a claim nothing tests.
func _classify_open(line: String) -> String:
	if line.contains("READ_WRITE"):
		return "non_truncating"
	if line.contains("FileAccess.WRITE") or line.contains("WRITE_READ"):
		return "truncating"
	if line.contains("FileAccess.READ"):
		return "non_truncating"
	return "unprovable"


## ⛔ THE COUNTS ALONE DO NOT CLOSE THE VACUITY, MEASURED RATHER THAN ASSUMED. Making the READ branch
## permissive (`if true`) leaves BOTH counts positive — writes still classify first — while every
## hoisted-mode open falls through unflagged. So the counts catch a DEAD branch and miss a
## PERMISSIVE one, which is the failure @cowir-music's mutation is actually about.
## The only control immune to both is watching the predicate say YES on a known offender.
func test_the_mode_classifier_can_actually_say_unprovable() -> void:
	assert_eq(_classify_open('\tvar w := FileAccess.open(path, mode)'), "unprovable",
		"control: a hoisted-mode open MUST classify unprovable, or the arm below cannot flag the form it exists for")
	assert_eq(_classify_open('\tvar f := FileAccess.open(p, FileAccess.READ)'), "non_truncating",
		"control: an inline READ must classify non_truncating, or the arm reports every open as an offender")
	assert_eq(_classify_open('\tvar f := FileAccess.open(p, FileAccess.WRITE)'), "truncating",
		"control: an inline WRITE must classify truncating")
	assert_eq(_classify_open('\tvar f := FileAccess.open(p, FileAccess.WRITE_READ)'), "truncating",
		"control: WRITE_READ truncates too — probed in-engine, 10 bytes to 0")
	assert_eq(_classify_open('\tvar f := FileAccess.open(p, FileAccess.READ_WRITE)'), "non_truncating",
		"control: READ_WRITE PRESERVES (probed: 10 bytes to 10) and contains \"WRITE\", so it must be tested BEFORE the bare WRITE match or it is mislabelled as truncating")


func test_every_open_proves_its_mode() -> void:
	var unprovable: Array = []
	var seen_write := 0
	var seen_read := 0
	for path in _lane_gd_files():
		var src: String = _code_of(path)
		if src == "":
			continue
		var n := 0
		for line in src.split("\n"):
			n += 1
			var t: String = line.strip_edges()
			if t.begins_with("#") or not line.contains("FileAccess.open("):
				continue
			var verdict: String = _classify_open(line)
			if verdict == "truncating":
				seen_write += 1
				continue
			if verdict == "non_truncating":
				seen_read += 1
				continue
			unprovable.append("%s:%d — %s" % [path, n, t])
	## ⛔ AN INVERTED-BURDEN ARM FAILS SAFE, SO IT BREAKS BY FINDING NOTHING TO FLAG — and an empty
	## `unprovable` is what a CORRECT run and a DEAD classifier both produce (@cowir-music). MEASURED
	## on this arm: forcing every open to classify read-only left it GREEN at 7 passing WITH A LIVE
	## HOISTED WRITE PLANTED IN THE LANE. Both branches must be watched firing, not assumed.
	assert_gt(seen_write, 0,
		"the classifier recognised NO write open in a lane that demonstrably has several — its write branch is dead and the verdict below is vacuous")
	assert_gt(seen_read, 0,
		"the classifier recognised NO read-only open — its read branch is dead, so either every open reads as unprovable or none are being seen at all")
	assert_eq(unprovable, [],
		"this open's mode is not on the line, so every write arm in this file and the gate ratchet on main are blind to it — name the mode inline (FileAccess.WRITE / FileAccess.READ) rather than hoisting it into a variable: %s" % str(unprovable))
