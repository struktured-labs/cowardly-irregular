extends GutTest

## The shared comment/docstring stripper had ONE consumer and NOTHING pinning its behaviour.
## This table is the pin, moved here from test_overworld_sheet_manifest_audit where it was
## guarding a private copy — six lanes wrote six private strippers this evening and the bugs
## they each debugged (a `A or (B and C)` precedence slip, a `#`-only strip blind to docstrings,
## an untested escape branch, a parity flip from splitting before stripping) were defects of
## DUPLICATION, not of reasoning. One implementation is only an improvement if it is the one
## that is actually tested.
##
## ⛔ A STRIPPER IS AN INSTRUMENT: over-stripping and a correct strip are the same green. Every
## row below that asserts something is GONE is paired with one asserting code SURVIVES, because
## a stripper that returns "" satisfies every removal assertion perfectly.
const GdSource := preload("res://test/unit/helpers/gd_source.gd")

## A `"""` inside a `#` comment. Splitting before stripping flips parity for the rest of the
## file — real code leaves the code half AND prose enters it, both directions from one flip.
const HAZ := "func a():\n\t# see the \"\"\" block below\n\tvar x = 1\n\t\"\"\"doc naming FOO\"\"\"\n\tvar y = 2"


func test_strip_comments_removes_comments_without_eating_code() -> void:
	var cases := [
		["var p = \"KEEP\"", "KEEP", true, "plain code survives"],
		["# var p = \"GONE\"", "GONE", false, "whole-line comment removed"],
		["var p = \"KEEP\"  # GONE", "GONE", false, "trailing comment removed"],
		["var p = \"KEEP\"  # GONE", "KEEP", true, "...without eating the code"],
		["## doc GONE", "GONE", false, "## doc comment removed"],
		["var p = \"a#b\"", "a#b", true, "a # INSIDE a string is not a comment"],
		["var p = 'a#b'", "a#b", true, "...single-quoted too"],
		# The escape branch survived an over-strip mutation at 12/12 before these two landed.
		["var p = \"a\\\"b\"", "a\\\"b", true, "an escaped quote inside a string is preserved"],
		["var p = \"a\\\"b\"  # GONE", "GONE", false, "...and the string still CLOSES, so a trailing # is still a comment"],
	]
	for c in cases:
		var got: String = GdSource.strip_comments(str(c[0]))
		assert_eq(got.contains(str(c[1])), bool(c[2]), "%s — got %s" % [c[3], got])


func test_split_removes_docstrings_without_eating_the_code_around_them() -> void:
	var body := "var a = 1\n\"\"\"GONE doc\"\"\"\nvar b = 2"
	var code: String = str(GdSource.split(body)["code"])
	assert_false(code.contains("GONE"), "a triple-quoted docstring is removed — got %s" % code)
	assert_true(code.contains("var a = 1"), "...without eating the code before it — got %s" % code)
	assert_true(code.contains("var b = 2"), "...or after it — got %s" % code)
	var doc: String = str(GdSource.split(body)["doc"])
	assert_true(doc.contains("GONE"), "the doc half must still CARRY it — an empty doc half passes the three arms above by construction")


## ⛔ THE ORDERING ARM. Three rows, not one: the flip fails in BOTH directions and no single row
## can fail for both. The prose row is the one a "does the code survive" instinct leaves out.
func test_a_fence_inside_a_comment_does_not_flip_parity() -> void:
	var code: String = str(GdSource.split(HAZ)["code"])
	assert_true(code.contains("var x = 1"), "a \"\"\" inside a # comment must not flip parity — var x survives. got: %s" % code)
	assert_true(code.contains("var y = 2"), "...and neither does var y. got: %s" % code)
	assert_false(code.contains("doc naming FOO"), "...and the PROSE must never enter the code half. got: %s" % code)


## ⛔ ANTI-VACUITY. Every arm above is satisfied by a stripper handed literals. None of them says
## the thing does any work on the corpus that matters, and a no-op stripper passes all of them
## that assert presence.
func test_the_stripper_does_real_work_on_a_real_file() -> void:
	var path := "res://src/exploration/TileSheetManifest.gd"
	var raw := FileAccess.get_file_as_string(path)
	assert_gt(raw.length(), 200, "PRECONDITION: %s must be readable" % path)
	assert_true(raw.contains("#"), "ANTI-VACUITY: %s carries no comment, so nothing can be shown to be removed" % path)
	var code: String = GdSource.code_of(path)
	assert_lt(code.length(), raw.length(), "the stripper removed NOTHING from %s — it is a no-op on real source" % path)
	assert_true(code.contains("func "), "OVER-STRIP: the code half of %s has no function left in it" % path)
