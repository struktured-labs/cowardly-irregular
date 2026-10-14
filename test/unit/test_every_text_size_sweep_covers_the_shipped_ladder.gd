extends GutTest

## Adding a Text Size preset to SettingsMenu silently fails to reach most of the suite.
##
## Measured on the pending .694 tree: 30 guards drive `GameState.text_size_scale` from a declared
## numeric ladder, and 25 of them reference `SettingsMenu.TEXT_SIZE_PRESETS` NOWHERE — they carry
## `const PRESETS: Array = [0.8, 1.0, 1.25, 1.5, 2.0]` and nothing ties it to what ships. A sixth
## preset would leave every one of those sweeps a rung short while each file still READ as covering
## every Text Size, which is the "a stale partition skips a rung AND reads as exhaustive" shape.
##
## ⛔ WHY THIS IS ONE GUARD AND NOT 25 PIN ARMS. Those files belong to eight lanes and several have
## branches in flight against them; a 25-file commit from one lane is a conflict surface for a
## check that belongs in one place. This file touches nothing and covers every future sweep too.
##
## ⛔ WHY THE ASSERTION IS A UNION AND NOT AN EQUALITY. Two files deliberately PARTITION the ladder
## rather than iterate it:
##
##     test_a_full_roster_keeps_the_log_at_every_text_size
##         const FITTING: Array     = [0.8, 1.0, 1.25]
##         const NOT_FITTING: Array = [1.5, 2.0]
##
## That split encodes a real decision — the full-roster battle log does not fit above 125% and the
## trade is held for struktured — so equality against either half would red on correct work. The
## union is what must cover the shipped ladder, and it is also the right assertion for the single-
## ladder case, where the union is the one list.
##
## 🔑 THE SELECTOR IS VALUE-INDEPENDENT, which is the whole point. Choosing the corpus by "contains
## the five shipped numbers" would make this arm a tautology: every member would match by
## construction and could never red. A file qualifies because it DRIVES `text_size_scale` from a
## declared array — true before and after the ladder changes — so when a preset is added the
## members stay in the corpus and their stale ladders red.

## ⚠️ WHAT THIS DOES NOT COVER, measured rather than assumed. Of 47 files that drive
## `text_size_scale`, 30 declare a ladder (this guard's corpus) and 18 do not. Eleven of those 18
## alias or pin the shipped const already. The other SEVEN sample individual presets inline —
## `_open(0.8)` / `_open(2.0)` helpers, before/after pairs at 1.0 and 1.5, and two that set the
## scale once and are not sweeps at all (`test_a_settings_load_says_what_it_applied`,
## `test_zz_text_size_scale_not_leaked_by_tests`). Those are point samples BY DESIGN, so demanding
## they cover five rungs would impose a different test shape on six other lanes. They are outside
## this guard deliberately, and a new preset does not silently un-cover them the way it does a
## stale ladder — there was never a list claiming to be complete.
##
## ✅ PROVEN TO FAIL BEFORE IT WAS COMMITTED, by reimplementing the predicate over the real corpus:
## 2795 guard files walked, 47 sweeps, 30 ladders, 0 red on the current tree — and with a 2.5 rung
## appended to the shipped ladder, 29 files red; with a MIDDLE rung of 1.75 inserted, 29 red. A
## check that cannot pass is as bad as one that cannot fail, and this one does both.
##
## ⛔ AND THE CORPUS COUNT IS NOT ASSERTED ANYWHERE, deliberately. See the planted control in the
## arm below: 30 is a measurement, never a floor, because several lanes are converting these files
## to the aliased const and every conversion correctly makes the number smaller.

const SETTINGS_PATH := "res://src/ui/SettingsMenu.gd"
const UNIT_DIR := "res://test/unit"

