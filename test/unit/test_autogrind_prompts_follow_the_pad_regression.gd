extends GutTest

## Four player-facing prompts in this lane named buttons that do not exist on the pad in the
## player's hands. A PlayStation player reading "Press A or B to continue" on the autogrind summary
## has neither button; on a DualSense those are Cross and Circle.
##
##   AutogrindSummary       "Press A or B to continue"     accepts ui_accept OR ui_cancel
##   AutogrindHistoryScreen "Press B or Esc to return"     accepts ui_cancel
##   AutogrindTemplatePicker"Press B or Esc to close"      accepts ui_cancel
##   AutobattleGridEditor   "D-Pad:Select A:Confirm B:Cancel"
##
## @cowir-controller found these while correcting the reach of their own ratchet, which matches
## `"[A]` and glyphs and is structurally blind to the UNBRACKETED spelling. Their words: the
## pattern is narrower than the defect, for the fourth time in one file. So this census patterns on
## the DEFECT -- a face-button letter used as a caption, in any spelling -- not on one form of it.
##
## Esc and D-Pad stay literal on purpose: a keyboard key does not change with the pad, and every
## pad has a d-pad. The thing that varies is the FACE letter, and only that is derived.
##
## ⛔ I FIRST EXEMPTED THREE OF THESE ON REASONS THAT WERE FALSE, and @cowir-controller measured
## them rather than reading them. I wrote that "Y:CycleOp" was the keyboard row — KEY_Y is bound to
## NOTHING in that file and the keyboard key is C (:1836); that Y is JOY_BUTTON_Y, Ⓧ on Nintendo and
## △ on PlayStation. I wrote that "Del/Y:Delete" named a pad button for a keyboard-only action —
## :1842-1847 deletes on JOY_BUTTON_Y whenever the cursor is off a condition cell. Both are now
## DERIVED through face_glyph_for_index, which is the right helper for a RAW button index (no
## action to look up), where glyph_for_action takes an action name.
##
## An exemption carrying a false reason is worse than no exemption: it reads as verified and stops
## the next sweep from looking. The reason field is the deliverable, so a wrong one is the one
## defect this design cannot absorb.

const LANE_DIRS := ["res://src/ui/autogrind", "res://src/ui/autobattle"]

## Frozen captions that are NOT fixed, each with the reason -- the value is required non-empty, so
## an entry can be explained green but never silenced green.
const DEFERRED := {
	"Sel:Auto": "Select is not a FACE button, so neither glyph_for_action nor face_glyph_for_index names it; @cowir-controller's non-face derivation is on an unfolded branch and duplicating it would create a second authority.",
	"Start:Save": "Start is not a face button; same reason as Sel:Auto.",
}


func _gd_files() -> Array:
	var out: Array = []
	for d in LANE_DIRS:
		var dir := DirAccess.open(d)
		if dir == null:
			continue
		for f in dir.get_files():
			if f.ends_with(".gd"):
				out.append(d + "/" + f)
	return out


func test_the_census_reads_a_real_corpus() -> void:
	var files := _gd_files()
	assert_gt(files.size(), 5, "CONTROL: the lane dirs must yield real files, or every assert below is vacuous")
	var total := 0
	for f in files:
		total += FileAccess.get_file_as_string(f).length()
	assert_gt(total, 20000, "CONTROL: and real content, not empty reads")


func test_no_face_button_letter_is_frozen_into_a_caption() -> void:
	# The defect in any spelling: "Press A", "A:Confirm", "A or B", "[A]".
	var re := RegEx.create_from_string("(Press [ABXY]\\b|\\b[ABXY]:[A-Za-z]|\\b[ABXY] or [ABXY]\\b|\\[[ABXY]\\])")
	var frozen: Array = []
	for f in _gd_files():
		var lines := FileAccess.get_file_as_string(f).split("\n")
		for i in lines.size():
			var l: String = lines[i]
			if l.strip_edges().begins_with("#"):
				continue
			if not l.contains("\""):
				continue
			var m := re.search(l)
			if m == null:
				continue
			var hit: String = m.get_string(1)
			if DEFERRED.has(hit):
				continue
			frozen.append("%s:%d  %s" % [f.get_file(), i + 1, hit])
	assert_eq(frozen.size(), 0,
		"a face-button letter is frozen into a caption -- derive it via InputProfileManager.glyph_for_action, or add it to DEFERRED with a reason:\n  %s"
		% "\n  ".join(frozen))


func test_the_four_repaired_surfaces_actually_ask_the_authority() -> void:
	# The census above proves no frozen letter remains; this proves the replacement DERIVES rather
	# than having simply deleted the caption.
	for f in ["res://src/ui/autogrind/AutogrindSummary.gd",
			  "res://src/ui/autogrind/AutogrindHistoryScreen.gd",
			  "res://src/ui/autogrind/AutogrindTemplatePicker.gd",
			  "res://src/ui/autobattle/AutobattleGridEditor.gd"]:
		var src := FileAccess.get_file_as_string(f)
		assert_gt(src.length(), 500, "CONTROL: %s was read" % f.get_file())
		assert_true(src.contains("InputProfileManager.glyph_for_action("),
			"%s must ask the authority for its button glyph" % f.get_file())


func test_deferred_entries_carry_a_reason_and_are_still_present() -> void:
	var all := ""
	for f in _gd_files():
		all += FileAccess.get_file_as_string(f)
	var stale: Array = []
	for k in DEFERRED.keys():
		if str(DEFERRED[k]).strip_edges().is_empty():
			stale.append("%s has an empty reason" % k)
		if not all.contains(k):
			stale.append("%s is no longer in the corpus -- remove the exemption" % k)
	assert_eq(stale, [], "DEFERRED entry is unexplained or stale")
