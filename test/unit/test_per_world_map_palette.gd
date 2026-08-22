extends GutTest
## The map palette is PER WORLD and the world id is REQUIRED.
##
## MEASURED 2026-08-22 across the six worlds' `_char_to_tile_type` arms: 48 distinct map
## characters, 30 of them used by more than one world, and ZERO of those 30 meaning the
## same thing in two worlds. "c" is COAST in W1, BASKETBALL_COURT in W2, CONCRETE in W3,
## CONVEYOR_BELT in W4 and CIRCUIT_FLOOR in W5. Overlap is total: 30 shared, 30 conflicting,
## 0 consistent.
##
## WHY THE ID IS REQUIRED RATHER THAN DEFAULTED, which is the whole point of this file.
## A W4 image decoded against W1's table does not error -- it produces a PLAUSIBLE MAP MADE
## OF THE WRONG TILES. Every pixel resolves, every row is the right length, the map renders.
## A default world would make that the quiet path and the mistake undetectable at the call
## site. So an unknown or missing world must decode NOTHING.

const Loader := preload("res://src/exploration/MapImageLoader.gd")
const W1_PNG := "res://data/maps/overworld_w1.png"


func test_an_unknown_world_fails_loudly_and_decodes_nothing() -> void:
	var err: String = Loader.ensure_palette("no_such_world")
	assert_ne(err, "", "an unknown world must return a reason, not succeed silently")
	assert_true(
		err.contains("no_such_world"),
		"the error must name the world that was asked for, so the call site is findable: %s" % err
	)
	var rows: Array = Loader.load_rows(W1_PNG, "no_such_world")
	assert_eq(
		rows, [],
		"an unknown world decoded %d rows. It must decode NOTHING -- falling back to another world's table renders a plausible map built from the wrong tiles." % rows.size()
	)


func test_two_worlds_disagree_about_the_same_character() -> void:
	var med: String = Loader.ensure_palette("medieval")
	var sub: String = Loader.ensure_palette("suburban")
	assert_eq(med, "", "medieval palette failed to load: %s" % med)
	assert_eq(sub, "", "suburban palette failed to load: %s" % sub)

	var shared: Array = []
	for ch in Loader.palette_chars("medieval"):
		if Loader.palette_chars("suburban").has(ch):
			shared.append(ch)
	assert_gt(
		shared.size(), 0,
		"the two worlds share no characters at all -- either a palette is empty or the scan is wrong, and this test would pass vacuously"
	)

	var differing: Array = []
	for ch in shared:
		if Loader.palette_rgb("medieval", ch) != Loader.palette_rgb("suburban", ch):
			differing.append(ch)
	assert_eq(
		differing.size(), shared.size(),
		"%d of %d shared characters carry the SAME colour in both worlds (%s). Every shared character means something different per world, so none may share a colour -- a shared colour is the mechanism by which one world's map silently decodes as another's." % [shared.size() - differing.size(), shared.size(), str(shared)]
	)


func test_w1_still_decodes_through_the_world_aware_api() -> void:
	var rows: Array = Loader.load_rows(W1_PNG, "medieval")
	assert_eq(rows.size(), 140, "W1 decoded %d rows, expected 140" % rows.size())
	if rows.is_empty():
		return
	assert_eq((rows[0] as String).length(), 200, "W1 row 0 is not 200 characters")
	var landmarks: Array = Loader.landmark_chars("medieval")
	assert_true(landmarks.has("V"), "medieval landmarks lost 'V' (Harmonia): %s" % str(landmarks))