## SELF-EXCLUSION. ⚠️ MEASURED RATHER THAN ASSUMED, and it is a BELT, not the thing holding the
## line — I first wrote here that without it the walk "would admit this file and measure its
## fixtures", and only the first half is true.
##
## Mutating this constant to a wrong name reds NOTHING: the file IS admitted to the corpus (its
## planted sources contain `text_size_scale =`), and it yields **0 ladders**, because `_ladders`
## anchors on `^[\t ]*(?:const|var)` and every fixture here sits INSIDE a string literal,
## mid-line, after `_ladders("`. So it lands in the `no_ladder` skip list, asserts nothing and
## cannot pollute the union either.
##
## What this constant actually defends is a FUTURE authoring pattern: a fixture written at column 0
## — a multi-line planted source whose line begins `const PRESETS...` — would match the anchor and
## enter as a real ladder. Cheap belt, kept deliberately, claimed accurately.
##
## 🔑 Third time this session I wrote down a protection's REASON without testing which clause
## supplies it (the other two: a clip_text claim's axis, and crediting the float filter for an
## exclusion the range bound makes). The cure is the same each time — cut the clause and look.
const SELF := "test_every_text_size_sweep_covers_the_shipped_ladder.gd"


## The shipped ladder, read through the constant MAP rather than as `settings.TEXT_SIZE_PRESETS`.
## A direct const read on a renamed name raises mid-arm, and GUT scores an aborted body as a PASS —
## so the arm that exists to notice the constant going away would go green on exactly that.
func _shipped() -> Array:
	var settings: Script = load(SETTINGS_PATH)
	if settings == null:
		return []
	return settings.get_script_constant_map().get("TEXT_SIZE_PRESETS", [])


## Every `const`/`var` whose initialiser is an array of FLOAT literals inside [lo, hi].
##
## ⚠️ Matched LINE BY LINE on purpose. The inner group is a negated class, and a negated class
## matches newlines — run against whole-file text it swallows everything between two brackets on
## different lines. Splitting first means the subject cannot contain a newline at all.
##
## ⛔ TWO FILTERS, AND I FIRST WROTE DOWN THE WRONG ATTRIBUTION. The RANGE bound is what keeps
## `const WORLDS := [0, 1, 6]` out (0 < 0.8 and 6 > 2.0) — not the float requirement, which I had
## credited here. Found by mutating the detector rather than by reading it: deleting the float
## filter reddened NOTHING in the original fixture set, because every int fixture I had was also
## out of range.
##
## The float requirement's own case is an int array INSIDE the range, `const LEVELS := [1, 2]`, and
## it is load-bearing in the FALSE-CLEAN direction: admitted, it contributes 1.0 and 2.0 to the
## union — two shipped presets — and helps satisfy an assertion it has nothing to do with. There is
## a fixture for it below now.
##
## The range bound is what keeps a coordinate list like [860.0, 900.0, 840.0] out, and it
## depends only on the ladder's ENDS, never on its membership — so it still admits today's arrays
## after a preset is added at either end.
func _ladders(src: String, lo: float, hi: float) -> Array:
	var re := RegEx.new()
	re.compile("^[\\t ]*(?:const|var)[\\t ]+[A-Za-z_][A-Za-z0-9_]*[\\t ]*(?::[\\t ]*Array(?:\\[float\\])?)?[\\t ]*:?=[\\t ]*\\[([^\\]]*)\\]")
	var out: Array = []
	for line in src.split("\n"):
		var m := re.search(line)
		if m == null:
			continue
		var inner: String = m.get_string(1).strip_edges()
		if inner == "":
			continue
		var vals: Array = []
		var ok := true
		for tok in inner.split(","):
			var t: String = tok.strip_edges()
			if t == "" or not t.contains(".") or not t.is_valid_float():
				ok = false
				break
			var v := t.to_float()
			if v < lo or v > hi:
				ok = false
				break
			vals.append(v)
		if ok and not vals.is_empty():
			out.append(vals)
	return out


