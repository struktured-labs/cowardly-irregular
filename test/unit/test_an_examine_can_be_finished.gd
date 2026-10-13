extends GutTest

## ⛔ 35 OF THE 45 AUTHORED EXAMINES COULD NOT BE READ. `QuestExaminePoint._toast` held a flat 2.2s
## with the fade starting at 1.0s, so the label was gone 3.2s after the press. The pack's toast-path
## rows carry a median of 36 words — about 8.6s of reading at 250 wpm — so the player saw one or two
## lines of a five-line paragraph and it left.
##
## 🔑 THE SAME PACK'S OTHER TEN ROWS WERE ALREADY FINE, which is what made the defect visible: the
## interior rows go through `ReadableProp`, a paged panel the player dismisses, while the village,
## castle and overworld rows went through the timed toast. One body of prose, two renderers, and only
## one of them timed the reader out.
##
## This file judges the HOLD, not the spelling of a literal: `toast_hold_for` is a static seam so the
## arms below call it with the pack's real word counts.

const PACK := "res://data/examine_texts.json"
const INTERIOR_DIR := "res://src/maps/interiors"
const GdSource := preload("res://test/unit/helpers/gd_source.gd")

## An independent reading rate, deliberately FASTER than the implementation's 4 words/sec. A
## restatement of the formula would pass by construction; 5 w/s is a bound the formula must beat,
## so lowering WORDS_PER_SECOND below 5 reds this file.
const FAST_READER_WPS := 5.0


func _entries() -> Dictionary:
	var raw := FileAccess.get_file_as_string(PACK)
	assert_ne(raw, "", "CONTROL: the pack must be readable or every arm here is vacuous")
	var parsed: Variant = JSON.parse_string(raw)
	assert_true(parsed is Dictionary, "CONTROL: the pack must parse")
	return (parsed as Dictionary).get("examines", {}) if parsed is Dictionary else {}


## Scene ids served by ReadableProp's paged panel — derived from the interior classes' own
## `_get_area_id()`, so a new room joins the panel population without editing this file.
func _panel_scenes() -> Array[String]:
	var out: Array[String] = []
	var rx := RegEx.create_from_string('func _get_area_id\\(\\)[^"]*return "([a-z0-9_]+)"')
	var d := DirAccess.open(INTERIOR_DIR)
	if d == null:
		return out
	for f in d.get_files():
		if not f.ends_with(".gd"):
			continue
		for m in rx.search_all(GdSource.code_of("%s/%s" % [INTERIOR_DIR, f])):
			var id: String = m.get_string(1)
			if not out.has(id):
				out.append(id)
	return out


## Rows that reach the player through the TIMED toast rather than the paged panel.
func _toast_rows() -> Array:
	var panel := _panel_scenes()
	var out: Array = []
	for k in _entries().keys():
		var e = _entries()[k]
		if not (e is Dictionary):
			continue
		if panel.has(str((e as Dictionary).get("scene", ""))):
			continue
		out.append({"key": str(k), "words": str((e as Dictionary).get("text", "")).split(" ", false).size()})
	return out


func test_the_corpus_is_real() -> void:
	assert_gt(_entries().size(), 40, "CONTROL: only %d entries read" % _entries().size())
	assert_gt(_panel_scenes().size(), 20, "CONTROL: the interior classes must declare their ids, saw %d" % _panel_scenes().size())
	assert_gt(_toast_rows().size(), 30, "CONTROL: the toast population must be non-trivial, saw %d — without it the arm below judges nothing" % _toast_rows().size())


## The arm the defect would have failed: every timed row gets long enough to be read by a FAST
## reader, bounded by the deliberate ceiling.
func test_every_timed_examine_outlasts_a_fast_read() -> void:
	var short: Array = []
	for row in _toast_rows():
		var words: int = int(row["words"])
		var need: float = minf(float(words) / FAST_READER_WPS, QuestExaminePoint.MAX_HOLD_SECONDS)
		var got: float = QuestExaminePoint.toast_hold_for(words)
		if got + 0.001 < need:
			short.append("%s (%d words: %.2fs held, %.2fs needed)" % [row["key"], words, got, need])
	assert_eq(short, [], "these examines fade before a fast reader finishes them: %s" % [short])


## The old flat value, stated as a consequence rather than as a spelling: the median row must now
## outlast the 3.2s the whole label used to live for.
func test_the_median_row_outlasts_the_old_whole_lifetime() -> void:
	var counts: Array = []
	for row in _toast_rows():
		counts.append(int(row["words"]))
	counts.sort()
	assert_gt(counts.size(), 0, "CONTROL: no toast rows to take a median of")
	var median: int = int(counts[counts.size() / 2])
	assert_gt(QuestExaminePoint.toast_hold_for(median), 3.2,
		"the median timed examine is %d words and holds only %.2fs — the whole label used to live 3.2s, so this is not an improvement" % [median, QuestExaminePoint.toast_hold_for(median)])


## Monotonic inside the band, and clamped at both ends — a constant hold passes none of these.
func test_the_hold_tracks_the_text() -> void:
	assert_gt(QuestExaminePoint.toast_hold_for(40), QuestExaminePoint.toast_hold_for(20),
		"a longer line must hold longer, or the hold is not derived from the text at all")
	assert_eq(QuestExaminePoint.toast_hold_for(1), QuestExaminePoint.MIN_HOLD_SECONDS,
		"a one-word line must sit at the floor, not below it")
	assert_eq(QuestExaminePoint.toast_hold_for(100000), QuestExaminePoint.MAX_HOLD_SECONDS,
		"a pathological line must sit at the ceiling, not pin the label forever")
	## CONTROL: the floor must not swallow the whole range, which would make the arm above vacuous.
	assert_lt(QuestExaminePoint.MIN_HOLD_SECONDS, QuestExaminePoint.MAX_HOLD_SECONDS,
		"the clamp band must be non-empty")
