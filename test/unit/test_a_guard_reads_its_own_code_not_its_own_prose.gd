extends GutTest

## `guard_subject.gd` derives the members a guard drives BY NAME from that guard's own source. It
## read the RAW file until 2026-09-16, so a member named in PROSE counted as a reach.
##
## ⛔ BOTH DIRECTIONS ARE SILENT, and a guard's header is the likeliest prose to trip either:
##
##   prose names a member the subject HAS    `found` is inflated   the void floor passes on comment text
##   prose names a member it has LOST        `missing` is inflated  a correct arm reds, and the
##                                                                  natural "fix" is to weaken the floor
##
## The second is the nastier one BECAUSE these floors exist to catch renames — the commit that
## renames a member is the commit whose header explains the rename, by name.
##
## 🔑 LATENT, NOT LIVE, and said plainly so the fix is not read as a bug report. Measured across
## all four callers before the strip went in: raw and stripped derived identical member sets, so
## nothing was wrong today. That is WHY it was cheap — no arm had to move.
##
## 📌 NO SILENT-PASS FLOOR HERE, deliberately. This file reaches GuardSubject as a static on a
## PRELOADED script, which is cowir-controller's parse-time row: rename `audit_calls` and the
## script is DROPPED, `run_tests.sh` exits 3 and says NOT ALL TEST FILES RAN. A floor would defend
## a rung this file cannot occupy — cowir-cutscenes' point that a defence copied where it is not
## needed is its own cost.
const GuardSubject := preload("res://test/unit/helpers/guard_subject.gd")
const FIXTURE := "res://test/unit/helpers/fixtures/a_guard_whose_prose_names_members.gd.txt"


## ⛔ THE FIXTURE FIRST. Every arm below asserts what is ABSENT from a derived set, and an absence
## is also what a fixture that lost its prose reports — so the needles are pinned before they are
## relied on. `.gd.txt` keeps it unparsed and uncollected; it exists only to be read.
func test_the_fixture_still_carries_both_kinds_of_prose() -> void:
	var raw := FileAccess.get_file_as_string(FIXTURE)
	assert_gt(raw.length(), 200, "the fixture must be readable and over guard_subject's 200-byte floor")
	for needle in ['.call("_only_in_hash_prose")', '.get("_hash_prop")',
			'.call("_only_in_docstring")', '.get("_docstring_prop")']:
		assert_true(raw.contains(needle),
			"the fixture no longer names %s in prose, so the arms below assert an absence nobody created" % needle)
	for needle in ['.call("_only_in_code")', '.get("_code_prop")']:
		assert_true(raw.contains(needle),
			"the fixture no longer REACHES %s, so a strip that deleted everything would read as correct" % needle)


## The discrimination itself. A null subject makes `missing` the full derived set, which reads the
## extraction out directly rather than through a subject that might happen to have the names.
func test_prose_members_are_not_derived_and_code_members_are() -> void:
	var calls: Dictionary = GuardSubject.audit_calls(FIXTURE, null)
	var props: Dictionary = GuardSubject.audit_properties(FIXTURE, null)
	assert_eq(str(calls["why"]), "", "the fixture must strip cleanly: %s" % calls["why"])

	var got_calls: Array = calls["missing"]
	var got_props: Array = props["missing"]
	got_calls.sort()
	got_props.sort()
	assert_eq(got_calls, ["_only_in_code"],
		("a `.call(\"name\")` written in a `##` line or a docstring is PROSE ABOUT the code, not a "
		+ "reach — deriving it makes the floor satisfiable by comment text: %s") % [got_calls])
	assert_eq(got_props, ["_code_prop"],
		"the same for a property named in prose: %s" % [got_props])
	assert_eq(int(calls["found"]), 1, "exactly one method is reached in the fixture's code")
	assert_eq(int(props["found"]), 1, "exactly one property is reached in the fixture's code")


## ⛔ THE ORDERING BUG, RIDDEN ALONG. The fixture's `##` header contains a `"""` inside a comment —
## the exact false fence gd_source.split() documents as load-bearing. Strip comments second and
## parity flips for the rest of the file, taking the real reach with it.
func test_a_triple_quote_inside_a_comment_does_not_eat_the_code() -> void:
	var raw := FileAccess.get_file_as_string(FIXTURE)
	var header: String = raw.substr(0, raw.find("func test_that_never_runs"))
	assert_true(header.contains('"""'),
		"the fixture's HEADER must still carry a `\"\"\"` inside a `##` line, or this arm proves nothing")
	assert_eq(int(GuardSubject.audit_calls(FIXTURE, null)["found"]), 1,
		"a `\"\"\"` inside a comment flipped parity and swallowed the fixture's real reach")


## The instrument's own failure, reported as the instrument rather than as a clean subject.
func test_an_unreadable_source_says_so_instead_of_reporting_nothing() -> void:
	var calls: Dictionary = GuardSubject.audit_calls("res://test/unit/__no_such_guard__.gd", null)
	assert_eq(int(calls["found"]), 0, "nothing can be derived from a file that does not exist")
	assert_eq(calls["missing"], [], "...and an empty derived set means an empty missing set")
	assert_string_contains(str(calls["why"]), "read as 0 bytes",
		("an absent source must be REPORTED, because `found 0 / missing []` is exactly what a "
		+ "subject with every member present also looks like: %s") % calls["why"])
