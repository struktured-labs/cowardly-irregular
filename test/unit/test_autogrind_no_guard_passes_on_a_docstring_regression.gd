extends GutTest

## GDScript docstrings are STRING LITERALS, not comments — a `#`-only strip leaves them, so prose
## naming a symbol reads exactly like the symbol. @cowir-music measured a live false green from this:
## a guard certifying that a tool resolves basenames passed 4/4 with every real call renamed, because
## `os.path.basename` appeared in the module docstring.
##
## MEASURED IN THIS LANE, and the result is a NEGATIVE:
##
##     guards whose target is src/autogrind or src/ui/autogrind    139
##     …that strip docstrings before a presence check                1
##     …with an asserted literal that lives ONLY in a docstring      0
##
## ⛔ So the SHAPE is in 138 guards and there is no instance today. Retrofitting a docstring strip into
## 138 files would be churn with nothing behind it — @cowir-music's own rule, "a shape is not a
## finding". This file is the alternative: ONE arm that detects the CONDITION for all of them, so the
## first docstring that happens to quote an asserted token reds here instead of quietly certifying
## deleted code. Ban the condition, not the instance.

const LANE_PREFIXES := ["src/autogrind/", "src/ui/autogrind/"]

## A literal that legitimately lives only in a docstring — a guard asserting the DOCUMENTATION says
## something, rather than the code doing it. Empty today; an entry needs a reason, not a tick.
const DOCSTRING_ASSERT_IS_THE_POINT := {}


func _docstring_lines(src: String) -> Dictionary:
	var inside := {}
	var in_block := false
	var start := -1
	var lines := src.split("\n")
	for i in lines.size():
		var fences: int = lines[i].count("\"\"\"")
		if not in_block and fences == 1:
			in_block = true
			start = i
			continue
		if in_block and fences >= 1:
			for n in range(start, i + 1):
				inside[n] = true
			in_block = false
	return inside


## True when `lit` occurs in `src` and EVERY occurrence is inside a docstring block.
func _only_in_a_docstring(src: String, lit: String) -> bool:
	var doc: Dictionary = _docstring_lines(src)
	var lines := src.split("\n")
	var any := false
	for i in lines.size():
		if lines[i].contains(lit):
			any = true
			if not doc.has(i):
				return false
	return any


