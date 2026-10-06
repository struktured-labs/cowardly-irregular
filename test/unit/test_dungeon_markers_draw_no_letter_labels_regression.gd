extends GutTest

## Regression for struktured 2026-10-06: "The dungeons have a lot of stubbed tiles with a P, C, B,
## L on them etc. that would be nice to fix." DungeonPuzzleLayer's portal/switch markers used to
## draw the raw layout letter as a Label; they now draw procedural pixel art keyed by hue/shape.
## This scan is DERIVED from source (DirAccess walk + regex), not a hand-listed set of files, so
## the next stub glyph trips the test instead of waiting for someone to spot it on screen.

const SCAN_DIRS := ["res://src/exploration", "res://src/maps"]


func _gd_files(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry != "." and entry != "..":
			var full := dir_path + "/" + entry
			if dir.current_is_dir():
				out.append_array(_gd_files(full))
			elif entry.ends_with(".gd"):
				out.append(full)
		entry = dir.get_next()
	dir.list_dir_end()
	return out


## Every quoted string on a line assigning `.text` that is 1-2 LETTERS ONLY -- the exact shape of
## the old portal-letter / "P" / "L" stubs (no punctuation glyphs like "!"/"▲" are ever flagged).
func _letter_label_offenders(path: String, src_override: String = "") -> Array[String]:
	var offenders: Array[String] = []
	var src := src_override if src_override != "" else FileAccess.get_file_as_string(path)
	var line_re := RegEx.new()
	line_re.compile("\\.text\\s*=")
	var quote_re := RegEx.new()
	quote_re.compile('"([^"]*)"')
	var letter_re := RegEx.new()
	letter_re.compile("^[A-Za-z]{1,2}$")
	var line_no := 0
	for line in src.split("\n"):
		line_no += 1
		if line_re.search(line) == null:
			continue
		for m in quote_re.search_all(line):
			var literal: String = m.get_string(1)
			if letter_re.search(literal) != null:
				offenders.append("%s:%d literal '%s'" % [path, line_no, literal])
	return offenders


func test_no_dungeon_or_overworld_marker_draws_a_bare_letter_label() -> void:
	var files: Array[String] = []
	for d in SCAN_DIRS:
		files.append_array(_gd_files(d))
	assert_gt(files.size(), 50, "CONTROL: the sweep itself is probably broken if it finds this few .gd files")
	var offenders: Array[String] = []
	for f in files:
		offenders.append_array(_letter_label_offenders(f))
	assert_eq(offenders, [] as Array[String],
		"a dungeon/overworld marker is drawing a bare 1-2 letter label as its art: %s" % str(offenders))


func test_the_offender_scan_can_actually_see_a_planted_stub() -> void:
	## CONTROL: without this, a scan that matched nothing (wrong regex, wrong dir) would pass
	## the assertion above for the wrong reason. Plant the exact old ternary stub in a buffer.
	var planted := 'var label := Label.new()\n\tlabel.text = "P" if kind == "plate" else "L"\n'
	var offenders := _letter_label_offenders("res://_probe.gd", planted)
	assert_eq(offenders.size(), 2, "the scan must catch BOTH quoted letters on a ternary .text line: %s" % str(offenders))


func test_the_scan_does_not_flag_punctuation_or_word_text() -> void:
	## CONTROL: arrows, exclamation marks and real words must survive untouched.
	var planted := 'label.text = "▲" if is_up else "▼"\n\tname_label.text = "?!"\n\tname_label.text = "Treasure"\n'
	var offenders := _letter_label_offenders("res://_probe.gd", planted)
	assert_eq(offenders, [] as Array[String], "punctuation glyphs and real words must not be flagged: %s" % str(offenders))
