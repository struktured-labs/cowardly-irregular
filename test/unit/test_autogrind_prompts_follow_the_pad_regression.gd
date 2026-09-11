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

const LANE_DIRS := ["res://src/ui/autogrind", "res://src/ui/autobattle"]

## Frozen captions that are NOT fixed, each with the reason -- the value is required non-empty, so
## an entry can be explained green but never silenced green.
const DEFERRED := {
	"Sel:Auto": "Select is not a face button; glyph_for_action reads FACE_GLYPHS only, and the non-face derivation is on @cowir-controller's unfolded branch. Duplicating it would create a second authority.",
	"Start:Save": "Start is not a face button; same reason as Sel:Auto.",
	"Y:C": "AutobattleGridEditor's help_label2 is the KEYBOARD row -- that Y is the keyboard letter for CycleOp, not the face button. Same spelling, different symbol; only the row says which.",
	"X:D": "AutogrindGridEditor 'Del/X:Delete' names a pad button for an action bound to KEY_DELETE/KEY_BACKSPACE only. Deriving it would assert a binding I could not establish -- recorded rather than guessed.",
	"Y:D": "AutobattleGridEditor 'Del/Y:Delete', same as X:D -- keyboard-only binding wearing a face-button caption.",
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