func test_no_lane_guard_asserts_a_literal_that_only_a_docstring_satisfies() -> void:
	var dir := DirAccess.open("res://test/unit")
	assert_not_null(dir, "CONTROL: test/unit must be listable or this arm checks nothing")
	var target_cache := {}
	var guards_seen := 0
	var literals_seen := 0
	var docstring_lines_seen := 0
	var offenders: Array = []

	for file_name in dir.get_files():
		if not (file_name.begins_with("test_") and file_name.ends_with(".gd")):
			continue
		var gsrc: String = FileAccess.get_file_as_string("res://test/unit/%s" % file_name)
		if gsrc == "":
			continue
		## Which lane files does this guard READ?
		var targets: Array = []
		for pre in LANE_PREFIXES:
			var from: int = 0
			while true:
				var i: int = gsrc.find("res://" + pre, from)
				if i < 0:
					break
				var j: int = gsrc.find(".gd", i)
				if j > -1:
					var path: String = gsrc.substr(i + 6, j + 3 - i - 6)
					if not targets.has(path):
						targets.append(path)
				from = i + 1
		if targets.is_empty():
			continue
		guards_seen += 1

		## Which literals does it assert are PRESENT?
		var lits: Array = []
		var from2: int = 0
		while true:
			var a: int = gsrc.find(".contains(\"", from2)
			if a < 0:
				break
			var b: int = gsrc.find("\")", a + 11)
			if b > -1:
				var lit: String = gsrc.substr(a + 11, b - a - 11)
				if lit.length() >= 4 and not lit.contains("\\") and not lits.has(lit):
					lits.append(lit)
			from2 = a + 1
		literals_seen += lits.size()

		for t in targets:
			if not target_cache.has(t):
				target_cache[t] = FileAccess.get_file_as_string("res://" + t)
			var tsrc: String = target_cache[t]
			if tsrc == "":
				continue
			docstring_lines_seen += _docstring_lines(tsrc).size()
			for lit in lits:
				if DOCSTRING_ASSERT_IS_THE_POINT.has(lit):
					continue
				if _only_in_a_docstring(tsrc, lit):
					offenders.append("%s asserts '%s' and only %s's DOCSTRING satisfies it" % [
						file_name, lit.substr(0, 40), t.get_file()])

	gut.p("  scanned %d lane guards, %d asserted literals" % [guards_seen, literals_seen])
	## ⛔ CONTROLS FIRST. A parser that finds no guards or no literals would report a clean zero
	## forever — the exact hollowness this file exists to detect, in the detector itself.
	assert_gt(guards_seen, 50, "CONTROL: expected the lane's guards, found %d — the target scan is broken" % guards_seen)
	assert_gt(literals_seen, 100, "CONTROL: expected many asserted literals, found %d — the literal scan is broken" % literals_seen)
	## ⛔ ANTI-VACUITY, @cowir-music's defence: the two controls above prove the scan found guards and
	## literals, and say NOTHING about whether it ever examined a DOCSTRING. If the lane's source had
	## none, `_only_in_a_docstring` could never return true and "0 offenders" would be meaningless —
	## the arm would pass by having nothing to do. Measured today: 31 blocks across 3 files, and all
	## three ARE scanned as targets. Floored well below that so it fails when the corpus loses them,
	## not when it merely shrinks.
	assert_gt(docstring_lines_seen, 30,
		"CONTROL: the scan examined only %d docstring LINES — with no docstrings in range this arm cannot fail, so its zero means nothing" % docstring_lines_seen)

	assert_eq(offenders, [],
		("a guard asserts a symbol is present and ONLY a docstring in the target contains it — the " +
		"real code could be deleted and it would stay green. Strip docstrings in that guard, or record " +
		"the literal in DOCSTRING_ASSERT_IS_THE_POINT with a reason: %s") % [offenders])

	## ⛔ Exception validation lives HERE, not in its own arm. As a separate test it looped over an
	## EMPTY dict, asserted nothing, and GUT flagged it Risky — the drained-list hollowness, in the
	## file written to detect hollowness. Folded in beside the controls, which always run.
	for lit in DOCSTRING_ASSERT_IS_THE_POINT.keys():
		var reason: String = str(DOCSTRING_ASSERT_IS_THE_POINT[lit])
		assert_gt(reason.length(), 40,
			"'%s' is excused with '%s' — an exception needs a reason a reader can disagree with" % [lit, reason])


## The detector must actually be able to SEE the condition. Without this, "0 offenders" could mean the
## docstring walker is broken rather than the lane being clean.
func test_the_detector_finds_a_planted_docstring_only_literal() -> void:
	var planted := "func _real_code():\n\t\"\"\"\n\tthis mentions ZZZ_ONLY_IN_PROSE and nothing else does\n\t\"\"\"\n\tpass\n"
	assert_true(_only_in_a_docstring(planted, "ZZZ_ONLY_IN_PROSE"),
		"the walker cannot see a literal that lives only inside a \"\"\" block, so every zero it reports is meaningless")
	## …and must NOT flag one that also appears in real code.
	var both := "func f():\n\t\"\"\"mentions REAL_TOKEN in prose\"\"\"\n\treturn REAL_TOKEN\n"
	assert_false(_only_in_a_docstring(both, "REAL_TOKEN"),
		"the walker flagged a literal that DOES appear in code — it would red on correct guards")
	## …and must not flag something absent entirely.
	assert_false(_only_in_a_docstring("func f():\n\tpass\n", "NOT_HERE"),
		"an absent literal must not be reported as docstring-only")