func test_every_text_size_sweep_covers_every_shipped_preset() -> void:
	var shipped: Array = _shipped()
	assert_gt(shipped.size(), 1,
		"CONTROL: SettingsMenu.TEXT_SIZE_PRESETS must read as a ladder, got %s" % [str(shipped)])

	var lo := INF
	var hi := -INF
	for p in shipped:
		lo = minf(lo, float(p))
		hi = maxf(hi, float(p))

	var dir := DirAccess.open(UNIT_DIR)
	assert_not_null(dir, "CONTROL: %s must be listable or this arm checks nothing" % UNIT_DIR)
	if dir == null:
		return

	var files_seen := 0
	var sweeps_seen := 0
	var ladders_seen := 0
	var short: Array = []
	var no_ladder: Array = []
	for file_name in dir.get_files():
		if not (file_name.begins_with("test_") and file_name.ends_with(".gd")):
			continue
		if file_name == SELF:
			continue
		files_seen += 1
		## ⚠ COMMENT-STRIPPED, via the house tool 202 guards already use. A selector that reads RAW
		## source can be captured by ANYONE'S prose: a comment writing `text_size_scale =` admits a
		## file that never sweeps — and a comment documenting this very hazard would write exactly
		## that, which is how a sibling lane captured their own anchor tonight.
		##
		## Measured on this tree before the change: 45 files admitted by a code occurrence, 3 by
		## both, and 0 by a comment ALONE — so this is structural hardening, not a live repair. The
		## blast radius was bounded anyway: a bare `contains` can only be fooled into a false
		## PRESENCE, so a wrongly-admitted file with no declared ladder is a benign skip, and only
		## one that ALSO carries a non-covering in-range float array could have reddened.
		var src: String = GdSource.code_of("%s/%s" % [UNIT_DIR, file_name])
		if src == "" or not src.contains("text_size_scale ="):
			continue
		sweeps_seen += 1
		var ladders: Array = _ladders(src, lo, hi)
		ladders_seen += ladders.size()
		if ladders.is_empty():
			## Not a failure: a sweep may drive two endpoints inline with no declared array. Counted
			## so the corpus figure below cannot quietly shrink to nothing.
			no_ladder.append(file_name)
			continue
		var union := {}
		for lad in ladders:
			for v in lad:
				union[snappedf(float(v), 0.0001)] = true
		var missing: Array = []
		for p in shipped:
			if not union.has(snappedf(float(p), 0.0001)):
				missing.append(float(p))
		if not missing.is_empty():
			short.append("%s sweeps %s and never reaches %s" % [
				file_name, str(union.keys()), str(missing)])

	assert_gt(files_seen, 100,
		"CONTROL: the walk must have read the suite — only %d guard files" % files_seen)
	## The SELECTOR control, which is safe as a floor because nothing is draining it: converting a
	## file to the aliased const leaves it driving `text_size_scale` exactly as before, so it stays
	## in this count. What this catches is the marker string going stale — a refactor to a setter
	## would take the corpus to zero and make every verdict below vacuous with nothing to say so.
	assert_gt(sweeps_seen, 10,
		"CONTROL: %d files drive text_size_scale; a selector that finds almost none makes every "
		% sweeps_seen + "verdict below vacuous")

	## ⛔ THE INSTRUMENT CONTROL IS A PLANTED FIXTURE, NOT A COUNT OF `ladders_seen`. That
	## population is being deliberately DRAINED: every file converted to
	## `const PRESETS := SettingsMenu.TEXT_SIZE_PRESETS` correctly stops declaring a literal and
	## correctly leaves this corpus. It went 31 -> 30 when one lane converted a file, and a second
	## lane's branch takes it 30 -> 25 in a single commit. ⚠️ SO ANY FLOOR ON IT REDS ON EXACTLY
	## THE WORK THIS GUARD WANTS — and it reds at the FOLD, where neither lane's own run can see
	## it, because the two branches are independently green. A floor on a set that several lanes
	## are shrinking on purpose is not a control, it is a countdown.
	##
	## ✅ A planted known answer proves the detector is live at ANY corpus size, including zero —
	## and zero is the correct END STATE here, where nothing is left to pin and this arm should
	## iterate nothing and pass. Built from the shipped ladder so it cannot fall outside lo..hi.
	var planted: Array = []
	for p in shipped:
		planted.append("%.4f" % float(p))
	var probe: Array = _ladders("const PROBE: Array = [%s]\n" % [", ".join(planted)], lo, hi)
	assert_eq(probe.size(), 1,
		"CONTROL: the detector must parse a planted ladder of the shipped presets — a regex that "
		+ "matches nothing reports a clean suite at every corpus size (parsed %d, %d real ladders "
		% [probe.size(), ladders_seen] + "found across %d sweeps)" % sweeps_seen)
	assert_eq(short, [],
		"a Text Size sweep does not cover the shipped ladder:\n  %s" % ["\n  ".join(short)])


