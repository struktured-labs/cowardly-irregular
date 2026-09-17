extends GutTest

## A bust cut from the FRAME frames whatever the frame holds — which is mostly empty air for
## half the roster. Job sheets place their figures very differently: measured 2026-09-16, the
## Fighter fills 0.38 of its 256px frame with its head at y=66, where the Cleric's head is at
## y=10. The old rule took the top 55% of the FRAME, so the Fighter's save-screen portrait was
## 8.7% character and 47% of its height was blank sky above the head, while the Cleric's filled.
##
## Both live consumers (SaveScreen's party row, CutsceneDialogue's job bust) had the same eight
## lines copied, so the rule now has ONE owner: HybridSpriteLoader.bust_region().
const MIN_FILL := 0.20
const RATIO := 0.55

## Starters plus the small-figure and large-figure ends of the roster. Not every job dir:
## `*_sdxl` / `*_artist` are experiment folders, not sheets any consumer loads.
const JobRoster := preload("res://test/unit/helpers/job_roster.gd")
# Starter + advanced, derived. Meta jobs (type 2) are deliberately out: they have no artist bust.
var JOBS: Array[String] = JobRoster.of_types([0, 1])


func _frame_image(job: String) -> Image:
	var path := HybridSpriteLoader.job_asset_path(job, "idle", "")
	if not ResourceLoader.exists(path):
		return null
	var tex := load(path) as Texture2D
	return tex.get_image() if tex != null else null


func _fill(img: Image, r: Rect2i) -> float:
	var sub := img.get_region(r)
	var n := 0
	for y in sub.get_height():
		for x in sub.get_width():
			if sub.get_pixel(x, y).a > 0.03:
				n += 1
	return float(n) / float(maxi(1, sub.get_width() * sub.get_height()))


func test_every_bust_is_mostly_character() -> void:
	var thin: Array = []
	var checked := 0
	for job in JOBS:
		var img := _frame_image(job)
		if img == null:
			continue
		checked += 1
		var frame: int = img.get_height()
		var fill := _fill(img, HybridSpriteLoader.bust_region(HybridSpriteLoader.job_asset_path(job, "idle", ""), frame, RATIO))
		if fill < MIN_FILL:
			thin.append("%s: bust is only %.1f%% character" % [job, fill * 100.0])
	assert_eq(checked, JOBS.size(), "every declared job sheet must be readable — %d of %d loaded" % [checked, JOBS.size()])
	assert_eq(thin, [], "a bust is framing empty space instead of the character: %s" % [thin])


## ⛔ THE FIX MUST BEAT THE THING IT REPLACED, per job. A region that merely clears the floor
## could still be worse than the old crop for some sheet; this compares them directly.
func test_the_figure_crop_beats_the_frame_crop_on_every_sheet() -> void:
	var worse: Array = []
	for job in JOBS:
		var img := _frame_image(job)
		if img == null:
			continue
		var frame: int = img.get_height()
		var old_fill := _fill(img, Rect2i(0, 0, frame, int(float(frame) * RATIO)))
		var new_fill := _fill(img, HybridSpriteLoader.bust_region(HybridSpriteLoader.job_asset_path(job, "idle", ""), frame, RATIO))
		if new_fill <= old_fill:
			worse.append("%s: %.1f%% -> %.1f%%" % [job, old_fill * 100.0, new_fill * 100.0])
	assert_eq(worse, [], "the figure-derived bust must frame more character than the frame crop did: %s" % [worse])


## ⛔ ANTI-VACUITY. If no sheet was badly framed to begin with, the arms above pass on a roster
## the fix was never needed for, and reverting it would still read green.
func test_at_least_one_sheet_was_badly_framed_by_the_frame_crop() -> void:
	var bad := 0
	for job in JOBS:
		var img := _frame_image(job)
		if img == null:
			continue
		var frame: int = img.get_height()
		if _fill(img, Rect2i(0, 0, frame, int(float(frame) * RATIO))) < 0.15:
			bad += 1
	assert_gt(bad, 0,
		"no sheet is poorly framed by the old frame crop — this guard is defending a problem that no longer exists, so check whether the fix is still earning its place")


## The head must be IN the bust. A box that frames the torso well and cuts the face is worse
## than the blank sky it replaced, and the fill arms cannot tell the difference.
func test_the_head_is_inside_the_bust() -> void:
	var headless: Array = []
	for job in JOBS:
		var path := HybridSpriteLoader.job_asset_path(job, "idle", "")
		var img := _frame_image(job)
		if img == null:
			continue
		var frame: int = img.get_height()
		var fig := HybridSpriteLoader.figure_rect(path)
		var bust := HybridSpriteLoader.bust_region(path, frame, RATIO)
		if fig.position.y < bust.position.y or fig.position.y > bust.end.y:
			headless.append("%s: figure top y=%d, bust spans y=%d..%d" % [job, fig.position.y, bust.position.y, bust.end.y])
		if bust.position.x < 0 or bust.position.y < 0 or bust.end.x > frame or bust.end.y > frame:
			headless.append("%s: bust %s escapes the %dpx frame" % [job, str(bust), frame])
	assert_eq(headless, [], "a bust must contain the figure's head and stay inside its frame: %s" % [headless])


## The consumers must ASK the owner. Two files held the same eight lines; a third copy is how
## this drifts back, and a copy keeps passing every arm above while the shipped screen regresses.
func test_both_bust_consumers_call_the_shared_owner() -> void:
	const GdSource := preload("res://test/unit/helpers/gd_source.gd")
	for path in ["res://src/ui/SaveScreen.gd", "res://src/cutscene/CutsceneDialogue.gd"]:
		var code := GdSource.code_of(path)
		assert_true(code.contains("HybridSpriteLoader.bust_region("),
			"%s must cut its bust through HybridSpriteLoader.bust_region()" % path)
		assert_false(code.contains("Rect2(0, 0, frame,"),
			"%s still cuts a bust from the FRAME — that is the rule this file replaced" % path)
