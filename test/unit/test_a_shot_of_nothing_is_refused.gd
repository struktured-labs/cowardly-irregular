extends GutTest

## tools/shot_guard.gd decides whether a rendered frame DEPICTS ANYTHING before it can land as a
## store screenshot. These arms lived in tools/shot_guard_selftest.gd, which nothing ever ran.
##
## ⛔ IT RAN NOWHERE, AND THAT IS NOT THE SAME AS "NOBODY TYPED IT". publish_all.sh derives its
## selftest corpus from what the publish chain invokes BY BASENAME (tools/derive_selftest_corpus.py),
## and the screenshot tools are not on the publish path — so the corpus could never contain it. A
## .sh wrapper was added 2026-09-18 to make it SAFE to run; nothing was added to make it RUN.
## Measured 2026-09-19: 0 invocations anywhere in the repo, 0 rows in the derived corpus.
##
## Here the same arms execute in every gate — the suite is the only thing in this repo that runs
## unconditionally. The standalone pair is deleted rather than kept: two copies of one set of arms
## drift, and the bare-`godot -s` hazard its wrapper existed to mitigate goes away with the file.
##
## WHAT IT DEFENDS, measured 2026-09-17: in a worktree with no import cache HarmoniaVillage.gd
## failed to parse, the .tscn instantiated anyway, and the renderer wrote a 5322-byte flat-grey PNG
## and printed "wrote". Three day phases produced three BYTE-IDENTICAL files. These frames feed the
## itch store page and nothing between the renderer and the store looks at the pixels.

const ShotGuard := preload("res://tools/shot_guard.gd")

var _dir: String = ""


func before_all() -> void:
	_dir = "user://shot_guard_arms"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_dir))


func after_all() -> void:
	## The arms write PNGs; leaving them makes a later run's file_exists() arms pass on stale files.
	var d := DirAccess.open(_dir)
	if d == null:
		return
	for f in d.get_files():
		d.remove(f)


## A 1280x720 image whose 1-in-8 sample grid holds EXACTLY `colours` distinct values — built on the
## same grid the scorer walks, so the arm's premise is the scorer's premise. A fixture drawn on a
## different grid would be testing my arithmetic rather than the guard.
func _img(colours: int) -> Image:
	var im := Image.create(1280, 720, false, Image.FORMAT_RGBA8)
	im.fill(Color8(0, 0, 0))
	var n := 0
	var y := 0
	while y < 720:
		var x := 0
		while x < 1280:
			var c: int = n if n < colours else 0
			im.set_pixel(x, y, Color8(c % 256, (c / 256) % 256, (c / 65536) % 256))
			n += 1
			x += 8
		y += 8
	return im


func test_the_floor_is_a_real_number() -> void:
	# CONTROL for every arm below: they all read CONTENT_FLOOR, so a missing or zero constant would
	# make the boundary arms compare 0 against 0 and pass by construction.
	var floor_v: int = ShotGuard.CONTENT_FLOOR
	assert_gt(floor_v, 1, "the floor must sit above a blank frame's score of 1")


func test_the_scorer_counts_distinct_colours() -> void:
	var floor_v: int = ShotGuard.CONTENT_FLOOR
	assert_eq(ShotGuard.content_score(_img(1)), 1, "a flat image scores 1")
	assert_eq(ShotGuard.content_score(_img(floor_v)), floor_v,
		"a %d-colour fixture must score %d" % [floor_v, floor_v])
	# Without this the fixture could be incapable of exceeding the floor, and every ACCEPT arm
	# below would be passing for the wrong reason.
	assert_eq(ShotGuard.content_score(_img(floor_v + 500)), floor_v + 500,
		"the fixture must be able to exceed the floor")


func test_a_blank_frame_is_refused_and_kept_as_evidence() -> void:
	var out := "%s/blank.png" % _dir
	assert_false(ShotGuard.save_or_refuse(_img(1), out), "a blank frame must be REFUSED")
	assert_false(FileAccess.file_exists(out), "no shot may be written under the deliverable name")
	assert_true(FileAccess.file_exists("%s/blank.REJECTED.png" % _dir),
		"the rejected frame is the diagnosis and must be kept")


func test_a_real_frame_is_accepted() -> void:
	# A guard that only ever refuses is not a guard.
	var floor_v: int = ShotGuard.CONTENT_FLOOR
	var out := "%s/good.png" % _dir
	assert_true(ShotGuard.save_or_refuse(_img(floor_v + 500), out), "a real frame must be ACCEPTED")
	assert_true(FileAccess.file_exists(out), "the shot must be written")
	assert_false(FileAccess.file_exists("%s/good.REJECTED.png" % _dir),
		"an accepted frame leaves no .REJECTED twin")


func test_both_sides_of_the_boundary() -> void:
	# Without BOTH sides the floor could be any number at all — a threshold nobody has watched
	# reject anything is a constant, not a threshold.
	var floor_v: int = ShotGuard.CONTENT_FLOOR
	assert_false(ShotGuard.save_or_refuse(_img(floor_v - 1), "%s/below.png" % _dir),
		"floor-1 distinct colours must be REFUSED")
	assert_true(ShotGuard.save_or_refuse(_img(floor_v), "%s/at.png" % _dir),
		"exactly floor distinct colours must be ACCEPTED")
