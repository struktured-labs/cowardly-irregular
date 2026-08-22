extends GutTest
## The connectivity auditor must not be able to report a clean map by failing to read one.
##
## FOUND 2026-08-22, by me, about my own change. Restoring W1 to the audit, I wrote
## `impassable_types("TileGenerator") or set()`. The regex bridges the signature to the
## return with \s*\n\s*, which does not cross TileGenerator's three comment lines, so it
## returned None -- and `or set()` turned that into "nothing blocks this world." The tool
## printed `block=(none) walkable 28000/28000 (100%) components=1`: a perfect audit,
## produced by reading nothing.
##
## WHY A GREP WOULD NOT DO. The defect was not a spelling; the tool's source was valid
## python that ran to completion and printed a confident answer. Only its OUTPUT was
## meaningless. This runs it and asks whether the answer could be a real one.
##
## THE ASSERTIONS ARE RELATIONSHIPS, NOT VALUES. Pinning "65% walkable" or "15 sites"
## would red on any correct map edit and pass on a wrong value re-typed. What cannot be
## true of a real W1 is that nothing blocks it, or that all 28000 cells are walkable when
## a third of the map is water.
##
## BOUND: this guards the auditor's ability to MEASURE. Whether W1's layout is good is a
## design question, and STRANDED is covered by the mutation arm in the commit, not here.

const AUDIT := "tools/audit_overworld_connectivity.py"


func _run(args: Array) -> Array:
	var out: Array = []
	var code := OS.execute("python3", args, out, true)
	return [code, "\n".join(out.map(func(x): return str(x)))]


func test_the_audit_cannot_report_a_world_that_nothing_blocks() -> void:
	var probe := _run(["-c", "print('alive')"])
	if int(probe[0]) != 0:
		pending("python3 unavailable -- the auditor cannot be exercised here")
		return
	assert_true(str(probe[1]).contains("alive"), "python control produced no output")

	var res := _run([AUDIT])
	var text := str(res[1])
	assert_eq(int(res[0]), 0, "the auditor did not run: " + text.substr(0, 300))
	assert_true(text.contains("W1 medieval"), "W1 is absent from the audit entirely")

	var w1 := ""
	for line in text.split("\n"):
		if line.begins_with("W1 medieval"):
			w1 = line
	assert_ne(w1, "", "no W1 result line to inspect")
	assert_false(w1.contains("block=(none)"), "W1 reports that nothing blocks it -- extraction failed silently")
	assert_false(w1.contains("28000/28000"), "W1 reports every cell walkable -- a third of the map is water")
	assert_true(w1.contains("components="), "the W1 line carries no component count")


func test_every_world_gets_a_classification_and_none_of_them_is_a_vacuous_ok() -> void:
	var probe := _run(["-c", "print('alive')"])
	if int(probe[0]) != 0:
		pending("python3 unavailable -- the auditor cannot be exercised here")
		return
	var text := str(_run([AUDIT])[1])

	# every world header must be followed by a classification; a silently skipped world
	# is the failure this counts, and it is exercised on every run
	var headers := 0
	var classified := 0
	var vacuous_ok := 0
	for line in text.split("\n"):
		if line.begins_with("W") and line.contains("block="):
			headers += 1
		if line.contains("sites "):
			classified += 1
		if line.contains("sites 0") and line.contains("OK"):
			vacuous_ok += 1
	assert_gt(headers, 5, "fewer than six worlds were audited -- the world list is not being read")
	assert_eq(classified, headers, "a world was audited but never classified")
	assert_eq(vacuous_ok, 0, "a world classified 0 sites and still printed OK")
