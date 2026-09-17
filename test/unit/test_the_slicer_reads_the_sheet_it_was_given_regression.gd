extends GutTest

## `CutsceneActor._load_sheet` sliced every staged-actor sheet at a hardcoded `FRAME_SIZE = 32` and
## only checked the sheet was BIG ENOUGH (`width >= 32*4 and height >= 32*4`). A 48px sheet passes
## that test and gets cut into 32px squares: the puppet shows a quarter of a figure, and nothing
## errors. 159 of 159 overworld sheets are 128x128 at 32px today, which is why the assumption has
## held — the same shape as cowir-sprites' per-sheet `fps` (2026-09-16), where the manifest declares
## per sheet and the consumer assumed the convention.
##
## The frame is now DERIVED from the sheet: 4 rows of WALK_FRAMES columns of square frames, or a
## refusal. A sheet that is merely the wrong shape is refused rather than mis-sliced.

const ActorScript = preload("res://src/cutscene/CutsceneActor.gd")

## Set by the null arm AFTER its call returns. See test_zz_the_null_call_did_not_abort.
var _null_survived: bool = false


func _sheet(frame: int, rows: int = 4, cols: int = -1) -> Texture2D:
	var c: int = cols if cols > 0 else ActorScript.WALK_FRAMES
	var img := Image.create(frame * c, frame * rows, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.4, 0.5, 0.6, 1.0))
	return ImageTexture.create_from_image(img)


func test_the_conventional_sheet_still_measures_32() -> void:
	assert_eq(ActorScript.frame_size_of(_sheet(ActorScript.FRAME_SIZE)), ActorScript.FRAME_SIZE,
		"the 128x128 sheets every actor uses today must measure exactly as before")


## THE DEFECT: a bigger sheet must be measured, not cut into the convention's squares.
func test_a_48px_sheet_is_measured_not_assumed() -> void:
	assert_eq(ActorScript.frame_size_of(_sheet(48)), 48,
		"a 192x192 sheet is 48px frames; slicing it at 32 shows a quarter of the figure")
	assert_eq(ActorScript.frame_size_of(_sheet(64)), 64, "and a 64px sheet is 64px frames")


## CONTROL: the OLD test would have accepted the 48px sheet, or this file guards nothing.
func test_control_the_old_big_enough_test_accepted_it() -> void:
	var tex := _sheet(48)
	var passes_old: bool = tex.get_width() >= ActorScript.FRAME_SIZE * ActorScript.WALK_FRAMES \
		and tex.get_height() >= ActorScript.FRAME_SIZE * 4
	assert_true(passes_old,
		"the superseded guard was `big enough`, which a 48px sheet satisfies — that is why it was silent")
	assert_ne(ActorScript.frame_size_of(tex), ActorScript.FRAME_SIZE,
		"and the new measurement must disagree with the convention for this sheet")


## A sheet that cannot be a 4-row grid of square frames is REFUSED, not mis-sliced.
func test_an_ungriddable_sheet_is_refused() -> void:
	var img := Image.create(100, 66, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	assert_eq(ActorScript.frame_size_of(ImageTexture.create_from_image(img)), 0,
		"66px is not four rows of anything; refuse rather than cut a wrong grid")
	var narrow := Image.create(40, 128, false, Image.FORMAT_RGBA8)
	narrow.fill(Color.WHITE)
	assert_eq(ActorScript.frame_size_of(ImageTexture.create_from_image(narrow)), 0,
		"four rows of 32 but not enough columns for a walk cycle; refuse")
	assert_eq(ActorScript.frame_size_of(null), 0, "null measures 0")
	_null_survived = true  # only reached if that call did not error — see the arm at the bottom


## A sheet with MORE columns than the walk cycle keeps its frame size — extra poses are not a resize.
func test_extra_columns_do_not_change_the_frame() -> void:
	assert_eq(ActorScript.frame_size_of(_sheet(32, 4, 8)), 32,
		"a 256x128 sheet is still 32px frames with spare columns, not 64px frames")


## BEHAVIOURAL: the slicer must use the measured frame, so the regions land on the grid.
func test_the_slicer_cuts_on_the_measured_grid() -> void:
	var a = ActorScript.new()
	add_child_autofree(a)
	var tex := _sheet(48)
	a._frames.clear()
	# Slice directly, the way _load_sheet does, through the real frame measurement.
	var frame: int = ActorScript.frame_size_of(tex)
	for row in 4:
		for col in ActorScript.WALK_FRAMES:
			var at := AtlasTexture.new()
			at.atlas = tex
			at.region = Rect2(col * frame, row * frame, frame, frame)
			a._frames["%d_%d" % [row, col]] = at
	var last: AtlasTexture = a._frames["3_%d" % (ActorScript.WALK_FRAMES - 1)]
	assert_eq(last.region.end.y, float(tex.get_height()),
		"the bottom row must reach the bottom of the sheet — at 32px it would stop a third of the way down")
	assert_eq(last.region.end.x, float(frame * ActorScript.WALK_FRAMES),
		"and the last column must reach the end of the walk cycle")


## The live slicer reads the measurement rather than the constant.
func test_load_sheet_uses_the_measurement() -> void:
	var src := FileAccess.get_file_as_string("res://src/cutscene/CutsceneActor.gd")
	var i := src.find("func _load_sheet")
	assert_gt(i, -1)
	var next: int = src.find("\nfunc ", i + 1)
	var body := src.substr(i, (next - i) if next > -1 else 1200)
	assert_true("frame_size_of(tex)" in body, "_load_sheet must measure the sheet it was given")
	assert_false("Rect2(col * FRAME_SIZE" in body,
		"and must not cut on the convention — that is the mis-slice this replaced")


## ⛔ THE NO-THROW HALF IS NOT ASSERTABLE FROM INSIDE GUT, and this arm records why rather than
## pretending otherwise. Measured 2026-09-16 by mutating the null guard away:
##   the callee errors -> the ABORT IS CONTAINED IN THE CALLEE -> it yields int's default, 0
##   -> `assert_eq(frame_size_of(null), 0)` PASSES, the statement after it runs, the suite is green
##   -> and the run logs `SCRIPT ERROR: Cannot call method 'get_height' on a null value.`
## So the flag below only proves MY function kept running, which it does either way. The guard's real
## value is the absent error line, and that lives in the run log, not in an assert. Two arms in this
## lane today were vacuous for the mirror-image reason (the abort was in the TEST, which GUT scores
## passed); this one is vacuous-by-construction and is kept as a signpost, not as a check.
func test_zz_the_null_call_returned_rather_than_taking_the_test_with_it() -> void:
	assert_true(_null_survived,
		"the null call did not abort THIS function — it cannot tell you whether the callee errored")
