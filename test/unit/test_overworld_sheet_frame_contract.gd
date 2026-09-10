extends GutTest

## Overworld sheets are cropped by a HARDCODED frame size, and nothing checked the sheets against it.
##
## RoamingMonster and MasteriteEncounter both draw from assets/sprites/monsters/overworld/<id>.png by
## setting region_rect = Rect2(col * FRAME_W, row * FRAME_H, FRAME_W, FRAME_H) with FRAME_W/H = 32.
## A sheet that is not a whole number of 32px frames does not error -- it renders a CORNER of the
## art, silently. The contract lived only in the consumers' constants and in whatever the sprite
## generator happened to emit.
##
## cowir-sprites measured the population on 2026-09-09: 85 of 85 sheets are exactly 128x128, a 4x4
## grid of 32, zero exceptions, and asked for it to be ASSERTED rather than derived -- deriving the
## frame size from the image is a guess (a 128x128 file could be 4x4 of 32 or one frame at 128), and
## a generator emitting the wrong size should fail loudly there rather than render a corner here.
##
## What is pinned is the RELATIONSHIP -- every sheet is a whole number of the frames its consumers
## crop -- not the 128, so a legitimately longer animation row stays green.

const OVERWORLD_DIR := "res://assets/sprites/monsters/overworld"
const CONSUMERS := [
	"res://src/exploration/RoamingMonster.gd",
	"res://src/exploration/MasteriteEncounter.gd",
]


func _sheets() -> Array:
	var out: Array = []
	var dir := DirAccess.open(OVERWORLD_DIR)
	if dir == null:
		return out
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if f.ends_with(".png"):
			out.append(f)
		f = dir.get_next()
	out.sort()
	return out


## Two consumers crop with their own copy of the number. They are supposed to AGREE, so assert that
## rather than modelling which one wins -- if they agree the question of precedence is moot.
func test_both_consumers_crop_with_the_same_frame_size() -> Vector2i:
	var sizes: Array = []
	for path in CONSUMERS:
		var consts: Dictionary = load(path).get_script_constant_map()
		assert_true(consts.has("FRAME_W") and consts.has("FRAME_H"),
			"%s has no FRAME_W/FRAME_H -- it crops by some other means and this ledger is stale" % path.get_file())
		if consts.has("FRAME_W") and consts.has("FRAME_H"):
			sizes.append(Vector2i(int(consts["FRAME_W"]), int(consts["FRAME_H"])))
	assert_eq(sizes.size(), CONSUMERS.size(), "not every consumer reported a frame size")
	for s in sizes:
		assert_eq(s, sizes[0],
			"the two overworld-sheet consumers crop different frame sizes %s -- one of them is drawing the wrong part of every sheet" % str(sizes))
	return sizes[0] if not sizes.is_empty() else Vector2i(32, 32)


func test_every_overworld_sheet_is_a_whole_number_of_frames() -> void:
	var frame := test_both_consumers_crop_with_the_same_frame_size()
	var sheets := _sheets()
	assert_gt(sheets.size(), 50,
		"CONTROL: only %d overworld sheets found (85 at time of writing) -- the scan is broken and any zero below is free" % sheets.size())

	var ragged: Array = []
	var measured := 0
	for f in sheets:
		var img := Image.load_from_file("%s/%s" % [OVERWORLD_DIR, f])
		if img == null:
			ragged.append("%s could not be read as an image" % f)
			continue
		measured += 1
		var w := img.get_width()
		var h := img.get_height()
		if w % frame.x != 0 or h % frame.y != 0 or w < frame.x or h < frame.y:
			ragged.append("%s is %dx%d, not a whole number of %dx%d frames" % [f, w, h, frame.x, frame.y])

	assert_eq(measured, sheets.size(), "read %d of %d sheets" % [measured, sheets.size()])
	assert_eq(ragged, [],
		"a sheet that is not a whole number of frames renders as a CORNER of itself, silently -- no error, no warning: %s" % str(ragged))


func test_the_probe_can_see_a_ragged_sheet() -> void:
	# CONTROL: the divisibility check must be able to come back red, or the sweep above is decoration.
	var frame := Vector2i(32, 32)
	var bad := Image.create(100, 128, false, Image.FORMAT_RGBA8)
	assert_true(bad.get_width() % frame.x != 0,
		"CONTROL: a 100px-wide sheet must read as ragged against a 32px frame")


## A sheet can satisfy every geometric contract above and still be EMPTY. The 2026-09-09
## dark_knight regen returned frames holding 13-94 opaque pixels -- correct size, correct
## divisibility, nothing to see. The cause was in the generator (a second chromakey pass whose
## corner seed landed on a near-black subject and keyed the whole figure out), but the class is
## general: any step between "the model returned art" and "the PNG is on disk" can drop the
## subject and leave a valid file. Geometry was checked here; occupancy was checked nowhere.
##
## TWO arms, because there are two failure SHAPES and neither instrument sees the other's:
##
##  1. RELATIVE -- a frame far thinner than its own sheet's typical frame. This is the real
##     defect shape (some frames survive, some are keyed out) and it needs no absolute idea of
##     how big a monster is, so a legitimately tiny sprite cannot trip it. Measured separation:
##     the lowest ratio across all 85 shipped sheets is 0.743 (troll), and the two broken
##     dark_knight builds scored 0.156 and 0.089. 0.35 sits between them with ~2x headroom on
##     BOTH sides. An absolute floor cannot do this job: the second broken build held 43 px,
##     which any floor low enough to clear bat's 154 would have passed.
##
##  2. ABSOLUTE -- a floor of 32 px, for the degenerate case arm 1 is blind to: a UNIFORMLY
##     empty sheet has a healthy ratio near 1.0 because its median is empty too.
const MIN_FRAME_FRACTION_OF_MEDIAN := 0.35
const MIN_OPAQUE_PX_PER_FRAME := 32