## ⚠️ A PLANTED KNOWN ANSWER IN BOTH DIRECTIONS. A detector is an instrument, and the arm above is
## the only consumer — so a regex that silently matched nothing would report a clean suite, and one
## that matched everything would report a clean suite too, by flooding the union.
func test_the_detector_reads_a_declared_ladder() -> void:
	var covering := "const PRESETS: Array = [0.8, 1.0, 1.25, 1.5, 2.0]\n\tgs.text_size_scale = s\n"
	var got: Array = _ladders(covering, 0.8, 2.0)
	assert_eq(got.size(), 1, "one declared ladder must parse out of %s" % [covering])
	if got.size() == 1:
		assert_eq((got[0] as Array).size(), 5, "and it must carry all five values")

	var partitioned := "const FITTING: Array = [0.8, 1.0, 1.25]\nconst NOT_FITTING: Array = [1.5, 2.0]\n"
	var both: Array = _ladders(partitioned, 0.8, 2.0)
	assert_eq(both.size(), 2, "a PARTITIONED sweep must yield both halves, got %s" % [str(both)])

	var untyped := "const PRESETS := [0.8, 1.0, 1.25, 1.5, 2.0]\n"
	assert_eq(_ladders(untyped, 0.8, 2.0).size(), 1, "an inferred-type const must parse too")

	var local := "\tvar presets := [0.8, 1.0, 1.25, 1.5, 2.0]\n"
	assert_eq(_ladders(local, 0.8, 2.0).size(), 1, "a function-local ladder must parse too")


## ⛔ THE ARM THAT MAKES THE STRIP LOAD-BEARING. Without a fixture only this clause rejects, the
## comment-stripping is an untested clause — the shape that reddened nothing when I cut the float
## filter earlier. A marker inside a comment must not reach the selector.
func test_a_commented_marker_does_not_admit_a_file() -> void:
	var prose := "## a sweep sets text_size_scale = 2.0 and measures the result
	pass
"
	assert_false(GdSource.strip_comments(prose).contains("text_size_scale ="),
		"a marker that exists only in a COMMENT must not survive the strip, or any lane's prose "
		+ "can admit a file to this corpus")
	## And the other direction, or the strip could be eating everything and the arm above would
	## pass for the wrong reason.
	var code := "	GameState.text_size_scale = s
"
	assert_true(GdSource.strip_comments(code).contains("text_size_scale ="),
		"a real assignment must SURVIVE the strip — a strip that eats code would empty the corpus "
		+ "and make every verdict vacuous")


func test_the_detector_rejects_what_is_not_a_ladder() -> void:
	assert_eq(_ladders("const WORLDS: Array = [0, 1, 6]\n", 0.8, 2.0).size(), 0,
		"an INT array is not a Text Size ladder")
	## ⛔ THE FIXTURE THE ORIGINAL SET WAS MISSING, and the only one the float filter alone rejects.
	## Every other int fixture here is ALSO out of range, so deleting that filter left the whole
	## arm inert — measured, not supposed. Its values sit inside 0.8..2.0, so the range bound
	## cannot help: admitted, it would contribute 1.0 and 2.0 to the union and help satisfy the
	## coverage assertion from a list that is not a Text Size ladder at all.
	assert_eq(_ladders("const LEVELS: Array = [1, 2]\n", 0.8, 2.0).size(), 0,
		"an INT array INSIDE the ladder's range is still not a ladder — this is the arm that makes "
		+ "the float filter load-bearing, and the false-clean direction if it is dropped")
	assert_eq(_ladders("\tvar xs := [860.0, 900.0, 840.0, 800.0, 760.0]\n", 0.8, 2.0).size(), 0,
		"floats outside the ladder's own ends are a coordinate list, not a ladder")
	assert_eq(_ladders("const NAMES: Array = [\"a\", \"b\"]\n", 0.8, 2.0).size(), 0,
		"a string array is not a ladder")
	assert_eq(_ladders("const EMPTY: Array = []\n", 0.8, 2.0).size(), 0,
		"an empty array is not a ladder")
	## The arm above would go green on a stale sweep if the detector dropped the offending half of a
	## partition, so prove a SHORT ladder still parses and is simply short.
	var short_only: Array = _ladders("const PRESETS: Array = [0.8, 1.0]\n", 0.8, 2.0)
	assert_eq(short_only.size(), 1, "a ladder that COVERS TOO LITTLE must still parse, or the "
		+ "sweep arm cannot see it to fail it")
