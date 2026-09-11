extends GutTest

## CLAUDE.md's Free Move table drifted twice. The Bard row said 0.4x for months after the data said
## 1.0x — "three lanes quoted 0.4x at each other in one morning", per the note still in that row.
## The Fighter row said "Strike" while jobs.json labels it "Attack"; Rogue is the one whose row
## reads Strike. Both are the same failure: a table nobody re-reads against the data it describes.
##
## So it is read against the data now. The precedent is test_claude_md_editor_table_is_true_regression.

const DOC := "res://CLAUDE.md"
const JOBS := "res://data/jobs.json"
const STARTERS := ["Fighter", "Cleric", "Mage", "Rogue", "Bard"]

func _doc() -> String:
	var s := FileAccess.get_file_as_string(DOC)
	assert_gt(s.length(), 5000, "CONTROL: read CLAUDE.md")
	return s

func _jobs() -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(JOBS))
	assert_not_null(parsed, "CONTROL: jobs.json parses")
	return parsed.get("jobs", parsed)

## The table's rows, as `Job -> the second column`.
func _table_rows() -> Dictionary:
	var doc := _doc()
	var i: int = doc.find("### Free Move (Per-Job)")
	assert_gt(i, -1, "CONTROL: located the Free Move section")
	var j: int = doc.find("\n### ", i + 10)
	var section: String = doc.substr(i, (j - i) if j > -1 else 1200)
	var out: Dictionary = {}
	for line in section.split("\n"):
		if not line.begins_with("|"):
			continue
		var cells: PackedStringArray = line.split("|")
		if cells.size() < 3:
			continue
		var job: String = cells[1].strip_edges()
		if job in STARTERS:
			out[job] = cells[2].strip_edges().replace("**", "")
	return out

func test_the_table_still_has_a_row_for_every_starter() -> void:
	## ⚠️ The vacuity guard. If the section is renamed or the rows reshaped, every assertion below
	## passes over an empty dict — which is how a table check reports health on a table it lost.
	var rows := _table_rows()
	var missing: Array = []
	for s in STARTERS:
		if not rows.has(s):
			missing.append(s)
	assert_eq(missing.size(), 0, "the parser found no row for: " + str(missing))

func test_every_documented_free_move_matches_its_LABEL_in_jobs_json() -> void:
	## The drift itself. The doc's second column must be the label a player actually reads, which is
	## free_move.label — NOT the ability id, and not a flavour name someone liked better.
	var rows := _table_rows()
	var jobs := _jobs()
	var wrong: Array = []
	for job_name in rows:
		var jid: String = job_name.to_lower()
		var fm: Dictionary = (jobs.get(jid, {}) as Dictionary).get("free_move", {})
		var label: String = str(fm.get("label", "Attack"))
		if str(rows[job_name]) != label:
			wrong.append("%s: doc says '%s', jobs.json labels it '%s'" % [job_name, rows[job_name], label])
	assert_eq(wrong.size(), 0, "the Free Move table disagrees with the data it describes: " + str(wrong))

func test_the_reader_discriminates() -> void:
	## A table reader that returns the same answer for every job proves nothing. Fighter and Rogue
	## are both basic_attack jobs and their labels DIFFER — that pair is the discriminator.
	var jobs := _jobs()
	var f: String = str(((jobs.get("fighter", {}) as Dictionary).get("free_move", {}) as Dictionary).get("label", "Attack"))
	var r: String = str(((jobs.get("rogue", {}) as Dictionary).get("free_move", {}) as Dictionary).get("label", "Attack"))
	assert_ne(f, r, "CONTROL: fighter and rogue must have different labels, or this file cannot detect a swap")
	var rows := _table_rows()
	assert_ne(str(rows.get("Fighter", "")), str(rows.get("Rogue", "")),
		"CONTROL: the parser reads the two rows separately rather than returning one value twice")

func test_the_ability_free_moves_name_an_ability_that_exists() -> void:
	## The other half: Pray/Channel/Riff are ability-typed, so their label is flavour and the ability
	## id is the load-bearing part. An id that resolves to nothing is a menu row that cannot fire.
	var jobs := _jobs()
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/abilities.json"))
	assert_not_null(parsed, "CONTROL: abilities.json parses")
	var abilities: Dictionary = parsed.get("abilities", parsed)
	var checked: int = 0
	var bad: Array = []
	for jid in ["fighter", "cleric", "mage", "rogue", "bard"]:
		var fm: Dictionary = (jobs.get(jid, {}) as Dictionary).get("free_move", {})
		if str(fm.get("type", "basic_attack")) != "ability":
			continue
		checked += 1
		var aid: String = str(fm.get("ability_id", ""))
		if aid == "" or not abilities.has(aid):
			bad.append("%s/%s" % [jid, aid])
	assert_eq(checked, 3, "CONTROL: exactly three starters use an ability free move (%d)" % checked)
	assert_eq(bad.size(), 0, "an ability free move names an id that does not exist: " + str(bad))
