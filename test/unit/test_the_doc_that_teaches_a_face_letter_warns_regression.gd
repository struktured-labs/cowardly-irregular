extends GutTest

## CLAUDE.md carries TWO gamepad control tables, both in Nintendo/SNES naming, and only one of
## them said so. Six frozen captions shipped between `.308` and `.332` naming `A`/`B` — every one
## inverted on an Xbox pad — and a lane authoring from the unwarned table would write the seventh.
##
## ⛔ THIS IS THE UPSTREAM OF THAT WHOLE CLASS. Every caption fix this lane shipped was downstream
## repair; the doc is where the convention is taught. A table that names `A` for Confirm without
## saying whose `A` it means is an instruction to freeze a Nintendo letter, and it is read by
## every lane rather than by the one that owns input.
##
## ⚠️ NOT PLAYER-VISIBLE, and worth saying plainly: nothing on screen changes. This guards the
## source of a recurring player-visible defect, which is a different claim from fixing one.
##
## Face positions measured against InputProfileManager rather than transcribed:
##   index 0 south  Ⓑ/Ⓐ/✕      index 1 east  Ⓐ/Ⓑ/○
##   index 2 west   Ⓨ/Ⓧ/□      index 3 north Ⓧ/Ⓨ/△
## so "A" is the EAST face and an Xbox pad prints B there.

const DOC := "res://CLAUDE.md"

## A table teaching a pad convention must carry these, near it and before it.
const DERIVE_MARKERS := ["hint_for_action", "Nintendo"]


func _doc() -> String:
	var s := FileAccess.get_file_as_string(DOC)
	assert_gt(s.length(), 5000, "CONTROL: CLAUDE.md must be readable and substantial, got %d" % s.length())
	return s


## Every "| Action | Gamepad | Keyboard |" header in the doc — the shape that teaches a mapping.
func _control_table_offsets(doc: String) -> Array:
	var out := []
	var at := doc.find("| Action | Gamepad | Keyboard |")
	while at > -1:
		out.append(at)
		at = doc.find("| Action | Gamepad | Keyboard |", at + 1)
	return out


## ⛔ THE RATCHET. Each control table must be preceded by the derive warning, within the section
## that introduces it — not merely somewhere in a 900-line file.
func test_every_gamepad_control_table_warns_before_it() -> void:
	var doc := _doc()
	var tables := _control_table_offsets(doc)
	assert_gt(tables.size(), 1,
		"CONTROL: the doc must hold more than one control table, or this guard has one case and " +
		"cannot have caught the asymmetry it exists for — found %d" % tables.size())
	var offenders: Array[String] = []
	for at in tables:
		# The warning must sit in the 1200 chars before the table — i.e. in its own section.
		var window := doc.substr(maxi(0, at - 1200), mini(1200, at))
		var missing := []
		for m in DERIVE_MARKERS:
			if window.find(m) == -1:
				missing.append(m)
		if not missing.is_empty():
			var head := doc.substr(maxi(0, at - 90), 90).replace("\n", " ⏎ ")
			offenders.append("table near …%s… lacks %s" % [head.strip_edges(), ", ".join(missing)])
	assert_eq(offenders, [] as Array[String],
		"a gamepad control table teaches a face letter with no warning that the column is ONE " +
		"family's naming.\nFIX: put the same paragraph the Autobattle Editor table carries above " +
		"it — say the column is Nintendo/SNES, and that anything a PLAYER sees must derive through " +
		"InputProfileManager.hint_for_action(action), or face_position_for_action(action) when no " +
		"pad is attached. Offenders: %s" % ", ".join(offenders))


## The doc must state the convention CORRECTLY, not merely state one. Confirm is the EAST face.
func test_the_doc_names_the_east_face_convention() -> void:
	var doc := _doc()
	assert_true(doc.find("EAST") > -1,
		"the doc must say Confirm sits on the EAST face — that single fact is what makes " +
		"'A' wrong on an Xbox pad, and every frozen caption came from not knowing it")
	assert_true(doc.find("face_position_for_action") > -1,
		"the doc must name the no-pad helper too: hint_for_action alone does not tell a lane what " +
		"to do when there is no pad, which is the bucket-4 half of the same class")


## The doc's claims must match the CODE, measured — a doc that teaches a stale table is the same
## defect one layer up, and this project has a documented history of exactly that.
func test_the_docs_face_table_matches_the_engine() -> void:
	var ipm = InputProfileManager
	assert_eq(ipm.FACE_POSITIONS[1], "East", "index 1 is the east face")
	assert_eq(str(ipm.FACE_GLYPHS["nintendo"][1]), "Ⓐ", "…and Nintendo prints A there")
	assert_eq(str(ipm.FACE_GLYPHS["xbox"][1]), "Ⓑ", "…while Xbox prints B there — the inversion")
	assert_eq(ipm.FACE_POSITIONS[0], "South", "index 0 is south")
	assert_eq(str(ipm.FACE_GLYPHS["xbox"][0]), "Ⓐ", "Xbox prints A on south, which is Cancel")
	var doc := _doc()
	for row in ["| A | east |", "| B | south |"]:
		assert_true(doc.find(row) > -1,
			"the doc's face table must carry the row '%s' — it is the thing a lane reads instead " % row +
			"of guessing, and it must agree with FACE_POSITIONS above")


## THE CONTROL. Without it the ratchet passes on an unreadable doc and a zero-table scan.
func test_the_scanner_finds_real_tables_and_can_miss() -> void:
	var doc := _doc()
	assert_gt(_control_table_offsets(doc).size(), 1, "the walker must find the real tables")
	assert_eq(_control_table_offsets("no tables here at all").size(), 0,
		"…and must find none in text that has none, or 'no offenders' means 'read nothing'")
	# A synthetic unwarned table must be seen as missing the markers.
	var synthetic := "### Some Controls\nnothing here says the word\n| Action | Gamepad | Keyboard |"
	var at := synthetic.find("| Action | Gamepad | Keyboard |")
	var window := synthetic.substr(0, at)
	assert_eq(window.find("hint_for_action"), -1,
		"CONTROL: an unwarned table's window must genuinely lack the marker, or the ratchet " +
		"cannot distinguish a warned table from an unwarned one")
