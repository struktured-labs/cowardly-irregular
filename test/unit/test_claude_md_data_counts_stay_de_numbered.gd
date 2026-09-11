extends GutTest

## FOUR drifted counts in CLAUDE.md in one hour, found by four lanes, all the same way: a number
## true when written, stale because CONTENT ARRIVED.
##   98 monsters -> 106 · 193 cutscenes -> 197 (x3) · 90 monster_sheets -> 114
##
## ⚠️ MY FIRST FIX WAS THE WRONG SHAPE AND THREE LANES TALKED ME OUT OF IT. I corrected the numbers
## and pinned them against the data. cowir-overworld's axis is why that is wrong: these sentences
## are DESCRIPTIVE — nobody acts on them — so a ratchet reds on every monster cowir-sprites adds and
## every scene cowir-story writes. A correct-work tax defending prose with no consumer.
##
## The distinction that makes cowir-music's counterpart worth ITS tax: theirs defends the LABEL —
## 161 files vs 165 entries vs the alias family, three true answers where the doc must say which.
## The ambiguity is the defended property. `monster_sheets` has one true answer and the sentence
## already names it, so there was nothing to defend but the digits.
##
## So the counts are DE-NUMBERED, and this guards only that they stay that way — which reds when
## someone reintroduces a bare count, and never when content arrives.

const DOC := "res://CLAUDE.md"

func _doc() -> String:
	var s := FileAccess.get_file_as_string(DOC)
	assert_gt(s.length(), 5000, "CONTROL: read CLAUDE.md")
	return s

func test_no_bare_count_returns_to_the_de_numbered_claims() -> void:
	var doc := _doc()
	var offenders: Array = []
	var patterns := {
		"[0-9]+ monsters \\(artist art": "the monster inventory count",
		"[0-9]+ entries in `monster_sheets`": "the monster_sheets count",
	}
	for pat in patterns:
		var re := RegEx.new()
		re.compile(pat)
		var m := re.search(doc)
		if m != null:
			offenders.append("%s is numbered again: \"%s\"" % [patterns[pat], m.get_string()])
	assert_eq(offenders.size(), 0,
		"a bare count came back to a sentence nobody acts on — it will go stale the next time content lands: " + str(offenders))

func test_the_sentences_still_say_what_they_are_about() -> void:
	## De-numbering must not become deleting. The reader still needs to know these things exist and
	## where to count them; losing that would be a worse fix than the drift.
	var doc := _doc()
	assert_true(doc.contains("count: `data/monsters.json`"),
		"the monster line must still point at where the real count lives")
	assert_true(doc.contains("registered in the `monster_sheets` section"),
		"the sprite line must still name the section it describes")

func test_the_reader_can_actually_fail() -> void:
	## A regex that cannot match is a guard that cannot fire. Prove both patterns match the form they
	## forbid, against strings rather than against the doc.
	var samples := ["106 monsters (artist art for x", "114 entries in `monster_sheets` section"]
	var pats := ["[0-9]+ monsters \\(artist art", "[0-9]+ entries in `monster_sheets`"]
	for i in samples.size():
		var re := RegEx.new()
		re.compile(pats[i])
		assert_not_null(re.search(samples[i]),
			"CONTROL: pattern %d must match the numbered form it forbids" % i)