func _frame_occupancy(img: Image, frame: Vector2i) -> Array:
	img.convert(Image.FORMAT_RGBA8)
	var data := img.get_data()
	var w := img.get_width()
	var out: Array = []
	for row in range(img.get_height() / frame.y):
		for col in range(w / frame.x):
			var n := 0
			for y in range(row * frame.y, (row + 1) * frame.y):
				for x in range(col * frame.x, (col + 1) * frame.x):
					if data[(y * w + x) * 4 + 3] > 10:
						n += 1
			out.append({"n": n, "at": Vector2i(col, row)})
	return out


func _median_n(cells: Array) -> float:
	var ns: Array = []
	for c in cells:
		ns.append(int(c["n"]))
	ns.sort()
	if ns.is_empty():
		return 0.0
	var m: int = ns.size() / 2
	return float(ns[m]) if ns.size() % 2 == 1 else (float(ns[m - 1]) + float(ns[m])) / 2.0


func test_no_overworld_frame_is_empty() -> void:
	var frame := test_both_consumers_crop_with_the_same_frame_size()
	var sheets := _sheets()
	assert_gt(sheets.size(), 50,
		"CONTROL: only %d overworld sheets found -- the scan is broken and any zero below is free" % sheets.size())

	var blank: Array = []
	var measured := 0
	var thinnest := 1 << 30
	for f in sheets:
		var img := Image.load_from_file("%s/%s" % [OVERWORLD_DIR, f])
		if img == null:
			continue
		measured += 1
		var cells := _frame_occupancy(img, frame)
		var med := _median_n(cells)
		for c in cells:
			var n: int = int(c["n"])
			thinnest = min(thinnest, n)
			if n < MIN_OPAQUE_PX_PER_FRAME:
				blank.append("%s frame (col %d,row %d) holds %d opaque px" % [f, c["at"].x, c["at"].y, n])
			elif med > 0.0 and float(n) / med < MIN_FRAME_FRACTION_OF_MEDIAN:
				blank.append("%s frame (col %d,row %d) holds %d px, %.0f%% of this sheet's median %d" % [
					f, c["at"].x, c["at"].y, n, 100.0 * float(n) / med, int(med)])

	assert_eq(measured, sheets.size(), "read %d of %d sheets" % [measured, sheets.size()])
	assert_gt(thinnest, 0,
		"CONTROL: the emptiest frame measured 0 px across every sheet -- the alpha probe is reading nothing")
	assert_eq(blank, [],
		"a frame with almost no pixels renders as an invisible monster -- the file is valid, the art is gone: %s" % str(blank))


func test_the_probe_can_see_an_emptied_frame() -> void:
	# CONTROL 1: the relative arm, at the REAL defect's magnitude -- 43 px beside 480 px frames,
	# the second broken dark_knight build. An absolute floor low enough to pass bat lets this by.
	var img := Image.create(128, 128, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 1))
	var kept := 0
	for y in range(96, 128):
		for x in range(96, 128):
			if kept < 43:
				kept += 1
			else:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
	var cells := _frame_occupancy(img, Vector2i(32, 32))
	var med := _median_n(cells)
	var last: Dictionary = cells[cells.size() - 1]
	assert_eq(int(last["n"]), 43, "CONTROL: the planted frame must hold exactly the defect's 43 px")
	assert_gt(int(last["n"]), MIN_OPAQUE_PX_PER_FRAME,
		"CONTROL: 43 px CLEARS the absolute floor -- this is precisely why the relative arm exists")
	assert_lt(float(last["n"]) / med, MIN_FRAME_FRACTION_OF_MEDIAN,
		"CONTROL: the relative arm must flag 43 px against a median of %d" % int(med))


func test_the_probe_can_see_a_uniformly_empty_sheet() -> void:
	# CONTROL 2: the relative arm is BLIND here -- every frame is equally empty, so the ratio is
	# a healthy 1.0. Only the absolute floor can fail this, which is the whole reason it stays.
	var img := Image.create(128, 128, false, Image.FORMAT_RGBA8)
	var cells := _frame_occupancy(img, Vector2i(32, 32))
	var med := _median_n(cells)
	assert_eq(int(cells[0]["n"]), 0, "CONTROL: the blank sheet must measure 0 opaque px")
	assert_eq(med, 0.0, "CONTROL: its median is 0, so the relative arm has nothing to divide by")
	assert_lt(int(cells[0]["n"]), MIN_OPAQUE_PX_PER_FRAME, "CONTROL: the absolute floor must catch it")
